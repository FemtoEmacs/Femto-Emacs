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
		} else if (screen_cols() <= c) {
			c = 0;
			start = scan;
		}
		++scan;
		c += *p == '\t' ? 8 - (c & 7) : 1;
	}
	return (c < screen_cols() ? start : finish);
}

/* Forward scan for start of logical line segment following 'finish' */
point_t segnext(buffer_t *bp, point_t start, point_t finish)
{
	char_t *p;
	int c = 0;

	point_t scan = segstart(bp, start, finish);
	for (;;) {
		p = ptr(bp, scan);
		if (bp->b_ebuf <= p || screen_cols() <= c)
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

/*
 * Syntax highlighting.
 *
 * The tokenizer used to live here, driven by tables filled from femtolisp.
 * It is now written in Common Lisp (lisp/highlight.lisp).  Before a window
 * is painted we hand Lisp a copy of the text, starting a little before the
 * top of the window so that comments and strings opened above the screen
 * are recognised, and Lisp gives back one colour per byte.
 */

#define HL_LOOKBACK 16384

static char_t *hl_text = NULL;
static char_t *hl_colors = NULL;
static int hl_cap = 0;
static point_t hl_start = 0;    /* buffer offset of hl_text[0] */
static int hl_len = 0;
static int hl_active = 0;

static void highlight_window(buffer_t *bp, int rows)
{
	point_t size = document_size(bp);
	point_t start, end, i;
	int len;

	hl_active = 0;
	start = bp->b_page - HL_LOOKBACK;
	if (start <= 0)
		start = 0;
	else
		start = lnstart(bp, start);
	/* a screen row shows at most screen_cols() characters of up to 4 bytes each */
	end = bp->b_page + (point_t) (rows + 1) * (screen_cols() + 1) * 4;
	if (end > size) end = size;
	len = (int) (end - start);
	if (len <= 0) return;

	if (len + 1 > hl_cap) {
		hl_cap = len + 1;
		hl_text = realloc(hl_text, hl_cap);
		hl_colors = realloc(hl_colors, hl_cap);
		assert(hl_text != NULL && hl_colors != NULL);
	}
	for (i = 0; i < len; i++)
		hl_text[i] = *ptr(bp, start + i);
	hl_text[len] = '\0';
	memset(hl_colors, ID_COLOR_ALPHA, len);

	hl_start = start;
	hl_len = len;
	hl_active = call_lisp_highlight(bp, hl_text, len, hl_colors);
}

static int color_at(buffer_t *bp, char_t *p)
{
	point_t off = pos(bp, p) - hl_start;
	int c;

	if (!hl_active || off < 0 || off >= hl_len)
		return is_upper_or_lower(*p) ? ID_COLOR_ALPHA : ID_COLOR_SYMBOL;
	c = hl_colors[off];
	/* the token faces, and the prose faces from ID_COLOR_HEADING on */
	if (c < 1 || c > ID_COLOR_LINK || c == ID_COLOR_REGION) c = ID_COLOR_ALPHA;
	return c;
}

/*
 * The active region (between mark and point, see mark_active) is shaded
 * in the selected window, as in Emacs.
 */
static point_t region_lo = 0, region_hi = 0;

static void set_region(window_t *wp)
{
	buffer_t *bp = wp->w_bufp;

	region_lo = region_hi = 0;
	if (wp != curwp || !mark_active || bp->b_mark == NOMARK)
		return;
	region_lo = bp->b_mark < bp->b_point ? bp->b_mark : bp->b_point;
	region_hi = bp->b_mark < bp->b_point ? bp->b_point : bp->b_mark;
}

static int face_for(buffer_t *bp, char_t *p)
{
	point_t off = pos(bp, p);

	if (off >= region_lo && off < region_hi)
		return ID_COLOR_REGION;
	if (bp->b_paren != NOPAREN && (off == bp->b_point || off == bp->b_paren))
		return ID_COLOR_BRACE;
	return color_at(bp, p);
}

void display_char(buffer_t *bp, char_t *p)
{
	face_on(face_for(bp, p));
	screen_addch(*p);
	face_on(ID_COLOR_SYMBOL);
}

char *get_file_extension(char *filename)
{
	static char exts[20];

	char *dot = strrchr(filename, '.');
	if (!dot || strlen(dot) >= sizeof(exts))
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

	highlight_window(bp, wp->w_rows);
	set_region(wp);

	screen_move(wp->w_top, 0); /* start from top of window */
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
				face_on(face_for(bp, p));
				display_utf8(bp, *p, nch);
				face_on(ID_COLOR_SYMBOL);
			} else if (isprint(*p) || *p == '\t' || *p == '\n') {
				j += *p == '\t' ? 8-(j&7) : 1;
				display_char(bp, p);
			} else {
				const char *ctrl = screen_unctrl(*p);
				j += (int) strlen(ctrl);
				screen_addstr(ctrl);
			}
		}
		if (*p == '\n' || screen_cols() <= j) {
			j -= screen_cols();
			if (j < 0)
				j = 0;
			++i;
		}
		bp->b_epage = bp->b_epage + nch;
	}

	/* replacement for clrtobot() to bottom of window */
	for (k=i; k < wp->w_top + wp->w_rows; k++) {
		screen_move(k, j); /* clear from very last char not start of line */
		screen_clrtoeol();
		j = 0; /* thereafter start of line */
	}

	b2w(wp); /* save buffer stuff on window */
	modeline(wp);
	if (wp == curwp && flag) {
		dispmsg();
		screen_move(bp->b_row, bp->b_col); /* set cursor */
		screen_refresh();
	}
	wp->w_update = FALSE;
}

/*
 * work out number of bytes based on first byte 
 *
 * 1 byte utf8 starts 0xxxxxxx  00 - 7F : 000 - 127
 * 2 byte utf8 starts 110xxxxx  C0 - DF : 192 - 223
 * 3 byte utf8 starts 1110xxxx  E0 - EF : 224 - 239
 * 4 byte utf8 starts 11110xxx  F0 - F7 : 240 - 247
 *
 */
int utf8_size(char_t c)
{
	if (c >= 192 && c < 224) {
		return 2; // 2 top bits set mean 2 byte utf8 char
	} else if (c >= 224 && c < 240) {
		return 3; // 3 top bits set mean 3 byte utf8 char
	} else if (c >= 240 && c < 248) {
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
	screen_addstr(sbuf);
}

/*
 * The mode line:
 *   SBEmacs: Ctrl-h for help == file.c*, L. 3 == Ctrl c r calls Claude; ...
 * (== in the selected window, -- in the others; * when modified).
 * The two hints can be changed from Lisp (set-mode-line-hints).
 */
static char modeline_help[128] = "Ctrl-h for help";
static char modeline_tail[128] = "Ctrl c r calls Claude; Ctrl c g calls GPT";

void fe_set_modeline_hints(char *help, char *tail)
{
	safe_strncpy(modeline_help, help, sizeof(modeline_help));
	safe_strncpy(modeline_tail, tail, sizeof(modeline_tail));
	mark_all_windows();
}

/*
 * A buffer can have hints of its own in place of the tail, e.g. the
 * assistant's answer: "C-c y inserts the code and closes this window".
 */
#define MAX_BUFFER_HINTS 16

static struct {
	char name[NBUFN];
	char hint[128];
} buffer_hints[MAX_BUFFER_HINTS];

/* HINT for the mode line of buffer NAME; an empty HINT removes it */
void fe_set_buffer_hint(char *name, char *hint)
{
	int i, free_slot = -1;

	for (i = 0; i < MAX_BUFFER_HINTS; i++) {
		if (buffer_hints[i].name[0] != '\0' && strncmp(buffer_hints[i].name, name, NBUFN - 1) == 0)
			break;
		if (buffer_hints[i].name[0] == '\0' && free_slot < 0)
			free_slot = i;
	}
	if (i == MAX_BUFFER_HINTS)
		i = free_slot;
	if (i < 0)
		return;
	if (hint[0] == '\0') {
		buffer_hints[i].name[0] = '\0';
	} else {
		safe_strncpy(buffer_hints[i].name, name, NBUFN);
		safe_strncpy(buffer_hints[i].hint, hint, sizeof(buffer_hints[i].hint));
	}
	mark_all_windows();
}

/* the buffer's own hint, or NULL */
static char *buffer_hint(buffer_t *bp)
{
	int i;
	for (i = 0; i < MAX_BUFFER_HINTS; i++)
		if (buffer_hints[i].name[0] != '\0' && strcmp(buffer_hints[i].name, bp->b_bname) == 0)
			return buffer_hints[i].hint;
	return NULL;
}

/* 1-based line number of offset OFF */
int line_number(buffer_t *bp, point_t off)
{
	point_t gap = bp->b_gap - bp->b_buf;
	char_t *p, *end;
	int n = 1;

	if (off > document_size(bp)) off = document_size(bp);
	end = bp->b_buf + (off < gap ? off : gap);
	for (p = bp->b_buf; p < end; p++)
		if (*p == '\n') n++;
	if (off > gap) {
		end = bp->b_egap + (off - gap);
		for (p = bp->b_egap; p < end; p++)
			if (*p == '\n') n++;
	}
	return n;
}

void modeline(window_t *wp)
{
	int i, n, cols = screen_cols();
	char lch, mch, och;
	char *hint;
	static char modeline_buf[1024];
	char *name = get_buffer_modeline_name(wp->w_bufp);
	point_t point = (wp == curwp) ? wp->w_bufp->b_point : wp->w_point;

	if (wp == curwp)
		screen_set_title(wp->w_bufp->b_fname[0] ? wp->w_bufp->b_fname : wp->w_bufp->b_bname);
	face_on(ID_COLOR_MODELINE);
	screen_move(wp->w_top + wp->w_rows, 0);
	lch = (wp == curwp ? '=' : '-');
	mch = ((wp->w_bufp->b_flags & B_MODIFIED) && !(wp->w_bufp->b_flags & B_SPECIAL) ? '*' : lch);
	och = ((wp->w_bufp->b_flags & B_OVERWRITE) ? 'O' : lch);

	/*
	 * a * after the name: modified; [overwrite]: overwrite mode.  A
	 * buffer with a hint of its own (the assistants' windows) shows
	 * only that, to stay short:
	 *   SBEmacs: *discussion*, L. 8 == C-c r send; C-c t code-tangle
	 */
	hint = buffer_hint(wp->w_bufp);
	if (hint != NULL)
		snprintf(modeline_buf, sizeof(modeline_buf), "SBEmacs: %s%s%s, L. %d %c%c %s ",
			 name, mch == '*' ? "*" : "", och == 'O' ? " [overwrite]" : "",
			 line_number(wp->w_bufp, point), lch, lch, hint);
	else
		snprintf(modeline_buf, sizeof(modeline_buf), "SBEmacs: %s %c%c %s%s%s, L. %d %c%c %s ",
			 modeline_help, lch, lch, name, mch == '*' ? "*" : "",
			 och == 'O' ? " [overwrite]" : "",
			 line_number(wp->w_bufp, point), lch, lch, modeline_tail);
	/* too wide: "Ctrl-h" becomes "C-h", "Ctrl c r" "C-c r", then the end is cut */
	if ((int) strlen(modeline_buf) > cols) {
		char *p;
		while ((p = strstr(modeline_buf, "Ctrl-")) != NULL)
			memmove(p + 1, p + 4, strlen(p + 4) + 1);
		while ((p = strstr(modeline_buf, "Ctrl ")) != NULL) {
			memmove(p + 1, p + 4, strlen(p + 4) + 1);
			p[1] = '-';
		}
	}
	/* the cells, not the bytes, must fit: cut on a character boundary */
	for (i = 0, n = 0; modeline_buf[i] != '\0'; i++) {
		if (((unsigned char) modeline_buf[i] & 0xC0) != 0x80) {
			if (n == cols) break;
			n++;
		}
	}
	modeline_buf[i] = '\0';
	screen_addstr(modeline_buf);

	for (; n < cols; n++)
		screen_addch(lch);
	face_on(ID_COLOR_SYMBOL);
}

void dispmsg()
{
	screen_move(MSGLINE, 0);
	if (msgflag) {
		screen_addstr(msgline);
		msgflag = FALSE;
	}
	screen_clrtoeol();
}

void clear_message_line()
{
	ZERO_STRING(msgline);
	msgflag = FALSE;
	screen_move(MSGLINE, 0);
	screen_clrtoeol();
}

void display_prompt_and_response(char *prompt, char *response)
{
	screen_mvaddstr(MSGLINE, 0, prompt);
	/* if we have a value print it and go to end of it */
	if (response[0] != '\0')
		screen_addstr(response);
	screen_clrtoeol();
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
		screen_refresh();
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
	screen_move(curwp->w_row, curwp->w_col); /* set cursor for curwp */
	screen_refresh();
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

/*
 * Move the cursor to the buffer position shown at screen ROW, COL (a
 * mouse click).  Clicking in another window selects it.  The walk mirrors
 * the painting loop in display().
 */
int goto_screen_position(int row, int col)
{
	window_t *wp;

	/* a window's text and its mode line below it */
	for (wp = wheadp; wp != NULL; wp = wp->w_next)
		if (row >= wp->w_top && row <= wp->w_top + wp->w_rows)
			break;
	if (wp == NULL)
		return FALSE;

	if (wp != curwp) {
		curwp->w_update = TRUE;
		curwp = wp;
		curbp = wp->w_bufp;
		if (curbp->b_cnt > 1)
			w2b(curwp);
	}
	if (row == wp->w_top + wp->w_rows)  /* the mode line selects only */
		return FALSE;
	return window_position(wp, row, col);
}

/*
 * Move the cursor of the current window WP to screen ROW, COL; rows
 * outside the window are taken as its first or last row (no scrolling).
 */
int window_position(window_t *wp, int row, int col)
{
	buffer_t *bp;
	point_t p, end;
	int i, j, w;
	char_t *c;

	if (row < wp->w_top) row = wp->w_top;
	if (row >= wp->w_top + wp->w_rows) row = wp->w_top + wp->w_rows - 1;
	if (col < 0) col = 0;
	bp = curbp;
	end = document_size(bp);
	p = bp->b_page;
	i = wp->w_top;
	j = 0;

	while (p < end) {
		c = ptr(bp, p);
		if (*c == '\t')
			w = 8 - (j & 7);
		else if (*c == '\n' || *c == '\r')
			w = 1;
		else if (*c >= 0x80)
			w = 1;
		else if (!isprint(*c))
			w = (int) strlen(screen_unctrl(*c));
		else
			w = 1;

		if (i == row && (col < j + w || *c == '\n'))
			break;
		if (i > row)
			break;

		p += (*c >= 0x80) ? utf8_size(*c) : 1;
		j += w;
		if (*c == '\n' || screen_cols() <= j) {
			j -= screen_cols();
			if (j < 0 || *c == '\n')
				j = 0;
			++i;
		}
	}
	bp->b_point = p;
	return TRUE;
}
