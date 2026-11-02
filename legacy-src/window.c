/* window.c, Femto Emacs, Hugh Barney, Public Domain, 2016 */

#include "header.h"

int win_cnt = 0;

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
	wp->w_top = 0;
	wp->w_rows = LINES - 2;
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

