/*
 * gap.c, Femto Emacs, Hugh Barney, Public Domain, 2016
 * Derived from: Anthony's Editor January 93, (Public Domain 1991, 1993 by Anthony Howe)
 */

#include <sys/stat.h>
#include <errno.h>
#include "header.h"

/*
 * Enlarge gap by n chars, position of gap cannot change.
 *
 * One byte more than the buffer is allocated, after b_ebuf, and kept 0: a
 * sentinel.  The commands read the byte at point (*ptr(bp, point)) without
 * asking whether point is at the end of the text, where ptr gives b_ebuf;
 * C-f at the end of the text, C-k on the last line, M-f, read it.  Without
 * the sentinel that was one byte past the allocation, which no test saw
 * until tests/fuzz-core.c ran under AddressSanitizer (21 November 2026).
 * With it, every such read finds 0, as at the end of a C string.
 */
int growgap(buffer_t *bp, point_t n)
{
	char_t *new;
	point_t buflen, newlen, xgap, xegap;

	assert(bp->b_buf <= bp->b_gap);
	assert(bp->b_gap <= bp->b_egap);
	assert(bp->b_egap <= bp->b_ebuf);

	xgap = bp->b_gap - bp->b_buf;
	xegap = bp->b_egap - bp->b_buf;
	buflen = bp->b_ebuf - bp->b_buf;

	/* reduce number of reallocs by growing by a minimum amount, and by an
	 * eighth of the buffer: by 512 bytes alone, M-% of 100,000 foo by
	 * barbaz moved all the text after the gap 600 times, and typing in a
	 * large file every 512 keys (tests/complexity.sh) */
	n = (n < MIN_GAP_EXPAND ? MIN_GAP_EXPAND : n);
	if (n < buflen / 8) n = buflen / 8;
	newlen = buflen + n * sizeof (char_t);

	if (buflen == 0) {
		if (newlen < 0 || MAX_SIZE_T < newlen)
			fatal(f_alloc);
		new = (char_t*) malloc((size_t) newlen + 1);
		if (new == NULL)
			fatal(f_alloc);	/* Cannot edit a file without a buffer. */
	} else {
		if (newlen < 0 || MAX_SIZE_T < newlen) {
			msg(m_alloc);
			return (FALSE);
		}
		new = (char_t*) realloc(bp->b_buf, (size_t) newlen + 1);
		if (new == NULL) {
			msg(m_alloc); /* Report non-fatal error. */
			return (FALSE);
		}
	}

	/* Relocate pointers in new buffer and append the new
	 * extension to the end of the gap.
	 */
	bp->b_buf = new;
	bp->b_gap = bp->b_buf + xgap;
	bp->b_ebuf = bp->b_buf + buflen;
	/* the text after the gap moves to the end of the new buffer */
	memmove(bp->b_buf + newlen - (buflen - xegap), bp->b_buf + xegap, (size_t) (buflen - xegap));
	bp->b_egap = bp->b_buf + newlen - (buflen - xegap);
	bp->b_ebuf = bp->b_buf + newlen;
	*bp->b_ebuf = 0;                        /* the sentinel */

	assert(bp->b_buf < bp->b_ebuf);          /* Buffer must exist. */
	assert(bp->b_buf <= bp->b_gap);
	assert(bp->b_gap < bp->b_egap);          /* Gap must grow only. */
	assert(bp->b_egap <= bp->b_ebuf);
	return (TRUE);
}

point_t movegap(buffer_t *bp, point_t offset)
{
	char_t *p = ptr(bp, offset);
	while (p < bp->b_gap)
		*--bp->b_egap = *--bp->b_gap;
	while (bp->b_egap < p)
		*bp->b_gap++ = *bp->b_egap++;
	assert(bp->b_gap <= bp->b_egap);
	assert(bp->b_buf <= bp->b_gap);
	assert(bp->b_egap <= bp->b_ebuf);
	return (pos(bp, bp->b_egap));
}

/* Given a buffer offset, convert it to a pointer into the buffer */
char_t * ptr(buffer_t *bp, register point_t offset)
{
	if (offset < 0)
		return (bp->b_buf);
	return (bp->b_buf+offset + (bp->b_buf + offset < bp->b_gap ? 0 : bp->b_egap-bp->b_gap));
}

/* Given a pointer into the buffer, convert it to a buffer offset */
point_t pos(buffer_t *bp, register char_t *cp)
{
	assert(bp->b_buf <= cp && cp <= bp->b_ebuf);
	return (cp - bp->b_buf - (cp < bp->b_egap ? 0 : bp->b_egap - bp->b_gap));
}

int posix_file(char *fn)
{
	if (fn[0] == '_')
		return (FALSE);

	for (; *fn != '\0'; ++fn) {
		if (!isalnum((unsigned char)*fn) && *fn != '.' && *fn != '_' && *fn != '-' && *fn != '/'
#ifdef _WIN32
		    && *fn != '\\' && *fn != ':'
#endif
		    )
			return (FALSE);
	}
	return (TRUE);
}

/*
 * The folder of FN does not exist (a first ~/.chezemax/init.scm, say):
 * ask, as Emacs does, and make it with the folders above it.  Only on an
 * explicit save, and only after a "y".
 */
static int make_parent_folders(char *fn)
{
	char dir[NAME_MAX + 1], *slash, *p;
	struct stat sb;

	if (strlen(fn) > NAME_MAX || (slash = strrchr(fn, '/')) == NULL || slash == fn)
		return (FALSE);
	memcpy(dir, fn, (size_t) (slash - fn));
	dir[slash - fn] = '\0';
	if (stat(dir, &sb) == 0)
		return (FALSE);                 /* it exists: some other reason */
	screen_mvaddstr(MSGLINE, 0, "Folder ");
	screen_addstr(dir);
	screen_addstr(" does not exist; create it (y/n) ?");
	screen_clrtoeol();
	if (!yesno(FALSE))
		return (FALSE);
	for (p = dir + 1; ; p++) {
		if (*p == '/' || *p == '\0') {
			char c = *p;
			*p = '\0';
			if (stat(dir, &sb) != 0 && mkdir(dir, 0755) != 0 && errno != EEXIST)
				return (FALSE);
			*p = c;
			if (c == '\0')
				break;
		}
	}
	return (TRUE);
}

/*
 * Another program may change the file while it is open here.  Emacs's
 * rule, the second of its two (17 November 2026): C-x C-s over a file
 * changed on disk since it was read or saved asks first, instead of
 * writing over the other program's change without a word.  The buffer
 * keeps the file as last read or written: its modification time and
 * size.  Not in the browser's editor (web/), whose saves go through the
 * native window, as before; the native window refreshes this record when
 * it writes or reloads the file for the browser (browser-save.h).
 */
static long long file_time_ns(const struct stat *sb)
{
#if defined(__APPLE__)
	return (long long) sb->st_mtimespec.tv_sec * 1000000000LL + sb->st_mtimespec.tv_nsec;
#else
	return (long long) sb->st_mtim.tv_sec * 1000000000LL + sb->st_mtim.tv_nsec;
#endif
}

void buffer_remember_disk(buffer_t *bp, const char *fn)
{
	struct stat sb;
	if (bp == NULL || fn == NULL || !*fn) return;
	if (stat(fn, &sb) == 0 && S_ISREG(sb.st_mode)) {
		bp->b_disk = 1;
		bp->b_disk_time = file_time_ns(&sb);
		bp->b_disk_size = (long long) sb.st_size;
	} else
		bp->b_disk = 2;
}

#ifndef __EMSCRIPTEN__
/* Has FN changed on disk since BP last read or wrote it? */
static int disk_changed(buffer_t *bp, const char *fn)
{
	struct stat sb;
	int there = stat(fn, &sb) == 0 && S_ISREG(sb.st_mode);
	if (bp->b_disk == 2) return there;
	if (bp->b_disk != 1) return 0;
	return !there || file_time_ns(&sb) != bp->b_disk_time || (long long) sb.st_size != bp->b_disk_size;
}
#endif

/* C-x C-w writes the file it names, whatever the disk holds: the
 * message about a file changed on disk points to it (command.c). */
int save_overwrites = 0;

/* Does FN hold exactly the text of BP?  A file whose time changed but
 * not its text (touch, a backup tool, git) is not another version. */
static int file_is_buffer(buffer_t *bp, const char *fn)
{
	FILE *fp;
	point_t size = document_size(bp), at = 0;
	char chunk[8192];
	size_t got;
	int same = 1;
	struct stat sb;
	if (stat(fn, &sb) != 0 || (long long) sb.st_size != (long long) size) return 0;
	if ((fp = fopen(fn, "rb")) == NULL) return 0;
	while (same && (got = fread(chunk, 1, sizeof chunk, fp)) > 0) {
		for (size_t i = 0; i < got; i++, at++)
			if (at >= size || (char) *ptr(bp, at) != chunk[i]) { same = 0; break; }
	}
	fclose(fp);
	return same && at == size;
}

int save_buffer(buffer_t *bp, char *fn)
{
	FILE *fp;
	point_t length;
	struct stat saved_file;

	if (bp->b_shard)                        /* shard.c: the whole file */
		return shard_save(bp, fn);

	/* Save As and a never-created file still need an actual write. */
	if (!save_overwrites && !(bp->b_flags & B_MODIFIED) && !strcmp(fn, bp->b_fname) &&
	    stat(fn, &saved_file) == 0 && S_ISREG(saved_file.st_mode)) {
#ifndef __EMSCRIPTEN__
		/* Nothing to write, but another program changed the file: this
		 * buffer shows an older text, and "No changes" hid it (Emacs
		 * saved, Chezweb kept the old lines; 18 November 2026).  Only
		 * said; the buffer is reloaded by hand, with C-x C-v. */
		if (disk_changed(bp, fn) && !file_is_buffer(bp, fn)) {
			msg("File changed on disk; C-x C-w overwrites it. C-x C-v reads it again.");
			return TRUE;
		}
		buffer_remember_disk(bp, fn);   /* only touched (touch, git): the same text */
#endif
		msg("(No changes need to be saved)");
		return TRUE;
	}
	if (!posix_file(fn)) {
		msg(m_badname);
		return (FALSE);
	}
#ifndef __EMSCRIPTEN__
	if (!save_overwrites && !strcmp(fn, bp->b_fname) && disk_changed(bp, fn)) {
		char question[NAME_MAX + 80];
		const char *name = strrchr(fn, '/');
		snprintf(question, sizeof question, "%s changed on disk since it was read or saved; save over it (y/n) ?",
			 name ? name + 1 : fn);
		screen_mvaddstr(MSGLINE, 0, question);
		screen_clrtoeol();
		if (!yesno(FALSE)) {
			msg("Not saved: %s keeps the other program's version", name ? name + 1 : fn);
			return (FALSE);
		}
	}
#endif
#ifndef __EMSCRIPTEN__
	/* backup.c: a temporary file, forced onto the disk and renamed over
	   the file, and the first save of a session keeps a backup */
	(void) fp; (void) length;
	{
		struct stat parent;
		char dir[NAME_MAX + 1], *slash;
		safe_strncpy(dir, fn, NAME_MAX);
		slash = strrchr(dir, '/');
		if (slash && slash != dir) { *slash = '\0'; if (stat(dir, &parent) != 0) (void) make_parent_folders(fn); }
	}
	if (!save_file_safely(bp, fn)) {
		msg("%s not saved: %s", fn, strerror(errno));
		return (FALSE);
	}
#else
	fp = fopen(fn, "wb");
	if (fp == NULL && errno == ENOENT && make_parent_folders(fn))
		fp = fopen(fn, "wb");
	if (fp == NULL) {
		msg(m_open, fn);
		return (FALSE);
	}
	(void) movegap(bp, (point_t) 0);
	length = (point_t) (bp->b_ebuf - bp->b_egap);
	if (fwrite(bp->b_egap, sizeof (char), (size_t) length, fp) != length) {
		msg(m_write, fn);
		return (FALSE);
	}
	if (fclose(fp) != 0) {
		msg(m_close, fn);
		return (FALSE);
	}
#endif
 if (!screen_save_file(fn)) {
  msg("Save failed; changes are still unsaved. See the browser notice.");
  return FALSE;
 }
	delete_mode(bp, B_MODIFIED);
	record_change(bp, 's', 0, NULL, 0);
	buffer_remember_disk(bp, fn);     /* the file is now this text */
	if (!strcmp(fn, bp->b_fname)) {
		extern void chezweb_saved(buffer_t *);
		chezweb_saved(bp);
		autosave_saved(bp);             /* backup.c: its auto-save is not needed */
	}
	if (!strcmp(screen_backend(),"browser")) msg("File saved. See the destination above.");
	else msg(m_saved, fn, pos(bp, bp->b_ebuf));
	return (TRUE);
}

void clear_buffer()
{
	zero_buffer(curbp);
	beginning_of_buffer();
}

int load_file(char *fn)
{
	int ok;
	clear_buffer();
	if (shard_wanted(fn))                   /* shard.c: too large to hold */
		return shard_open(curbp, fn);
	ok = insert_file(fn, FALSE);
	record_change(curbp, 'r', 0, NULL, 0);  /* a fresh file: no history */
	return ok;
}

/* reads file into buffer at point */
int insert_file(char *fn, int modflag)
{
	FILE *fp;
	size_t len;
	struct stat sb;

	if (stat(fn, &sb) < 0) {
		if (!modflag) curbp->b_disk = 2;      /* a new file: not on disk yet */
		msg(m_stat, fn);
		return (FALSE);
	}
	if (MAX_SIZE_T < sb.st_size) {
		msg(m_toobig, fn);
		return (FALSE);
	}
	if (curbp->b_egap - curbp->b_gap < sb.st_size * sizeof (char_t) && !growgap(curbp, sb.st_size))
		return (FALSE);
	if ((fp = fopen(fn, "rb")) == NULL) {
		msg(m_open, fn);
		return (FALSE);
	}
	curbp->b_point = movegap(curbp, curbp->b_point);
	undoset();
	curbp->b_gap += len = fread(curbp->b_gap, sizeof (char), (size_t) sb.st_size, fp);
	/*
	 * Inserting a file (C-x i) is a change that undo must know.  Visiting
	 * one (MODFLAG 0) is not: both callers, load_file and main, record 'r'
	 * at once, which forgets the history.  Reporting the insertion first
	 * copied the whole text into the undo machinery (the bridge's buffer,
	 * the compiled program's memory, a bytevector) only to drop it: three
	 * more copies of the file, and the runtimes' heap growth on top; the
	 * memory of a 100 MB file grew to 650 MB.
	 * Lean/undo-visit.lean proves that dropping the report changes nothing.
	 */
	if (modflag == INSERT_UNRECORDED)    /* C-x i with undo off: no bytes to it */
		record_change_unreported(curbp, 'i', curbp->b_point, (long) len);
	else if (modflag)
		record_change(curbp, 'i', curbp->b_point, curbp->b_gap - len, (long) len);

	if (fclose(fp) != 0) {
		msg(m_close, fn);
		return (FALSE);
	}
	/* C-x i changed the text; visiting a file did not.  (This was
	 * b_flags &= (modflag ? B_MODIFIED : ~B_MODIFIED), which for C-x i
	 * left the flag as it was and cleared every other one: read-only,
	 * overwrite.  An insertion into an unmodified buffer was not saved.) */
	if (modflag) add_mode(curbp, B_MODIFIED);
	else delete_mode(curbp, B_MODIFIED);
	if (!modflag && S_ISREG(sb.st_mode)) {   /* visiting FN: the file as read */
		curbp->b_disk = 1;
		curbp->b_disk_time = file_time_ns(&sb);
		curbp->b_disk_size = (long long) sb.st_size;
	}
	msg(m_loaded, fn, len);
	return (TRUE);
}

/* Record a new undo location, deprecated ! */
void undoset()
{
	curbp->b_ubuf.u_point = curbp->b_point;
	curbp->b_ubuf.u_gap = curbp->b_gap - curbp->b_buf;
	curbp->b_ubuf.u_egap = curbp->b_egap - curbp->b_buf;
	curbp->b_ubuf.u_flags = curbp->b_flags;

}

/* additional support funtions not in original gap.c */

/* find the point for start of line ln */
point_t line_to_point(int ln)
{
 if (ln < 1) return -1;
 if (ln == 1) return 0;
 point_t end = document_size(curbp);
 for (point_t p = 0; p < end; p++)
  if (*ptr(curbp, p) == '\n' && --ln == 1) return p + 1;
 return -1;
}

/* scan buffer and fill in curline and lastline */
void get_line_stats(int *curline, int *lastline)
{
	point_t end_p = pos(curbp, curbp->b_ebuf);
	point_t p;
	int line;

	*curline = -1;

	for (p=0, line=0; p < end_p; p++) {
		line += (*(ptr(curbp,p)) == '\n') ? 1 : 0;
		*lastline = line;

		if (*curline == -1 && p == curbp->b_point) {
			*curline = (*(ptr(curbp,p)) == '\n') ? line : line + 1;
		}
	}

	*lastline = *lastline + 1;

	if (curbp->b_point == end_p)
		*curline = *lastline;
}
