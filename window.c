/* window.c, Femto Emacs, Hugh Barney, Public Domain, 2016 */

#include "header.h"

int win_cnt = 0;

window_t* new_window()
{
	window_t *wp = (window_t *)malloc(sizeof(window_t));
	
	assert(wp != NULL); /* call fatal instead XXX */
	wp->w_next = NULL;
	wp->w_bufp = NULL;
	wp->w_point = 0;
	wp->w_mark = NOMARK;
	wp->w_top = 0;	
	wp->w_rows = 0;	
	wp->w_update = FALSE;
	wp->w_temp = FALSE;
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
	(void)split_window_temp(FALSE);	
}

window_t *split_window_temp(int temp_flag)
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

	wp->w_temp = temp_flag;
  
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
	return wp;
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
window_t *popup_window(char *bname, int temp_flag)
{
	window_t *wp;

	wp = find_window(bname);

	/* if already displayed do nothing */
	if (wp != NULL)
		return wp;

	if (count_windows() == 1) {
		wp = split_window_temp(temp_flag);
	} else {

		/* find first window from the top that is not the current buffer */
		for (wp = wheadp; wp != NULL; wp = wp->w_next)
			if (wp != curwp)
				break;

		assert(wp != NULL);
	}	

	select_buffer(bname);
	other_window();
	return wp;
}

int count_windows()
{
	window_t* wp;
	int i;

	for (i=0, wp=wheadp; wp != NULL; wp = wp->w_next)
		i++;

	return i;
}

void associate_b2w(buffer_t *bp, window_t *wp) {
	assert(bp != NULL);
	assert(wp != NULL);
	wp->w_bufp = bp;
	bp->b_cnt++;
}

void disassociate_b(window_t *wp) {
	assert(wp != NULL);
	assert(wp->w_bufp != NULL);
	wp->w_bufp->b_cnt--;
}
