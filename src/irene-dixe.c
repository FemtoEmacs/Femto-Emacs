/*
 * irene-dixe.c -- draws the sketches that Chezemax's C-c p asks for
 *
 *   irene-dixe FILE [SAVE.png]   a window; s saves the picture, q or Esc closes
 *   irene-dixe --render FILE OUT write the picture to OUT (PNG; BMP if OUT ends in .bmp)
 *
 * FILE is written by scheme/extensions/sketch.scm, one record per line,
 * numbers in the data's own units:
 *
 *   title TEXT / subtitle TEXT
 *   xaxis LO HI LABEL / xticks T... / yaxis LO HI LABEL / yticks T...
 *   series I R G B DASHED LABEL      a curve and its legend entry
 *   seg I X1 Y1 X2 Y2                a horizontal or vertical step segment
 *   link I X1 Y1 X2 Y2               a dotted join between sampled landmarks
 *   point I X Y                      a sampled landmark (a dot)
 *   censor I X Y                     a censor tick
 *   gap I X1 X2 REASON               an unresolved interval (shaded)
 *   risktimes T... / risk I N...     numbers at risk under the plot
 *   stat TEXT / note TEXT / remark TEXT
 *
 * A file that starts with "table 1" is a printed table instead, written by
 * sketch.scm from a (data-table ...): see "Tables" below.
 *
 * Unknown records are ignored, so the format can grow (diagnostic-image
 * sketches will add their own).  Only SDL2 and SDL2_ttf are needed.
 */
#include <SDL.h>
#include <SDL_ttf.h>
#include <ctype.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_SERIES 16
#define MAX_ITEMS 4096
#define MAX_TICKS 64
#define MAX_TEXTS 32
#define TEXT_LEN 256

typedef struct { int series; double x1, y1, x2, y2; } seg_t;
typedef struct { int series; double x, y; } point_t;
typedef struct { int series; double x1, x2; } gap_t;
typedef struct { int r, g, b, dashed; char label[TEXT_LEN]; int used; } series_t;

static char title[TEXT_LEN], subtitle[TEXT_LEN], xlabel[TEXT_LEN], ylabel[TEXT_LEN];
static double xlo = 0, xhi = 1, ylo = 0, yhi = 1;
static double xticks[MAX_TICKS], yticks[MAX_TICKS], risktimes[MAX_TICKS];
static int nxticks, nyticks, nrisktimes;
static series_t series[MAX_SERIES];
static seg_t segs[MAX_ITEMS], links[MAX_ITEMS];
static point_t censors[MAX_ITEMS], points[MAX_ITEMS];
static int nlinks, npoints;
static gap_t gaps[MAX_SERIES * 4];
static int nsegs, ncensors, ngaps;
static char risk[MAX_SERIES][TEXT_LEN];
static char texts[MAX_TEXTS][TEXT_LEN];
static int ntexts;

static TTF_Font *font, *bold;
static float scale = 1.0f;
static char status[4600];
static int for_file;                 /* drawing a picture to save: no window hints */

/* ------------------------------------------------------------------ */
/* Reading the file                                                    */
/* ------------------------------------------------------------------ */

static void copy_text(char *to, const char *from)
{
	snprintf(to, TEXT_LEN, "%s", from ? from : "");
}

static const char *skip_fields(const char *s, int n)
{
	while (n-- > 0) {
		while (*s && !isspace((unsigned char) *s)) s++;
		while (*s == ' ') s++;
	}
	return s;
}

static int read_numbers(const char *s, double *out, int max)
{
	int n = 0;
	char *end;
	while (n < max) {
		double v = strtod(s, &end);
		if (end == s) break;
		out[n++] = v;
		s = end;
	}
	return n;
}

/* ------------------------------------------------------------------ */
/* Tables: a (data-table ...) shown as a table                         */
/* ------------------------------------------------------------------ */

/* FILE starts with "table 1" and has, besides title, subtitle and remark,
 *
 *   header<TAB>STUB<TAB>COLUMN 1<TAB>COLUMN 2 ...
 *   row DEPTH GROUP<TAB>LABEL<TAB>CELL 1<TAB>CELL 2 ...
 *
 * DEPTH is the indentation of a subcategory; GROUP is 1 for a row that has
 * subcategories under it (drawn in bold).  Cells are already printed text. */

#define MAX_ROWS 512
#define MAX_COLS 16
#define CELL_LEN 160

typedef struct { int depth, group, n; char cell[MAX_COLS][CELL_LEN]; } row_t;

static int is_table, ncols, nrows;
static char header[MAX_COLS][CELL_LEN];
static row_t rows[MAX_ROWS];
static int scroll_x, scroll_y;
static TTF_Font *strong;             /* bold at the body size: headers, groups */

/* Split the tab-separated fields after the first tab of LINE into OUT. */
static int split_tabs(const char *line, char out[][CELL_LEN], int max)
{
	const char *p = strchr(line, '\t');
	int n = 0;
	while (p && n < max) {
		const char *q = strchr(p + 1, '\t');
		size_t len = q ? (size_t) (q - p - 1) : strlen(p + 1);
		if (len >= CELL_LEN) len = CELL_LEN - 1;
		memcpy(out[n], p + 1, len);
		out[n][len] = '\0';
		n++;
		p = q;
	}
	return n;
}

static int read_table_record(const char *tag, const char *line, const char *rest)
{
	double v[2];
	if (!strcmp(tag, "table")) { is_table = 1; return 1; }
	if (!strcmp(tag, "header")) { ncols = split_tabs(line, header, MAX_COLS); return 1; }
	if (!strcmp(tag, "row") && nrows < MAX_ROWS && read_numbers(rest, v, 2) == 2) {
		row_t *row = &rows[nrows++];
		row->depth = (int) v[0];
		row->group = (int) v[1];
		row->n = split_tabs(line, row->cell, MAX_COLS);
		return 1;
	}
	return 0;
}

static int read_sketch(const char *path)
{
	FILE *f = fopen(path, "r");
	char line[4096];
	if (!f) { fprintf(stderr, "irene-dixe: cannot read %s\n", path); return 0; }
	while (fgets(line, sizeof(line), f)) {
		char tag[32];
		double v[8];
		size_t len = strlen(line);
		while (len && (line[len - 1] == '\n' || line[len - 1] == '\r')) line[--len] = '\0';
		if (sscanf(line, "%31s", tag) != 1) continue;
		const char *rest = skip_fields(line, 1);
		if (read_table_record(tag, line, rest)) continue;
		if (!strcmp(tag, "title")) copy_text(title, rest);
		else if (!strcmp(tag, "subtitle")) copy_text(subtitle, rest);
		else if (!strcmp(tag, "xaxis") && read_numbers(rest, v, 2) == 2) {
			xlo = v[0]; xhi = v[1]; copy_text(xlabel, skip_fields(rest, 2));
		} else if (!strcmp(tag, "yaxis") && read_numbers(rest, v, 2) == 2) {
			ylo = v[0]; yhi = v[1]; copy_text(ylabel, skip_fields(rest, 2));
		} else if (!strcmp(tag, "xticks")) nxticks = read_numbers(rest, xticks, MAX_TICKS);
		else if (!strcmp(tag, "yticks")) nyticks = read_numbers(rest, yticks, MAX_TICKS);
		else if (!strcmp(tag, "risktimes")) nrisktimes = read_numbers(rest, risktimes, MAX_TICKS);
		else if (!strcmp(tag, "series") && read_numbers(rest, v, 5) == 5) {
			int i = (int) v[0];
			if (i < 0 || i >= MAX_SERIES) continue;
			series[i].r = (int) v[1]; series[i].g = (int) v[2]; series[i].b = (int) v[3];
			series[i].dashed = (int) v[4];
			series[i].used = 1;
			copy_text(series[i].label, skip_fields(rest, 5));
		} else if (!strcmp(tag, "seg") && nsegs < MAX_ITEMS && read_numbers(rest, v, 5) == 5) {
			seg_t s = { (int) v[0], v[1], v[2], v[3], v[4] };
			segs[nsegs++] = s;
		} else if (!strcmp(tag, "link") && nlinks < MAX_ITEMS && read_numbers(rest, v, 5) == 5) {
			seg_t s = { (int) v[0], v[1], v[2], v[3], v[4] };
			links[nlinks++] = s;
		} else if (!strcmp(tag, "point") && npoints < MAX_ITEMS && read_numbers(rest, v, 3) == 3) {
			point_t p = { (int) v[0], v[1], v[2] };
			points[npoints++] = p;
		} else if (!strcmp(tag, "censor") && ncensors < MAX_ITEMS && read_numbers(rest, v, 3) == 3) {
			point_t p = { (int) v[0], v[1], v[2] };
			censors[ncensors++] = p;
		} else if (!strcmp(tag, "gap") && ngaps < MAX_SERIES * 4 && read_numbers(rest, v, 3) == 3) {
			gap_t g = { (int) v[0], v[1], v[2] };
			gaps[ngaps++] = g;
		} else if (!strcmp(tag, "risk") && read_numbers(rest, v, 1) == 1) {
			int i = (int) v[0];
			if (i >= 0 && i < MAX_SERIES) copy_text(risk[i], skip_fields(rest, 1));
		} else if ((!strcmp(tag, "stat") || !strcmp(tag, "note") || !strcmp(tag, "remark"))
			   && ntexts < MAX_TEXTS) {
			snprintf(texts[ntexts++], TEXT_LEN, "%s%s", strcmp(tag, "note") ? "" : "Check: ", rest);
		}
	}
	fclose(f);
	if (xhi <= xlo) xhi = xlo + 1;
	if (yhi <= ylo) yhi = ylo + 1;
	return 1;
}

/* ------------------------------------------------------------------ */
/* Fonts                                                               */
/* ------------------------------------------------------------------ */

static const char *font_candidates[] = {
#if defined(__APPLE__)
	"/System/Library/Fonts/Helvetica.ttc",
	"/System/Library/Fonts/Supplemental/Arial.ttf",
	"/Library/Fonts/Arial.ttf",
	"/System/Library/Fonts/Menlo.ttc",
#elif defined(_WIN32)
	"C:\\Windows\\Fonts\\arial.ttf",
	"C:\\Windows\\Fonts\\segoeui.ttf",
	"C:\\Windows\\Fonts\\consola.ttf",
#else
	"/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
	"/usr/share/fonts/dejavu/DejaVuSans.ttf",
	"/usr/share/fonts/TTF/DejaVuSans.ttf",
	"/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
	"/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf",
	"/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
#endif
	NULL
};

static int open_fonts(void)
{
	int i, px = (int) (13 * scale + 0.5f);
	if (strong && strong != font) TTF_CloseFont(strong);
	if (font) TTF_CloseFont(font);
	if (bold && bold != font) TTF_CloseFont(bold);
	font = bold = strong = NULL;
	for (i = 0; font_candidates[i] && !font; i++) {
		font = TTF_OpenFont(font_candidates[i], px);
		if (font) {
			bold = TTF_OpenFont(font_candidates[i], (int) (15 * scale + 0.5f));
			if (bold) TTF_SetFontStyle(bold, TTF_STYLE_BOLD);
			strong = TTF_OpenFont(font_candidates[i], px);
			if (strong) TTF_SetFontStyle(strong, TTF_STYLE_BOLD);
		}
	}
	if (!font) { fprintf(stderr, "irene-dixe: no usable font found\n"); return 0; }
	if (!bold) bold = font;
	if (!strong) strong = font;
	return 1;
}

/* ------------------------------------------------------------------ */
/* Drawing                                                             */
/* ------------------------------------------------------------------ */

static int S(double v) { return (int) (v * scale + 0.5); }

/* ALIGN: 0 left, 1 centre, 2 right of X; Y is the top of the text */
static int text(SDL_Renderer *r, TTF_Font *f, const char *s, int x, int y, int align, SDL_Color c)
{
	if (!s || !*s) return 0;
	SDL_Surface *surf = TTF_RenderUTF8_Blended(f, s, c);
	if (!surf) return 0;
	SDL_Texture *t = SDL_CreateTextureFromSurface(r, surf);
	SDL_Rect d = { x, y, surf->w, surf->h };
	if (align == 1) d.x -= surf->w / 2;
	if (align == 2) d.x -= surf->w;
	if (t) { SDL_RenderCopy(r, t, NULL, &d); SDL_DestroyTexture(t); }
	SDL_FreeSurface(surf);
	return d.h;
}

static int text_width(TTF_Font *f, const char *s)
{
	int w = 0, h = 0;
	if (s && *s) TTF_SizeUTF8(f, s, &w, &h);
	return w;
}

static void num_label(char *out, size_t n, double v)
{
	if (v == (long) v) snprintf(out, n, "%ld", (long) v);
	else snprintf(out, n, "%.2g", v);
}

typedef struct { int left, top, width, height; } frame_t;

static int px(frame_t f, double x) { return f.left + (int) ((x - xlo) / (xhi - xlo) * f.width + 0.5); }
static int py(frame_t f, double y) { return f.top + f.height - (int) ((y - ylo) / (yhi - ylo) * f.height + 0.5); }

static void thick_segment(SDL_Renderer *r, int x1, int y1, int x2, int y2, int w, int dashed)
{
	int horizontal = (y1 == y2), a, b, dash = S(7), step;
	if (horizontal) { a = x1 < x2 ? x1 : x2; b = x1 < x2 ? x2 : x1; }
	else { a = y1 < y2 ? y1 : y2; b = y1 < y2 ? y2 : y1; }
	step = dashed ? dash : (b - a + 1);
	for (int p = a; p <= b; p += dashed ? 2 * dash : step) {
		int q = p + step > b ? b : p + step;
		SDL_Rect rect = horizontal ? (SDL_Rect) { p, y1 - w / 2, q - p + 1, w }
					   : (SDL_Rect) { x1 - w / 2, p, w, q - p + 1 };
		SDL_RenderFillRect(r, &rect);
		if (!dashed) break;
	}
}

/* A dotted line in any direction: square dots of side W every 3W pixels.
 * Between sampled landmarks the curve's shape is unknown; the dots say so. */
static void dotted_line(SDL_Renderer *r, int x1, int y1, int x2, int y2, int w)
{
	double dx = x2 - x1, dy = y2 - y1, len = sqrt(dx * dx + dy * dy);
	int n = (int) (len / (3.0 * w));
	for (int k = 0; k <= n; k++) {
		double t = n ? (double) k / n : 0;
		SDL_Rect d = { (int) (x1 + t * dx) - w / 2, (int) (y1 + t * dy) - w / 2, w, w };
		SDL_RenderFillRect(r, &d);
	}
}

static void dot(SDL_Renderer *r, int x, int y, int radius)
{
	for (int j = -radius; j <= radius; j++) {
		int half = (int) sqrt((double) (radius * radius - j * j));
		SDL_RenderDrawLine(r, x - half, y + j, x + half, y + j);
	}
}

/* ------------------------------------------------------------------ */
/* Tables: drawing                                                     */
/* ------------------------------------------------------------------ */

/* The lines of S wrapped to WIDTH pixels, drawn at (X, Y) when R is not
 * NULL.  Returns the height used. */
static int wrapped(SDL_Renderer *r, TTF_Font *f, const char *s, int x, int y, int width, SDL_Color c)
{
	char piece[TEXT_LEN];
	int h = 0, line_h = TTF_FontLineSkip(f);
	while (*s) {
		int n = 0, last_space = -1;
		while (s[n] && n < TEXT_LEN - 1) {
			piece[n] = s[n];
			piece[n + 1] = '\0';
			if (s[n] == ' ') last_space = n;
			if (text_width(f, piece) > width) break;
			n++;
		}
		if (s[n] && last_space > 0) n = last_space;
		if (n == 0) n = 1;
		memcpy(piece, s, (size_t) n);
		piece[n] = '\0';
		if (r) text(r, f, piece, x, y + h, 0, c);
		h += line_h;
		s += n;
		while (*s == ' ') s++;
	}
	return h;
}

typedef struct { int col[MAX_COLS], width, row_h, pad, indent; } table_geometry_t;

static table_geometry_t table_geometry(void)
{
	table_geometry_t g;
	int i, j;
	g.pad = S(10);
	g.indent = S(18);
	g.row_h = TTF_FontLineSkip(font) + S(8);
	for (j = 0; j < ncols; j++) g.col[j] = text_width(strong, header[j]);
	for (i = 0; i < nrows; i++)
		for (j = 0; j < rows[i].n && j < ncols; j++) {
			int w = text_width(rows[i].group ? strong : font, rows[i].cell[j]);
			if (j == 0) w += rows[i].depth * g.indent;
			if (w > g.col[j]) g.col[j] = w;
		}
	g.width = 0;
	for (j = 0; j < ncols; j++) g.width += g.col[j] + 2 * g.pad;
	return g;
}

/* The picture the whole table needs, at the current scale. */
static void table_size(int *W, int *H)
{
	SDL_Color c = { 0, 0, 0, 255 };
	table_geometry_t g = table_geometry();
	int width = g.width, i;
	if (text_width(bold, title) > width) width = text_width(bold, title);
	if (width > S(1400)) width = S(1400);
	int h = S(10) + TTF_FontLineSkip(bold) + TTF_FontLineSkip(font) + S(14)
		+ g.row_h * (nrows + 1) + S(14);
	for (i = 0; i < ntexts; i++) h += wrapped(NULL, font, texts[i], 0, 0, width, c) + S(3);
	*W = width + S(32);
	*H = h + TTF_FontLineSkip(font) + S(16);
}

static void clamp_scroll(int W, int H)
{
	int tw, th;
	table_size(&tw, &th);
	if (scroll_x > tw - W) scroll_x = tw - W;
	if (scroll_y > th - H) scroll_y = th - H;
	if (scroll_x < 0) scroll_x = 0;
	if (scroll_y < 0) scroll_y = 0;
}

static void draw_table(SDL_Renderer *r, int W, int H)
{
	SDL_Color ink = { 30, 30, 30, 255 }, grey = { 110, 110, 110, 255 };
	table_geometry_t g = table_geometry();
	int x0 = S(16) - scroll_x, y = S(10) - scroll_y, i, j;
	int width = g.width;
	if (text_width(bold, title) > width) width = text_width(bold, title);
	if (width > S(1400)) width = S(1400);

	SDL_SetRenderDrawColor(r, 255, 255, 255, 255);
	SDL_RenderClear(r);
	y += wrapped(r, bold, title, x0, y, width, ink);
	y += wrapped(r, font, subtitle, x0, y, width, grey) + S(14);

	int text_dy = (g.row_h - TTF_FontLineSkip(font)) / 2;
	SDL_Rect rule = { x0, y, g.width, S(2) };
	SDL_SetRenderDrawColor(r, 30, 30, 30, 255);
	SDL_RenderFillRect(r, &rule);
	/* the header: the stub on the left, the column headers centred */
	int x = x0;
	for (j = 0; j < ncols; j++) {
		int cw = g.col[j] + 2 * g.pad;
		if (j == 0) text(r, strong, header[j], x + g.pad, y + text_dy, 0, ink);
		else text(r, strong, header[j], x + cw / 2, y + text_dy, 1, ink);
		x += cw;
	}
	y += g.row_h;
	rule.y = y;
	rule.h = S(1);
	SDL_RenderFillRect(r, &rule);

	for (i = 0; i < nrows; i++) {
		if (i % 2) {                   /* banded rows, so the eye keeps the line */
			SDL_Rect band = { x0, y, g.width, g.row_h };
			SDL_SetRenderDrawColor(r, 244, 245, 247, 255);
			SDL_RenderFillRect(r, &band);
		}
		TTF_Font *f = rows[i].group ? strong : font;
		x = x0;
		for (j = 0; j < ncols; j++) {
			int cw = g.col[j] + 2 * g.pad;
			const char *s = j < rows[i].n ? rows[i].cell[j] : "";
			if (j == 0) text(r, f, s, x + g.pad + rows[i].depth * g.indent, y + text_dy, 0, ink);
			else text(r, f, s, x + cw / 2, y + text_dy, 1, ink);
			x += cw;
		}
		y += g.row_h;
	}
	rule.y = y;
	rule.h = S(2);
	SDL_SetRenderDrawColor(r, 30, 30, 30, 255);
	SDL_RenderFillRect(r, &rule);
	y += S(10);
	for (i = 0; i < ntexts; i++) y += wrapped(r, font, texts[i], x0, y, width, grey) + S(3);

	/* the footer stays put while the table scrolls */
	int line_h = TTF_FontLineSkip(font);
	SDL_Rect foot = { 0, H - line_h - S(10), W, line_h + S(10) };
	SDL_SetRenderDrawColor(r, 255, 255, 255, 255);
	SDL_RenderFillRect(r, &foot);
	if (for_file)
		text(r, font, "irene-dixe: shown from the textified table, not the original page",
		     S(10), H - line_h - S(6), 0, grey);
	else if (status[0])
		text(r, font, status, S(10), H - line_h - S(6), 0, grey);
	else {
		text(r, font, "arrows, wheel or PgUp/PgDn scroll; s saves a picture; q closes",
		     W - S(10), H - line_h - S(6), 2, grey);
		text(r, font, "irene-dixe: shown from the textified table", S(10), H - line_h - S(6), 0, grey);
	}
}

static void draw(SDL_Renderer *r, int W, int H)
{
	if (is_table) { draw_table(r, W, H); return; }
	SDL_Color ink = { 30, 30, 30, 255 }, grey = { 110, 110, 110, 255 };
	int line_h = TTF_FontLineSkip(font), nseries = 0, i;
	for (i = 0; i < MAX_SERIES; i++) if (series[i].used) nseries = i + 1;
	int nrisk = 0;
	for (i = 0; i < nseries; i++) if (risk[i][0]) nrisk++;

	/* legend column on the right: as wide as its longest line, within limits */
	int legend_w = S(160);
	for (i = 0; i < nseries; i++) {
		int w = text_width(font, series[i].label) + S(40);
		if (w > legend_w) legend_w = w;
	}
	if (legend_w > W / 3) legend_w = W / 3;

	frame_t f;
	f.left = S(70);
	f.top = S(26) + 2 * line_h + S(10);
	f.width = W - f.left - legend_w - S(30);
	f.height = H - f.top - S(54) - (nrisk ? (nrisk + 1) * line_h + S(8) : 0)
		   - (ntexts ? 0 : 0);
	if (f.width < S(100)) f.width = S(100);
	if (f.height < S(100)) f.height = S(100);

	SDL_SetRenderDrawColor(r, 255, 255, 255, 255);
	SDL_RenderClear(r);

	text(r, bold, title, S(16), S(10), 0, ink);
	text(r, font, subtitle, S(16), S(12) + TTF_FontLineSkip(bold), 0, grey);

	/* unresolved intervals: shaded bands, in the curve's colour */
	SDL_SetRenderDrawBlendMode(r, SDL_BLENDMODE_BLEND);
	for (i = 0; i < ngaps; i++) {
		series_t *s = &series[gaps[i].series % MAX_SERIES];
		SDL_SetRenderDrawColor(r, s->r, s->g, s->b, 28);
		SDL_Rect band = { px(f, gaps[i].x1), f.top, px(f, gaps[i].x2) - px(f, gaps[i].x1), f.height };
		SDL_RenderFillRect(r, &band);
	}

	/* grid and ticks */
	char buf[64];
	for (i = 0; i < nyticks; i++) {
		int y = py(f, yticks[i]);
		SDL_SetRenderDrawColor(r, 232, 232, 232, 255);
		SDL_RenderDrawLine(r, f.left, y, f.left + f.width, y);
		num_label(buf, sizeof(buf), yticks[i]);
		text(r, font, buf, f.left - S(8), y - line_h / 2, 2, ink);
	}
	for (i = 0; i < nxticks; i++) {
		int x = px(f, xticks[i]);
		SDL_SetRenderDrawColor(r, 60, 60, 60, 255);
		SDL_RenderDrawLine(r, x, f.top + f.height, x, f.top + f.height + S(5));
		num_label(buf, sizeof(buf), xticks[i]);
		text(r, font, buf, x, f.top + f.height + S(7), 1, ink);
	}
	SDL_SetRenderDrawColor(r, 60, 60, 60, 255);
	SDL_Rect axis_x = { f.left, f.top + f.height, f.width + 1, S(1.5) > 0 ? S(1.5) : 1 };
	SDL_Rect axis_y = { f.left - (S(1.5) > 0 ? S(1.5) : 1), f.top, S(1.5) > 0 ? S(1.5) : 1, f.height + 1 };
	SDL_RenderFillRect(r, &axis_x);
	SDL_RenderFillRect(r, &axis_y);
	text(r, font, xlabel, f.left + f.width / 2, f.top + f.height + S(8) + line_h, 1, ink);
	text(r, font, ylabel, S(8), f.top - line_h - S(4), 0, ink);

	/* curves, then censor ticks on top */
	SDL_RenderSetClipRect(r, &(SDL_Rect) { f.left - S(3), f.top - S(3), f.width + S(6), f.height + S(6) });
	for (i = 0; i < nsegs; i++) {
		series_t *s = &series[segs[i].series % MAX_SERIES];
		SDL_SetRenderDrawColor(r, s->r, s->g, s->b, 255);
		thick_segment(r, px(f, segs[i].x1), py(f, segs[i].y1), px(f, segs[i].x2), py(f, segs[i].y2),
			      S(2) > 1 ? S(2) : 2, s->dashed);
	}
	for (i = 0; i < nlinks; i++) {
		series_t *s = &series[links[i].series % MAX_SERIES];
		SDL_SetRenderDrawColor(r, s->r, s->g, s->b, 255);
		dotted_line(r, px(f, links[i].x1), py(f, links[i].y1), px(f, links[i].x2), py(f, links[i].y2),
			    S(2) > 1 ? S(2) : 2);
	}
	for (i = 0; i < npoints; i++) {
		series_t *s = &series[points[i].series % MAX_SERIES];
		SDL_SetRenderDrawColor(r, s->r, s->g, s->b, 255);
		dot(r, px(f, points[i].x), py(f, points[i].y), S(4) > 3 ? S(4) : 3);
	}
	for (i = 0; i < ncensors; i++) {
		series_t *s = &series[censors[i].series % MAX_SERIES];
		int x = px(f, censors[i].x), y = py(f, censors[i].y);
		SDL_SetRenderDrawColor(r, s->r / 2, s->g / 2, s->b / 2, 255);
		SDL_Rect tick = { x - S(1), y - S(6), S(2) > 1 ? S(2) : 2, S(12) };
		SDL_RenderFillRect(r, &tick);
	}
	SDL_RenderSetClipRect(r, NULL);

	/* numbers at risk, aligned with their times */
	if (nrisk && nrisktimes) {
		int y = f.top + f.height + S(10) + 2 * line_h;
		text(r, bold, "At risk", S(8), y, 0, ink);
		y += line_h + S(2);
		for (i = 0; i < nseries; i++) {
			if (!risk[i][0]) continue;
			SDL_Color c = { (Uint8) series[i].r, (Uint8) series[i].g, (Uint8) series[i].b, 255 };
			const char *p = risk[i];
			for (int k = 0; k < nrisktimes && *p; k++) {
				char cell[32];
				int n = 0;
				while (*p == ' ') p++;
				while (*p && *p != ' ' && n < 31) cell[n++] = *p++;
				cell[n] = '\0';
				if (risktimes[k] >= xlo && risktimes[k] <= xhi)
					text(r, font, cell, px(f, risktimes[k]), y, 1, c);
			}
			y += line_h;
		}
	}

	/* legend and statistics */
	int lx = f.left + f.width + S(24), ly = f.top;
	for (i = 0; i < nseries; i++) {
		if (!series[i].used) continue;
		SDL_SetRenderDrawColor(r, series[i].r, series[i].g, series[i].b, 255);
		thick_segment(r, lx, ly + line_h / 2, lx + S(22), ly + line_h / 2, S(3) > 2 ? S(3) : 3, series[i].dashed);
		text(r, font, series[i].label, lx + S(30), ly, 0, ink);
		ly += line_h + S(4);
	}
	if (npoints) {
		SDL_SetRenderDrawColor(r, 60, 60, 60, 255);
		dotted_line(r, lx, ly + line_h / 2, lx + S(22), ly + line_h / 2, S(2) > 1 ? S(2) : 2);
		dot(r, lx + S(11), ly + line_h / 2, S(4) > 3 ? S(4) : 3);
		text(r, font, "sampled point", lx + S(30), ly, 0, ink);
		ly += line_h + S(4);
	}
	if (ncensors) {
		SDL_SetRenderDrawColor(r, 60, 60, 60, 255);
		SDL_Rect tick = { lx + S(10), ly + line_h / 2 - S(6), S(2) > 1 ? S(2) : 2, S(12) };
		SDL_RenderFillRect(r, &tick);
		text(r, font, "censored", lx + S(30), ly, 0, ink);
		ly += line_h + S(4);
	}
	if (ngaps) {
		SDL_SetRenderDrawColor(r, 120, 120, 120, 45);
		SDL_Rect band = { lx, ly + S(2), S(22), line_h - S(4) };
		SDL_RenderFillRect(r, &band);
		text(r, font, "unresolved", lx + S(30), ly, 0, ink);
		ly += line_h + S(4);
	}
	ly += S(8);
	for (i = 0; i < ntexts && ly + line_h < H - S(30); i++) {
		/* wrap each line to the legend column */
		const char *p = texts[i];
		while (*p && ly + line_h < H - S(30)) {
			char piece[TEXT_LEN];
			int n = 0, last_space = -1;
			while (p[n] && n < TEXT_LEN - 1) {
				piece[n] = p[n];
				piece[n + 1] = '\0';
				if (p[n] == ' ') last_space = n;
				if (text_width(font, piece) > W - lx - S(10)) break;
				n++;
			}
			if (p[n] && last_space > 0) n = last_space;
			if (n == 0) n = 1;
			memcpy(piece, p, (size_t) n);
			piece[n] = '\0';
			text(r, font, piece, lx, ly, 0, grey);
			ly += line_h;
			p += n;
			while (*p == ' ') p++;
		}
		ly += S(3);
	}

	if (for_file)
		text(r, font, "irene-dixe: redrawn from the textified table, not the original figure",
		     S(10), H - line_h - S(6), 0, grey);
	else if (status[0])
		text(r, font, status, S(10), H - line_h - S(6), 0, grey);
	else {
		text(r, font, "s saves a picture; q closes", W - S(10), H - line_h - S(6), 2, grey);
		text(r, font, "irene-dixe: redrawn from the textified table, not the original figure",
		     S(10), H - line_h - S(6), 0, grey);
	}
}

/* ------------------------------------------------------------------ */
/* Main                                                                */
/* ------------------------------------------------------------------ */

/* ------------------------------------------------------------------ */
/* PNG, written here: no SDL_image or zlib to install                  */
/* ------------------------------------------------------------------ */

/* Each row is stored with PNG's "Up" filter (the difference from the row
 * above), so the white of a plot becomes runs of zeros; DEFLATE with its
 * fixed Huffman codes then packs every run as a copy at distance 1. */

typedef struct { unsigned char *data; size_t len, cap; unsigned bits; int nbits; } out_t;

static int out_byte(out_t *o, unsigned char b)
{
	if (o->len == o->cap) {
		size_t cap = o->cap ? o->cap * 2 : 65536;
		unsigned char *d = realloc(o->data, cap);
		if (!d) return 0;
		o->data = d; o->cap = cap;
	}
	o->data[o->len++] = b;
	return 1;
}

static void put_bits(out_t *o, unsigned value, int n)      /* LSB first */
{
	o->bits |= value << o->nbits;
	o->nbits += n;
	while (o->nbits >= 8) { out_byte(o, (unsigned char) o->bits); o->bits >>= 8; o->nbits -= 8; }
}

static void put_code(out_t *o, unsigned code, int n)       /* Huffman: MSB first */
{
	unsigned r = 0;
	for (int i = 0; i < n; i++) r |= ((code >> i) & 1u) << (n - 1 - i);
	put_bits(o, r, n);
}

static void put_symbol(out_t *o, int v)                     /* fixed literal/length code */
{
	if (v < 144) put_code(o, 0x30 + v, 8);
	else if (v < 256) put_code(o, 0x190 + (v - 144), 9);
	else if (v < 280) put_code(o, v - 256, 7);
	else put_code(o, 0xC0 + (v - 280), 8);
}

static void put_match(out_t *o, int len)                    /* copy LEN bytes at distance 1 */
{
	static const int base[] = { 3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,
				    67,83,99,115,131,163,195,227,258 };
	static const int extra[] = { 0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0 };
	int i = 28;
	while (base[i] > len) i--;
	put_symbol(o, 257 + i);
	if (extra[i]) put_bits(o, (unsigned) (len - base[i]), extra[i]);
	put_code(o, 0, 5);                                  /* distance code 0: distance 1 */
}

static unsigned long crc_table[256];

static unsigned long crc(const unsigned char *b, size_t n, unsigned long c)
{
	if (!crc_table[1])
		for (unsigned long k = 0; k < 256; k++) {
			unsigned long v = k;
			for (int j = 0; j < 8; j++) v = v & 1 ? 0xEDB88320UL ^ (v >> 1) : v >> 1;
			crc_table[k] = v;
		}
	c ^= 0xFFFFFFFFUL;
	for (size_t i = 0; i < n; i++) c = crc_table[(c ^ b[i]) & 255] ^ (c >> 8);
	return c ^ 0xFFFFFFFFUL;
}

static void be32(unsigned char *p, unsigned long v)
{
	p[0] = (unsigned char) (v >> 24); p[1] = (unsigned char) (v >> 16);
	p[2] = (unsigned char) (v >> 8); p[3] = (unsigned char) v;
}

static int chunk(FILE *f, const char *type, const unsigned char *data, size_t n)
{
	unsigned char head[8], tail[4];
	be32(head, (unsigned long) n);
	memcpy(head + 4, type, 4);
	unsigned long c = crc(head + 4, 4, 0);
	c = crc(data, n, c);
	be32(tail, c);
	return fwrite(head, 1, 8, f) == 8 && (n == 0 || fwrite(data, 1, n, f) == n) && fwrite(tail, 1, 4, f) == 4;
}

static int save_png(SDL_Surface *s, const char *path)
{
	int W = s->w, H = s->h, ok = 0;
	size_t row = (size_t) W * 3, n = (row + 1) * (size_t) H;
	unsigned char *raw = malloc(n), *prev = calloc(row, 1), *cur = malloc(row);
	out_t o = { 0 };
	if (!raw || !prev || !cur) goto done;
	for (int y = 0; y < H; y++) {
		Uint32 *px = (Uint32 *) ((Uint8 *) s->pixels + (size_t) y * (size_t) s->pitch);
		for (int x = 0; x < W; x++) {
			Uint8 r, g, b;
			SDL_GetRGB(px[x], s->format, &r, &g, &b);
			cur[3 * x] = r; cur[3 * x + 1] = g; cur[3 * x + 2] = b;
		}
		unsigned char *line = raw + (size_t) y * (row + 1);
		line[0] = 2;                                        /* filter: Up */
		for (size_t i = 0; i < row; i++) line[1 + i] = (unsigned char) (cur[i] - prev[i]);
		memcpy(prev, cur, row);
	}
	out_byte(&o, 0x78); out_byte(&o, 0x01);                     /* zlib header */
	put_bits(&o, 1, 1); put_bits(&o, 1, 2);                     /* last block, fixed codes */
	for (size_t i = 0; i < n;) {
		size_t run = 0;
		if (i > 0)
			while (i + run < n && run < 258 && raw[i + run] == raw[i - 1]) run++;
		if (run >= 3) { put_match(&o, (int) run); i += run; }
		else put_symbol(&o, raw[i++]);
	}
	put_symbol(&o, 256);
	if (o.nbits) put_bits(&o, 0, 8 - o.nbits);
	unsigned long a = 1, b = 0;                                 /* Adler-32 */
	for (size_t i = 0; i < n; i++) { a = (a + raw[i]) % 65521; b = (b + a) % 65521; }
	unsigned char adler[4];
	be32(adler, (b << 16) | a);
	for (int i = 0; i < 4; i++) out_byte(&o, adler[i]);
	if (!o.data) goto done;

	FILE *f = fopen(path, "wb");
	if (!f) goto done;
	static const unsigned char signature[8] = { 137, 'P', 'N', 'G', 13, 10, 26, 10 };
	unsigned char ihdr[13];
	be32(ihdr, (unsigned long) W); be32(ihdr + 4, (unsigned long) H);
	ihdr[8] = 8; ihdr[9] = 2; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;   /* 8-bit RGB */
	ok = fwrite(signature, 1, 8, f) == 8 && chunk(f, "IHDR", ihdr, 13)
	     && chunk(f, "IDAT", o.data, o.len) && chunk(f, "IEND", NULL, 0);
	ok = (fclose(f) == 0) && ok;
done:
	free(raw); free(prev); free(cur); free(o.data);
	return ok;
}

static int ends_with(const char *s, const char *tail)
{
	size_t a = strlen(s), b = strlen(tail);
	return a >= b && !strcmp(s + a - b, tail);
}

/* The picture is drawn again by SDL's software renderer into a surface of
 * its own and saved from there.  Reading the window back
 * (SDL_RenderReadPixels) is unreliable with the Metal and OpenGL renderers:
 * on macOS it can "succeed" without the file appearing. */
static int picture_to(const char *out, int W, int H)
{
	int sx = scroll_x, sy = scroll_y;
	if (is_table) { table_size(&W, &H); scroll_x = scroll_y = 0; }   /* the whole table */
	SDL_Surface *s = SDL_CreateRGBSurfaceWithFormat(0, W, H, 32, SDL_PIXELFORMAT_ARGB8888);
	SDL_Renderer *r = s ? SDL_CreateSoftwareRenderer(s) : NULL;
	int ok = 0;
	if (r) {
		for_file = 1;
		draw(r, W, H);
		for_file = 0;
		SDL_RenderPresent(r);
		ok = ends_with(out, ".bmp") ? SDL_SaveBMP(s, out) == 0 : save_png(s, out);
		SDL_DestroyRenderer(r);
	}
	if (s) SDL_FreeSurface(s);
	scroll_x = sx;
	scroll_y = sy;
	if (ok) {                          /* trust the disk, not the return code */
		FILE *f = fopen(out, "rb");
		long size = 0;
		if (f) { fseek(f, 0, SEEK_END); size = ftell(f); fclose(f); }
		ok = size > 50;
	}
	return ok;
}

/* "~/x" -> "$HOME/x" */
static void expand_home(char *out, size_t n, const char *path)
{
	const char *home = getenv("HOME");
	if (path[0] == '~' && path[1] == '/' && home) snprintf(out, n, "%s%s", home, path + 1);
	else snprintf(out, n, "%s", path);
}

static void save_picture(const char *wanted, int W, int H)
{
	char out[4096], fallback[4400];
	const char *home = getenv("HOME"), *slash = strrchr(wanted, '/');
	expand_home(out, sizeof(out), wanted);
	if (picture_to(out, W, H)) { snprintf(status, sizeof(status), "saved %s", out); return; }
	snprintf(fallback, sizeof(fallback), "%s/%s", home ? home : ".", slash ? slash + 1 : wanted);
	if (strcmp(fallback, out) && picture_to(fallback, W, H))
		snprintf(status, sizeof(status), "could not write beside the file; saved %s", fallback);
	else
		snprintf(status, sizeof(status), "could not save %s (%s)", out, SDL_GetError());
}

static int render_offscreen(const char *out)
{
	if (!open_fonts()) return 1;
	if (picture_to(out, 1000, 640)) return 0;
	fprintf(stderr, "irene-dixe: cannot write %s (%s)\n", out, SDL_GetError());
	return 1;
}

int main(int argc, char **argv)
{
	int offscreen = argc == 4 && !strcmp(argv[1], "--render");
	const char *path = offscreen ? argv[2] : argv[1];
	const char *save_as = (!offscreen && argc == 3) ? argv[2] : NULL;
	if (!(argc == 2 || argc == 3 || offscreen)) {
		fprintf(stderr, "usage: irene-dixe FILE [SAVE.png] | irene-dixe --render FILE OUT.png\n");
		return 2;
	}
	if (!read_sketch(path)) return 1;
	if (TTF_Init() != 0) { fprintf(stderr, "irene-dixe: %s\n", TTF_GetError()); return 1; }
	if (offscreen) return render_offscreen(argv[3]);

	if (SDL_Init(SDL_INIT_VIDEO) != 0) { fprintf(stderr, "irene-dixe: %s\n", SDL_GetError()); return 1; }
	char window_title[TEXT_LEN + 16];
	snprintf(window_title, sizeof(window_title), "irene-dixe: %s", title[0] ? title : "plot");
	int width = 1000, height = 640;
	if (is_table) {                      /* as large as the table, within reason */
		if (!open_fonts()) return 1;
		table_size(&width, &height);
		if (width < 520) width = 520;
		if (width > 1400) width = 1400;
		if (height < 240) height = 240;
		if (height > 900) height = 900;
	}
	SDL_Window *w = SDL_CreateWindow(window_title, SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
					 width, height, SDL_WINDOW_RESIZABLE | SDL_WINDOW_ALLOW_HIGHDPI);
	if (!w) { fprintf(stderr, "irene-dixe: %s\n", SDL_GetError()); return 1; }
	SDL_Renderer *r = SDL_CreateRenderer(w, -1, SDL_RENDERER_ACCELERATED);
	if (!r) r = SDL_CreateRenderer(w, -1, SDL_RENDERER_SOFTWARE);
	if (!r) { fprintf(stderr, "irene-dixe: %s\n", SDL_GetError()); return 1; }
	SDL_RaiseWindow(w);                  /* in front of the editor that started it */

	int running = 1, W = 0, H = 0, ww = 0, wh = 0;
	float last_scale = 0;
	while (running) {
		SDL_GetWindowSize(w, &ww, &wh);
		SDL_GetRendererOutputSize(r, &W, &H);
		scale = ww > 0 ? (float) W / (float) ww : 1.0f;
		if (scale < 1.0f) scale = 1.0f;
		if (scale != last_scale) { if (!open_fonts()) return 1; last_scale = scale; }
		if (is_table) clamp_scroll(W, H);
		draw(r, W, H);
		SDL_RenderPresent(r);
		SDL_Event e;
		if (!SDL_WaitEvent(&e)) break;
		do {
			if (e.type == SDL_QUIT) running = 0;
			else if (e.type == SDL_MOUSEWHEEL && is_table) {
				scroll_y -= e.wheel.y * S(40);
				scroll_x -= e.wheel.x * S(40);
			} else if (e.type == SDL_KEYDOWN) {
				SDL_Keycode k = e.key.keysym.sym;
				int page = H - S(60);
				if (k == SDLK_q || k == SDLK_ESCAPE) running = 0;
				else if (is_table && k == SDLK_DOWN) scroll_y += S(40);
				else if (is_table && k == SDLK_UP) scroll_y -= S(40);
				else if (is_table && k == SDLK_RIGHT) scroll_x += S(60);
				else if (is_table && k == SDLK_LEFT) scroll_x -= S(60);
				else if (is_table && (k == SDLK_PAGEDOWN || k == SDLK_SPACE)) scroll_y += page;
				else if (is_table && k == SDLK_PAGEUP) scroll_y -= page;
				else if (is_table && k == SDLK_HOME) scroll_x = scroll_y = 0;
				else if (is_table && k == SDLK_END) scroll_y = 1 << 30;
				else if (k == SDLK_s) {
					char out[4096];
					if (save_as) snprintf(out, sizeof(out), "%s", save_as);
					else snprintf(out, sizeof(out), "%s.png", path);
					save_picture(out, W, H);
				}
			}
		} while (SDL_PollEvent(&e));
	}
	SDL_DestroyRenderer(r);
	SDL_DestroyWindow(w);
	TTF_Quit();
	SDL_Quit();
	return 0;
}
