/*
 * gui.c, SBEmacs
 *
 * The window back end of the screen layer (screen.h), on SDL2 and
 * SDL2_ttf.  Linked into libsbemacs-gui.
 *
 * The editor core draws into a grid of cells exactly as it would draw
 * into a terminal; screen_refresh() paints the grid into the window with
 * a monospace font.  Keyboard and mouse events are turned into the bytes
 * a terminal would send, so the core's key tables work unchanged.
 */

#define SDL_MAIN_HANDLED
#include <SDL.h>
#include <SDL_ttf.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "screen.h"

/* from the editor core */
extern void set_scrap(unsigned char *);

#define MAX_FACE 16
#define PAD 4                   /* margin around the text, in points */

typedef struct {
	Uint32 cp;                  /* Unicode code point, 0 = blank */
	unsigned char face;         /* ID_COLOR_* */
	unsigned char reverse;      /* the mark */
} cell_t;

static SDL_Window   *window = NULL;
static SDL_Renderer *renderer = NULL;
static TTF_Font     *fonts[4];  /* regular, bold, italic, bold italic */
static int active = 0;
static int focused = 1;

static int rows = 34, cols = 100;
static cell_t *grid = NULL;
static int cur_row = 0, cur_col = 0;
/* the grid or the cursor changed since the window was last painted */
static int dirty = 1;
static int cur_face = 1;

static int cell_w = 8, cell_h = 16, pad = PAD;
static float scale = 1.0f;      /* drawable pixels per window point (HiDPI) */

/* faces and colours */
static long face_fg[MAX_FACE + 1], face_bg[MAX_FACE + 1];
static int  face_attr[MAX_FACE + 1];
static long default_fg = SCR_RGB(0xc5, 0xc8, 0xc6);
static long default_bg = SCR_RGB(0x1d, 0x1f, 0x21);
static long cursor_color = SCR_RGB(0xf0, 0xc6, 0x74);

/* font */
static char font_path[1024] = "";
static int  font_points = 14;

/* options */
static int option_is_meta = 1;  /* Alt / Option sends ESC prefixes */

/* window title */
static char title[256] = "";

/* ------------------------------------------------------------------ */
/* Input queue: the bytes a terminal would have sent                   */
/* ------------------------------------------------------------------ */

#define QSIZE 8192
static unsigned char queue[QSIZE];
static int q_head = 0, q_tail = 0;

static void push_byte(int b)
{
	int next = (q_tail + 1) % QSIZE;
	if (next == q_head) return;     /* full: drop */
	queue[q_tail] = (unsigned char) b;
	q_tail = next;
}

static void push_bytes(const char *s, int n)
{
	int i;
	for (i = 0; i < n; i++) push_byte((unsigned char) s[i]);
}

static void push_string(const char *s) { push_bytes(s, (int) strlen(s)); }

static int queue_empty(void) { return q_head == q_tail; }

static int pop_byte(void)
{
	int b = queue[q_head];
	q_head = (q_head + 1) % QSIZE;
	return b;
}

void screen_flushinp(void) { q_head = q_tail = 0; }

/* ------------------------------------------------------------------ */
/* Colours                                                             */
/* ------------------------------------------------------------------ */

static SDL_Color rgb(long c)
{
	SDL_Color col;
	col.r = (Uint8) ((c >> 16) & 0xFF);
	col.g = (Uint8) ((c >> 8) & 0xFF);
	col.b = (Uint8) (c & 0xFF);
	col.a = 255;
	return col;
}

/* xterm palette -> 24-bit */
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

/* a colour from the core (-1, 0-255, or RGB) as 24-bit, with a default */
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
}

static void measure(int *out_rows, int *out_cols);
static void resize_grid(int r, int c);

/* ------------------------------------------------------------------ */
/* Fonts and the glyph cache                                           */
/* ------------------------------------------------------------------ */

typedef struct {
	Uint32 key;                 /* code point << 2 | style, 0 = empty */
	SDL_Texture *tex;
	int w, h;
} glyph_t;

#define GCACHE 8192
static glyph_t gcache[GCACHE];

static void clear_glyphs(void)
{
	int i;
	for (i = 0; i < GCACHE; i++) {
		if (gcache[i].tex) SDL_DestroyTexture(gcache[i].tex);
		gcache[i].tex = NULL;
		gcache[i].key = 0;
	}
}

static int encode_utf8(Uint32 cp, char *out)
{
	if (cp < 0x80) { out[0] = (char) cp; out[1] = 0; return 1; }
	if (cp < 0x800) {
		out[0] = (char) (0xC0 | (cp >> 6));
		out[1] = (char) (0x80 | (cp & 0x3F));
		out[2] = 0; return 2;
	}
	if (cp < 0x10000) {
		out[0] = (char) (0xE0 | (cp >> 12));
		out[1] = (char) (0x80 | ((cp >> 6) & 0x3F));
		out[2] = (char) (0x80 | (cp & 0x3F));
		out[3] = 0; return 3;
	}
	out[0] = (char) (0xF0 | (cp >> 18));
	out[1] = (char) (0x80 | ((cp >> 12) & 0x3F));
	out[2] = (char) (0x80 | ((cp >> 6) & 0x3F));
	out[3] = (char) (0x80 | (cp & 0x3F));
	out[4] = 0; return 4;
}

/* a white glyph texture, tinted at draw time */
static glyph_t *glyph(Uint32 cp, int style)
{
	Uint32 key = (cp << 2) | (Uint32) style;
	unsigned int h = (key * 2654435761u) % GCACHE;
	int probes;
	char utf8[5];
	SDL_Color white = { 255, 255, 255, 255 };
	SDL_Surface *surf;

	for (probes = 0; probes < GCACHE; probes++) {
		glyph_t *g = &gcache[h];
		if (g->key == key && g->tex) return g;
		if (g->key == 0) {
			encode_utf8(cp, utf8);
			surf = TTF_RenderUTF8_Blended(fonts[style], utf8, white);
			if (!surf) return NULL;
			g->tex = SDL_CreateTextureFromSurface(renderer, surf);
			g->w = surf->w;
			g->h = surf->h;
			g->key = key;
			SDL_FreeSurface(surf);
			return g->tex ? g : NULL;
		}
		h = (h + 1) % GCACHE;
	}
	clear_glyphs();             /* full: start again */
	return glyph(cp, style);
}

static const char *font_candidates[] = {
#if defined(__APPLE__)
	"/System/Library/Fonts/Menlo.ttc",
	"/System/Library/Fonts/Monaco.ttf",
	"/System/Library/Fonts/SFNSMono.ttf",
	"/Library/Fonts/Courier New.ttf",
#elif defined(_WIN32)
	"C:\\Windows\\Fonts\\consola.ttf",
	"C:\\Windows\\Fonts\\cour.ttf",
	"C:\\Windows\\Fonts\\lucon.ttf",
#else
	"/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
	"/usr/share/fonts/dejavu/DejaVuSansMono.ttf",
	"/usr/share/fonts/TTF/DejaVuSansMono.ttf",
	"/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf",
	"/usr/share/fonts/liberation-mono/LiberationMono-Regular.ttf",
	"/usr/share/fonts/truetype/noto/NotoSansMono-Regular.ttf",
	"/usr/share/fonts/truetype/ubuntu/UbuntuMono-R.ttf",
#endif
	NULL
};

static void close_fonts(void)
{
	int i;
	for (i = 0; i < 4; i++) {
		if (fonts[i]) TTF_CloseFont(fonts[i]);
		fonts[i] = NULL;
	}
}

static int open_fonts_from(const char *path)
{
	static const int styles[4] = {
		TTF_STYLE_NORMAL, TTF_STYLE_BOLD, TTF_STYLE_ITALIC, TTF_STYLE_BOLD | TTF_STYLE_ITALIC
	};
	int i, px = (int) (font_points * scale + 0.5f);

	for (i = 0; i < 4; i++) {
		fonts[i] = TTF_OpenFontIndex(path, px, 0);
		if (!fonts[i]) { close_fonts(); return 0; }
		TTF_SetFontStyle(fonts[i], styles[i]);
		TTF_SetFontHinting(fonts[i], TTF_HINTING_LIGHT);
	}
	return 1;
}

/* (re)open the fonts at the current scale and measure a cell */
static int load_fonts(void)
{
	int i, w = 0, h = 0;

	close_fonts();
	clear_glyphs();
	if (!(font_path[0] && open_fonts_from(font_path))) {
		for (i = 0; font_candidates[i]; i++)
			if (open_fonts_from(font_candidates[i])) break;
		if (!fonts[0]) {
			fprintf(stderr, "sbemacs: no usable monospace font found; "
				"set one with (set-gui-font \"/path/to/font.ttf\" 14)\n");
			return 0;
		}
	}
	TTF_SizeUTF8(fonts[0], "M", &w, &h);
	cell_w = w > 0 ? w : 8;
	cell_h = TTF_FontLineSkip(fonts[0]);
	if (cell_h < h) cell_h = h;
	if (cell_h <= 0) cell_h = 16;
	pad = (int) (PAD * scale);
	return 1;
}

void screen_set_font(const char *path, int points)
{
	if (path) strncpy(font_path, path, sizeof(font_path) - 1);
	if (points > 0) font_points = points;
	if (active) {
		int r, c;
		load_fonts();
		measure(&r, &c);
		resize_grid(r, c);
		push_byte(SCR_KEY_RESIZE);  /* the editor re-lays out its windows */
	}
}

/* ------------------------------------------------------------------ */
/* The grid                                                            */
/* ------------------------------------------------------------------ */

static void measure(int *out_rows, int *out_cols)
{
	int w = 0, h = 0;
	SDL_GetRendererOutputSize(renderer, &w, &h);
	*out_cols = (w - 2 * pad) / cell_w;
	*out_rows = (h - 2 * pad) / cell_h;
	if (*out_cols < 20) *out_cols = 20;
	if (*out_rows < 5) *out_rows = 5;
}

static void blank(cell_t *c)
{
	c->cp = 0;
	c->face = 1;
	c->reverse = 0;
}

static void resize_grid(int r, int c)
{
	cell_t *g = malloc(sizeof(cell_t) * (size_t) r * (size_t) c);
	int i, j;

	if (!g) return;
	for (i = 0; i < r; i++)
		for (j = 0; j < c; j++) {
			if (grid && i < rows && j < cols)
				g[i * c + j] = grid[i * cols + j];
			else
				blank(&g[i * c + j]);
		}
	free(grid);
	grid = g;
	rows = r;
	cols = c;
	if (cur_row >= rows) cur_row = rows - 1;
	if (cur_col >= cols) cur_col = cols - 1;
}

static void update_scale(void)
{
	int ww = 0, wh = 0, dw = 0, dh = 0;
	SDL_GetWindowSize(window, &ww, &wh);
	SDL_GetRendererOutputSize(renderer, &dw, &dh);
	scale = (ww > 0) ? (float) dw / (float) ww : 1.0f;
	if (scale < 1.0f) scale = 1.0f;
}

int  screen_active(void) { return active; }
int  screen_rows(void)   { return rows; }
int  screen_cols(void)   { return cols; }
const char *screen_backend(void) { return "gui"; }

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

static void put(Uint32 cp, int reverse)
{
	cell_t *c = &grid[cur_row * cols + cur_col];
	c->cp = cp;
	c->face = (unsigned char) cur_face;
	c->reverse = (unsigned char) reverse;
	advance();
	dirty = 1;
}

void screen_clrtoeol(void)
{
	int j;
	for (j = cur_col; j < cols; j++)
		blank(&grid[cur_row * cols + j]);
	dirty = 1;
}

void screen_clear(void)
{
	int i;
	for (i = 0; i < rows * cols; i++)
		blank(&grid[i]);
	cur_row = cur_col = 0;
	dirty = 1;
}

void screen_addch(int c)
{
	int b = c & 0xFF;
	int rev = (c & SCR_REVERSE_CHAR) != 0;

	if (b == '\n') {
		/* like curses: clear the rest of the line, go to the next */
		screen_clrtoeol();
		if (cur_row < rows - 1) cur_row++;
		cur_col = 0;
	} else if (b == '\t') {
		do put(' ', rev); while (cur_col % 8 != 0 && cur_col != 0);
	} else if (b == '\r') {
		/* nothing */
	} else {
		put((Uint32) b, rev);
	}
}

void screen_addstr(const char *s)
{
	const unsigned char *p = (const unsigned char *) s;

	while (*p) {
		Uint32 cp;
		int n;

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

static void fill(int x, int y, int w, int h, long color)
{
	SDL_Color c = rgb(color);
	SDL_Rect r;
	r.x = x; r.y = y; r.w = w; r.h = h;
	SDL_SetRenderDrawColor(renderer, c.r, c.g, c.b, 255);
	SDL_RenderFillRect(renderer, &r);
}

static void draw_glyph(Uint32 cp, int style, int x, int y, long color)
{
	glyph_t *g;
	SDL_Color c = rgb(color);
	SDL_Rect dst;

	if (cp == 0 || cp == ' ') return;
	g = glyph(cp, style);
	if (!g) return;
	SDL_SetTextureColorMod(g->tex, c.r, c.g, c.b);
	dst.x = x;
	dst.y = y + (cell_h - g->h) / 2;
	/* wide glyphs are squeezed into the cell rather than overlapping */
	dst.w = g->w > cell_w + cell_w / 4 ? cell_w : g->w;
	dst.h = g->h;
	SDL_RenderCopy(renderer, g->tex, NULL, &dst);
}

static void cell_colors(const cell_t *c, long *fg, long *bg, int *style, int *underline)
{
	int f = c->face, a = face_attr[f];
	long tmp;

	*fg = resolve(face_fg[f], default_fg);
	*bg = resolve(face_bg[f], default_bg);
	if (a & SCR_REVERSE) { tmp = *fg; *fg = *bg; *bg = tmp; }
	if (c->reverse)      { tmp = *fg; *fg = *bg; *bg = tmp; }
	if (a & SCR_DIM) {
		/* halfway towards the background */
		*fg = ((((*fg >> 16) & 0xFF) + ((*bg >> 16) & 0xFF)) / 2) << 16
		    | ((((*fg >> 8) & 0xFF) + ((*bg >> 8) & 0xFF)) / 2) << 8
		    | (((*fg & 0xFF) + (*bg & 0xFF)) / 2);
	}
	*style = ((a & SCR_BOLD) ? 1 : 0) | ((a & SCR_ITALIC) ? 2 : 0);
	*underline = (a & SCR_UNDERLINE) != 0;
}

static void render(void)
{
	int i, j;
	long dbg = resolve(-1, default_bg);

	if (!active) return;
	fill(0, 0, 100000, 100000, dbg);
	for (i = 0; i < rows; i++)
		for (j = 0; j < cols; j++) {
			const cell_t *c = &grid[i * cols + j];
			long fg, bg;
			int style, underline;
			int x = pad + j * cell_w, y = pad + i * cell_h;

			cell_colors(c, &fg, &bg, &style, &underline);
			if (bg != dbg) {
				/* rows of the same background are filled to the edge */
				fill(x, y, cell_w, cell_h, bg);
				if (j == cols - 1) fill(x + cell_w, y, 100000, cell_h, bg);
			}
			draw_glyph(c->cp, style, x, y, fg);
			if (underline)
				fill(x, y + cell_h - (int) scale - 1, cell_w, (int) scale, fg);
		}

	/* the cursor: a block when focused, an outline otherwise */
	{
		const cell_t *c = &grid[cur_row * cols + cur_col];
		int x = pad + cur_col * cell_w, y = pad + cur_row * cell_h;
		long fg, bg;
		int style, underline;

		cell_colors(c, &fg, &bg, &style, &underline);
		if (focused) {
			fill(x, y, cell_w, cell_h, cursor_color);
			draw_glyph(c->cp, style, x, y, bg);
		} else {
			SDL_Color cc = rgb(cursor_color);
			SDL_Rect r;
			r.x = x; r.y = y; r.w = cell_w; r.h = cell_h;
			SDL_SetRenderDrawColor(renderer, cc.r, cc.g, cc.b, 255);
			SDL_RenderDrawRect(renderer, &r);
		}
	}
	SDL_RenderPresent(renderer);
	dirty = 0;
}

void screen_refresh(void) { render(); }

void screen_set_title(const char *t)
{
	char full[300];
	if (!t || strcmp(t, title) == 0) return;
	strncpy(title, t, sizeof(title) - 1);
	snprintf(full, sizeof(full), "%s - SBEmacs", title);
	if (window) SDL_SetWindowTitle(window, full);
}

void screen_set_clipboard(const char *text)
{
	if (active && text) SDL_SetClipboardText(text);
}

/* paste the system clipboard: put it in the editor's scrap and yank */
static void paste_clipboard(void)
{
	char *text, *copy, *s, *d;

	if (!SDL_HasClipboardText()) return;
	text = SDL_GetClipboardText();
	if (!text) return;
	copy = malloc(strlen(text) + 1);
	if (copy) {
		/* CRLF and CR line ends become LF */
		for (s = text, d = copy; *s; s++) {
			if (*s == '\r') {
				*d++ = '\n';
				if (s[1] == '\n') s++;
			} else {
				*d++ = *s;
			}
		}
		*d = '\0';
		if (copy[0]) {
			set_scrap((unsigned char *) copy);
			push_byte(0x19);            /* C-y */
		} else {
			free(copy);
		}
	}
	SDL_free(text);
}

/* ------------------------------------------------------------------ */
/* Keyboard and mouse                                                  */
/* ------------------------------------------------------------------ */

static int suppress_text = 0;   /* the key-down was handled; skip its text */

static const char *special_key(SDL_Keycode k)
{
	switch (k) {
	case SDLK_UP:        return "\x1b[A";
	case SDLK_DOWN:      return "\x1b[B";
	case SDLK_RIGHT:     return "\x1b[C";
	case SDLK_LEFT:      return "\x1b[D";
	case SDLK_HOME:      return "\x1bOH";
	case SDLK_END:       return "\x1bOF";
	case SDLK_PAGEUP:    return "\x1b[5~";
	case SDLK_PAGEDOWN:  return "\x1b[6~";
	case SDLK_INSERT:    return "\x1b[2~";
	case SDLK_DELETE:    return "\x1b[3~";
	case SDLK_BACKSPACE: return "\x7f";
	case SDLK_RETURN:
	case SDLK_KP_ENTER:  return "\r";
	case SDLK_TAB:       return "\t";
	case SDLK_ESCAPE:    return "\x1b";
	case SDLK_F1:        return "\x1bOP";
	default:             return NULL;
	}
}

static int is_meta(Uint16 mod)
{
	if (!option_is_meta) return 0;
#if defined(__APPLE__)
	return (mod & KMOD_ALT) != 0;
#else
	/* right Alt is AltGr on many layouts: leave it for text */
	return (mod & KMOD_LALT) != 0 && !(mod & KMOD_RALT);
#endif
}

static void key_down(SDL_KeyboardEvent *e)
{
	SDL_Keycode k = e->keysym.sym;
	Uint16 mod = e->keysym.mod;
	int ctrl = (mod & KMOD_CTRL) != 0;
	int meta = is_meta(mod);
	int shift = (mod & KMOD_SHIFT) != 0;
	const char *seq = special_key(k);

	suppress_text = 0;

#if defined(_WIN32)
	/* AltGr arrives as Ctrl+Alt: it types text */
	if ((mod & KMOD_RALT) && (mod & KMOD_LCTRL)) return;
#endif

#if defined(__APPLE__)
	/* the usual Mac shortcuts */
	if (mod & KMOD_GUI) {
		suppress_text = 1;
		switch (k) {
		case SDLK_v: paste_clipboard(); return;
		case SDLK_c: push_string("\x1bw"); return;      /* copy-region */
		case SDLK_x: push_byte(0x17); return;           /* kill-region */
		case SDLK_z:                                    /* undo, Shift: redo */
			if (shift) push_string("\x1b\x1f"); else push_byte(0x15);
			return;
		case SDLK_s: push_string("\x18\x13"); return;   /* save */
		case SDLK_q: push_string("\x18\x03"); return;   /* exit */
		case SDLK_EQUALS: case SDLK_PLUS:
			screen_set_font(NULL, font_points + 1); return;
		case SDLK_MINUS:
			if (font_points > 6) screen_set_font(NULL, font_points - 1); return;
		default: suppress_text = 0; return;
		}
	}
#endif
	if (k == SDLK_INSERT && shift) {    /* Shift-Insert pastes everywhere */
		paste_clipboard();
		suppress_text = 1;
		return;
	}
	if (ctrl && (k == SDLK_EQUALS || k == SDLK_PLUS)) {
		screen_set_font(NULL, font_points + 1);
		suppress_text = 1;
		return;
	}
	if (ctrl && k == SDLK_MINUS) {
		if (font_points > 6) screen_set_font(NULL, font_points - 1);
		suppress_text = 1;
		return;
	}

	if (seq) {
		/* C-backspace is M-backspace (backward-kill-word) */
		if (meta || (ctrl && k == SDLK_BACKSPACE)) push_byte(0x1b);
		push_string(seq);
		suppress_text = 1;
		return;
	}

	if (ctrl) {
		int b = -1;
		if (k >= SDLK_a && k <= SDLK_z) b = (int) (k - SDLK_a + 1);
		else if (k == SDLK_SPACE || k == SDLK_2 || k == SDLK_AT) b = 0;
		else if (k == SDLK_LEFTBRACKET) b = 0x1b;
		else if (k == SDLK_BACKSLASH) b = 0x1c;
		else if (k == SDLK_RIGHTBRACKET) b = 0x1d;
		else if (k == SDLK_6) b = 0x1e;
		else if (k == SDLK_MINUS || k == SDLK_SLASH || k == SDLK_UNDERSCORE) b = 0x1f;
		if (b >= 0) {
			if (meta) push_byte(0x1b);
			push_byte(b);
			suppress_text = 1;
		}
		return;
	}

	if (meta && k >= 32 && k < 127) {
		int ch = (int) k;
		if (shift && ch >= 'a' && ch <= 'z') ch -= 32;
		else if (shift) {
			/* shifted punctuation on a US layout */
			static const char *plain = "`1234567890-=[]\\;',./";
			static const char *shifted = "~!@#$%^&*()_+{}|:\"<>?";
			const char *p = strchr(plain, ch);
			if (p) ch = shifted[p - plain];
		}
		push_byte(0x1b);
		push_byte(ch);
		suppress_text = 1;
	}
}

/* a mouse event in the xterm SGR encoding the core understands (key.c) */
static int mouse_last_row = -1, mouse_last_col = -1;

static void push_mouse(int button, int px, int py, int release)
{
	char buf[48];
	int col = ((int) (px * scale) - pad) / cell_w;
	int row = ((int) (py * scale) - pad) / cell_h;
	if (col < 0) col = 0;
	if (row < 0) row = 0;
	if (col >= cols) col = cols - 1;
	if (row >= rows) row = rows - 1;
	if (button & 32) {              /* motion: only when the cell changes */
		if (row == mouse_last_row && col == mouse_last_col) return;
	}
	mouse_last_row = row;
	mouse_last_col = col;
	snprintf(buf, sizeof(buf), "\x1b[<%d;%d;%d%c", button, col + 1, row + 1, release ? 'm' : 'M');
	push_string(buf);
}

static void handle(SDL_Event *e)
{
	switch (e->type) {
	case SDL_QUIT:
		push_string("\x18\x03");           /* C-x C-c asks about unsaved buffers */
		break;
	case SDL_WINDOWEVENT:
		switch (e->window.event) {
		case SDL_WINDOWEVENT_SIZE_CHANGED: {
			int r, c;
			float old = scale;
			update_scale();
			if (scale != old) load_fonts();
			measure(&r, &c);
			if (r != rows || c != cols) {
				resize_grid(r, c);
				push_byte(SCR_KEY_RESIZE);
			}
			render();
			break;
		}
		case SDL_WINDOWEVENT_EXPOSED:
			render();
			break;
		case SDL_WINDOWEVENT_FOCUS_GAINED:
			focused = 1; render();
			break;
		case SDL_WINDOWEVENT_FOCUS_LOST:
			focused = 0; render();
			break;
		}
		break;
	case SDL_KEYDOWN:
		key_down(&e->key);
		break;
	case SDL_TEXTINPUT:
		if (suppress_text) suppress_text = 0;
		else push_string(e->text.text);
		break;
	case SDL_MOUSEBUTTONDOWN:
		if (e->button.button == SDL_BUTTON_LEFT)
			push_mouse(0, e->button.x, e->button.y, 0);
		else if (e->button.button == SDL_BUTTON_MIDDLE)
			paste_clipboard();
		break;
	case SDL_MOUSEMOTION:
		if (e->motion.state & SDL_BUTTON_LMASK)
			push_mouse(32, e->motion.x, e->motion.y, 0);
		break;
	case SDL_MOUSEBUTTONUP:
		if (e->button.button == SDL_BUTTON_LEFT)
			push_mouse(0, e->button.x, e->button.y, 1);
		break;
	}
}

/*
 * Like curses' getch(), which refreshes the terminal before it waits: the
 * prompts of the C core (C-x C-f, C-s, query-replace...) write to the
 * grid and then wait for a key, without asking for a refresh.  Without
 * this the window would show nothing of them, and seem frozen.
 */
int screen_getch(void)
{
	SDL_Event e;

	if (queue_empty() && dirty) render();
	while (queue_empty()) {
		if (!SDL_WaitEvent(&e)) continue;
		handle(&e);
		/* take everything that is already waiting */
		while (SDL_PollEvent(&e)) handle(&e);
	}
	return pop_byte();
}

/* ------------------------------------------------------------------ */
/* Life cycle                                                          */
/* ------------------------------------------------------------------ */

static void hints(void)
{
	/* SBCL owns the signals */
	SDL_SetHint(SDL_HINT_NO_SIGNAL_HANDLERS, "1");
	SDL_SetHint(SDL_HINT_MOUSE_FOCUS_CLICKTHROUGH, "1");
#ifdef SDL_HINT_VIDEO_X11_NET_WM_BYPASS_COMPOSITOR
	SDL_SetHint(SDL_HINT_VIDEO_X11_NET_WM_BYPASS_COMPOSITOR, "0");
#endif
}

/* a real windowing system, not SDL's offscreen, dummy or framebuffer drivers */
static int usable_driver(void)
{
	static const char *real[] = { "x11", "wayland", "cocoa", "windows", "winrt", NULL };
	const char *d = SDL_GetCurrentVideoDriver();
	int i;
	for (i = 0; d && real[i]; i++)
		if (strcmp(d, real[i]) == 0) return 1;
	return 0;
}

int screen_probe(void)
{
	int ok;
	hints();
	ok = SDL_Init(SDL_INIT_VIDEO) == 0 && usable_driver();
	SDL_Quit();
	return ok;
}

int screen_init(int mouse)
{
	int i, r, c;

	(void) mouse;                        /* the mouse is always on */
	hints();
	if (SDL_Init(SDL_INIT_VIDEO) != 0) {
		fprintf(stderr, "sbemacs: SDL_Init: %s\n", SDL_GetError());
		return 0;
	}
	if (TTF_Init() != 0) {
		fprintf(stderr, "sbemacs: TTF_Init: %s\n", TTF_GetError());
		return 0;
	}
	window = SDL_CreateWindow("SBEmacs", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
				  800, 600,
				  SDL_WINDOW_RESIZABLE | SDL_WINDOW_ALLOW_HIGHDPI | SDL_WINDOW_HIDDEN);
	if (!window) {
		fprintf(stderr, "sbemacs: SDL_CreateWindow: %s\n", SDL_GetError());
		return 0;
	}
	renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED);
	if (!renderer)
		renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_SOFTWARE);
	if (!renderer) {
		fprintf(stderr, "sbemacs: SDL_CreateRenderer: %s\n", SDL_GetError());
		return 0;
	}
	update_scale();
	if (!load_fonts())
		return 0;

	/* 100 x 34 cells to start with */
	SDL_SetWindowSize(window,
			  (int) ((100 * cell_w + 2 * pad) / scale),
			  (int) ((34 * cell_h + 2 * pad) / scale));
	SDL_ShowWindow(window);
	update_scale();
	measure(&r, &c);
	resize_grid(r, c);
	for (i = 0; i < rows * cols; i++) blank(&grid[i]);
	for (i = 0; i <= MAX_FACE; i++) { face_fg[i] = -1; face_bg[i] = -1; face_attr[i] = 0; }

	SDL_StartTextInput();
	active = 1;
	return 1;
}

void screen_end(void)
{
	if (!active) return;
	active = 0;
	clear_glyphs();
	close_fonts();
	if (renderer) SDL_DestroyRenderer(renderer);
	if (window) SDL_DestroyWindow(window);
	renderer = NULL;
	window = NULL;
	TTF_Quit();
	SDL_Quit();
}

/* options set from Lisp (lisp/gui.lisp) */
void screen_set_option(const char *name, int value)
{
	if (strcmp(name, "option-is-meta") == 0) option_is_meta = value;
}
