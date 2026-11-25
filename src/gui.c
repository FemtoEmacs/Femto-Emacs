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

#define MAX_FACE 127             /* interface.c's FE_MAX_COLOR */
extern int term_poll_ms(void);    /* terminal.c */
#define PAD 4                   /* margin around the text, in points */

#define NMARK 6                 /* 👨‍👩‍👧: the man, then four more */
typedef struct {
	Uint32 cp;                  /* Unicode code point, 0 = blank, WIDE_TAIL =
	                               the right half of the cell before */
	Uint32 mark[NMARK];         /* drawn with cp, 0 = none: combining accents,
	                               and the rest of an emoji sequence */
	unsigned char face;         /* ID_COLOR_* */
	unsigned char reverse;      /* the mark */
} cell_t;
#define WIDE_TAIL 0xFFFFFFFFu
extern int char_width(unsigned long);   /* width.c */
extern int screen_clusters;             /* display.c */

static SDL_Window   *window = NULL;
static SDL_Renderer *renderer = NULL;
static TTF_Font     *fonts[4];  /* regular, bold, italic, bold italic */
/* fonts for the characters the main font has not (Hangul, Chinese ...),
 * in the order of wide_candidates; NULL where absent */
#define NWIDE 4
static TTF_Font     *wide_fonts[NWIDE];
static TTF_Font     *emoji_font = NULL;  /* the system's colour emoji, or NULL */
static void clear_emoji(void);
static TTF_Font     *font_for(Uint32 cp, int style);
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
			surf = TTF_RenderUTF8_Blended(font_for(cp, style), utf8, white);
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

/* Fonts for what a Latin monospace font has not: Menlo, DejaVu Sans Mono
 * and Consolas have no Hangul nor Chinese characters, which would show as
 * boxes (M-x korean-input, M-x chinese-input).  The first that exists of
 * each line is opened, at the size of the main font. */
static const char *wide_candidates[NWIDE][4] = {
#if defined(__APPLE__)
	{ "/System/Library/Fonts/AppleSDGothicNeo.ttc", NULL },
	{ "/System/Library/Fonts/Hiragino Sans GB.ttc", "/System/Library/Fonts/STHeiti Medium.ttc", NULL },
	{ "/System/Library/Fonts/Supplemental/Arial Unicode.ttf", "/Library/Fonts/Arial Unicode.ttf", NULL },
	{ NULL },
#elif defined(_WIN32)
	{ "C:\\Windows\\Fonts\\malgun.ttf", NULL },
	{ "C:\\Windows\\Fonts\\msyh.ttc", "C:\\Windows\\Fonts\\simsun.ttc", NULL },
	{ "C:\\Windows\\Fonts\\seguisym.ttf", NULL },
	{ NULL },
#else
	{ "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
	  "/usr/share/fonts/noto-cjk/NotoSansCJK-Regular.ttc",
	  "/usr/share/fonts/google-noto-cjk/NotoSansCJK-Regular.ttc", NULL },
	{ "/usr/share/fonts/truetype/nanum/NanumGothic.ttf",
	  "/usr/share/fonts/truetype/unfonts-core/UnDotum.ttf", NULL },
	{ "/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf",
	  "/usr/share/fonts/truetype/arphic/uming.ttc", NULL },
	{ "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", NULL },
#endif
};

static int has_glyph(TTF_Font *f, Uint32 cp)
{
#if SDL_TTF_VERSION_ATLEAST(2, 0, 18)
	return TTF_GlyphIsProvided32(f, cp) != 0;
#else
	return cp < 0x10000 && TTF_GlyphIsProvided(f, (Uint16) cp) != 0;
#endif
}

/* The font that draws CP: the main one, or the first fallback that has it */
static TTF_Font *font_for(Uint32 cp, int style)
{
	int i;

	if (cp < 0x370 || has_glyph(fonts[style], cp)) return fonts[style];
	for (i = 0; i < NWIDE; i++)
		if (wide_fonts[i] && has_glyph(wide_fonts[i], cp)) {
			TTF_SetFontStyle(wide_fonts[i], style & 1 ? TTF_STYLE_BOLD : TTF_STYLE_NORMAL);
			return wide_fonts[i];
		}
	return fonts[style];
}

static const char *emoji_candidates[] = {
#if defined(__APPLE__)
	"/System/Library/Fonts/Apple Color Emoji.ttc",
#elif defined(_WIN32)
	"C:\\Windows\\Fonts\\seguiemj.ttf",
#else
	"/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf",
	"/usr/share/fonts/noto/NotoColorEmoji.ttf",
	"/usr/share/fonts/google-noto-emoji/NotoColorEmoji.ttf",
	"/usr/share/fonts/TTF/NotoColorEmoji.ttf",
#endif
	NULL
};

static void open_wide_fonts(int px)
{
	int i, k;

	clear_emoji();
	if (emoji_font) TTF_CloseFont(emoji_font);
	emoji_font = NULL;
	for (k = 0; emoji_candidates[k] && !emoji_font; k++)
		emoji_font = TTF_OpenFontIndex(emoji_candidates[k], px, 0);

	for (i = 0; i < NWIDE; i++) {
		if (wide_fonts[i]) TTF_CloseFont(wide_fonts[i]);
		wide_fonts[i] = NULL;
		for (k = 0; k < 4 && wide_candidates[i][k] && !wide_fonts[i]; k++)
			wide_fonts[i] = TTF_OpenFontIndex(wide_candidates[i][k], px, 0);
		if (wide_fonts[i]) TTF_SetFontHinting(wide_fonts[i], TTF_HINTING_LIGHT);
	}
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
			fprintf(stderr, "chezemax: no usable monospace font found; "
				"set one with (set-gui-font \"/path/to/font.ttf\" 14)\n");
			return 0;
		}
	}
	open_wide_fonts((int) (font_points * scale + 0.5f));
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
	memset(c->mark, 0, sizeof c->mark);
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

/* the cell of the character before the cursor, or NULL at a row's start */
static cell_t *cell_before(void)
{
	cell_t *row = grid + cur_row * cols, *c;
	if (cur_col == 0) return NULL;
	c = row + cur_col - 1;
	if (c->cp == WIDE_TAIL && c > row) c--;
	return c;
}

static void add_mark(cell_t *c, Uint32 cp)
{
	int k;
	for (k = 0; k < NMARK; k++)
		if (c->mark[k] == 0) { c->mark[k] = cp; return; }
}

/* the cell at the cursor becomes the right half of the one before */
static void tail_here(int reverse)
{
	cell_t *c = &grid[cur_row * cols + cur_col];
	c->cp = WIDE_TAIL;
	memset(c->mark, 0, sizeof c->mark);
	c->face = (unsigned char) cur_face;
	c->reverse = (unsigned char) reverse;
	advance();
}

static int regional(Uint32 cp) { return cp >= 0x1F1E6 && cp <= 0x1F1FF; }

/*
 * A character into the cell at the cursor.  A combining accent (width 0,
 * width.c) joins the character in the cell before; a wide one takes the
 * next cell too, marked WIDE_TAIL, on the same row (display.c never
 * starts one in the last column).  An emoji sequence is one picture in two
 * cells, as display.c counts it (screen_clusters, cluster_cell_width): the
 * selector U+FE0F widens the heart before it to two cells; an emoji after
 * U+200D joins the one before (the family); a second regional letter joins
 * the first, and the flag takes two cells.
 */
static int joining = 0;         /* the character before was U+200D */

static void put(Uint32 cp, int reverse)
{
	cell_t *c = &grid[cur_row * cols + cur_col], *before = cell_before();
	int width = cp >= 0x300 ? char_width(cp) : 1;
	int join = joining;

	joining = 0;
	if (before && join && width == 2) { add_mark(before, cp); dirty = 1; return; }
	if (before && cp == 0xFE0F) {
		add_mark(before, cp);
		if (before == c - 1 && char_width(before->cp) == 1 && cur_col < cols) tail_here(reverse);
		dirty = 1;
		return;
	}
	if (before && regional(cp) && before == c - 1 && regional(before->cp) && before->mark[0] == 0 &&
	    cur_col < cols) {
		add_mark(before, cp);
		tail_here(reverse);
		dirty = 1;
		return;
	}
	if (width == 0) {
		if (before) c = before;
		add_mark(c, cp);
		joining = cp == 0x200D;
		dirty = 1;
		return;
	}
	c->cp = cp;
	memset(c->mark, 0, sizeof c->mark);
	c->face = (unsigned char) cur_face;
	c->reverse = (unsigned char) reverse;
	advance();
	if (width == 2 && cur_col > 0) tail_here(reverse);
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
	int span = cp >= 0x1100 && char_width(cp) == 2 ? 2 : 1;

	if (cp == 0 || cp == ' ' || cp == WIDE_TAIL) return;
	g = glyph(cp, style);
	if (!g) return;
	SDL_SetTextureColorMod(g->tex, c.r, c.g, c.b);
	dst.x = x;
	dst.y = y + (cell_h - g->h) / 2;
	/* a glyph wider than its cells is squeezed rather than overlapping;
	 * a wide character (CJK, emoji) has two cells */
	dst.w = g->w > span * cell_w + cell_w / 4 ? span * cell_w : g->w;
	dst.h = g->h;
	if (span == 2 && g->w > 0 && g->w < 2 * cell_w) {
		/* narrower than its two cells (Hangul, CJK in a Latin font's
		 * cells): widened to fill them (by at most 30%, at most 10%
		 * taller, within its row) and centred, or 이상순 reads 이 상 순 */
		double kx = (double) (2 * cell_w) / g->w, ky;
		if (kx > 1.3) kx = 1.3;
		ky = kx < 1.1 ? kx : 1.1;
		if (g->h * ky > cell_h) ky = (double) cell_h / g->h;
		dst.w = (int) (g->w * kx + 0.5);
		dst.h = (int) (g->h * ky + 0.5);
		dst.x = x + (2 * cell_w - dst.w) / 2;
		dst.y = y + (cell_h - dst.h) / 2;
	}
	SDL_RenderCopy(renderer, g->tex, NULL, &dst);
}

/*
 * Emoji: the window's font has none, so they come from the system's colour
 * emoji font (emoji_font), as a sequence: the heart with its selector, a
 * flag's two letters, a family joined by U+200D become one picture, drawn
 * in their colours (not tinted with the face) and scaled into the cells
 * the sequence takes.  Cached by sequence: the window is painted whole on
 * every change.
 */
static int is_emoji(const cell_t *cell)
{
	int k;
	if (!emoji_font || cell->cp == 0 || cell->cp == WIDE_TAIL) return 0;
	if (cell->cp >= 0x1F000 && cell->cp <= 0x1FAFF) return 1;
	for (k = 0; k < NMARK && cell->mark[k]; k++)
		if (cell->mark[k] == 0xFE0F || cell->mark[k] == 0x200D) return 1;
	return 0;
}

#define ECACHE 256
typedef struct {
	Uint32 cps[NMARK + 1];      /* the sequence, cps[0] == 0: empty */
	SDL_Texture *tex;
	int w, h;
} emoji_t;
static emoji_t ecache[ECACHE];

static void clear_emoji(void)
{
	int i;
	for (i = 0; i < ECACHE; i++) {
		if (ecache[i].tex) SDL_DestroyTexture(ecache[i].tex);
		memset(&ecache[i], 0, sizeof ecache[i]);
	}
}

static emoji_t *emoji(const cell_t *cell)
{
	Uint32 h = cell->cp * 2654435761u;
	char utf8[4 * (NMARK + 1) + 1];
	SDL_Color white = { 255, 255, 255, 255 };
	SDL_Surface *surf;
	int k, n, probes;

	for (k = 0; k < NMARK; k++) h = (h ^ cell->mark[k]) * 16777619u;
	for (probes = 0; probes < ECACHE; probes++) {
		emoji_t *e = &ecache[(h + (Uint32) probes) % ECACHE];
		if (e->cps[0] == cell->cp && memcmp(e->cps + 1, cell->mark, sizeof cell->mark) == 0)
			return e->tex ? e : NULL;
		if (e->cps[0] == 0) {
			n = encode_utf8(cell->cp, utf8);
			for (k = 0; k < NMARK && cell->mark[k]; k++) n += encode_utf8(cell->mark[k], utf8 + n);
			e->cps[0] = cell->cp;
			memcpy(e->cps + 1, cell->mark, sizeof cell->mark);
			surf = TTF_RenderUTF8_Blended(emoji_font, utf8, white);
			if (!surf) return NULL;
			e->tex = SDL_CreateTextureFromSurface(renderer, surf);
			e->w = surf->w;
			e->h = surf->h;
			SDL_FreeSurface(surf);
			return e->tex ? e : NULL;
		}
	}
	clear_emoji();              /* full: start again */
	return emoji(cell);
}

static void draw_emoji(const cell_t *cell, int span, int x, int y)
{
	emoji_t *e = emoji(cell);
	SDL_Rect dst;
	double k;

	if (!e || e->w <= 0 || e->h <= 0) return;
	k = (double) (span * cell_w) / e->w;
	if (e->h * k > cell_h) k = (double) cell_h / e->h;
	dst.w = (int) (e->w * k + 0.5);
	dst.h = (int) (e->h * k + 0.5);
	dst.x = x + (span * cell_w - dst.w) / 2;
	dst.y = y + (cell_h - dst.h) / 2;
	SDL_RenderCopy(renderer, e->tex, NULL, &dst);
}

/* A cell's character with its combining accents, rendered together (not
 * cached: accents are rare) so that the font places them.  SPAN: the
 * cells it takes, 2 when the next is its right half. */
static void draw_cell(const cell_t *cell, int style, int x, int y, long color, int span)
{
	char utf8[4 * (NMARK + 1) + 1];
	int n, k;
	SDL_Color c = rgb(color);
	SDL_Surface *surf;
	SDL_Texture *tex;
	SDL_Rect dst;

	if (is_emoji(cell)) {
		draw_emoji(cell, span, x, y);
		return;
	}
	if (cell->mark[0] == 0 || cell->cp == 0 || cell->cp == WIDE_TAIL) {
		draw_glyph(cell->cp, style, x, y, color);
		return;
	}
	n = encode_utf8(cell->cp, utf8);
	for (k = 0; k < NMARK && cell->mark[k]; k++) n += encode_utf8(cell->mark[k], utf8 + n);
	surf = TTF_RenderUTF8_Blended(fonts[style], utf8, c);
	if (!surf) return;
	tex = SDL_CreateTextureFromSurface(renderer, surf);
	if (tex) {
		dst.x = x;
		dst.y = y + (cell_h - surf->h) / 2;
		dst.w = surf->w > cell_w + cell_w / 4 ? cell_w : surf->w;
		dst.h = surf->h;
		SDL_RenderCopy(renderer, tex, NULL, &dst);
		SDL_DestroyTexture(tex);
	}
	SDL_FreeSurface(surf);
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
	/* backgrounds first, then glyphs: a wide glyph spans the next cell */
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
		}
	for (i = 0; i < rows; i++)
		for (j = 0; j < cols; j++) {
			const cell_t *c = &grid[i * cols + j];
			long fg, bg;
			int style, underline;
			int x = pad + j * cell_w, y = pad + i * cell_h;

			cell_colors(c, &fg, &bg, &style, &underline);
			draw_cell(c, style, x, y, fg,
			          j + 1 < cols && grid[i * cols + j + 1].cp == WIDE_TAIL ? 2 : 1);
			if (underline)
				fill(x, y + cell_h - (int) scale - 1, cell_w, (int) scale, fg);
		}

	/* the cursor: a block when focused, an outline otherwise */
	{
		const cell_t *c = &grid[cur_row * cols + cur_col];
		int x = pad + cur_col * cell_w, y = pad + cur_row * cell_h;
		long fg, bg;
		int style, underline;

		int span = cur_col + 1 < cols && grid[cur_row * cols + cur_col + 1].cp == WIDE_TAIL ? 2 : 1;

		cell_colors(c, &fg, &bg, &style, &underline);
		if (focused) {
			/* as wide as the emoji, CJK character it is on */
			fill(x, y, span * cell_w, cell_h, cursor_color);
			draw_cell(c, style, x, y, bg, span);
		} else {
			SDL_Color cc = rgb(cursor_color);
			SDL_Rect r;
			r.x = x; r.y = y; r.w = span * cell_w; r.h = cell_h;
			SDL_SetRenderDrawColor(renderer, cc.r, cc.g, cc.b, 255);
			SDL_RenderDrawRect(renderer, &r);
		}
	}
	SDL_RenderPresent(renderer);
	dirty = 0;
}

void screen_refresh(void) { render(); }

void screen_pause(int ms)
{
	if (dirty) render();
	SDL_Delay((Uint32) ms);
}

void screen_set_title(const char *t)
{
	char full[300];
	if (!t || strcmp(t, title) == 0) return;
	strncpy(title, t, sizeof(title) - 1);
	snprintf(full, sizeof(full), "%s - Chezweb", title);
	if (window) SDL_SetWindowTitle(window, full);
}

void screen_set_clipboard(const char *text)
{
	if (active && text) SDL_SetClipboardText(text);
}

/* CRLF and CR line ends become LF, in place */
static void unix_line_ends(char *t)
{
	char *s, *d;
	for (s = t, d = t; *s; s++) {
		if (*s == '\r') {
			*d++ = '\n';
			if (s[1] == '\n') s++;
		} else {
			*d++ = *s;
		}
	}
	*d = '\0';
}

const char *screen_clipboard_tool(void) { return "SDL"; }

char *screen_get_clipboard(void)
{
	char *text, *copy;

	if (!active || !SDL_HasClipboardText()) return NULL;
	text = SDL_GetClipboardText();
	if (!text) return NULL;
	copy = malloc(strlen(text) + 1);
	if (copy) {
		strcpy(copy, text);
		unix_line_ends(copy);
	}
	SDL_free(text);
	return copy;
}

/* NULL also when the clipboard holds exactly the N bytes of SAME (then
 * *WAS_SAME is 1); *LEN its bytes (a C string here: no NUL in it) */
char *screen_get_clipboard_unless(const char *same, size_t n, size_t *len, int *was_same)
{
	char *text = screen_get_clipboard();
	if (len) *len = text ? strlen(text) : 0;
	if (was_same) *was_same = 0;
	if (text && same && strlen(text) == n && memcmp(text, same, n) == 0) {
		free(text);
		if (len) *len = 0;
		if (was_same) *was_same = 1;
		return NULL;
	}
	return text;
}

/* paste the system clipboard: put it in the editor's scrap and yank */
static void paste_clipboard(void)
{
	char *copy = screen_get_clipboard();

	if (!copy) return;
	if (copy[0]) {
		set_scrap((unsigned char *) copy);
		push_byte(0x19);            /* C-y */
	} else {
		free(copy);
	}
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
		else
			push_mouse(35, e->motion.x, e->motion.y, 0);
		break;
	case SDL_MOUSEBUTTONUP:
		if (e->button.button == SDL_BUTTON_LEFT)
			push_mouse(0, e->button.x, e->button.y, 1);
		break;
	case SDL_MOUSEWHEEL: {
		/*
		 * The wheel, as a terminal reports it: button 64 up, 65 down,
		 * one report a notch, at the pointer.  The direction is the
		 * system's (natural scrolling on a Mac included).
		 */
		int x, y, notches = e->wheel.y, i;
		SDL_GetMouseState(&x, &y);
		if (notches > 5) notches = 5;
		if (notches < -5) notches = -5;
		for (i = 0; i < (notches < 0 ? -notches : notches); i++)
			push_mouse(notches > 0 ? 64 : 65, x, y, 0);
		break;
	}
	}
}

/*
 * Like curses' getch(), which refreshes the terminal before it waits: the
 * prompts of the C core (C-x C-f, C-s, query-replace...) write to the
 * grid and then wait for a key, without asking for a refresh.  Without
 * this the window would show nothing of them, and seem frozen.
 */
int screen_save_file(const char *path) { (void)path; return 1; }
int screen_getch(void)
{
	SDL_Event e;

	if (queue_empty() && dirty) render();
	while (queue_empty()) {
		if (editor_is_idle()) {
			if (!SDL_WaitEventTimeout(&e, term_poll_ms())) { editor_idle_poll(); continue; }
		} else if (!SDL_WaitEvent(&e)) continue;
		handle(&e);
		/* take everything that is already waiting */
		while (SDL_PollEvent(&e)) handle(&e);
	}
	return pop_byte();
}

/* the window draws its own cursor, which a terminal's dark cells do not hide */
void screen_cursor_shown(int on) { (void) on; }

int screen_key_waiting(int ms)
{
	SDL_Event e;
	Uint32 end = SDL_GetTicks() + (Uint32) ms;

	while (queue_empty()) {
		Sint32 left = (Sint32) (end - SDL_GetTicks());
		if (left <= 0 || !SDL_WaitEventTimeout(&e, left)) break;
		handle(&e);
		while (SDL_PollEvent(&e)) handle(&e);
	}
	return !queue_empty();
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
	screen_clusters = 1;                 /* display.c: emoji sequences in two cells */
	hints();
	if (SDL_Init(SDL_INIT_VIDEO) != 0) {
		fprintf(stderr, "chezemax: SDL_Init: %s\n", SDL_GetError());
		return 0;
	}
	if (TTF_Init() != 0) {
		fprintf(stderr, "chezemax: TTF_Init: %s\n", TTF_GetError());
		return 0;
	}
	window = SDL_CreateWindow("Chezweb", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
				  800, 600,
				  SDL_WINDOW_RESIZABLE | SDL_WINDOW_ALLOW_HIGHDPI | SDL_WINDOW_HIDDEN);
	if (!window) {
		fprintf(stderr, "chezemax: SDL_CreateWindow: %s\n", SDL_GetError());
		return 0;
	}
	renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED);
	if (!renderer)
		renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_SOFTWARE);
	if (!renderer) {
		fprintf(stderr, "chezemax: SDL_CreateRenderer: %s\n", SDL_GetError());
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

int screen_test_cancelled(void)
{
 SDL_Event e;
 int cancel = 0;
 while (SDL_PollEvent(&e)) {
  if (e.type == SDL_QUIT || (e.type == SDL_KEYDOWN &&
      (e.key.keysym.sym == SDLK_ESCAPE || (e.key.keysym.sym == SDLK_g && (e.key.keysym.mod & KMOD_CTRL))))) cancel = 1;
  if (e.type == SDL_WINDOWEVENT) {
   int old_rows = rows, old_cols = cols;
   handle(&e);
   if (old_rows != rows || old_cols != cols) cancel = 1;
  }
 }
 q_head = q_tail = 0;
 return cancel;
}

/* key.c, during a terminal paste: here a key byte at a time */
int screen_read_keys(unsigned char *buf, int max)
{
	int c = screen_getch();
	(void) max;
	if (c < 0) return c;
	buf[0] = (unsigned char) c;
	return 1;
}
