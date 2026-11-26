/*
 * backup.c -- what keeps the text through a power cut or a mistake
 * (26 November 2026; Eduardo asked for it)
 *
 * 1. The save itself (save_file_safely, called by gap.c's save_buffer).
 *    It used to empty the file and write it again in place, so a power cut
 *    in between could leave it empty or cut short.  Now the text goes to a
 *    temporary file in the same folder, is forced onto the disk (fsync; on
 *    macOS F_FULLFSYNC, which also empties the drive's cache), and is
 *    renamed over the file in one step; then the folder is forced too.
 *    After a power cut there is the old file or the new one, whole.  The
 *    file keeps its permissions; a symbolic link keeps pointing to the file
 *    it named, which is the one written.  A file with other hard links, or
 *    owned by someone else, is written in place, as before (a rename would
 *    break the links or change the owner), but forced onto the disk too.
 *
 * 2. Backups (backup_before_save).  The first save of a file in a session
 *    keeps the version on disk before it in ~/.chezemax/backup, under the
 *    file's whole path with / written as ! (as Emacs's backup-directory-
 *    alist names them): !Users!eduardo!notes.md.~1~, the newest, then .~2~
 *    and .~3~.  The old file is linked there, not copied, when it is on the
 *    same disk: the rename leaves it to the backup, at no cost whatever its
 *    size.  Otherwise it is copied, up to AUTOSAVE_LIMIT.
 *
 * 3. Auto-save (autosave_key, autosave_idle).  After 30 seconds without a
 *    key, and every 300 keys, every buffer of a file with changes not yet
 *    saved nor auto-saved is written to ~/.chezemax/auto-save/#!path#, the
 *    same safe way.  Up to 10 MB (AUTOSAVE_LIMIT): about 20 ms on an SSD,
 *    not felt.  Not files in shards, nor buffers without a file.  Saving
 *    the file removes its auto-save.  Visiting a file whose auto-save is
 *    newer says so; M-x recover-file puts the auto-save's text in the
 *    buffer (C-/ undoes it).
 *
 * No backups of files in the temporary folder ($TMPDIR, else /tmp), as in
 * Emacs.  The browser saves through its page (web/files.js): none of this there.
 */
#include "header.h"
#include <fcntl.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>
#include <errno.h>
#include <limits.h>
#include <dirent.h>

extern void fe_delete_region(long start, long end);     /* interface.c */

#define AUTOSAVE_LIMIT (10L * 1024 * 1024)
#define AUTOSAVE_IDLE_MS 30000
#define AUTOSAVE_KEYS 300
#define BACKUPS 3

#ifndef __EMSCRIPTEN__

static long long now_ms(void)
{
	struct timespec t;
	clock_gettime(CLOCK_MONOTONIC, &t);
	return (long long) t.tv_sec * 1000 + t.tv_nsec / 1000000;
}

/* force FD onto the disk; on macOS fsync leaves it in the drive's cache */
static int force(int fd)
{
#ifdef F_FULLFSYNC
	if (fcntl(fd, F_FULLFSYNC) == 0) return 0;
#endif
	return fsync(fd);
}

static void force_folder(const char *path)
{
	char dir[PATH_MAX];
	char *slash;
	int fd;

	snprintf(dir, sizeof dir, "%s", path);
	slash = strrchr(dir, '/');
	if (slash == dir) dir[1] = '\0';
	else if (slash) *slash = '\0';
	else strcpy(dir, ".");
	if ((fd = open(dir, O_RDONLY)) >= 0) { (void) force(fd); close(fd); }
}

/* ~/.chezemax/NAME, made if missing (0700: the texts are the user's) */
static int chezemax_folder(const char *name, char *out, size_t n)
{
	const char *home = getenv("HOME");
	if (home == NULL || home[0] == '\0') return 0;
	snprintf(out, n, "%s/.chezemax", home);
	(void) mkdir(out, 0700);
	snprintf(out, n, "%s/.chezemax/%s", home, name);
	if (mkdir(out, 0700) != 0 && errno != EEXIST) return 0;
	return 1;
}

/* FN's whole path with / written as !: /Users/e/a.md -> !Users!e!a.md */
static int mangled(const char *fn, char *out, size_t n)
{
	char whole[PATH_MAX], *p;

	if (fn[0] == '/') {
		if (snprintf(whole, sizeof whole, "%s", fn) >= (int) sizeof whole) return 0;
	} else {
		char cwd[PATH_MAX];
		if (getcwd(cwd, sizeof cwd) == NULL) return 0;
		if (snprintf(whole, sizeof whole, "%s/%s", cwd, fn) >= (int) sizeof whole) return 0;
	}
	{       /* the real path when the folder exists: one name for one file */
		char real[PATH_MAX], dir[PATH_MAX], again[PATH_MAX];
		char *slash = strrchr(whole, '/');
		if (snprintf(dir, sizeof dir, "%.*s", (int) (slash - whole), whole) >= (int) sizeof dir) return 0;
		if (dir[0] && realpath(dir, real) != NULL &&
		    snprintf(again, sizeof again, "%s/%s", strcmp(real, "/") ? real : "", slash + 1) < (int) sizeof again)
			strcpy(whole, again);
	}
	for (p = whole; *p; p++) if (*p == '/') *p = '!';
	if (strlen(whole) + 1 > n) return 0;
	strcpy(out, whole);
	return 1;
}

/* the auto-save of FN: ~/.chezemax/auto-save/#!path!name# */
static int autosave_name(const char *fn, char *out, size_t n)
{
	char dir[PATH_MAX], m[PATH_MAX];
	if (!chezemax_folder("auto-save", dir, sizeof dir) || !mangled(fn, m, sizeof m)) return 0;
	return snprintf(out, n, "%s/#%s#", dir, m) < (int) n;
}

/* write the text of BP to FD, the two sides of the gap as they lie */
static int write_text(buffer_t *bp, int fd)
{
	const char_t *part[2];
	size_t len[2];
	int k;

	part[0] = bp->b_buf;  len[0] = (size_t) (bp->b_gap - bp->b_buf);
	part[1] = bp->b_egap; len[1] = (size_t) (bp->b_ebuf - bp->b_egap);
	for (k = 0; k < 2; k++) {
		size_t done = 0;
		while (done < len[k]) {
			ssize_t w = write(fd, part[k] + done, len[k] - done);
			if (w < 0) { if (errno == EINTR) continue; return 0; }
			done += (size_t) w;
		}
	}
	return 1;
}

/* the text of BP to PATH through a temporary file beside it, forced and
 * renamed; MODE for a new file */
static int write_by_rename(buffer_t *bp, const char *path, mode_t mode)
{
	char temp[PATH_MAX + 32];
	int fd, ok;

	snprintf(temp, sizeof temp, "%s.chezweb-%ld~", path, (long) getpid());
	fd = open(temp, O_WRONLY | O_CREAT | O_TRUNC, 0600);
	if (fd < 0) return -1;                  /* the folder: not writable */
	ok = write_text(bp, fd) && fchmod(fd, mode) == 0 && force(fd) == 0;
	if (close(fd) != 0) ok = 0;
	if (ok && rename(temp, path) != 0) ok = 0;
	if (!ok) { (void) unlink(temp); return 0; }
	force_folder(path);
	return 1;
}

static int write_in_place(buffer_t *bp, const char *path, mode_t mode)
{
	int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, mode), ok;
	if (fd < 0) return 0;
	ok = write_text(bp, fd) && force(fd) == 0;
	if (close(fd) != 0) ok = 0;
	return ok;
}

/* copy FROM to TO (a backup the rename cannot leave: another disk) */
static int copy_file(const char *from, const char *to)
{
	char buf[65536];
	int in = open(from, O_RDONLY), out;
	ssize_t n;
	int ok = 1;

	if (in < 0) return 0;
	out = open(to, O_WRONLY | O_CREAT | O_TRUNC, 0600);
	if (out < 0) { close(in); return 0; }
	while ((n = read(in, buf, sizeof buf)) > 0)
		if (write(out, buf, (size_t) n) != n) { ok = 0; break; }
	if (n < 0) ok = 0;
	if (force(out) != 0) ok = 0;
	close(in);
	if (close(out) != 0) ok = 0;
	return ok;
}

/* Is FILE in the temporary folder ($TMPDIR, else /tmp)?  Emacs makes no
 * backups there (normal-backup-enable-predicate), nor does this: the tests
 * save files there by the hundred. */
static int in_temp_folder(const char *file)
{
	const char *t = getenv("TMPDIR");
	char tmp[PATH_MAX], real[PATH_MAX];
	size_t n;
	if (realpath(t && *t ? t : "/tmp", tmp) == NULL || realpath(file, real) == NULL) return 0;
	n = strlen(tmp);
	while (n > 1 && tmp[n - 1] == '/') tmp[--n] = '\0';
	return strncmp(real, tmp, n) == 0 && real[n] == '/';
}

/*
 * Before the first save of FILE in this session (BP->b_backed_up): the
 * version on disk to ~/.chezemax/backup, .~1~ the newest of BACKUPS.
 */
static void backup_before_save(buffer_t *bp, const char *file, const struct stat *sb, int may_link)
{
	char dir[PATH_MAX], m[PATH_MAX], name[PATH_MAX + 16], older[PATH_MAX + 16];
	int k;

	if (bp->b_backed_up) return;
	bp->b_backed_up = 1;
	if (!S_ISREG(sb->st_mode) || in_temp_folder(file)) return;
	if (!chezemax_folder("backup", dir, sizeof dir) || !mangled(file, m, sizeof m)) return;
	if (strlen(dir) + strlen(m) + 8 > sizeof name) return;   /* too long a name */
	for (k = BACKUPS; k > 1; k--) {          /* .~2~ -> .~3~, .~1~ -> .~2~ */
		if (snprintf(older, sizeof older, "%s/%s.~%d~", dir, m, k) >= (int) sizeof older ||
		    snprintf(name, sizeof name, "%s/%s.~%d~", dir, m, k - 1) >= (int) sizeof name) return;
		(void) rename(name, older);
	}
	if (snprintf(name, sizeof name, "%s/%s.~1~", dir, m) >= (int) sizeof name) return;
	(void) unlink(name);
	/* the old file itself, kept: the rename leaves it to the backup (not
	   when the file is written in place: the link would see it change) */
	if (may_link && link(file, name) == 0) return;
	if ((long long) sb->st_size <= AUTOSAVE_LIMIT && copy_file(file, name)) return;
	(void) unlink(name);
}

/*
 * gap.c, save_buffer: the text of BP to FN, safely.  1 written, 0 not
 * (errno says why).
 */
int save_file_safely(buffer_t *bp, const char *fn)
{
	char target[PATH_MAX];
	struct stat sb, lsb;
	int exists, r, in_place;
	mode_t mode;

	/* a symbolic link: the file it names is written, the link stays */
	snprintf(target, sizeof target, "%s", fn);
	if (lstat(fn, &lsb) == 0 && S_ISLNK(lsb.st_mode)) {
		char real[PATH_MAX];
		if (realpath(fn, real) != NULL) snprintf(target, sizeof target, "%s", real);
	}
	exists = stat(target, &sb) == 0;
	if (exists && !S_ISREG(sb.st_mode)) return write_in_place(bp, target, 0666);
	if (exists) {
		mode = sb.st_mode & 07777;
	} else {
		mode_t mask = umask(0);
		umask(mask);
		mode = 0666 & ~mask;
	}
	/* in place: other hard links (a rename would break them), another
	   owner (it would change), a folder that takes no new file */
	{
		char dir[PATH_MAX], *slash;
		snprintf(dir, sizeof dir, "%s", target);
		slash = strrchr(dir, '/');
		if (slash == dir) dir[1] = '\0';
		else if (slash) *slash = '\0';
		else strcpy(dir, ".");
		in_place = (exists && (sb.st_nlink > 1 || sb.st_uid != geteuid())) ||
		           access(dir, W_OK) != 0;
	}
	if (exists && bp->b_fname[0] && strcmp(fn, bp->b_fname) == 0)
		backup_before_save(bp, target, &sb, !in_place);
	if (in_place) return write_in_place(bp, target, mode);
	r = write_by_rename(bp, target, mode);
	if (r < 0) return write_in_place(bp, target, mode);
	return r;
}

/* ------------------------------------------------------------------ */
/* Auto-save                                                           */
/* ------------------------------------------------------------------ */

static long long last_key_ms = 0;
static int keys_since = 0;
static int idle_done = 1;               /* auto-saved since the last key */

static int wants_autosave(buffer_t *bp)
{
	return bp->b_fname[0] && (bp->b_flags & B_MODIFIED) && !(bp->b_flags & B_SPECIAL) &&
	       bp->b_shard == NULL && bp->b_changes != bp->b_autosaved &&
	       document_size(bp) <= AUTOSAVE_LIMIT;
}

/* the buffers that want it, auto-saved; said at the bottom, as Emacs says
 * "Auto-saving...done": 1 when something was said */
static int autosave_all(const char *why)
{
	buffer_t *bp, *one = NULL;
	char name[PATH_MAX + 16];
	int n = 0, failed = 0;
	long long t0 = now_ms();

	for (bp = bheadp; bp != NULL; bp = bp->b_next) {
		if (!wants_autosave(bp)) continue;
		if (autosave_name(bp->b_fname, name, sizeof name) && write_by_rename(bp, name, 0600) == 1) {
			bp->b_autosaved = bp->b_changes;
			one = bp;
			n++;
		} else {
			bp->b_autosaved = bp->b_changes;      /* not again at every key */
			failed++;
		}
	}
	if (failed) msg("Auto-save failed (%s): check ~/.chezemax/auto-save", strerror(errno));
	else if (n == 1) msg("Auto-saving %s...done", one->b_bname);
	else if (n > 1) msg("Auto-saving %d buffers...done", n);
	if (n && backdoor_on)
		backdoor_note("  auto-saved %d buffer(s) in %lld ms, %s", n, now_ms() - t0, why);
	return n > 0 || failed > 0;
}

/* Is BP a changed buffer of a file that is never auto-saved (above 10 MB,
 * in shards)?  display.c marks it ** on the mode line, where others show
 * *: silence would look like safety (Eduardo, dem-autosave-big.txt, 26
 * November 2026). */
int autosave_unprotected(buffer_t *bp)
{
	return bp != NULL && bp->b_fname[0] && (bp->b_flags & B_MODIFIED) && !(bp->b_flags & B_SPECIAL) &&
	       (bp->b_shard != NULL || document_size(bp) > AUTOSAVE_LIMIT);
}

/* The first change of such a buffer also says it, once until it is
 * saved: what ** means. */
static void warn_not_autosaved(buffer_t *bp)
{
	if (!autosave_unprotected(bp) || bp->b_autosave_warned) return;
	/* short, within 80 columns with a name of 20 characters */
	if (bp->b_shard)
		msg("%s: in shards, not auto-saved; ** until C-x C-s saves", bp->b_bname);
	else
		msg("%s: not auto-saved (%.0f MB > %ld MB); ** until C-x C-s saves",
		    bp->b_bname, document_size(bp) / 1048576.0, AUTOSAVE_LIMIT / 1048576);
	bp->b_autosave_warned = 1;
}

/* main.c, after each key */
void autosave_key(void)
{
	last_key_ms = now_ms();
	idle_done = 0;
	warn_not_autosaved(curbp);
	if (++keys_since >= AUTOSAVE_KEYS) {
		keys_since = 0;
		(void) autosave_all("after 300 keys");     /* said at the next display */
	}
}

/* main.c, while the editor waits for a key (every 100 ms).  The tests
 * shorten the wait: $CHEZWEB_AUTOSAVE_IDLE_MS. */
int autosave_idle(void)
{
	static long long wait_ms = -1;
	if (wait_ms < 0) {
		const char *e = getenv("CHEZWEB_AUTOSAVE_IDLE_MS");
		wait_ms = e && atoll(e) > 0 ? atoll(e) : AUTOSAVE_IDLE_MS;
	}
	if (idle_done || now_ms() - last_key_ms < wait_ms) return 0;
	idle_done = 1;
	keys_since = 0;
	return autosave_all("after 30 s without a key");   /* 1: show what it said */
}

/* gap.c, after BP was saved as its own file: its auto-save is not needed */
void autosave_saved(buffer_t *bp)
{
	char name[PATH_MAX + 16];
	bp->b_autosaved = bp->b_changes;
	bp->b_autosave_warned = 0;              /* the next change says it again */
	if (bp->b_fname[0] && autosave_name(bp->b_fname, name, sizeof name)) (void) unlink(name);
}

/* command.c and main.c, after a file was visited: is there newer work? */
void autosave_visited(buffer_t *bp)
{
	char name[PATH_MAX + 16];
	struct stat a, f;

	if (!bp->b_fname[0] || !autosave_name(bp->b_fname, name, sizeof name)) return;
	if (stat(name, &a) != 0) return;
	if (stat(bp->b_fname, &f) == 0 && a.st_mtime < f.st_mtime) return;
	msg("%s has auto-saved changes newer than the file: M-x recover-file restores them",
	    bp->b_bname);
}

/* M-x recover-file: the auto-save's text in place of the buffer's */
void recover_file(void)
{
	char name[PATH_MAX + 16], question[200];
	struct stat a;

	if (!curbp->b_fname[0] || !autosave_name(curbp->b_fname, name, sizeof name) ||
	    stat(name, &a) != 0) {
		msg("No auto-save for this buffer");
		return;
	}
	if (curbp->b_shard || curbp->b_narrowed) {
		msg("Not in a file in shards, nor narrowed (C-x n w widens)");
		return;
	}
	snprintf(question, sizeof question, "Replace the text with its auto-save of %ld bytes (y/n) ?",
		 (long) a.st_size);
	screen_mvaddstr(MSGLINE, 0, question);
	screen_clrtoeol();
	if (!yesno(FALSE)) { msg("Not recovered"); return; }
	fe_delete_region(0, document_size(curbp));
	curbp->b_point = 0;
	if (insert_file(name, TRUE)) {
		curbp->b_point = 0;
		msg("Recovered from the auto-save; C-x C-s saves it, C-/ undoes it");
	}
}

/* ------------------------------------------------------------------ */
/* Cleaning the two folders                                            */
/* ------------------------------------------------------------------ */

/* Is NAME one of ours: !path... in backup/, #!path...# in auto-save/? */
static int ours(const char *folder, const char *name)
{
	size_t n = strlen(name);
	if (!strcmp(folder, "backup")) return name[0] == '!' && n > 1 && name[n - 1] == '~';
	return name[0] == '#' && name[1] == '!' && n > 2 && name[n - 1] == '#';
}

/* The buffer open with changes not saved whose auto-save is NAME, or NULL */
static buffer_t *of_open_work(const char *name)
{
	buffer_t *bp;
	char mine[PATH_MAX + 16];
	const char *base;
	for (bp = bheadp; bp != NULL; bp = bp->b_next) {
		if (!bp->b_fname[0] || !(bp->b_flags & B_MODIFIED)) continue;
		if (!autosave_name(bp->b_fname, mine, sizeof mine)) continue;
		base = strrchr(mine, '/');
		if (base && !strcmp(base + 1, name)) return bp;
	}
	return NULL;
}

/* In ~/.chezemax/FOLDER: count (DELETE 0) or delete (1) our files older
 * than DAYS days (0: all), keeping the auto-saves of open work.  KEPT:
 * those left; OPEN: of them, the auto-saves of open work, and ONE, the
 * buffer of one of them. */
static int sweep(const char *folder, long days, int delete, int *kept, int *open, buffer_t **one)
{
	char dir[PATH_MAX], path[PATH_MAX * 2];
	DIR *d;
	struct dirent *e;
	struct stat sb;
	time_t limit = time(NULL) - (time_t) days * 86400;
	int n = 0;

	*kept = *open = 0;
	*one = NULL;
	if (!chezemax_folder(folder, dir, sizeof dir) || (d = opendir(dir)) == NULL) return 0;
	while ((e = readdir(d)) != NULL) {
		if (!ours(folder, e->d_name)) continue;
		if (snprintf(path, sizeof path, "%s/%s", dir, e->d_name) >= (int) sizeof path) continue;
		if (stat(path, &sb) != 0 || !S_ISREG(sb.st_mode)) continue;
		if (!strcmp(folder, "auto-save")) {
			buffer_t *bp = of_open_work(e->d_name);
			if (bp) { (*kept)++; (*open)++; *one = bp; continue; }
		}
		if (days > 0 && sb.st_mtime > limit) { (*kept)++; continue; }
		if (!delete || unlink(path) == 0) n++;
	}
	closedir(d);
	return n;
}

/* the days asked for: DAYS, or -1 when cancelled or not a number */
static long ask_days(const char *what)
{
	char answer[32] = "30", prompt[100];
	long days;

	snprintf(prompt, sizeof prompt, "Delete %s older than how many days (0: all)? ", what);
	if (!getinput(prompt, answer, sizeof answer, F_NONE)) return -1;
	days = atol(answer);
	if (days < 0 || (days == 0 && strcmp(answer, "0") != 0)) {
		msg("Not a number of days: %s", answer);
		return -1;
	}
	return days;
}

/*
 * M-x delete-old-backups: the backups older than a number of days (30, or
 * as answered; 0: all of them), after a y.  The files, ~/.chezemax/backup,
 * can be looked at first with C-x d.
 */
void delete_old_backups(void)
{
	char question[160];
	long days = ask_days("backups");
	int n, kept, open;
	buffer_t *one;

	if (days < 0) return;
	n = sweep("backup", days, 0, &kept, &open, &one);
	if (n == 0) { msg("No backups to delete (%d kept)", kept); return; }
	snprintf(question, sizeof question, "Delete %d backup%s for good, keep %d (y/n) ?",
		 n, n == 1 ? "" : "s", kept);
	screen_mvaddstr(MSGLINE, 0, question);
	screen_clrtoeol();
	if (!yesno(FALSE)) { msg("Nothing deleted"); return; }
	n = sweep("backup", days, 1, &kept, &open, &one);
	msg("Deleted %d backup%s; %d kept in ~/.chezemax/backup", n, n == 1 ? "" : "s", kept);
}

/*
 * M-x delete-auto-saves: the auto-saves older than a number of days (30,
 * or as answered; 0: all of them), but never those of buffers open now
 * with changes not saved (they would only come back).  An auto-save is
 * the one copy of changes never saved: it asks first.
 */
void delete_auto_saves(void)
{
	char question[200], why[160] = "";
	long days = ask_days("auto-saves");
	int n, kept, open;
	buffer_t *one;

	if (days < 0) return;
	n = sweep("auto-save", days, 0, &kept, &open, &one);
	/* why some stay: the work open now with changes, and the newer */
	if (open == 1)
		snprintf(why, sizeof why, "%s, open with changes (C-x C-s or C-x k it first)", one->b_bname);
	else if (open > 1)
		snprintf(why, sizeof why, "%d of buffers open with changes", open);
	if (kept > open)
		snprintf(why + strlen(why), sizeof why - strlen(why), "%s%d newer than %ld days",
			 open ? "; " : "", kept - open, days);
	if (n == 0) { msg("No auto-saves to delete; kept: %s", kept ? why : "none there"); return; }
	snprintf(question, sizeof question,
		 "Delete %d auto-save%s of changes never saved%s%s (y/n) ?",
		 n, n == 1 ? "" : "s", kept ? "; kept: " : "", why);
	screen_mvaddstr(MSGLINE, 0, question);
	screen_clrtoeol();
	if (!yesno(FALSE)) { msg("Nothing deleted"); return; }
	n = sweep("auto-save", days, 1, &kept, &open, &one);
	msg("Deleted %d auto-save%s%s%s", n, n == 1 ? "" : "s", kept ? "; kept: " : "", why);
}

#else   /* the browser: its page saves */

int save_file_safely(buffer_t *bp, const char *fn) { (void) bp; (void) fn; errno = ENOSYS; return 0; }
void autosave_key(void) {}
int autosave_idle(void) { return 0; }
int autosave_unprotected(buffer_t *bp) { (void) bp; return 0; }
void autosave_saved(buffer_t *bp) { (void) bp; }
void autosave_visited(buffer_t *bp) { (void) bp; }
void recover_file(void) { msg("No auto-save in the browser"); }
void delete_old_backups(void) { msg("No backups in the browser"); }
void delete_auto_saves(void) { msg("No auto-saves in the browser"); }

#endif
