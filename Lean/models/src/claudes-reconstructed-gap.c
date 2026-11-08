/*
 * gap.c, Femto Emacs, Hugh Barney, Public Domain, 2016
 * Derived from: Anthony's Editor January 93, (Public Domain 1991, 1993 by Anthony Howe)
 */

#include <sys/stat.h>
#include <errno.h>
#include "header.h"

/*
 * Enlarge the gap by max(n, MIN_GAP_EXPAND) bytes; the gap's position and
 * the text do not change.  The first allocation of a buffer (allocation
 * length zero) that fails is fatal; a later one that fails says so and
 * returns FALSE with the buffer as it was.  A request whose new length
 * point_t or size_t cannot hold is refused the same way, before any
 * arithmetic can overflow.
 */
int growgap(buffer_t *bp, point_t n)
{
	char_t *newbuf;
	point_t buflen, gapstart, gapend, suffix, amount;
	size_t newlen;
	int initial;

	if (bp->b_buf == NULL) {
		/* the unallocated buffer: four NULL pointers, nothing to order */
		assert(bp->b_gap == NULL && bp->b_egap == NULL && bp->b_ebuf == NULL);
		buflen = gapstart = gapend = 0;
	} else {
		assert(bp->b_buf <= bp->b_gap);
		assert(bp->b_gap <= bp->b_egap);
		assert(bp->b_egap <= bp->b_ebuf);
		buflen = (point_t) (bp->b_ebuf - bp->b_buf);
		gapstart = (point_t) (bp->b_gap - bp->b_buf);
		gapend = (point_t) (bp->b_egap - bp->b_buf);
	}
	suffix = buflen - gapend;
	initial = (buflen == 0);
	amount = n < MIN_GAP_EXPAND ? MIN_GAP_EXPAND : n;

	/* buflen + amount must fit point_t and MAX_SIZE_T: check before adding */
	if (amount > LONG_MAX - buflen ||
	    (unsigned long) (buflen + amount) > (unsigned long) MAX_SIZE_T) {
		if (initial)
			fatal(f_alloc);
		msg(m_alloc);
		return (FALSE);
	}
	newlen = (size_t) (buflen + amount);

	/* the result goes to a temporary: bp is untouched if it is NULL */
	if (initial)
		newbuf = (char_t *) malloc(newlen);
	else
		newbuf = (char_t *) realloc(bp->b_buf, newlen);
	if (newbuf == NULL) {
		if (initial)
			fatal(f_alloc);
		msg(m_alloc);
		return (FALSE);
	}

	/* the text after the gap moves to the end; the regions may overlap */
	if (suffix > 0)
		memmove(newbuf + gapend + amount, newbuf + gapend, (size_t) suffix);

	bp->b_buf = newbuf;
	bp->b_gap = newbuf + gapstart;
	bp->b_egap = newbuf + gapend + amount;
	bp->b_ebuf = newbuf + buflen + amount;

	assert(bp->b_buf < bp->b_ebuf);
	assert(bp->b_buf <= bp->b_gap);
	assert(bp->b_gap < bp->b_egap);
	assert(bp->b_egap <= bp->b_ebuf);
	return (TRUE);
}

/*
 * Move the gap to OFFSET, a logical position in [0, text length]; return
 * it.  The text, the gap's size, the allocation and every other field are
 * unchanged.  Offsets outside that range are not handled here (the
 * specification leaves their policy to the integration).
 */
point_t movegap(buffer_t *bp, point_t offset)
{
	point_t gapstart, gapend, gapsize;

	if (bp->b_buf == NULL)
		return (offset);	/* unallocated and empty: only 0 is valid */

	gapstart = (point_t) (bp->b_gap - bp->b_buf);
	gapend = (point_t) (bp->b_egap - bp->b_buf);
	gapsize = gapend - gapstart;

	/* copy first, then move the boundaries */
	if (gapsize > 0) {
		if (offset < gapstart)
			memmove(bp->b_buf + offset + gapsize, bp->b_buf + offset,
				(size_t) (gapstart - offset));
		else if (offset > gapstart)
			memmove(bp->b_buf + gapstart, bp->b_buf + gapend,
				(size_t) (offset - gapstart));
	}
	bp->b_gap = bp->b_buf + offset;
	bp->b_egap = bp->b_gap + gapsize;

	assert(bp->b_buf <= bp->b_gap);
	assert(bp->b_gap <= bp->b_egap);
	assert(bp->b_egap <= bp->b_ebuf);
	return (offset);
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

int save_buffer(buffer_t *bp, char *fn)
{
	FILE *fp;
	point_t length;
	struct stat saved_file;

	/* Save As and a never-created file still need an actual write. */
	if (!(bp->b_flags & B_MODIFIED) && !strcmp(fn, bp->b_fname) &&
	    stat(fn, &saved_file) == 0 && S_ISREG(saved_file.st_mode)) {
		msg("(No changes need to be saved)");
		return TRUE;
	}
	if (!posix_file(fn)) {
		msg(m_badname);
		return (FALSE);
	}
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
 if (!screen_save_file(fn)) {
  msg("Save failed; changes are still unsaved. See the browser notice.");
  return FALSE;
 }
	delete_mode(bp, B_MODIFIED);
	record_change(bp, 's', 0, NULL, 0);
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
	record_change(curbp, 'i', curbp->b_point, curbp->b_gap - len, (long) len);

	if (fclose(fp) != 0) {
		msg(m_close, fn);
		return (FALSE);
	}
	curbp->b_flags &= (modflag ? B_MODIFIED : ~B_MODIFIED);
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
