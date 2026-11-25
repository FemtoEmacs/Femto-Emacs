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
#ifndef _WIN32
#include <errno.h>
#include <unistd.h>
#endif
#include "screen.h"
#if defined(__CYGWIN__) || defined(CHEZWEB_TEST_CYGWIN_CLIPBOARD)
#include "system.h"
#endif
extern int term_poll_ms(void);

#define MAX_FACE 127             /* interface.c's FE_MAX_COLOR */

static int active = 0;
static int mouse_on = 0;

/*
 * xterm mouse reporting: 1003 includes passive motion for button hints;
 * 1006 is the SGR encoding (ESC [ < b ; x ; y M/m),
 * which has no 223-column limit.  key.c decodes it.  Most terminals still
 * select text natively with Shift (Option in Terminal.app) held down.
 */
static void mouse_reporting(int on)
{
	fputs(on ? "\033[?1000h\033[?1003h\033[?1006h" : "\033[?1006l\033[?1003l\033[?1002l\033[?1000l", stdout);
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
	wtimeout(stdscr, 250);
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
	fputs("\033[?2004h", stdout); /* Clipboard paste is one literal edit. */
	fflush(stdout);
	active = 1;
	return 1;
}

void screen_end(void)
{
	if (!active) return;
	fputs("\033[?2004l", stdout);
	fflush(stdout);
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
/*
 * U+FE0F, the variation selector after ❤ that asks for the emoji: the
 * terminal then draws the pair two columns wide, but curses (and the C
 * core, width.c) count one, so everything after it on the row was drawn
 * a column to the right of where the cursor goes (Eduardo, dem-unicode.txt,
 * 25 November 2026: over the heart the cursor seemed to need two presses,
 * and over the faces after it to jump two).  It is left out here, in the
 * terminal only: the heart is drawn as text, one column, where the cursor
 * expects it.  The text keeps it; the window and the browser draw it.
 */
void screen_addstr(const char *s)
{
	if (strcmp(s, "\xEF\xB8\x8F") == 0) return;
	addstr(s);
}
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

int screen_save_file(const char *path) { (void)path; return 1; }
static int pushed_back = 0;     /* screen_key_waiting gave curses a byte back */

int screen_getch(void)
{
 int c;
 if (editor_is_idle()) {
  timeout(term_poll_ms());    /* terminal.c: shorter while a shell runs */
  while ((c = getch()) == ERR) editor_idle_poll();
  timeout(-1);
 } else c = getch();
 if (c != ERR) pushed_back = 0;
	/* KEY_RESIZE (0x19A) arrives as its low byte, SCR_KEY_RESIZE */
	return c == ERR ? SCR_KEY_IDLE : (c & 0xFF);
}

void screen_flushinp(void) { flushinp(); }

void screen_cursor_shown(int on)
{
	static int shown = 1;
	if (on == shown) return;
	shown = on;
	curs_set(on ? 1 : 0);
}

int screen_key_waiting(int ms)
{
	int c;
	timeout(ms);
	c = getch();
	timeout(-1);
	if (c == ERR) return 0;
	ungetch(c);
	pushed_back = 1;
	return 1;
}

/*
 * Up to MAX key bytes at once, at least one (key.c, during a terminal
 * paste).  Curses reads a byte a read() a byte: a paste of 15 MB took 11
 * seconds (tests/paste-stress.sh).  Without keypad(), curses keeps no byte
 * of its own once getch has returned one, except the one given back by
 * screen_key_waiting, read first.
 */
int screen_read_keys(unsigned char *buf, int max)
{
	int c;
	if (pushed_back || max <= 1) {
		c = screen_getch();
		if (c < 0) return c;
		buf[0] = (unsigned char) c;
		return 1;
	}
#ifndef _WIN32
	for (;;) {
		ssize_t n = read(0, buf, (size_t) max);
		if (n > 0) return (int) n;
		if (n < 0 && errno == EINTR) continue;
		return -1;
	}
#else
	c = screen_getch();
	if (c < 0) return c;
	buf[0] = (unsigned char) c;
	return 1;
#endif
}

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

#if defined(__CYGWIN__) || defined(CHEZWEB_TEST_CYGWIN_CLIPBOARD)
/* Do not fork the editor after Wasmtime has reserved its JIT address
 * space.  Use the same native process launcher as the rest of the port. */
static int clip_run(const char *command, const char *input, size_t len, sys_run_result *r)
{
	char *args[] = {"-c", (char *) command};
	return sys_run_program("/bin/sh", args, 2, input, len, 30, NULL, r) == NULL;
}
#endif

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
#if defined(__CYGWIN__) || defined(CHEZWEB_TEST_CYGWIN_CLIPBOARD)
		sys_run_result r = {0};
		int ok = clip_run(probe, NULL, 0, &r) && r.status == 0;
		sys_run_result_free(&r);
		if (ok) { found = t; break; }
#else
		if (system(probe) == 0) { found = t; break; }
#endif
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
#if defined(__CYGWIN__) || defined(CHEZWEB_TEST_CYGWIN_CLIPBOARD)
	(void) f;
	if (t) {
		sys_run_result r = {0};
		int ok = clip_run(t->copy, text, strlen(text), &r) && r.status == 0;
		sys_run_result_free(&r);
		if (ok) return;
	}
#else
	if (t && (f = popen(t->copy, "w")) != NULL) {
		fputs(text, f);
		if (pclose(f) == 0) return;
	}
#endif
	osc52_copy(text);
}

/* the growing copy of what the paste tool prints; CRLF and CR become LF */
struct clip_copy { char *buf; size_t len, cap; int prev, failed; };

static void clip_put(struct clip_copy *k, int c)
{
	char *bigger;
	if (k->failed) return;
	if (c == '\n' && k->prev == '\r') { k->prev = c; return; }
	if (k->len + 2 > k->cap) {
		/* Keep large clipboard growth within 12.5 percent.  Doubling
		 * leaves huge freed blocks which macOS can reuse without
		 * splitting for the subsequent gap-buffer allocation. */
		size_t extra = k->cap < 1048576 ? k->cap : k->cap / 8;
		if (extra > (size_t)-1 - k->cap) { k->failed = 1; return; }
		size_t cap = k->cap ? k->cap + extra : 4096;
		if ((bigger = realloc(k->buf, cap)) == NULL) { k->failed = 1; return; }
		k->buf = bigger;
		k->cap = cap;
	}
	k->buf[k->len++] = (char) (c == '\r' ? '\n' : c);
	k->prev = c;
}

/*
 * What the paste tool prints, or NULL when it prints nothing, fails, or
 * prints exactly the N bytes of SAME (the text C-y inserts, put there by
 * this editor's own C-w or M-w).  The bytes are compared as they come, and
 * a copy is made only from the first byte that differs: a cut of 21 MB
 * pasted back costs no second copy.
 */
char *screen_get_clipboard_unless(const char *same, size_t n, size_t *len, int *was_same)
{
	const struct clip_tool *t = clip_tool();
	struct clip_copy k = { NULL, 0, 0, 0, 0 };
	FILE *f;
	size_t i = 0, j;
	int c, matching = same != NULL, status;

	if (len) *len = 0;
	if (was_same) *was_same = 0;
#if defined(__CYGWIN__) || defined(CHEZWEB_TEST_CYGWIN_CLIPBOARD)
	(void) f; (void) c;
	if (!t) return NULL;
	sys_run_result r = {0};
	if (!clip_run(t->paste, NULL, 0, &r) || r.status != 0) {
		sys_run_result_free(&r);
		return NULL;
	}
	/* Adopt the launcher's exact-sized output; normalize CRLF in place. */
	k.buf = r.out; k.cap = r.out_len + 1;
	for (j = 0; j < r.out_len; j++) {
		unsigned char byte = (unsigned char) k.buf[j];
		if (byte == '\n' && k.prev == '\r') { k.prev = byte; continue; }
		k.buf[k.len++] = byte == '\r' ? '\n' : byte;
		k.prev = byte;
	}
	r.out = NULL; sys_run_result_free(&r);
	if (same && k.len == n && memcmp(k.buf, same, n) == 0) {
		if (was_same) *was_same = 1;
		free(k.buf); return NULL;
	}
	matching = 0; status = 0;
#else
	if (!t || (f = popen(t->paste, "r")) == NULL) return NULL;
	while ((c = getc(f)) != EOF) {
		if (matching) {
			if (i < n && (unsigned char) same[i] == (unsigned char) c) { i++; continue; }
			matching = 0;
			for (j = 0; j < i; j++) clip_put(&k, (unsigned char) same[j]);
		}
		clip_put(&k, c);
	}
	status = pclose(f);
#endif
	if (matching && i < n)                 /* a proper prefix of SAME */
		for (j = 0; j < i; j++) clip_put(&k, (unsigned char) same[j]);
	if (status == 0 && matching && i == n && n > 0 && was_same) *was_same = 1;
	if (status != 0 || k.failed || k.buf == NULL) { free(k.buf); return NULL; }
	k.buf[k.len] = '\0';
	if (len) *len = k.len;                 /* NUL bytes included */
	/* the copy may stay as what C-y inserts: no doubling's spare room */
	if (k.cap > k.len + 1 + 4096) {
		/* realloc may keep the old capacity on a shrink (notably on
		 * macOS).  A fresh allocation bounds the scrap we retain. */
		char *exact = malloc(k.len + 1);
		if (exact == NULL) { free(k.buf); return NULL; }
		memcpy(exact, k.buf, k.len + 1);
		free(k.buf);
		k.buf = exact;
	}
	return k.buf;
}

char *screen_get_clipboard(void) { return screen_get_clipboard_unless(NULL, 0, NULL, NULL); }

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
char *screen_get_clipboard_unless(const char *same, size_t n, size_t *len, int *was_same)
{
	(void) same; (void) n;
	if (len) *len = 0;
	if (was_same) *was_same = 0;
	return NULL;
}
#endif

void screen_pause(int ms) { refresh(); napms(ms); }

/* nothing to do in a terminal */
void screen_set_font(const char *path, int points) { (void) path; (void) points; }
void screen_set_default_colors(long fg, long bg, long cursor) { (void) fg; (void) bg; (void) cursor; }
void screen_set_title(const char *title) { (void) title; }
void screen_set_option(const char *name, int value) { (void) name; (void) value; }

int screen_test_cancelled(void)
{
 int cancel = 0, c;
 nodelay(stdscr, TRUE);
 while ((c = getch()) != ERR) if (c == 7 || c == 27 || c == KEY_RESIZE) cancel = 1;
 nodelay(stdscr, FALSE);
 return cancel;
}
