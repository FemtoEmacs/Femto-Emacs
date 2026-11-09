/*
 * fold.c -- hidden text: Org's folded headings (TAB, compiled/scripts/
 * org-fold.scm)
 *
 * A fold hides the bytes [a, b] of a buffer: from the newline that ends a
 * heading line (a) to the newline before the next heading (b).  The
 * heading's row shows "..." and the next row starts at b + 1.  So the
 * positions a + 1 .. b are hidden; a (the end of the heading's text) and
 * b + 1 are not.  Folds may nest (a folded parent over folded children).
 *
 * What keeps the cursor out of hidden text:
 *   - dndn and upup (display.c), the moves by screen rows that C-n, C-p,
 *     the display and the mouse use, step over a fold;
 *   - C-f and C-b (command.c) step over it;
 *   - any other move into it (a search, M-<, a script's goto-char) opens
 *     the folds around point, as Emacs does (fold_reveal, display.c).
 * Edits move the folds after them (fold_change, from record_change): an
 * edit inside a fold opens it; a reload or an erase drops them all.
 *
 * A buffer without folds pays one test of b_nfolds in those places.
 */
#include "header.h"

/* The fold with the largest range around P: a < P <= b; 1 if there is one */
static int outermost(buffer_t *bp, point_t p, point_t *a, point_t *b)
{
	int k, found = 0;

	for (k = 0; k < bp->b_nfolds; k++) {
		fold_t *f = &bp->b_folds[k];
		if (f->a < p && p <= f->b && (!found || f->b - f->a > *b - *a)) {
			*a = f->a;
			*b = f->b;
			found = 1;
		}
	}
	return found;
}

/* Is P hidden? */
int fold_hidden(buffer_t *bp, point_t p)
{
	point_t a, b;
	return bp->b_nfolds > 0 && outermost(bp, p, &a, &b);
}

/* P, or the first position after the folds that hide it */
point_t fold_skip_forward(buffer_t *bp, point_t p)
{
	point_t a, b;

	while (bp->b_nfolds > 0 && outermost(bp, p, &a, &b)) p = b + 1;
	return p;
}

/* P, or the end of the heading text before the folds that hide it */
point_t fold_skip_backward(buffer_t *bp, point_t p)
{
	point_t a, b;

	while (bp->b_nfolds > 0 && outermost(bp, p, &a, &b)) p = a;
	return p;
}

/* The end b of the outermost fold that starts at P (P = a), or NOMARK */
point_t fold_end_at(buffer_t *bp, point_t p)
{
	point_t end = NOMARK, a, b;
	int k;

	/* a fold starting at P, if no larger one hides P's own position */
	if (outermost(bp, p, &a, &b)) return NOMARK;
	for (k = 0; k < bp->b_nfolds; k++)
		if (bp->b_folds[k].a == p && (end == NOMARK || bp->b_folds[k].b > end))
			end = bp->b_folds[k].b;
	return end;
}

static void remove_fold(buffer_t *bp, int k)
{
	bp->b_folds[k] = bp->b_folds[--bp->b_nfolds];
	if (bp->b_nfolds == 0) {
		free(bp->b_folds);
		bp->b_folds = NULL;
		bp->b_capfolds = 0;
	}
}

/* Open the folds that hide P (a search found something there) */
void fold_reveal(buffer_t *bp, point_t p)
{
	int k;

	for (k = bp->b_nfolds - 1; k >= 0; k--)
		if (bp->b_folds[k].a < p && p <= bp->b_folds[k].b)
			remove_fold(bp, k);
}

/* The text changed (undo.c, record_change): insert ('i') or delete ('d')
 * LEN bytes at POS, or everything ('r') */
void fold_change(buffer_t *bp, int kind, point_t pos, long len)
{
	int k;

	if (kind == 'r') {
		while (bp->b_nfolds > 0) remove_fold(bp, bp->b_nfolds - 1);
		return;
	}
	if (kind != 'i' && kind != 'd') return;
	for (k = bp->b_nfolds - 1; k >= 0; k--) {
		fold_t *f = &bp->b_folds[k];
		if (kind == 'i') {
			if (pos <= f->a) { f->a += len; f->b += len; }
			else if (pos <= f->b) remove_fold(bp, k);       /* typed inside */
		} else {
			point_t end = pos + (point_t) len;
			if (end <= f->a) { f->a -= len; f->b -= len; }
			else if (pos <= f->b) remove_fold(bp, k);       /* cut into it */
		}
	}
}

/* (fe-fold A B): hide [A, B] of the current buffer; 1 done, 0 if the
 * range is not in the text */
int fe_fold(long a, long b)
{
	point_t size = document_size(curbp);

	if (a < 0 || b <= a || b >= size) return 0;
	if (curbp->b_nfolds == curbp->b_capfolds) {
		int cap = curbp->b_capfolds ? 2 * curbp->b_capfolds : 16;
		fold_t *f = realloc(curbp->b_folds, (size_t) cap * sizeof *f);
		if (f == NULL) return 0;
		curbp->b_folds = f;
		curbp->b_capfolds = cap;
	}
	curbp->b_folds[curbp->b_nfolds].a = (point_t) a;
	curbp->b_folds[curbp->b_nfolds].b = (point_t) b;
	curbp->b_nfolds++;
	if (fold_hidden(curbp, curbp->b_point)) curbp->b_point = (point_t) a;
	return 1;
}

/* (fe-unfold FROM TO): open the folds that start in [FROM, TO] */
void fe_unfold(long from, long to)
{
	int k;

	for (k = curbp->b_nfolds - 1; k >= 0; k--)
		if (from <= curbp->b_folds[k].a && curbp->b_folds[k].a <= to)
			remove_fold(curbp, k);
}

/* (fe-folded-at A): the end of the fold starting at A, or -1 */
long fe_folded_at(long a)
{
	long end = -1;
	int k;

	for (k = 0; k < curbp->b_nfolds; k++)
		if (curbp->b_folds[k].a == a && curbp->b_folds[k].b > end)
			end = curbp->b_folds[k].b;
	return end;
}

/* (fe-hidden-p P): 1 if P is hidden by a fold */
int fe_hidden_p(long p) { return fold_hidden(curbp, (point_t) p); }

/* (fe-unfold-everywhere): no folds in any buffer (M-x org-mode, off) */
void fe_unfold_everywhere(void)
{
	buffer_t *bp;

	for (bp = bheadp; bp != NULL; bp = bp->b_next) fold_free(bp);
}

/* The buffer is going away (buffer.c) */
void fold_free(buffer_t *bp)
{
	free(bp->b_folds);
	bp->b_folds = NULL;
	bp->b_nfolds = bp->b_capfolds = 0;
}
