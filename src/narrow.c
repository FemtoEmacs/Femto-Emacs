/*
 * narrow.c -- narrowing: only a part of a buffer is shown and edited
 *
 * As Emacs's C-x n n (narrow-to-region), C-x n s (Org's subtree) and
 * C-x n w (widen).  The text outside stays in the buffer and is saved
 * with it; it is not shown, point and mark cannot go there, and search
 * does not find it.  The part is kept as its start and the number of
 * bytes after its end, so that it grows and shrinks with what is typed in
 * it.  A buffer that is not narrowed pays one test of b_narrowed.
 *
 * The display (display.c) frames the page inside the part and stops
 * drawing at its end; it also brings point and mark back inside, so that
 * no command has to know: M-> goes to the end of the part, C-n stops at
 * its last line.  The mode line shows "Narrow".
 */
#include "header.h"

/* The first byte shown */
point_t visible_start(buffer_t *bp)
{
	point_t size = document_size(bp);

	if (!bp->b_narrowed) return 0;
	return bp->b_narrow_start < size ? bp->b_narrow_start : size;
}

/* The byte after the last one shown */
point_t visible_end(buffer_t *bp)
{
	point_t size = document_size(bp), end;

	if (!bp->b_narrowed) return size;
	end = size - bp->b_narrow_tail;
	if (end < visible_start(bp)) end = visible_start(bp);
	return end;
}

/* Point and mark inside the part shown */
void narrow_clamp(buffer_t *bp)
{
	point_t from, to;

	if (!bp->b_narrowed) return;
	from = visible_start(bp);
	to = visible_end(bp);
	if (bp->b_point < from) bp->b_point = from;
	if (bp->b_point > to) bp->b_point = to;
	if (bp->b_mark != NOMARK) {
		if (bp->b_mark < from) bp->b_mark = from;
		if (bp->b_mark > to) bp->b_mark = to;
	}
	if (bp->b_page < from) bp->b_page = from;
}

/* (fe-narrow FROM TO): show only [FROM, TO) of the current buffer;
 * 1 done, 0 if the range is empty or outside the text */
int fe_narrow(long from, long to)
{
	point_t size = document_size(curbp);

	if (from > to) { long t = from; from = to; to = t; }
	if (from < 0) from = 0;
	if (to > size) to = size;
	if (from >= to) return 0;
	curbp->b_narrowed = 1;
	curbp->b_narrow_start = (point_t) from;
	curbp->b_narrow_tail = size - (point_t) to;
	narrow_clamp(curbp);
	curbp->b_page = (point_t) from;         /* the display frames point */
	return 1;
}

/* (fe-widen): all the text again */
void fe_widen(void)
{
	curbp->b_narrowed = 0;
	curbp->b_narrow_start = curbp->b_narrow_tail = 0;
}

/* (fe-narrow-start), (fe-narrow-end): the part shown; -1 when the buffer
 * is not narrowed */
long fe_narrow_start(void) { return curbp->b_narrowed ? (long) visible_start(curbp) : -1; }
long fe_narrow_end(void) { return curbp->b_narrowed ? (long) visible_end(curbp) : -1; }
