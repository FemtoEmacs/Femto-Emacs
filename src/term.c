/*
 * term.c, SBEmacs
 *
 * The terminal back end of the screen layer (screen.h), on ncurses.
 * Linked into libsbemacs-term.
 */

#include <curses.h>
#include <string.h>
#include "screen.h"

#define MAX_FACE 16

static int active = 0;
static attr_t face_attrs[MAX_FACE + 1];

const char *screen_backend(void) { return "terminal"; }

int screen_probe(void) { return 1; }

int screen_init(int mouse)
{
	if (initscr() == NULL)
		return 0;
	raw();
	noecho();
	idlok(stdscr, TRUE);
	if (has_colors()) {
		start_color();
		use_default_colors();
	}
	if (mouse)
		mousemask(ALL_MOUSE_EVENTS | REPORT_MOUSE_POSITION, NULL);
	curs_set(1);
	active = 1;
	return 1;
}

void screen_end(void)
{
	if (!active) return;
	move(LINES - 1, 0);
	refresh();
	noraw();
	endwin();
	active = 0;
}

int screen_active(void) { return active; }
int screen_rows(void)   { return LINES; }
int screen_cols(void)   { return COLS; }

void screen_move(int row, int col)      { move(row, col); }
void screen_addstr(const char *s)       { addstr(s); }
void screen_mvaddstr(int r, int c, const char *s) { mvaddstr(r, c, s); }
void screen_clrtoeol(void)              { clrtoeol(); }
void screen_clear(void)                 { clear(); }
void screen_refresh(void)               { refresh(); }
const char *screen_unctrl(int c)        { return unctrl((chtype) (c & 0xFF)); }

void screen_addch(int c)
{
	chtype ch = (chtype) (c & 0xFF);
	if (c & SCR_REVERSE_CHAR)
		ch |= A_REVERSE;
	addch(ch);
}

int screen_getch(void)
{
	int c = getch();
	/* KEY_RESIZE (0x19A) arrives as its low byte, SCR_KEY_RESIZE */
	return c < 0 ? c : (c & 0xFF);
}

void screen_flushinp(void) { flushinp(); }

int screen_colors(void)
{
	return has_colors() ? COLORS : 0;
}

/* the six levels of the xterm 6x6x6 colour cube */
static int cube_level(int v)
{
	if (v < 48) return 0;
	if (v < 115) return 1;
	return (v - 35) / 40;
}

/* a curses colour number for one of our colours */
static short terminal_color(long c)
{
	int r, g, b;

	if (c < 0) return -1;
	if (!SCR_IS_RGB(c))
		return (short) (c < COLORS ? c : -1);
	r = (int) ((c >> 16) & 0xFF);
	g = (int) ((c >> 8) & 0xFF);
	b = (int) (c & 0xFF);
	if (COLORS >= 256) {
		/* grey ramp for greys, the colour cube otherwise */
		if (r == g && g == b) {
			if (r < 8) return 16;
			if (r > 238) return 231;
			return (short) (232 + (r - 8) / 10);
		}
		return (short) (16 + 36 * cube_level(r) + 6 * cube_level(g) + cube_level(b));
	}
	/* eight colours: one bit per channel */
	return (short) ((r > 127 ? 1 : 0) | (g > 127 ? 2 : 0) | (b > 127 ? 4 : 0));
}

void screen_set_face(int id, long fg, long bg, int attrs)
{
	attr_t a = 0;

	if (id < 1 || id > MAX_FACE) return;
	if (attrs & SCR_BOLD)      a |= A_BOLD;
	if (attrs & SCR_UNDERLINE) a |= A_UNDERLINE;
	if (attrs & SCR_REVERSE)   a |= A_REVERSE;
	if (attrs & SCR_DIM)       a |= A_DIM;
#ifdef A_ITALIC
	if (attrs & SCR_ITALIC)    a |= A_ITALIC;
#endif
	if (has_colors()) {
		init_pair((short) id, terminal_color(fg), terminal_color(bg));
		a |= COLOR_PAIR(id);
	}
	face_attrs[id] = a;
	if (id == 1)                        /* the default face is the background */
		bkgd((chtype) (' ' | (has_colors() ? COLOR_PAIR(1) : 0)));
}

void screen_face(int id)
{
	if (id >= 1 && id <= MAX_FACE)
		attrset(face_attrs[id]);
}

/* nothing to do in a terminal */
void screen_set_clipboard(const char *text) { (void) text; }
void screen_set_font(const char *path, int points) { (void) path; (void) points; }
void screen_set_default_colors(long fg, long bg, long cursor) { (void) fg; (void) bg; (void) cursor; }
void screen_set_title(const char *title) { (void) title; }
void screen_set_option(const char *name, int value) { (void) name; (void) value; }
