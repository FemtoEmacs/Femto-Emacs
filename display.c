/*
 * display.c, Femto Emacs, Hugh Barney, Public Domain, 2016
 * Derived from: Anthony's Editor January 93, (Public Domain 1991, 1993 by Anthony Howe)
 */

#include "header.h"

/* Reverse scan for start of logical line containing offset */
point_t lnstart(buffer_t *bp, register point_t off)
{
	register char_t *p;
	do
		p = ptr(bp, --off);
	while (bp->b_buf < p && *p != '\n');
	return (bp->b_buf < p ? ++off : 0);
}

/*
 * Forward scan for start of logical line segment containing 'finish'.
 * A segment of a logical line corresponds to a physical screen line.
 */
point_t segstart(buffer_t *bp, point_t start, point_t finish)
{
	char_t *p;
	int c = 0;
	point_t scan = start;

	while (scan < finish) {
		p = ptr(bp, scan);
		if (*p == '\n') {
			c = 0;
			start = scan+1;
		} else if (COLS <= c) {
			c = 0;
			start = scan;
		}
		++scan;
		c += *p == '\t' ? 8 - (c & 7) : 1;
	}
	return (c < COLS ? start : finish);
}

/* Forward scan for start of logical line segment following 'finish' */
point_t segnext(buffer_t *bp, point_t start, point_t finish)
{
	char_t *p;
	int c = 0;

	point_t scan = segstart(bp, start, finish);
	for (;;) {
		p = ptr(bp, scan);
		if (bp->b_ebuf <= p || COLS <= c)
			break;
		++scan;
		if (*p == '\n')
			break;
		c += *p == '\t' ? 8 - (c & 7) : 1;
	}
	return (p < bp->b_ebuf ? scan : pos(bp, bp->b_ebuf));
}

/* Move up one screen line */
point_t upup(buffer_t *bp, point_t off)
{
	point_t curr = lnstart(bp, off);
	point_t seg = segstart(bp, curr, off);
	if (curr < seg)
		off = segstart(bp, curr, seg-1);
	else
		off = segstart(bp, lnstart(bp,curr-1), curr-1);
	return (off);
}

/* Move down one screen line */
point_t dndn(buffer_t *bp, point_t off)
{
	return (segnext(bp, lnstart(bp,off), off));
}

/* Return the offset of a column on the specified line */
point_t lncolumn(buffer_t *bp, point_t offset, int column)
{
	int c = 0;
	char_t *p;
	while ((p = ptr(bp, offset)) < bp->b_ebuf && *p != '\n' && c < column) {
		c += *p == '\t' ? 8 - (c & 7) : 1;
		++offset;
	}
	return (offset);
}

int is_upper_or_lower(char_t c)
{
	return ( (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c == '_'));
}

int is_digit(char_t c)
{
        return (c >= '0' && c <= '9');
}

int escapequote(char_t a, char_t c) {
	return ( (a == 92) && (c == '"'));
}

int in_block_comment = 0;
int in_line_comment = 0;
int in_string= 0;
int endcmt= 0;

int charquote(char_t a, char_t c, char_t b )
{
	return ( (in_string == 0) &&  (c == '"') && (a == 39) && (b == 39));
}

void display_char(buffer_t *bp, char_t *p, int keyword_char_count, int token_type)
{
	if (in_string==1) {
		attron(COLOR_PAIR(ID_COLOR_STRING));
        } else if (in_line_comment== 1) {
                attron(COLOR_PAIR(ID_COLOR_COMMENTS));
        } else if (in_block_comment==1) {
		attron(COLOR_PAIR(ID_COLOR_BLOCK));
        } else if ( (ptr(bp, bp->b_mark) == p) && (bp->b_mark != NOMARK)) {
                addch(*p | A_REVERSE);
                return;
        } else if ( token_type == ID_TOKEN_KEYWORD  && keyword_char_count > 0 ) {
                attron(COLOR_PAIR(ID_COLOR_KEYWORD));
        } else if (pos(bp,p) == bp->b_point && bp->b_paren != NOPAREN) {
                attron(COLOR_PAIR(ID_COLOR_BRACE));
        } else if (bp->b_paren != NOPAREN && pos(bp,p) == bp->b_paren) {
                attron(COLOR_PAIR(ID_COLOR_BRACE));
        } else if ( token_type == ID_TOKEN_DIGITS && keyword_char_count > 0) {
		attron(COLOR_PAIR(ID_COLOR_DIGITS));
        } else if (is_upper_or_lower(*p)) {
                attron(COLOR_PAIR(ID_COLOR_ALPHA));
        } else {
                attron(COLOR_PAIR(ID_COLOR_SYMBOL));
        }

	if (endcmt > 0) {
		attron(COLOR_PAIR(ID_COLOR_BLOCK));
		endcmt= endcmt-1;
        } else if (!in_block_comment && in_string == 0 && *p=='"' && (!charquote(*(p-1), *p, *(p+1)))) {
		attron(COLOR_PAIR(ID_COLOR_STRING));
	}
        addch(*p);
	
	if (in_string == 1)
		attron(COLOR_PAIR(ID_COLOR_STRING));
        else
		attron(COLOR_PAIR(ID_COLOR_ALPHA));
}


char *get_file_extension(char *filename)
{
	static char exts[20];

	char *dot = strrchr(filename, '.');
	if (!dot)
		strcpy(exts, "");
	else
		strcpy(exts, dot);
	return exts;
}

void display(window_t *wp, int flag)
{
	char_t *p;
	int i, j, k, nch;
	buffer_t *bp = wp->w_bufp;
        int keywd_char_count = 0;
        int token_type = ID_TOKEN_NONE;

	setLanguage(get_file_extension(bp->b_fname));
        in_block_comment = 0;
        in_line_comment = 0;
        in_string= 0;
        endcmt= 0;
	
	/* find start of screen, handle scroll up off page or top of file  */
	/* point is always within b_page and b_epage */
	if (bp->b_point < bp->b_page)
		bp->b_page = segstart(bp, lnstart(bp,bp->b_point), bp->b_point);

	/* reframe when scrolled off bottom */
	if (bp->b_epage <= bp->b_point) {
		/* Find end of screen plus one. */
		bp->b_page = dndn(bp, bp->b_point);
		/* if we scoll to EOF we show 1 blank line at bottom of screen */
		if (pos(bp, bp->b_ebuf) <= bp->b_page) {
			bp->b_page = pos(bp, bp->b_ebuf);
			i = wp->w_rows - 1;
		} else {
			i = wp->w_rows - 0;
		}
		/* Scan backwards the required number of lines. */
		while (0 < i--)
			bp->b_page = upup(bp, bp->b_page);
	}

	move(wp->w_top, 0); /* start from top of window */
	i = wp->w_top;
	j = 0;
	bp->b_epage = bp->b_page;

	/* paint screen from top of page until we hit maxline */
	while (1) {
		/* reached point - store the cursor position */
		if (bp->b_point == bp->b_epage) {
			bp->b_row = i;
			bp->b_col = j;
		}
		p = ptr(bp, bp->b_epage);
		nch = 1;
		if (wp->w_top + wp->w_rows <= i || bp->b_ebuf <= p) /* maxline */
			break;
		if (*p != '\r') {
			nch = utf8_size(*p);
			if ( nch > 1) {
				j++;				
				display_utf8(bp, *p, nch);
			} else if (isprint(*p) || *p == '\t' || *p == '\n') {
				j += *p == '\t' ? 8-(j&7) : 1;
				if (in_string== 0)
	                            scan_for_comments(p, &in_block_comment, &endcmt, &in_line_comment);
				
				if (!in_block_comment && *p == '"' && !charquote(*(p-1), *p, *(p+1)) && !escapequote(*(p-1), *p))
					in_string = (in_string == 1 ? 0 : 1);

				if (keywd_char_count <= 0)
                                        keywd_char_count = scan_for_keywords(p, &token_type);
                                display_char(bp, p, keywd_char_count--, token_type);
			} else {
				const char *ctrl = unctrl(*p);
				j += (int) strlen(ctrl);
				addstr(ctrl);
			}
		}
		if (*p == '\n' || COLS <= j) {
			j -= COLS;
			if (j < 0)
				j = 0;
			++i;
		}
		bp->b_epage = bp->b_epage + nch;
	}

	/* replacement for clrtobot() to bottom of window */
	for (k=i; k < wp->w_top + wp->w_rows; k++) {
		move(k, j); /* clear from very last char not start of line */
		clrtoeol();
		j = 0; /* thereafter start of line */
	}

	b2w(wp); /* save buffer stuff on window */
	modeline(wp);
	if (wp == curwp && flag) {
		dispmsg();
		move(bp->b_row, bp->b_col); /* set cursor */
		refresh();
	}
	wp->w_update = FALSE;
}

/* work out number of bytes based on first byte */
int utf8_size(char_t c)
{
	if (c >= 192 && c < 224) {
		return 2; // 2 top bits set mean 2 byte utf8 char
	} else if (c >= 224 && c < 240) {
		return 3; // 3 top bits set mean 3 byte utf8 char
	} else if (c >= 240) {
		return 4; // 4 top bits set mean 4 byte utf8 char
	}

	return 1; /* if in doubt it is 1 */
}

void display_utf8(buffer_t *bp, char_t c, int n)
{
	char sbuf[6];
	int i = 0;

	for (i=0; i<n; i++) {
		sbuf[i] = *ptr(bp, bp->b_epage + i);
	}
	sbuf[n] = '\0';
	addstr(sbuf);
}

void modeline(window_t *wp)
{
	int i;
	char lch, mch, och;
	static char modeline_buf[256];

	/* n = utf8_size(*(ptr(wp->w_bufp, wp->w_bufp->b_point))); */
	attron(COLOR_PAIR(ID_COLOR_MODELINE));
	move(wp->w_top + wp->w_rows, 0);
	lch = (wp == curwp ? '=' : '-');
	mch = ((wp->w_bufp->b_flags & B_MODIFIED) ? '*' : lch);
	och = ((wp->w_bufp->b_flags & B_OVERWRITE) ? 'O' : lch);

	/* debug version */
	/* sprintf(modeline_buf, "%c%c%c Femto: %c%c %s %s  T%dR%d Pt%ld Pg%ld Pe%ld r%dc%d B%d",  lch,och,mch,lch,lch, wp->w_name, get_buffer_modeline_name(wp->w_bufp), wp->w_top, wp->w_rows, wp->w_point, wp->w_bufp->b_page, wp->w_bufp->b_epage, wp->w_bufp->b_row, wp->w_bufp->b_col, wp->w_bufp->b_cnt); */

	/* sprintf(modeline_buf, "%c%c%c Femto: %c%c %s %s  T%dR%d Pt%ld Pg%ld Pe%ld r%dc%d B%d N%d",  lch,och,mch,lch,lch, wp->w_name, get_buffer_modeline_name(wp->w_bufp), wp->w_top, wp->w_rows, wp->w_point, wp->w_bufp->b_page, wp->w_bufp->b_epage, wp->w_bufp->b_row, wp->w_bufp->b_col, wp->w_bufp->b_cnt, n); */

	sprintf(modeline_buf, "%c%c%c Femto: %c%c %s",  lch,och,mch,lch,lch, get_buffer_modeline_name(wp->w_bufp));
	addstr(modeline_buf);

	for (i = strlen(modeline_buf) + 1; i <= COLS; i++)
		addch(lch);
	attron(COLOR_PAIR(ID_COLOR_SYMBOL));
}

void dispmsg()
{
	move(MSGLINE, 0);
	if (msgflag) {
		addstr(msgline);
		msgflag = FALSE;
	}
	clrtoeol();
}

void clear_message_line()
{
	ZERO_STRING(msgline);
	msgflag = FALSE;
	move(MSGLINE, 0);
	clrtoeol();
}

void display_prompt_and_response(char *prompt, char *response)
{
	mvaddstr(MSGLINE, 0, prompt);
	/* if we have a value print it and go to end of it */
	if (response[0] != '\0')
		addstr(response);
	clrtoeol();
}

void update_display()
{
	window_t *wp;
	buffer_t *bp;

	bp = curwp->w_bufp;
	bp->b_cpoint = bp->b_point; /* cpoint only ever set here */

	/* only one window */
	if (wheadp->w_next == NULL) {
		display(curwp, TRUE);
		refresh();
		bp->b_psize = bp->b_size;
		return;
	}

	display(curwp, FALSE); /* this is key, we must call our win first to get accurate page and epage etc */

	/* never curwp,  but same buffer in different window or update flag set*/
	for (wp=wheadp; wp != NULL; wp = wp->w_next) {
		if (wp != curwp && (wp->w_bufp == bp || wp->w_update)) {
			w2b(wp);
			display(wp, FALSE);
		}
	}

	/* now display our window and buffer */
	w2b(curwp);
	dispmsg();
	move(curwp->w_row, curwp->w_col); /* set cursor for curwp */
	refresh();
	bp->b_psize = bp->b_size;  /* now safe to save previous size for next time */
}

void w2b(window_t *w)
{
	w->w_bufp->b_point = w->w_point;
	w->w_bufp->b_page = w->w_page;
	w->w_bufp->b_epage = w->w_epage;
	w->w_bufp->b_row = w->w_row;
	w->w_bufp->b_col = w->w_col;

	/* fixup pointers in other windows of the same buffer, if size of edit text changed */
	if (w->w_bufp->b_point > w->w_bufp->b_cpoint) {
		w->w_bufp->b_point += (w->w_bufp->b_size - w->w_bufp->b_psize);
		w->w_bufp->b_page += (w->w_bufp->b_size - w->w_bufp->b_psize);
		w->w_bufp->b_epage += (w->w_bufp->b_size - w->w_bufp->b_psize);
	}
}

void b2w(window_t *w)
{
	w->w_point = w->w_bufp->b_point;
	w->w_page = w->w_bufp->b_page;
	w->w_epage = w->w_bufp->b_epage;
	w->w_row = w->w_bufp->b_row;
	w->w_col = w->w_bufp->b_col;
	w->w_bufp->b_size = (w->w_bufp->b_ebuf - w->w_bufp->b_buf) - (w->w_bufp->b_egap - w->w_bufp->b_gap);
}

/*
 * save buffer data on all windows that reference this buffer
 * special behaviour for where we want to see updates in real time
 * (for example *messages* buffer)
 */
void b2w_all_windows(buffer_t *bp)
{
	window_t *wp;

	for (wp=wheadp; wp != NULL; wp = wp->w_next) {
		if (wp->w_bufp == bp) {
			b2w(wp);
		}
	}
}
