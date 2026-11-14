/* window.c, Femto Emacs, Hugh Barney, Public Domain, 2016 */

#include "header.h"

int win_cnt = 0;
static int side_split;

int side_by_side(void) { return side_split; }

int window_width(const window_t *wp)
{
 int cols = screen_cols();
 return !side_split ? cols : wp == wheadp ? (cols - 1) / 2 : cols / 2;
}

int window_left(const window_t *wp)
{
 return side_split && wp != wheadp ? screen_cols() - window_width(wp) : 0;
}

void split_window_right(void)
{
 if (wheadp->w_next) {
  msg(side_split ? "Vertically split panes do not accept further splits" :
      "C-x 3 requires one pane. Use C-x 1 first.");
  return;
 }
 if (screen_cols() < 21 || screen_rows() < 3) {
  msg("Screen too small for a side-by-side split");
  return;
 }
 window_t *right = new_window();
 associate_b2w(curbp, right);
 b2w(right);
 curwp->w_next = right;
 side_split = TRUE;
 relayout_windows();
 screen_clear();
}

window_t* new_window()
{
	window_t *wp = (window_t *)malloc(sizeof(window_t));

	assert(wp != NULL);
	wp->w_next = NULL;
	wp->w_bufp = NULL;
	wp->w_hijack = NULL;
	wp->w_point = 0;
	wp->w_mark = NOMARK;
	wp->w_top = 0;
	wp->w_rows = 0;
	wp->w_update = FALSE;
	sprintf(wp->w_name, "W%d", ++win_cnt);
	return wp;
}

void one_window(window_t *wp)
{
	side_split = FALSE;
	wp->w_top = 0;
	wp->w_rows = screen_rows() - 2;
	wp->w_next = NULL;
}

void split_window()
{
	(void)split_current_window();
}

/* always returns the previous current window pointer */
window_t *split_current_window()
{
	window_t *wp, *wp2;
	int ntru, ntrl;

	if (side_split) {
		msg("Vertically split panes do not accept further splits");
		return NULL;
	}
	if (curwp->w_rows < 3) {
		msg("Cannot split a %d line window", curwp->w_rows);
		return NULL;
	}

	wp = new_window();
	associate_b2w(curwp->w_bufp,wp);
	b2w(wp); /* inherit buffer settings */

	ntru = (curwp->w_rows - 1) / 2; /* Upper size */
	ntrl = (curwp->w_rows - 1) - ntru; /* Lower size */

	/* Old is upper window */
	curwp->w_rows = ntru;
	wp->w_top = curwp->w_top + ntru + 1;
	wp->w_rows = ntrl;

	/* insert it in the list */
	wp2 = curwp->w_next;
	curwp->w_next = wp;
	wp->w_next = wp2;
	redraw(); /* mark the lot for update */
	return curwp;
}

void other_window() {
	curwp->w_update = TRUE; /* make sure modeline gets updated */
	curwp = (curwp->w_next == NULL ? wheadp : curwp->w_next);
	curbp = curwp->w_bufp;

	if (curbp->b_cnt > 1)
		w2b(curwp); /* push win vars to buffer */
}

void delete_other_windows()
{
	if (wheadp->w_next == NULL)
		return;
	free_other_windows(curwp);
	screen_clear();
}

void free_other_windows(window_t *winp)
{
	window_t *wp, *next;

	for (wp = next = wheadp; next != NULL; wp = next) {
		next = wp->w_next; /* get next before a call to free() makes wp undefined */
		if (wp != winp) {
			disassociate_b(wp); /* this window no longer references its buffer */
			free(wp);
		}
	}

	wheadp = curwp = winp;
	one_window(winp);
}

window_t *find_window(char *bname)
{
	window_t *wp;

	for (wp = wheadp; wp != NULL; wp = wp->w_next)
		if (strcmp(wp->w_bufp->b_bname, bname) == 0)
			return wp;

	return NULL;
}

/*
 * Popup a window with buffer bname inside it
 * If such a window already exists do nothing
 * If there are no other windows split the screen and select the other window
 * if the screen is already split select the next window from the top that is not
 * the current buffer.
 */

window_t *popup_window(char *bname)
{
	window_t *wp;
	buffer_t *bp;

	wp = find_window(bname);

	/* if already displayed do nothing */
	if (wp != NULL)
		return wp;

	bp = find_buffer(bname, FALSE);
	assert(bp != NULL);

	if (count_windows() == 1) {
		/* returns the top window pointer */
		wp = split_current_window();
		disassociate_b(wp);
		associate_b2w(bp,wp);
		other_window();
	} else {

		/* find first window from the top that is not the current buffer */
		for (wp = wheadp; wp != NULL; wp = wp->w_next)
			if (wp != curwp)
				break;

		assert(wp != NULL);
		assert(wp->w_hijack == NULL);
		hijack_window(wp, bp);
	}

	wp->w_update = TRUE;
	return wp;
}

void mark_all_windows()
{
	window_t *wp;

	for (wp=wheadp; wp != NULL; wp = wp->w_next)
		wp->w_update = TRUE;
}

int count_windows()
{
	window_t* wp;
	int i;

	for (i=0, wp=wheadp; wp != NULL; wp = wp->w_next)
		i++;

	return i;
}

/*
 * allows a pop up window to highjack an already displayed window
 * the w_hijack member holds the previously associated buffer.
 */
void hijack_window(window_t *wp, buffer_t *bp)
{
	assert(bp != NULL);
	assert(wp != NULL);
	assert(wp->w_hijack == NULL);
	wp->w_hijack = wp->w_bufp;

	disassociate_b(wp);
	associate_b2w(bp,wp);
	wp->w_update = TRUE;
}

void restore_hijacked_window(window_t *wp)
{
	assert(wp != NULL);
	if (wp->w_hijack == NULL) return;

	disassociate_b(wp);
	associate_b2w(wp->w_hijack, wp);
	wp->w_hijack = NULL;
	wp->w_update = TRUE;
}

void associate_b2w(buffer_t *bp, window_t *wp)
{
	assert(bp != NULL);
	assert(wp != NULL);
	wp->w_bufp = bp;
	bp->b_cnt++;
}

/*
 * this decrements the window association count on the buffer
 * the window should either be deleted OR associated with a new buffer.
 *
 */
void disassociate_b(window_t *wp)
{
	assert(wp != NULL);
	assert(wp->w_bufp != NULL);
	wp->w_bufp->b_cnt--;
}


/* C-x 0: delete the selected window; its lines go to the one above (or below) */
void delete_window()
{
	window_t *wp, *prev = NULL;

	if (wheadp->w_next == NULL) {
		msg("Cannot delete the only window");
		return;
	}
	if (side_split) {
		wp = curwp == wheadp ? curwp->w_next : wheadp;
		if (wp->w_bufp == curbp) w2b(wp);
		free_other_windows(wp);
		curbp = wp->w_bufp;
		screen_clear();
		return;
	}
	for (wp = wheadp; wp != NULL && wp != curwp; wp = wp->w_next)
		prev = wp;
	if (prev != NULL) {
		prev->w_next = curwp->w_next;
		prev->w_rows += curwp->w_rows + 1;
		wp = prev;
	} else {
		wheadp = curwp->w_next;
		wheadp->w_top = curwp->w_top;
		wheadp->w_rows += curwp->w_rows + 1;
		wp = wheadp;
	}
	if (curwp->w_hijack != NULL)
		restore_hijacked_window(curwp);
	/* the remaining window keeps its own cursor, even on the same buffer */
	if (wp->w_bufp->b_cnt > 1)
		w2b(wp);
	disassociate_b(curwp);
	free(curwp);
	curwp = wp;
	curbp = wp->w_bufp;
	mark_all_windows();
}

/* C-x ^: one more line for the selected window, taken from a neighbour */
void enlarge_window()
{
	window_t *wp, *prev = NULL;

	if (side_split) {
		msg("Use C-x 1 to expand the selected side-by-side pane");
		return;
	}
	for (wp = wheadp; wp != NULL && wp != curwp; wp = wp->w_next)
		prev = wp;
	if (curwp->w_next != NULL && curwp->w_next->w_rows > 1) {
		curwp->w_rows++;
		curwp->w_next->w_top++;
		curwp->w_next->w_rows--;
	} else if (prev != NULL && prev->w_rows > 1) {
		prev->w_rows--;
		curwp->w_top--;
		curwp->w_rows++;
	} else {
		msg("Cannot enlarge this window");
		return;
	}
	mark_all_windows();
}

/*
 * The screen changed size (a terminal or window resize): the windows keep
 * their share of the rows, as in Emacs.  Femto made a single window here,
 * which lost the windows of C-x 2 at every resize.  A window that gets
 * shorter scrolls so that its cursor stays in view.  Only if the screen
 * becomes too short for every window to keep a row of text do the last
 * ones go, never the selected one.
 */
void relayout_windows(void)
{
	window_t *wp, *last, *prev;
	int old = 0, avail = screen_rows() - 1, n = 0, top = 0, left, k = 0;

	if (wheadp == NULL || curwp == NULL) return;
	if (side_split) {
		if (screen_cols() < 21 || screen_rows() < 3)
			free_other_windows(curwp);
		else
			for (wp = wheadp; wp != NULL; wp = wp->w_next) {
				wp->w_top = 0;
				wp->w_rows = screen_rows() - 2;
				wp->w_epage = wp->w_page;
			}
		curbp->b_epage = curbp->b_page;
		mark_all_windows();
		return;
	}
	for (wp = wheadp; wp != NULL; wp = wp->w_next) { old += wp->w_rows + 1; n++; }
	/* each window needs a row of text and its mode line */
	while (n > 1 && avail < 2 * n) {
		last = NULL;
		for (wp = wheadp; wp != NULL; wp = wp->w_next)
			if (wp != curwp) last = wp;
		if (last == NULL) break;
		prev = NULL;
		for (wp = wheadp; wp != NULL && wp != last; wp = wp->w_next) prev = wp;
		if (prev) prev->w_next = last->w_next; else wheadp = last->w_next;
		old -= last->w_rows + 1;
		n--;
	}
	if (old <= 0) old = 1;
	left = avail;
	for (wp = wheadp; wp != NULL; wp = wp->w_next, k++) {
		int share = wp->w_next == NULL ? left : (int) ((long) (wp->w_rows + 1) * avail / old);
		if (share < 2) share = 2;
		if (share > left - 2 * (n - k - 1)) share = left - 2 * (n - k - 1);
		if (share - 1 < wp->w_rows) {
			wp->w_epage = wp->w_page;
			/* the selected window's live values are its buffer's */
			if (wp == curwp) wp->w_bufp->b_epage = wp->w_bufp->b_page;
		}
		wp->w_top = top;
		wp->w_rows = share - 1;
		wp->w_update = TRUE;
		top += share;
		left -= share;
	}
	mark_all_windows();
}
