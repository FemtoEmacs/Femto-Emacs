/*
 * shard.c -- files too large to hold: one shard in the buffer at a time,
 * as Emacs's VLF (Very Large File) does.
 *
 * A file above shard_threshold bytes (C-x C-f), or any file (M-x
 * find-file-shards), is cut into shards of about shard_bytes, each ending
 * at a newline (a line longer than twice that is cut at a character
 * boundary, never inside a UTF-8 character).  The index, built in one pass
 * when the file is opened, gives each shard its offset, its length and the
 * number of newlines in it.  Only the current shard is in the buffer; every
 * command works on it as on any text, and the region, query-replace and
 * undo belong to it.
 *
 *   C-c C-v n, C-c C-v p    the next, the previous shard (shards.scm)
 *   C-c C-v g               shard number N
 *   C-c C-v [, C-c C-v ]    the first shard, the last one
 *   M-g                     line N of the whole file
 *   C-s                     at a failing search, C-s again looks in the
 *                           shards that follow (search.c)
 *   C-x C-s                 the whole file: shards in order to a temporary
 *                           file, renamed over the original at the end
 *
 * An edited shard keeps its text in the index when the cursor goes to
 * another one, so nothing is saved until C-x C-s.  The mode line shows the
 * shard ("[3/41]") and the line of the whole file.  The browser window does
 * not shard (it loads whole files, as before).  Lean/shards.lean states
 * what saving must do and proves it of a model.
 */
#include "header.h"
#include <errno.h>
#include <sys/stat.h>

#ifdef __EMSCRIPTEN__
long shard_threshold = 0;               /* never: the browser loads whole files */
#else
long shard_threshold = 1L << 30;        /* 1 GB */
#endif
long shard_bytes = 16L << 20;           /* 16 MB a shard */

typedef struct shard_entry {
	long long off, len;     /* in the file as read or last saved */
	long lines;             /* newlines in the shard */
	char_t *text;           /* the edited text, or NULL: the file's bytes */
	long long tlen;
} shard_entry;

struct shard_t {
	char path[NAME_MAX + 1];
	long long size, mtime;  /* the file, as indexed */
	shard_entry *e;
	int n, cap, cur;
	unsigned long changes;  /* b_changes when the current shard was read */
};

/* (fe-shard-threshold N), (fe-shard-size N): set when N > 0; the setting */
long fe_shard_threshold(long n) { if (n > 0) shard_threshold = n; return shard_threshold; }
long fe_shard_size(long n) { if (n >= 64) shard_bytes = n; return shard_bytes; }

static long long mtime_ns(const struct stat *sb)
{
#if defined(__APPLE__)
	return (long long) sb->st_mtimespec.tv_sec * 1000000000LL + sb->st_mtimespec.tv_nsec;
#elif defined(_WIN32)
	return (long long) sb->st_mtime * 1000000000LL;
#else
	return (long long) sb->st_mtim.tv_sec * 1000000000LL + sb->st_mtim.tv_nsec;
#endif
}

static int add(struct shard_t *s, long long off, long long len, long lines)
{
	if (s->n == s->cap) {
		int cap = s->cap ? 2 * s->cap : 64;
		shard_entry *e = realloc(s->e, (size_t) cap * sizeof *e);
		if (e == NULL) return 0;
		s->e = e;
		s->cap = cap;
	}
	s->e[s->n].off = off;
	s->e[s->n].len = len;
	s->e[s->n].lines = lines;
	s->e[s->n].text = NULL;
	s->e[s->n].tlen = 0;
	s->n++;
	return 1;
}

/* The index: shards of at least shard_bytes ending at a newline; a run of
 * twice that without one is cut before a byte that starts a character */
static int build_index(struct shard_t *s, FILE *fp)
{
	static unsigned char block[1 << 20];
	long long at = 0, start = 0;
	long lines = 0;
	size_t got;

	while ((got = fread(block, 1, sizeof block, fp)) > 0) {
		for (size_t k = 0; k < got; k++, at++) {
			unsigned char c = block[k];
			if (at - start >= 2 * (long long) shard_bytes && (c & 0xC0) != 0x80) {
				if (!add(s, start, at - start, lines)) return 0;
				start = at;
				lines = 0;
			}
			if (c == '\n') {
				lines++;
				if (at + 1 - start >= shard_bytes) {
					if (!add(s, start, at + 1 - start, lines)) return 0;
					start = at + 1;
					lines = 0;
				}
			}
		}
	}
	if (ferror(fp)) return 0;
	if (start < at || s->n == 0)
		if (!add(s, start, at - start, lines)) return 0;
	return 1;
}

static int file_moved(struct shard_t *s);

static int any_edited(struct shard_t *s)
{
	for (int k = 0; k < s->n; k++)
		if (s->e[k].text != NULL) return 1;
	return 0;
}

/* Is a shard other than the current one edited? */
int shard_others_edited(buffer_t *bp)
{
	struct shard_t *s = bp->b_shard;
	for (int k = 0; s && k < s->n; k++)
		if (k != s->cur && s->e[k].text != NULL) return 1;
	return 0;
}

/* Does BP hold the bytes [OFF, OFF + LEN) of the file?  Read in blocks */
static int same_as_file(buffer_t *bp, struct shard_t *s, long long off, long long len)
{
	static unsigned char block[1 << 16];
	FILE *fp;
	long long at = 0;
	int same = 1;

	if ((long long) document_size(bp) != len || file_moved(s)) return 0;
	if ((fp = fopen(s->path, "rb")) == NULL || fseeko(fp, (off_t) off, SEEK_SET) != 0) {
		if (fp) fclose(fp);
		return 0;
	}
	while (same && at < len) {
		size_t want = len - at < (long long) sizeof block ? (size_t) (len - at) : sizeof block;
		if (fread(block, 1, want, fp) != want) { same = 0; break; }
		for (size_t k = 0; k < want; k++)
			if (*ptr(bp, (point_t) (at + (long long) k)) != block[k]) { same = 0; break; }
		at += (long long) want;
	}
	fclose(fp);
	return same;
}

/* The lines before shard K: the newlines of the shards before it */
static long lines_before(struct shard_t *s, int k)
{
	long n = 0;
	for (int j = 0; j < k; j++) n += s->e[j].lines;
	return n;
}

static void label(buffer_t *bp)
{
	struct shard_t *s = bp->b_shard;
	snprintf(bp->b_shard_label, sizeof bp->b_shard_label, " [%d/%d]", s->cur + 1, s->n);
	bp->b_line_base = lines_before(s, s->cur);
}

static void count_lines(buffer_t *bp, long *lines)
{
	point_t end = document_size(bp);
	long n = 0;
	for (point_t p = 0; p < end; p++)
		if (*ptr(bp, p) == '\n') n++;
	*lines = n;
}

/* Keep the current shard's text in the index if it was edited since it
 * was read (the change counter moved: an edit, a fold, a narrowing) */
static int keep(buffer_t *bp)
{
	struct shard_t *s = bp->b_shard;
	shard_entry *e = &s->e[s->cur];
	point_t size = document_size(bp), before = bp->b_gap - bp->b_buf;
	char_t *text;

	if (bp->b_changes == s->changes) return 1;
	/* edited and undone, or typed and deleted: the file's bytes again */
	if (same_as_file(bp, s, e->off, e->len)) {
		free(e->text);
		e->text = NULL;
		s->changes = bp->b_changes;
		return 1;
	}
	text = malloc((size_t) size + 1);
	if (text == NULL) { msg("No memory to keep this shard's changes"); return 0; }
	memcpy(text, bp->b_buf, (size_t) before);
	memcpy(text + before, bp->b_egap, (size_t) (bp->b_ebuf - bp->b_egap));
	free(e->text);
	e->text = text;
	e->tlen = size;
	count_lines(bp, &e->lines);
	s->changes = bp->b_changes;
	return 1;
}

/* Did another program change the file since it was indexed or saved? */
static int file_moved(struct shard_t *s)
{
	struct stat sb;
	return stat(s->path, &sb) != 0 || (long long) sb.st_size != s->size || mtime_ns(&sb) != s->mtime;
}

/* Put shard K into BP, point at its start (AT_END: at its end) */
static int read_shard(buffer_t *bp, int k, int at_end)
{
	struct shard_t *s = bp->b_shard;
	shard_entry *e = &s->e[k];
	long long len = e->text ? e->tlen : e->len;
	FILE *fp = NULL;

	if (e->text == NULL) {
		if (file_moved(s)) {
			msg("File changed on disk; C-x C-v reads it again.");
			return 0;
		}
		if ((fp = fopen(s->path, "rb")) == NULL || fseeko(fp, (off_t) e->off, SEEK_SET) != 0) {
			if (fp) fclose(fp);
			msg(m_open, s->path);
			return 0;
		}
	}
	if (bp->b_narrowed) {                  /* narrow.c: a shard is shown whole */
		bp->b_narrowed = 0;
		bp->b_narrow_start = bp->b_narrow_tail = 0;
	}
	zero_buffer(bp);                        /* 'r': no history, no folds */
	if (bp->b_egap - bp->b_gap < len && !growgap(bp, (point_t) len)) {
		if (fp) fclose(fp);
		return 0;
	}
	if (e->text) memcpy(bp->b_gap, e->text, (size_t) len);
	else {
		size_t got = fread(bp->b_gap, 1, (size_t) len, fp);
		fclose(fp);
		if ((long long) got != len) { msg("Could not read shard %d of %s", k + 1, s->path); return 0; }
	}
	bp->b_gap += len;
	bp->b_point = at_end ? (point_t) len : 0;
	bp->b_page = 0;
	record_change(bp, 'r', 0, NULL, 0);
	s->cur = k;
	s->changes = bp->b_changes;
	if (any_edited(s)) add_mode(bp, B_MODIFIED);
	else delete_mode(bp, B_MODIFIED);
	label(bp);
	return 1;
}

/* N bytes for people: "512 KB", "16 MB", "1.3 GB" */
static const char *amount(long long n, char *out, size_t size)
{
	if (n < (1LL << 20)) snprintf(out, size, "%lld KB", n >> 10);
	else if (n < (1LL << 30)) snprintf(out, size, "%lld MB", n >> 20);
	else snprintf(out, size, "%.1f GB", (double) n / (double) (1LL << 30));
	return out;
}

static void tell(buffer_t *bp)
{
	struct shard_t *s = bp->b_shard;
	shard_entry *e = &s->e[s->cur];
	long first = lines_before(s, s->cur) + 1;
	long lines;
	count_lines(bp, &lines);                /* the shard as it is now */
	char at[32], all[32];
	msg("Shard %d/%d: lines %ld-%ld, from %s of %s; C-c C-v n/p/g, M-g a line",
	    s->cur + 1, s->n, first, first + (lines ? lines - 1 : 0),
	    amount(e->off, at, sizeof at), amount(s->size, all, sizeof all));
}

int shard_wanted(const char *fn)
{
	struct stat sb;
	return shard_threshold > 0 && stat(fn, &sb) == 0 && S_ISREG(sb.st_mode) &&
	       (long long) sb.st_size > (long long) shard_threshold;
}

/* Visit FN in BP by shards; FALSE if it cannot be read */
int shard_open(buffer_t *bp, const char *fn)
{
	struct shard_t *s;
	struct stat sb;
	FILE *fp;

	if (stat(fn, &sb) != 0 || !S_ISREG(sb.st_mode) || (fp = fopen(fn, "rb")) == NULL) {
		msg(m_open, fn);
		return FALSE;
	}
	s = calloc(1, sizeof *s);
	if (s == NULL) { fclose(fp); return FALSE; }
	safe_strncpy(s->path, (char *) fn, NAME_MAX);
	s->size = (long long) sb.st_size;
	s->mtime = mtime_ns(&sb);
	{
		char all[32];
		msg("Indexing %s (%s)...", fn, amount(s->size, all, sizeof all));
	}
	screen_refresh();
	if (!build_index(s, fp)) {
		fclose(fp);
		free(s->e);
		free(s);
		msg("Could not index %s", fn);
		return FALSE;
	}
	fclose(fp);
	shard_free(bp);
	bp->b_shard = s;
	if (!read_shard(bp, 0, 0)) {
		shard_free(bp);
		return FALSE;
	}
	buffer_remember_disk(bp, fn);
	tell(bp);
	return TRUE;
}

void shard_free(buffer_t *bp)
{
	struct shard_t *s = bp->b_shard;
	if (s == NULL) return;
	for (int k = 0; k < s->n; k++) free(s->e[k].text);
	free(s->e);
	free(s);
	bp->b_shard = NULL;
	bp->b_shard_label[0] = '\0';
	bp->b_line_base = 0;
}

int shard_current(buffer_t *bp) { return bp->b_shard ? bp->b_shard->cur : -1; }

/* (fe-shard-current): the current buffer's shard, from 0, or -1 */
long fe_shard_current(void) { return shard_current(curbp); }

/* Go to shard K of BP (the current buffer), keeping the current one's edits */
int shard_switch(buffer_t *bp, int k, int at_end)
{
	struct shard_t *s = bp->b_shard;
	if (s == NULL || k < 0 || k >= s->n) return 0;
	if (k == s->cur) return 1;
	if (!keep(bp)) return 0;
	return read_shard(bp, k, at_end);
}

static int sharded(void)
{
	if (curbp->b_shard) return 1;
	msg("Not a file in shards (M-x find-file-shards opens one)");
	return 0;
}

void shard_next(void)
{
	if (!sharded()) return;
	if (curbp->b_shard->cur + 1 >= curbp->b_shard->n) { msg("The last shard"); return; }
	if (shard_switch(curbp, curbp->b_shard->cur + 1, 0)) tell(curbp);
}

void shard_previous(void)
{
	if (!sharded()) return;
	if (curbp->b_shard->cur == 0) { msg("The first shard"); return; }
	if (shard_switch(curbp, curbp->b_shard->cur - 1, 1)) tell(curbp);
}

/* C-c C-v [ and ]: the first shard, at its start; the last, at its end */
void shard_first(void)
{
	if (!sharded()) return;
	if (!shard_switch(curbp, 0, 0)) return;
	curbp->b_point = 0;
	tell(curbp);
}

void shard_last(void)
{
	if (!sharded()) return;
	if (!shard_switch(curbp, curbp->b_shard->n - 1, 1)) return;
	curbp->b_point = document_size(curbp);
	tell(curbp);
}

void shard_goto(void)
{
	int k;
	if (!sharded()) return;
	if (!getinput("Shard: ", (char *) response_buf, STRBUF_S, F_CLEAR)) return;
	k = atoi((char *) response_buf);
	if (k < 1 || k > curbp->b_shard->n) { msg("No shard %d: there are %d", k, curbp->b_shard->n); return; }
	if (shard_switch(curbp, k - 1, 0)) tell(curbp);
}

/* M-g in a file in shards: LINE of the whole file */
/* does shard K end with a newline?  Not when a line longer than two
 * shards was cut inside (build_index): the next shard starts in it */
static int ends_with_newline(struct shard_t *s, int k)
{
	shard_entry *e = &s->e[k];
	FILE *fp;
	int c;
	if (e->text) return e->tlen > 0 && e->text[e->tlen - 1] == '\n';
	if (e->len <= 0 || (fp = fopen(s->path, "rb")) == NULL) return 1;
	c = fseeko(fp, (off_t) (e->off + e->len - 1), SEEK_SET) == 0 ? getc(fp) : '\n';
	fclose(fp);
	return c == '\n';
}

/*
 * M-g: line LINE of the whole file.  It starts after newline LINE - 1:
 * in the shard that holds that newline, or at the start of the next one
 * when the newline ends its shard.  Taking a shard's first line for the
 * line after the newlines before it is wrong for a shard that starts
 * inside a long line: M-g to that line went to the cut, not to the start
 * of the line (tests/shard-boundary.sh).
 */
int shard_goto_line(int line)
{
	struct shard_t *s = curbp->b_shard;
	long base = 0, need = line - 1;
	int k;
	point_t p;

	if (line < 1) return 0;
	if (!keep(curbp)) return 0;
	/* a line past the end: stay where it is */
	{
		long total = 1;
		for (k = 0; k < s->n; k++) total += s->e[k].lines;
		if (line > total) return 0;
	}
	if (need == 0) {
		if (!shard_switch(curbp, 0, 0)) return 0;
		curbp->b_point = 0;
		return 1;
	}
	/* the shard that holds newline NEED */
	for (k = 0; k + 1 < s->n && base + s->e[k].lines < need; k++)
		base += s->e[k].lines;
	if (base + s->e[k].lines == need && k + 1 < s->n && ends_with_newline(s, k)) {
		if (!shard_switch(curbp, k + 1, 0)) return 0;
		curbp->b_point = 0;
		return 1;
	}
	if (!shard_switch(curbp, k, 0)) return 0;
	p = line_to_point((int) (need - base + 1));
	if (p == -1) return 0;
	curbp->b_point = p;
	return 1;
}

/* M-x find-file-shards: any file, in shards */
void find_file_shards(void)
{
	buffer_t *bp;
	if (!getfilename("Find file in shards: ", (char *) response_buf, NAME_MAX)) return;
	bp = find_buffer_by_fname((char *) response_buf);
	disassociate_b(curwp);
	curbp = bp;
	associate_b2w(curbp, curwp);
	if (bp->b_shard == NULL) {
		if (shard_open(bp, (char *) response_buf))
			safe_strncpy(bp->b_fname, (char *) response_buf, NAME_MAX);
	} else
		tell(bp);
}

/* Is STEXT in [TEXT, TEXT + LEN)?  Its offset, or -1 */
static long long find_in(const char_t *text, long long len, const char *stext)
{
	size_t n = strlen(stext);
	if (n == 0 || (long long) n > len) return -1;
	for (long long i = 0; i + (long long) n <= len; i++)
		if (text[i] == (char_t) stext[0] && memcmp(text + i, stext, n) == 0) return i;
	return -1;
}

/* C-s at a failing search: STEXT in the shards after the current one.
 * Point after the match, as C-s leaves it; 1 if found */
int shard_search_forward(const char *stext)
{
	struct shard_t *s = curbp->b_shard;
	char_t *buf = NULL;
	FILE *fp = NULL;
	int found = -1;
	long long at = -1;

	if (s == NULL) return 0;
	if (!keep(curbp)) return 0;
	for (int k = s->cur + 1; k < s->n && found < 0; k++) {
		shard_entry *e = &s->e[k];
		msg("Searching shard %d/%d...", k + 1, s->n);
		screen_refresh();
		if (e->text) {
			at = find_in(e->text, e->tlen, stext);
		} else {
			if (fp == NULL) {
				if (file_moved(s) || (fp = fopen(s->path, "rb")) == NULL) {
					msg("File changed on disk; C-x C-v reads it again.");
					break;
				}
			}
			char_t *nb = realloc(buf, (size_t) e->len + 1);
			if (nb == NULL) break;
			buf = nb;
			if (fseeko(fp, (off_t) e->off, SEEK_SET) != 0 ||
			    fread(buf, 1, (size_t) e->len, fp) != (size_t) e->len)
				break;
			at = find_in(buf, e->len, stext);
		}
		if (at >= 0) found = k;
	}
	if (fp) fclose(fp);
	free(buf);
	if (found < 0 || !shard_switch(curbp, found, 0)) return 0;
	curbp->b_point = (point_t) (at + (long long) strlen(stext));
	return 1;
}

static int copy_range(FILE *from, long long off, long long len, FILE *to)
{
	static unsigned char block[1 << 20];
	if (fseeko(from, (off_t) off, SEEK_SET) != 0) return 0;
	while (len > 0) {
		size_t want = len < (long long) sizeof block ? (size_t) len : sizeof block;
		if (fread(block, 1, want, from) != want || fwrite(block, 1, want, to) != want) return 0;
		len -= (long long) want;
	}
	return 1;
}

/*
 * C-x C-s (and C-x C-w) of a file in shards: every shard in order, the
 * edited ones from the index, the others from the file, to a temporary
 * file beside FN, renamed over FN at the end; a failure leaves FN as it
 * was.  Then the index describes the new file.
 */
int shard_save(buffer_t *bp, char *fn)
{
	extern int save_overwrites;
	struct shard_t *s = bp->b_shard;
	char tmp[NAME_MAX + 32];
	struct stat sb;
	FILE *in = NULL, *out;
	int same = !strcmp(fn, s->path), ok = 1, edited;
	long long off = 0;

	if (!keep(bp)) return FALSE;
	edited = any_edited(s);
	if (same && !edited && !save_overwrites) {
		if (file_moved(s)) msg("File changed on disk; C-x C-w overwrites it. C-x C-v reads it again.");
		else msg("(No changes need to be saved)");
		return TRUE;
	}
	if (same && !save_overwrites && file_moved(s)) {
		const char *name = strrchr(fn, '/');
		char question[NAME_MAX + 80];
		snprintf(question, sizeof question, "%s changed on disk since it was read or saved; save over it (y/n) ?",
			 name ? name + 1 : fn);
		screen_mvaddstr(MSGLINE, 0, question);
		screen_clrtoeol();
		if (!yesno(FALSE)) {
			msg("Not saved: %s keeps the other program's version", name ? name + 1 : fn);
			return FALSE;
		}
	}
	snprintf(tmp, sizeof tmp, "%s.chezweb-save", fn);
	if ((in = fopen(s->path, "rb")) == NULL) { msg(m_open, s->path); return FALSE; }
	if ((out = fopen(tmp, "wb")) == NULL) { fclose(in); msg(m_open, tmp); return FALSE; }
	msg("Writing %s...", fn);
	screen_refresh();
	for (int k = 0; k < s->n && ok; k++) {
		shard_entry *e = &s->e[k];
		if (e->text) ok = fwrite(e->text, 1, (size_t) e->tlen, out) == (size_t) e->tlen;
		else ok = copy_range(in, e->off, e->len, out);
	}
	fclose(in);
	if (fclose(out) != 0) ok = 0;
	if (ok && stat(s->path, &sb) == 0) (void) chmod(tmp, sb.st_mode & 07777);
	if (!ok || rename(tmp, fn) != 0) {
		remove(tmp);
		msg("Not saved: could not write %s (%s)", fn, strerror(errno));
		return FALSE;
	}
	/* the index of the new file */
	for (int k = 0; k < s->n; k++) {
		shard_entry *e = &s->e[k];
		if (e->text) { e->len = e->tlen; free(e->text); e->text = NULL; }
		e->off = off;
		off += e->len;
	}
	safe_strncpy(s->path, fn, NAME_MAX);
	s->size = off;
	if (stat(fn, &sb) == 0) s->mtime = mtime_ns(&sb);
	delete_mode(bp, B_MODIFIED);
	record_change(bp, 's', 0, NULL, 0);
	s->changes = bp->b_changes;
	buffer_remember_disk(bp, fn);
	label(bp);
	msg(m_saved, fn, (long) off);
	return TRUE;
}
