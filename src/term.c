/*
 * term.c, SBEmacs
 *
 * The terminal back end of the screen layer (screen.h), on ncurses.
 * Linked into libsbemacs-term.
 */

#include <curses.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "screen.h"

#define MAX_FACE 16

static int active = 0;
static int mouse_on = 0;

/*
 * xterm mouse reporting: 1002 reports presses, releases and motion while
 * a button is down; 1006 is the SGR encoding (ESC [ < b ; x ; y M/m),
 * which has no 223-column limit.  key.c decodes it.  Most terminals still
 * select text natively with Shift (Option in Terminal.app) held down.
 */
static void mouse_reporting(int on)
{
	fputs(on ? "\033[?1000h\033[?1002h\033[?1006h" : "\033[?1006l\033[?1002l\033[?1000l", stdout);
	fflush(stdout);
}
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
	curs_set(1);
	refresh();
	if (mouse) {
		mouse_reporting(1);
		mouse_on = 1;
	}
	active = 1;
	return 1;
}

void screen_end(void)
{
	if (!active) return;
	move(LINES - 1, 0);
	refresh();
	if (mouse_on) {
		mouse_reporting(0);
		mouse_on = 0;
	}
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

/*
 * The system clipboard, from a terminal.  A terminal program cannot reach
 * the clipboard by itself, so it asks the system's own tools, through a
 * pipe: the text goes to their standard input, or comes from their
 * standard output, never through a shell command line.  LC_CTYPE=UTF-8
 * makes pbcopy and pbpaste take the bytes as UTF-8 even when the locale is
 * unset.  When no tool is there (over ssh, say), the copy is sent to the
 * terminal itself as an OSC 52 escape, which iTerm2, kitty, WezTerm,
 * foot, Windows Terminal and tmux (set-clipboard on) understand; OSC 52
 * cannot be read back, so pasting from other programs then needs the
 * terminal's own paste key.
 */
#ifndef _WIN32
/* NEEDS: an environment variable that must be set; PROGRAM: must exist */
struct clip_tool { const char *needs, *program, *copy, *paste; };

static const struct clip_tool clip_tools[] = {
#ifdef __APPLE__
	{ NULL, "pbcopy", "LC_CTYPE=UTF-8 pbcopy", "LC_CTYPE=UTF-8 pbpaste" },
#endif
	{ "WAYLAND_DISPLAY", "wl-copy", "wl-copy 2>/dev/null", "wl-paste --no-newline 2>/dev/null" },
	{ "DISPLAY", "xclip", "xclip -selection clipboard -in 2>/dev/null",
	             "xclip -selection clipboard -out 2>/dev/null" },
	{ "DISPLAY", "xsel", "xsel --clipboard --input 2>/dev/null", "xsel --clipboard --output 2>/dev/null" },
	{ NULL, NULL, NULL, NULL }
};

/* the first tool whose program exists (and whose display is set); once */
static const struct clip_tool *clip_tool(void)
{
	static int searched = 0;
	static const struct clip_tool *found = NULL;
	const struct clip_tool *t;
	char probe[128];

	if (searched) return found;
	searched = 1;
	for (t = clip_tools; t->program; t++) {
		if (t->needs && !getenv(t->needs)) continue;
		snprintf(probe, sizeof probe, "command -v %s >/dev/null 2>&1", t->program);
		if (system(probe) == 0) { found = t; break; }
	}
	return found;
}

static void osc52_copy(const char *text)
{
	static const char b64[] =
		"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
	const unsigned char *p = (const unsigned char *) text;
	size_t len = strlen(text), i;

	if (len > 74994) return;           /* terminals cap OSC 52 near 100 kB */
	fputs("\033]52;c;", stdout);
	for (i = 0; i + 2 < len; i += 3) {
		putchar(b64[p[i] >> 2]);
		putchar(b64[((p[i] & 3) << 4) | (p[i+1] >> 4)]);
		putchar(b64[((p[i+1] & 15) << 2) | (p[i+2] >> 6)]);
		putchar(b64[p[i+2] & 63]);
	}
	if (i < len) {
		putchar(b64[p[i] >> 2]);
		if (i + 1 < len) {
			putchar(b64[((p[i] & 3) << 4) | (p[i+1] >> 4)]);
			putchar(b64[(p[i+1] & 15) << 2]);
		} else {
			putchar(b64[(p[i] & 3) << 4]);
			putchar('=');
		}
		putchar('=');
	}
	fputs("\a", stdout);
	fflush(stdout);
}

void screen_set_clipboard(const char *text)
{
	const struct clip_tool *t;
	FILE *f;

	if (!text || !*text) return;
	t = clip_tool();
	if (t && (f = popen(t->copy, "w")) != NULL) {
		fputs(text, f);
		if (pclose(f) == 0) return;
	}
	osc52_copy(text);
}

char *screen_get_clipboard(void)
{
	const struct clip_tool *t = clip_tool();
	FILE *f;
	char *buf = NULL, *bigger;
	size_t len = 0, cap = 0;
	int c, prev = 0, status;

	if (!t || (f = popen(t->paste, "r")) == NULL) return NULL;
	while ((c = getc(f)) != EOF) {
		if (len + 2 > cap) {
			cap = cap ? 2 * cap : 4096;
			if ((bigger = realloc(buf, cap)) == NULL) {
				free(buf);
				pclose(f);
				return NULL;
			}
			buf = bigger;
		}
		/* CRLF and CR line ends become LF */
		if (c == '\n' && prev == '\r') { prev = c; continue; }
		buf[len++] = (char) (c == '\r' ? '\n' : c);
		prev = c;
	}
	status = pclose(f);
	if (status != 0 || buf == NULL) { free(buf); return NULL; }
	buf[len] = '\0';
	return buf;
}
const char *screen_clipboard_tool(void)
{
	const struct clip_tool *t = clip_tool();
	return t ? t->program : "";
}
#else
/* the Windows build has only the window, which uses SDL's clipboard */
const char *screen_clipboard_tool(void) { return ""; }
void screen_set_clipboard(const char *text) { (void) text; }
char *screen_get_clipboard(void) { return NULL; }
#endif

void screen_pause(int ms) { refresh(); napms(ms); }

/* nothing to do in a terminal */
void screen_set_font(const char *path, int points) { (void) path; (void) points; }
void screen_set_default_colors(long fg, long bg, long cursor) { (void) fg; (void) bg; (void) cursor; }
void screen_set_title(const char *title) { (void) title; }
void screen_set_option(const char *name, int value) { (void) name; (void) value; }
