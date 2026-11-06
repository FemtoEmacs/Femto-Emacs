/*
 * web.c, Browsered
 *
 * The browser back end of the screen layer (screen.h).  The editor core,
 * compiled to WebAssembly, draws into a grid of cells exactly as it does
 * in a terminal or in the SDL window (gui.c); screen_refresh() hands the
 * cells to the page (web/shell.js), which paints them on a canvas.
 * Keyboard and mouse events arrive from the page as the bytes a terminal
 * would send, so the core's key tables work unchanged.
 *
 * screen_getch() waits for the page through Asyncify: the C loop keeps
 * its shape, and the browser's own event loop runs while it waits.
 */

#include <emscripten.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "screen.h"

extern void set_scrap(unsigned char *);
extern char *scheme_eval(char *);
extern void web_layer_update(void);

#define MAX_FACE 16

/* one cell as the page reads it: 4 int32 words */
typedef struct {
	int cp;         /* Unicode code point, 0 = blank */
	int fg, bg;     /* 24-bit colours, resolved */
	int style;      /* 1 bold, 2 italic, 4 underline */
} cell_t;

static int active = 0;
static int rows = 34, cols = 100;
static cell_t *grid = NULL;
static unsigned char *faces = NULL;     /* the face of each cell */
static unsigned char *reversed = NULL;  /* the mark (SCR_REVERSE_CHAR) */
static int cur_row = 0, cur_col = 0, cur_face = 1;
static int dirty = 1;

static long face_fg[MAX_FACE + 1], face_bg[MAX_FACE + 1];
static int  face_attr[MAX_FACE + 1];
static long default_fg = SCR_RGB(0xc5, 0xc8, 0xc6);
static long default_bg = SCR_RGB(0x1d, 0x1f, 0x21);
static long cursor_color = SCR_RGB(0xf0, 0xc6, 0x74);

/* ------------------------------------------------------------------ */
/* The page's side                                                     */
/* ------------------------------------------------------------------ */

EM_JS(int, web_rows, (void), { return Module.browsered.rows(); });
EM_JS(int, web_cols, (void), { return Module.browsered.cols(); });
EM_JS(void, web_paint, (int ptr, int nrows, int ncols, int crow, int ccol,
                        int bg, int cursor), {
	Module.browsered.paint(ptr, nrows, ncols, crow, ccol, bg, cursor);
});
EM_ASYNC_JS(int, web_next_byte, (void), {
	return await Module.browsered.nextByte();
});
EM_ASYNC_JS(void, web_sleep, (int ms), {
	await new Promise(function (r) { setTimeout(r, ms); });
});
/* Scheme the page asks to run (a dropped file to open, say), or NULL */
EM_JS(char *, web_take_eval, (void), {
	var text = Module.browsered.takeEval();
	if (text === null) return 0;
	var n = lengthBytesUTF8(text) + 1, p = _malloc(n);
	stringToUTF8(text, p, n);
	return p;
});
EM_JS(void, web_layer_applied, (int ok), { ChezwebGrammar.applied(!!ok); });
EM_JS(void, web_flush_input, (void), { Module.browsered.flushInput(); });
EM_JS(void, web_copy, (const char *text), {
	Module.browsered.copy(UTF8ToString(text));
});
EM_ASYNC_JS(int, web_paste, (void), {
	var text = await Module.browsered.paste();
	if (text === null) return 0;
	var n = lengthBytesUTF8(text) + 1, p = _malloc(n);
	stringToUTF8(text, p, n);
	return p;
});
EM_JS(void, web_title, (const char *t), {
	document.title = UTF8ToString(t) + " - Chezweb";
});
EM_JS(void, web_font, (const char *family, int points), {
	Module.browsered.font(family ? UTF8ToString(family) : "", points);
});

/* ------------------------------------------------------------------ */
/* Colours                                                             */
/* ------------------------------------------------------------------ */

/* xterm palette -> 24-bit, as gui.c */
static long palette(int n)
{
	static const long basic[16] = {
		0x1d1f21, 0xcc6666, 0xb5bd68, 0xf0c674, 0x81a2be, 0xb294bb, 0x8abeb7, 0xc5c8c6,
		0x969896, 0xff3334, 0x9ec400, 0xf0c674, 0x81a2be, 0xb777e0, 0x54ced6, 0xffffff
	};
	static const int level[6] = { 0, 95, 135, 175, 215, 255 };

	if (n < 16) return basic[n];
	if (n < 232) {
		n -= 16;
		return ((long) level[n / 36] << 16) | ((long) level[(n / 6) % 6] << 8) | level[n % 6];
	}
	n = 8 + (n - 232) * 10;
	return ((long) n << 16) | ((long) n << 8) | n;
}

static long resolve(long c, long dflt)
{
	if (c < 0) return dflt & 0xFFFFFF;
	if (SCR_IS_RGB(c)) return c & 0xFFFFFF;
	return palette((int) (c & 0xFF));
}

void screen_set_face(int id, long fg, long bg, int attrs)
{
	if (id < 1 || id > MAX_FACE) return;
	face_fg[id] = fg;
	face_bg[id] = bg;
	face_attr[id] = attrs;
	dirty = 1;
}

void screen_face(int id)
{
	if (id >= 1 && id <= MAX_FACE) cur_face = id;
}

int screen_colors(void) { return 16777216; }

void screen_set_default_colors(long fg, long bg, long cursor)
{
	if (fg >= 0) default_fg = fg;
	if (bg >= 0) default_bg = bg;
	if (cursor >= 0) cursor_color = cursor;
	dirty = 1;
}

/* ------------------------------------------------------------------ */
/* The grid                                                            */
/* ------------------------------------------------------------------ */

static void resize_grid(int r, int c)
{
	int i;

	if (r < 4) r = 4;
	if (c < 20) c = 20;
	free(grid);
	free(faces);
	free(reversed);
	grid = calloc((size_t) (r * c), sizeof(cell_t));
	faces = calloc((size_t) (r * c), 1);
	reversed = calloc((size_t) (r * c), 1);
	if (!grid || !faces || !reversed) {
		fputs("browsered: out of memory\n", stderr);
		exit(1);
	}
	rows = r;
	cols = c;
	for (i = 0; i < r * c; i++) faces[i] = 1;
	if (cur_row >= rows) cur_row = rows - 1;
	if (cur_col >= cols) cur_col = cols - 1;
	dirty = 1;
}

static void blank(int i)
{
	grid[i].cp = 0;
	faces[i] = (unsigned char) cur_face;
	reversed[i] = 0;
}

int  screen_active(void) { return active; }
int  screen_rows(void)   { return rows; }
int  screen_cols(void)   { return cols; }
const char *screen_backend(void) { return "browser"; }

void screen_move(int row, int col)
{
	if (row < 0) row = 0;
	if (row >= rows) row = rows - 1;
	if (col < 0) col = 0;
	if (col >= cols) col = cols - 1;
	cur_row = row;
	cur_col = col;
	dirty = 1;
}

static void advance(void)
{
	if (++cur_col >= cols) {
		if (cur_row < rows - 1) {
			cur_row++;
			cur_col = 0;
		} else {
			cur_col = cols - 1;
		}
	}
}

static void put(int cp, int reverse)
{
	int i = cur_row * cols + cur_col;
	grid[i].cp = cp;
	faces[i] = (unsigned char) cur_face;
	reversed[i] = (unsigned char) reverse;
	advance();
	dirty = 1;
}

void screen_clrtoeol(void)
{
	int j;
	for (j = cur_col; j < cols; j++) blank(cur_row * cols + j);
	dirty = 1;
}

void screen_clear(void)
{
	int i;
	for (i = 0; i < rows * cols; i++) blank(i);
	cur_row = cur_col = 0;
	dirty = 1;
}

void screen_addch(int c)
{
	int b = c & 0xFF;
	int rev = (c & SCR_REVERSE_CHAR) != 0;

	if (b == '\n') {
		screen_clrtoeol();
		if (cur_row < rows - 1) cur_row++;
		cur_col = 0;
	} else if (b == '\t') {
		do put(' ', rev); while (cur_col % 8 != 0 && cur_col != 0);
	} else if (b == '\b') {
		if (cur_col > 0) cur_col--;     /* as a terminal: yesno's " n\b" */
	} else if (b != '\r') {
		put(b, rev);
	}
}

void screen_addstr(const char *s)
{
	const unsigned char *p = (const unsigned char *) s;

	while (*p) {
		int cp, n;

		if (*p < 0x80) {
			screen_addch(*p++);
			continue;
		}
		if ((*p & 0xE0) == 0xC0)      { cp = *p & 0x1F; n = 1; }
		else if ((*p & 0xF0) == 0xE0) { cp = *p & 0x0F; n = 2; }
		else if ((*p & 0xF8) == 0xF0) { cp = *p & 0x07; n = 3; }
		else { put(0xFFFD, 0); p++; continue; }
		p++;
		while (n-- > 0) {
			if ((*p & 0xC0) != 0x80) { cp = 0xFFFD; break; }
			cp = (cp << 6) | (*p++ & 0x3F);
		}
		put(cp, 0);
	}
}

void screen_mvaddstr(int row, int col, const char *s)
{
	screen_move(row, col);
	screen_addstr(s);
}

const char *screen_unctrl(int c)
{
	static char buf[8];
	c &= 0xFF;
	if (c < 32) { buf[0] = '^'; buf[1] = (char) (c + 64); buf[2] = 0; }
	else if (c == 127) strcpy(buf, "^?");
	else if (c >= 128) snprintf(buf, sizeof(buf), "\\%03o", c);
	else { buf[0] = (char) c; buf[1] = 0; }
	return buf;
}

/* ------------------------------------------------------------------ */
/* Painting                                                            */
/* ------------------------------------------------------------------ */

/* resolve every cell's colours, as gui.c's cell_colors(), for the page */
static void render(void)
{
	int i;
	long dbg = resolve(-1, default_bg);

	if (!active) return;
	for (i = 0; i < rows * cols; i++) {
		int f = faces[i], a = face_attr[f];
		long fg = resolve(face_fg[f], default_fg);
		long bg = resolve(face_bg[f], dbg);
		long tmp;

		if (a & SCR_REVERSE) { tmp = fg; fg = bg; bg = tmp; }
		if (reversed[i])     { tmp = fg; fg = bg; bg = tmp; }
		if (a & SCR_DIM)
			fg = ((((fg >> 16) & 0xFF) + ((bg >> 16) & 0xFF)) / 2) << 16
			   | ((((fg >> 8) & 0xFF) + ((bg >> 8) & 0xFF)) / 2) << 8
			   | (((fg & 0xFF) + (bg & 0xFF)) / 2);
		grid[i].fg = (int) fg;
		grid[i].bg = (int) bg;
		grid[i].style = ((a & SCR_BOLD) ? 1 : 0) | ((a & SCR_ITALIC) ? 2 : 0)
			      | ((a & SCR_UNDERLINE) ? 4 : 0);
	}
	web_paint((int) grid, rows, cols, cur_row, cur_col, (int) dbg,
		  (int) (cursor_color & 0xFFFFFF));
	web_layer_update();   /* the text Grammarly sees (web-layer.c) */
	dirty = 0;
}

void screen_refresh(void) { render(); }

void screen_pause(int ms)
{
	if (dirty) render();
	web_sleep(ms);
}

/* ------------------------------------------------------------------ */
/* Input                                                               */
/* ------------------------------------------------------------------ */

/*
 * Like curses' getch(), which refreshes before it waits.  A resize of the
 * page, and Scheme the page asks to run, are dealt with here, and the
 * editor never sees them as keys: the core answers SCR_KEY_RESIZE with a
 * single window (resize_terminal), and the windows of C-x 2 were lost
 * whenever the browser window changed size.  Here the windows keep their
 * share (web_relayout, web-layer.c) and everything is drawn again.
 */
extern void web_relayout(int rows);
extern void web_redisplay(void);
int screen_getch(void)
{
	int b;

	for (;;) {
		if (dirty) render();
		b = web_next_byte();
		if (b == -2) {
			/* the page has Scheme to run: here, on the editor's own
			 * stack, between keys */
			char *expr = web_take_eval();
			if (expr) {
				char *answer=scheme_eval(expr);
                extern int scheme_error;
                if(scheme_error){extern void fe_message(char *);fe_message(answer);}
                if(!strncmp(expr,"(web-layer-edit ",16))web_layer_applied(!scheme_error);
				free(expr);
			}
			web_redisplay();
			continue;
		}
		if (b == SCR_KEY_RESIZE) {
			int r = web_rows(), c = web_cols();
			if (r != rows || c != cols) {
				resize_grid(r, c);
				web_relayout(r);
			}
			web_redisplay();
			continue;
		}
		return b;
	}
}

void screen_flushinp(void) { web_flush_input(); }

/* the page pastes (Cmd-V, Ctrl-V, the middle button): scrap, then C-y */
EMSCRIPTEN_KEEPALIVE void web_set_scrap(char *text)
{
	set_scrap((unsigned char *) text);  /* takes ownership */
}

/* ------------------------------------------------------------------ */
/* Clipboard, title, fonts                                             */
/* ------------------------------------------------------------------ */

void screen_set_clipboard(const char *text)
{
	if (text && *text) web_copy(text);
}

char *screen_get_clipboard(void)
{
	return (char *) web_paste();
}

const char *screen_clipboard_tool(void) { return "browser"; }

void screen_set_title(const char *title) { web_title(title ? title : ""); }

/* a font file path means nothing in a page: its name is a font family */
void screen_set_font(const char *path, int points)
{
	const char *name = NULL;

	if (path && *path) {
		const char *slash = strrchr(path, '/');
		name = slash ? slash + 1 : path;
	}
	web_font(name, points);
	{
		int r = web_rows(), c = web_cols();
		if (r != rows || c != cols) resize_grid(r, c);
	}
}

EM_JS(void, web_option, (const char *name, int value), {
	Module.browsered.setOption(UTF8ToString(name), value);
});
void screen_set_option(const char *name, int value) { web_option(name, value); }

/* ------------------------------------------------------------------ */
/* Life cycle                                                          */
/* ------------------------------------------------------------------ */

int screen_probe(void) { return 1; }

int screen_init(int mouse)
{
	int i;

	(void) mouse;
	for (i = 0; i <= MAX_FACE; i++) { face_fg[i] = -1; face_bg[i] = -1; face_attr[i] = 0; }
	resize_grid(web_rows(), web_cols());
	active = 1;
	return 1;
}

void screen_end(void)
{
	active = 0;
}

int screen_test_cancelled(void) { return 0; } /* Native tester only. */

/* A virtual fclose is not proof that a granted file or native document saved. */
EM_ASYNC_JS(int,screen_save_file,(const char *path),{
 return await Module.browsered.confirmSave(UTF8ToString(path)) ? 1 : 0;
});
