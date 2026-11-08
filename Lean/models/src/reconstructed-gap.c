/*
 * gap.c, Femto Emacs, Hugh Barney, Public Domain, 2016
 * Derived from: Anthony's Editor January 93, (Public Domain 1991, 1993 by Anthony Howe)
 */

#include <sys/stat.h>
#include <errno.h>
#include <stdint.h>
#include "header.h"

/* Enlarge gap by n chars, position of gap cannot change */
/* Implements GapBP.growgap in ../gap_bp-calculator.lean.
 * See ../gap_bp-reconstruction-plan.md for the representation mapping. */
int growgap(buffer_t *bp, point_t n)
{
    point_t length = 0, start = 0, end = 0;
    char_t *newbuf;
    size_t newlength;

    assert(bp != NULL);
    if (bp->b_buf == NULL) {
        assert(bp->b_gap == NULL && bp->b_egap == NULL && bp->b_ebuf == NULL);
    } else {
        assert(bp->b_buf <= bp->b_gap);
        assert(bp->b_gap <= bp->b_egap);
        assert(bp->b_egap <= bp->b_ebuf);
        length = bp->b_ebuf - bp->b_buf;
        start = bp->b_gap - bp->b_buf;
        end = bp->b_egap - bp->b_buf;
    }
    if (n < MIN_GAP_EXPAND) n = MIN_GAP_EXPAND;
    /* Reject before signed addition or conversion to size_t can overflow. */
    if (n > LONG_MAX - length ||
        (uintmax_t) length + (uintmax_t) n > (uintmax_t) MAX_SIZE_T ||
        (uintmax_t) length + (uintmax_t) n > (uintmax_t) PTRDIFF_MAX) {
        if (length == 0) fatal(f_alloc);
        else msg(m_alloc);
        return FALSE; /* Also safe if a test double makes fatal return. */
    }
    newlength = (size_t) length + (size_t) n;
    newbuf = length == 0 ? malloc(newlength) : realloc(bp->b_buf, newlength);
    if (newbuf == NULL) {
        if (length == 0) fatal(f_alloc);
        else msg(m_alloc);
        return FALSE;
    }
    /* Shift the suffix right; memmove permits overlapping source/destination. */
    if (length != end)
        memmove(newbuf + end + n, newbuf + end, (size_t) (length - end));
    bp->b_buf = newbuf;
    bp->b_gap = newbuf + start;
    bp->b_egap = newbuf + end + n;
    bp->b_ebuf = newbuf + newlength;
    assert(bp->b_buf < bp->b_ebuf);
    assert(bp->b_buf <= bp->b_gap);
    assert(bp->b_gap < bp->b_egap);
    assert(bp->b_egap <= bp->b_ebuf);
    return TRUE;
}

/* Implements GapBP.movegap: repartition unchanged text at OFFSET. */
point_t movegap(buffer_t *bp, point_t offset)
{
    point_t start, end, gap, length;
    assert(bp != NULL);
    if (bp->b_buf == NULL) {
        assert(bp->b_gap == NULL && bp->b_egap == NULL && bp->b_ebuf == NULL);
        assert(offset == 0);
        return 0;
    }
    assert(bp->b_buf <= bp->b_gap && bp->b_gap <= bp->b_egap);
    assert(bp->b_egap <= bp->b_ebuf);
    start = bp->b_gap - bp->b_buf;
    end = bp->b_egap - bp->b_buf;
    gap = end - start;
    length = (bp->b_ebuf - bp->b_buf) - gap;
    /* Invalid requests assert in debug builds; release builds leave bp alone. */
    assert(0 <= offset && offset <= length);
    if (offset < 0 || offset > length) return start;
    if (gap != 0 && offset < start)
        memmove(bp->b_buf + offset + gap, bp->b_buf + offset,
                (size_t) (start - offset));
    else if (gap != 0 && start < offset)
        memmove(bp->b_buf + start, bp->b_buf + end,
                (size_t) (offset - start));
    bp->b_gap = bp->b_buf + offset;
    bp->b_egap = bp->b_buf + offset + gap;
    assert(bp->b_gap <= bp->b_egap);
    assert(bp->b_buf <= bp->b_gap);
    assert(bp->b_egap <= bp->b_ebuf);
    return offset;
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
