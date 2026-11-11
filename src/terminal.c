/*
 * terminal.c -- M-x term: a shell in a buffer, as Emacs's term and Neovim's
 * :terminal
 *
 * Two halves.  A pseudo-terminal (forkpty): the shell runs at one end,
 * believing it talks to a terminal; the editor holds the other.  And a
 * terminal emulator, libvterm (libvterm/, bundled), which reads what the
 * shell and its programs write -- text, and escape sequences that move
 * the cursor, clear, colour, switch to the alternate screen -- and keeps
 * the grid of cells a terminal would show.
 *
 * The buffer shows that grid.  Its text is the lines that scrolled off the
 * top (the history, at most TERM_HISTORY lines), then the screen's rows;
 * after each read, the rows are written again from the grid, and point
 * goes where the terminal's cursor is.  A byte array beside the text
 * gives each byte a face (display.c asks term_faces), so the colours of
 * ls and git show.  The buffer is read-only for the editor's commands;
 * only this file writes it, without undo history.
 *
 * Keys.  While the terminal is the current buffer, the keyboard's bytes go
 * to the shell as they come (term_take_key, from the main loop), except:
 *   C-c C-c    C-c to the shell
 *   C-c C-j    copy mode: the buffer is an ordinary read-only buffer
 *              (search, the mark, M-w); C-c C-k goes back
 *   C-c KEY    the editor's C-x KEY (C-c b: another buffer, C-c o: the
 *              other window), as in Emacs's ansi-term; C-c M-x: M-x;
 *              C-c C-x: C-x (C-c C-x C-c quits the editor)
 *   the mouse  the editor's (clicks, the wheel, the mode line)
 * and a paste is sent as one, bracketed when the program asked for it.
 *
 * Output is read while the editor waits for a key (editor_idle_poll),
 * every TERM_POLL_MS while a terminal runs.  The window's size is the
 * terminal's; when it changes, the shell is told (TIOCSWINSZ).
 *
 * Not in the browser: a web page cannot start a shell (term_open says so
 * there).  Without a terminal, this costs a NULL test per key and per
 * idle poll.
 */
#include "header.h"
#include "screen.h"

#ifdef __EMSCRIPTEN__
const char *term_open(void) { return "M-x term needs the terminal or SDL window: a browser page cannot start a shell"; }
int term_poll(void) { return 0; }
int term_takes_keys(buffer_t *bp) { (void) bp; return 0; }
void term_take_key(void) {}
int term_faces(buffer_t *bp, point_t start, char_t *faces, long len) { (void) bp; (void) start; (void) faces; (void) len; return 0; }
void term_buffer_gone(buffer_t *bp) { (void) bp; }
int term_running(void) { return 0; }
int term_state(buffer_t *bp) { (void) bp; return 0; }
int term_owns_cursor(buffer_t *bp) { (void) bp; return 0; }
int term_poll_ms(void) { return 100; }
int fe_term_state(void) { return 0; }
int fe_term_copy_mode(int on) { (void) on; return 0; }
char *fe_term_open(void) { return (char *) term_open(); }
#else

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>
#if defined(__APPLE__)
#include <util.h>
#elif defined(__FreeBSD__)
#include <libutil.h>
#else
#include <pty.h>
#endif
#include "vterm.h"

#define TERM_HISTORY 10000      /* lines kept above the screen */
#define TERM_POLL_MS 15         /* how often output is read while idle */

/* The faces of a terminal's colours (header.h): 17-32 the sixteen ANSI
 * colours, 33 reverse video (interface.c gives them their colours), and
 * from 34 faces made for the pairs programs use (cell_face) */

typedef struct term_t {
	struct term_t *next;
	buffer_t *bp;
	VTerm *vt;
	VTermScreen *vs;
	int fd;                 /* the editor's end of the pty, -1 once closed */
	pid_t pid;
	int rows, cols;
	point_t screen_start;   /* the screen's first byte in the buffer */
	long history;           /* lines above it */
	char_t *face;           /* a face for each byte of the buffer */
	long nface, capface;
	int copy;               /* copy mode: the editor's keys, point left alone */
	int damaged;            /* the grid changed since it was last written */
	int exited;
	int cursor_hidden;       /* the program hid the cursor (CSI ?25l): for the backdoor */
} term_t;

static term_t *terms;
static int editor_turn;          /* the next key is the editor's (after C-c) */

/* ------------------------------------------------------------------ */
/* The buffer's text and faces, without undo                          */
/* ------------------------------------------------------------------ */

static int reserve_faces(term_t *t, long n)
{
	if (n <= t->capface) return 1;
	long cap = t->capface ? t->capface : 4096;
	while (cap < n) cap *= 2;
	char_t *f = realloc(t->face, (size_t) cap);
	if (f == NULL) return 0;
	t->face = f;
	t->capface = cap;
	return 1;
}

/* [START, END) of the buffer becomes the N bytes S with the faces F */
static void put_text(term_t *t, point_t start, point_t end, const char *s, const char_t *f, long n)
{
	buffer_t *bp = t->bp;
	point_t size = document_size(bp);
	long del, grow;

	if (end > size) end = size;
	if (start > end) start = end;
	del = end - start;
	grow = n - del;
	if (!reserve_faces(t, t->nface + (grow > 0 ? grow : 0) + 1)) return;
	if (n >= bp->b_egap - bp->b_gap + del && !growgap(bp, n)) return;
	movegap(bp, start);
	bp->b_egap += del;                       /* the old bytes go */
	memcpy(bp->b_gap, s, (size_t) n);         /* the new come */
	bp->b_gap += n;
	memmove(t->face + start + n, t->face + end, (size_t) (t->nface - end));
	memcpy(t->face + start, f, (size_t) n);
	t->nface += grow;
	bp->b_changes++;                         /* display.c: redraw */
	if (bp->b_mark != NOMARK && bp->b_mark > start)
		bp->b_mark = bp->b_mark >= end ? bp->b_mark + grow : start;
}

/* ------------------------------------------------------------------ */
/* From the grid to text                                              */
/* ------------------------------------------------------------------ */

typedef struct { char *s; char_t *f; long n, cap; } out_t;

static int out_reserve(out_t *o, long more)
{
	if (o->n + more <= o->cap) return 1;
	long cap = o->cap ? o->cap : 1024;
	while (cap < o->n + more) cap *= 2;
	char *s = realloc(o->s, (size_t) cap);
	if (s == NULL) return 0;
	o->s = s;
	char_t *f = realloc(o->f, (size_t) cap);
	if (f == NULL) return 0;
	o->f = f;
	o->cap = cap;
	return 1;
}

static void out_put(out_t *o, const char *s, int n, int face)
{
	if (!out_reserve(o, n)) return;
	memcpy(o->s + o->n, s, (size_t) n);
	memset(o->f + o->n, face, (size_t) n);
	o->n += n;
}

static int utf8_encode(uint32_t c, char *out)
{
	if (c < 0x80) { out[0] = (char) c; return 1; }
	if (c < 0x800) { out[0] = (char) (0xC0 | (c >> 6)); out[1] = (char) (0x80 | (c & 0x3F)); return 2; }
	if (c < 0x10000) {
		out[0] = (char) (0xE0 | (c >> 12)); out[1] = (char) (0x80 | ((c >> 6) & 0x3F));
		out[2] = (char) (0x80 | (c & 0x3F)); return 3;
	}
	out[0] = (char) (0xF0 | (c >> 18)); out[1] = (char) (0x80 | ((c >> 12) & 0x3F));
	out[2] = (char) (0x80 | ((c >> 6) & 0x3F)); out[3] = (char) (0x80 | (c & 0x3F)); return 4;
}

/* the nearest of the sixteen ANSI colours (xterm's) to R G B */
static int nearest_ansi(int r, int g, int b)
{
	static const unsigned char rgb[16][3] = {
		{0,0,0},{205,0,0},{0,205,0},{205,205,0},{0,0,238},{205,0,205},{0,205,205},{229,229,229},
		{127,127,127},{255,0,0},{0,255,0},{255,255,0},{92,92,255},{255,0,255},{0,255,255},{255,255,255}
	};
	int best = 7, i;
	long dbest = -1;
	for (i = 0; i < 16; i++) {
		long dr = r - rgb[i][0], dg = g - rgb[i][1], db = b - rgb[i][2];
		long d = dr * dr + dg * dg + db * db;
		if (dbest < 0 || d < dbest) { dbest = d; best = i; }
	}
	return best;
}

/* The faces made for the colour pairs programs use: a background, the 256
 * colours, RGB (ID_COLOR_TERM_POOL to ID_COLOR_LAST, shared by all the
 * terminals); when they run out, the nearest of the simple faces */
typedef struct { long fg, bg; int attr; } pen_t;
static pen_t pens[ID_COLOR_LAST - ID_COLOR_TERM_POOL + 1];
static int npens;

static long color_value(term_t *t, VTermColor c)
{
	if (VTERM_COLOR_IS_DEFAULT_FG(&c) || VTERM_COLOR_IS_DEFAULT_BG(&c)) return -1;
	if (VTERM_COLOR_IS_INDEXED(&c)) return c.indexed.idx;
	vterm_screen_convert_color_to_rgb(t->vs, &c);
	return SCR_RGB(c.rgb.red, c.rgb.green, c.rgb.blue);
}

static int simple_face(term_t *t, const VTermScreenCell *c)
{
	VTermColor fg = c->fg;

	if (c->attrs.reverse || !VTERM_COLOR_IS_DEFAULT_BG(&c->bg))
		return ID_COLOR_TERM_REVERSE;
	if (VTERM_COLOR_IS_DEFAULT_FG(&fg)) {
		if (c->attrs.bold) return ID_COLOR_STRONG;
		if (c->attrs.italic) return ID_COLOR_EMPHASIS;
		if (c->attrs.underline) return ID_COLOR_LINK;
		return ID_COLOR_ALPHA;
	}
	if (VTERM_COLOR_IS_INDEXED(&fg) && fg.indexed.idx < 16) {
		int i = fg.indexed.idx;
		if (c->attrs.bold && i < 8) i += 8;
		return ID_COLOR_TERM0 + i;
	}
	vterm_screen_convert_color_to_rgb(t->vs, &fg);
	return ID_COLOR_TERM0 + nearest_ansi(fg.rgb.red, fg.rgb.green, fg.rgb.blue);
}

static int cell_face(term_t *t, const VTermScreenCell *c)
{
	long fg = color_value(t, c->fg), bg = color_value(t, c->bg);
	int attr = (c->attrs.bold ? SCR_BOLD : 0) | (c->attrs.underline ? SCR_UNDERLINE : 0)
		 | (c->attrs.reverse ? SCR_REVERSE : 0) | (c->attrs.italic ? SCR_ITALIC : 0);
	int k;

	/* plain text, and the sixteen colours on the default background */
	if (bg < 0 && !c->attrs.reverse && !c->attrs.italic && !c->attrs.underline &&
	    (fg < 0 || (!SCR_IS_RGB(fg) && fg < 16)))
		return simple_face(t, c);
	for (k = 0; k < npens; k++)
		if (pens[k].fg == fg && pens[k].bg == bg && pens[k].attr == attr)
			return ID_COLOR_TERM_POOL + k;
	if (npens == (int) (sizeof pens / sizeof pens[0]))
		return simple_face(t, c);
	pens[npens].fg = fg;
	pens[npens].bg = bg;
	pens[npens].attr = attr;
	term_face(ID_COLOR_TERM_POOL + npens, fg, bg, attr);
	return ID_COLOR_TERM_POOL + npens++;
}

/* Row ROW of the grid, without its trailing blanks (but up to column
 * KEEP, where the cursor is, or -1); *AT gets the byte offset in O of
 * column CURSOR, when CURSOR >= 0 */
static void row_text(term_t *t, int row, out_t *o, int cursor, long *at)
{
	long start = o->n, keep_to = -1, last = o->n;
	int col = 0, n, i;
	char buf[4 * VTERM_MAX_CHARS_PER_CELL + 4];
	VTermScreenCell cell;
	VTermPos p;

	p.row = row;
	while (col < t->cols) {
		p.col = col;
		if (!vterm_screen_get_cell(t->vs, p, &cell)) break;
		int here = col == cursor;
		if (here) *at = o->n;
		if (cell.chars[0] == (uint32_t) -1) { col++; continue; }   /* a wide char's right half */
		n = 0;
		if (cell.chars[0] == 0) buf[n++] = ' ';
		else for (i = 0; i < VTERM_MAX_CHARS_PER_CELL && cell.chars[i]; i++)
			n += utf8_encode(cell.chars[i], buf + n);
		int face = cell_face(t, &cell);
		out_put(o, buf, n, face);
		if (here) keep_to = o->n;               /* the cursor's cell stays, blank or not */
		if (!(n == 1 && buf[0] == ' ' && face == ID_COLOR_ALPHA)) last = o->n;
		col += cell.width > 0 ? cell.width : 1;
	}
	if (cursor >= col && cursor >= 0) {          /* the cursor past the cells: a blank cell for it */
		while (col < cursor) { out_put(o, " ", 1, ID_COLOR_ALPHA); col++; }
		*at = o->n;
		out_put(o, " ", 1, ID_COLOR_ALPHA);
		keep_to = o->n;
	}
	if (keep_to > last) last = keep_to;
	o->n = last > start ? last : start;          /* the trailing blanks go */
}

/* The screen's rows, written again into the buffer; point to the cursor */
static void draw(term_t *t)
{
	out_t o = {0};
	VTermPos cursor;
	long at = 0;
	int row;
	window_t *wp;

	vterm_state_get_cursorpos(vterm_obtain_state(t->vt), &cursor);
	for (row = 0; row < t->rows; row++) {
		row_text(t, row, &o, row == cursor.row ? cursor.col : -1, &at);
		if (row + 1 < t->rows) out_put(&o, "\n", 1, ID_COLOR_ALPHA);
	}
	/* The cursor is drawn by the editor, as a cell of its own colour: the
	 * terminal's own cursor is hidden while the shell has the keys
	 * (term_owns_cursor), because a terminal draws it in its text colour,
	 * which vanished on the black cells of Neovim (11 November 2026).
	 * Not when the program hid it, nor in copy mode. */
	if (!t->copy && !t->cursor_hidden && at < o.n && o.s[at] != '\n') {
		unsigned char c = (unsigned char) o.s[at];
		long len = c >= 0xf0 ? 4 : c >= 0xe0 ? 3 : c >= 0xc0 ? 2 : 1;
		if (at + len > o.n) len = o.n - at;
		memset(o.f + at, ID_COLOR_TERM_CURSOR, (size_t) len);
	}
	put_text(t, t->screen_start, document_size(t->bp), o.s ? o.s : "", o.f, o.n);
	free(o.s);
	free(o.f);
	t->damaged = 0;
	if (backdoor_on)
		backdoor_note("  terminal %s: drawn, its cursor at row %d, column %d%s; point %ld%s",
			      t->bp->b_bname, cursor.row, cursor.col, t->cursor_hidden ? " (the program hid it)" : "",
			      (long) (t->screen_start + at), t->copy ? " (copy mode: point stays)" : "");
	if (t->copy) return;
	/* the screen at the window's top, the cursor where the terminal's is */
	t->bp->b_point = t->screen_start + at;
	t->bp->b_page = t->screen_start;
	for (wp = wheadp; wp != NULL; wp = wp->w_next)
		if (wp->w_bufp == t->bp) {
			wp->w_point = t->bp->b_point;
			wp->w_page = t->bp->b_page;
			wp->w_update = TRUE;
		}
}

/* ------------------------------------------------------------------ */
/* libvterm's callbacks                                               */
/* ------------------------------------------------------------------ */

static int on_damage(VTermRect rect, void *user) { (void) rect; ((term_t *) user)->damaged = 1; return 1; }
static int on_movecursor(VTermPos p, VTermPos old, int visible, void *user)
{
	term_t *t = user;
	(void) p; (void) old;
	t->cursor_hidden = !visible;
	t->damaged = 1;
	return 1;
}

/* the program shows or hides the cursor (CSI ?25h / ?25l) */
static int on_settermprop(VTermProp prop, VTermValue *val, void *user)
{
	term_t *t = user;
	if (prop == VTERM_PROP_CURSORVISIBLE) { t->cursor_hidden = !val->boolean; t->damaged = 1; }
	return 1;
}

/* a line leaves the top of the screen: it joins the history, before the
 * screen (whose rows draw writes again) */
static int on_pushline(int cols, const VTermScreenCell *cells, void *user)
{
	term_t *t = user;
	out_t o = {0};
	int col = 0, n, i;
	long last = 0;
	char buf[4 * VTERM_MAX_CHARS_PER_CELL + 4];

	while (col < cols) {
		const VTermScreenCell *c = &cells[col];
		if (c->chars[0] == (uint32_t) -1) { col++; continue; }
		n = 0;
		if (c->chars[0] == 0) buf[n++] = ' ';
		else for (i = 0; i < VTERM_MAX_CHARS_PER_CELL && c->chars[i]; i++)
			n += utf8_encode(c->chars[i], buf + n);
		int face = cell_face(t, c);
		out_put(&o, buf, n, face);
		if (!(n == 1 && buf[0] == ' ' && face == ID_COLOR_ALPHA)) last = o.n;
		col += c->width > 0 ? c->width : 1;
	}
	o.n = last;
	out_put(&o, "\n", 1, ID_COLOR_ALPHA);
	put_text(t, t->screen_start, t->screen_start, o.s, o.f, o.n);
	t->screen_start += o.n;
	t->history++;
	free(o.s);
	free(o.f);
	if (t->history > TERM_HISTORY) {          /* the oldest thousand go */
		point_t p = 0, size = t->screen_start;
		long k = 0;
		while (p < size && k < 1000) { if (*ptr(t->bp, p) == '\n') k++; p++; }
		put_text(t, 0, p, "", NULL, 0);
		t->screen_start -= p;
		t->history -= k;
	}
	return 1;
}

/* what the terminal answers (cursor reports, the keys it encodes) goes
 * to the shell */
static void on_output(const char *s, size_t len, void *user)
{
	term_t *t = user;
	while (len > 0 && t->fd >= 0) {
		ssize_t k = write(t->fd, s, len);
		if (k < 0) { if (errno == EINTR || errno == EAGAIN) continue; break; }
		s += k;
		len -= (size_t) k;
	}
}

static VTermScreenCallbacks callbacks = {
	.damage = on_damage,
	.movecursor = on_movecursor,
	.settermprop = on_settermprop,
	.sb_pushline = on_pushline,
};

/* ------------------------------------------------------------------ */
/* Life                                                               */
/* ------------------------------------------------------------------ */

static term_t *find(buffer_t *bp)
{
	term_t *t;
	for (t = terms; t != NULL; t = t->next)
		if (t->bp == bp) return t;
	return NULL;
}

/* the size of the window showing T: its rows, and the screen's columns
 * but one -- a line that fills a row exactly is followed by an empty row
 * in the editor's display (display.c, segstart), which would show every
 * full-width line of Neovim or less with a blank row under it */
static void window_size(term_t *t, int *rows, int *cols)
{
	window_t *wp;
	*rows = 24;
	*cols = screen_cols() - 1;
	for (wp = wheadp; wp != NULL; wp = wp->w_next)
		if (wp->w_bufp == t->bp) { *rows = wp->w_rows; break; }
	if (*rows < 2) *rows = 2;
	if (*cols < 10) *cols = 10;
}

static void close_term(term_t *t, int status_known, int status)
{
	char note[128];

	if (t->fd >= 0) { close(t->fd); t->fd = -1; }
	if (t->pid > 0) {
		if (!status_known) {
			kill(-t->pid, SIGHUP);
			if (waitpid(t->pid, &status, WNOHANG) == t->pid) status_known = 1;
		}
		t->pid = 0;
	}
	t->cursor_hidden = 1;                  /* the last drawing without the cursor's cell */
	if (t->vt) draw(t);
	snprintf(note, sizeof note, "\n[Process exited%s%d]\n",
		 status_known && WIFSIGNALED(status) ? ": signal " : " with status ",
		 status_known ? (WIFSIGNALED(status) ? WTERMSIG(status) : WEXITSTATUS(status)) : 0);
	{
		char_t f[128];
		long n = (long) strlen(note);
		memset(f, ID_COLOR_ALPHA, (size_t) n);
		put_text(t, document_size(t->bp), document_size(t->bp), note, f, n);
	}
	t->exited = 1;
	t->bp->b_point = document_size(t->bp);
	t->bp->b_flags &= ~B_READONLY;      /* an ordinary buffer now (its colours stay) */
	if (t->vt) { vterm_free(t->vt); t->vt = NULL; t->vs = NULL; }
}

static void forget(term_t *t)
{
	term_t **p;
	for (p = &terms; *p != NULL; p = &(*p)->next)
		if (*p == t) { *p = t->next; break; }
	free(t->face);
	free(t);
}

static void kill_all(void)
{
	term_t *t;
	for (t = terms; t != NULL; t = t->next)
		if (t->pid > 0) kill(-t->pid, SIGHUP);
}

/* M-x term: a shell in the current buffer (term.scm makes *terminal*) */
const char *term_open(void)
{
	static int registered;
	struct winsize ws;
	term_t *t;
	const char *shell = getenv("SHELL");
	int fd;
	pid_t pid;

	if (find(curbp) != NULL) return "This buffer is already a terminal";
	t = calloc(1, sizeof *t);
	if (t == NULL) return "No memory for a terminal";
	t->bp = curbp;
	t->fd = -1;
	window_size(t, &t->rows, &t->cols);
	memset(&ws, 0, sizeof ws);
	ws.ws_row = (unsigned short) t->rows;
	ws.ws_col = (unsigned short) t->cols;
	if (shell == NULL || *shell == '\0' || access(shell, X_OK) != 0) shell = "/bin/sh";

	pid = forkpty(&fd, NULL, NULL, &ws);
	if (pid < 0) { free(t); return "Cannot open a pseudo-terminal"; }
	if (pid == 0) {
		const char *name = strrchr(shell, '/');
		setenv("TERM", "xterm-256color", 1);
		setenv("CHEZWEB_TERMINAL", "1", 1);
		unsetenv("COLUMNS");
		unsetenv("LINES");
		signal(SIGINT, SIG_DFL);
		signal(SIGQUIT, SIG_DFL);
		signal(SIGPIPE, SIG_DFL);
		execl(shell, name ? name + 1 : shell, (char *) NULL);
		_exit(127);
	}
	fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK);
	fcntl(fd, F_SETFD, FD_CLOEXEC);
	t->fd = fd;
	t->pid = pid;
	t->vt = vterm_new(t->rows, t->cols);
	vterm_set_utf8(t->vt, 1);
	vterm_output_set_callback(t->vt, on_output, t);
	t->vs = vterm_obtain_screen(t->vt);
	vterm_screen_set_callbacks(t->vs, &callbacks, t);
	vterm_screen_enable_altscreen(t->vs, 1);
	vterm_screen_set_damage_merge(t->vs, VTERM_DAMAGE_SCROLL);
	vterm_screen_reset(t->vs, 1);

	/* the buffer: emptied, read-only for the editor's commands */
	{
		point_t size = document_size(curbp);
		t->nface = size;
		if (!reserve_faces(t, size + 1)) { close(fd); kill(pid, SIGHUP); free(t); return "No memory for a terminal"; }
		memset(t->face, ID_COLOR_ALPHA, (size_t) size);
		put_text(t, 0, size, "", NULL, 0);
	}
	curbp->b_flags |= B_READONLY;
	curbp->b_flags &= ~B_MODIFIED;
	t->screen_start = 0;
	t->damaged = 1;
	t->next = terms;
	terms = t;
	if (!registered) { atexit(kill_all); registered = 1; }
	return "";
}

/* ------------------------------------------------------------------ */
/* Each poll: output, size, the end of the shell                      */
/* ------------------------------------------------------------------ */

int term_poll(void)
{
	term_t *t, *next;
	int changed = 0;
	char buf[16384];

	for (t = terms; t != NULL; t = next) {
		next = t->next;
		if (t->exited) continue;
		int rows, cols;
		window_size(t, &rows, &cols);
		if (rows != t->rows || cols != t->cols) {
			struct winsize ws;
			memset(&ws, 0, sizeof ws);
			ws.ws_row = (unsigned short) rows;
			ws.ws_col = (unsigned short) cols;
			t->rows = rows;
			t->cols = cols;
			vterm_set_size(t->vt, rows, cols);
			ioctl(t->fd, TIOCSWINSZ, &ws);
			t->damaged = 1;
		}
		for (int rounds = 0; rounds < 64; rounds++) {
			ssize_t n = read(t->fd, buf, sizeof buf);
			if (n > 0) { vterm_input_write(t->vt, buf, (size_t) n); continue; }
			if (n < 0 && (errno == EAGAIN || errno == EINTR)) break;
			/* EOF or EIO: the shell is gone */
			int status = 0, known = waitpid(t->pid, &status, 0) == t->pid;
			if (t->damaged) draw(t);
			close_term(t, known, status);
			changed = 1;
			break;
		}
		if (!t->exited && t->damaged) { draw(t); changed = 1; }
	}
	return changed;
}

/* ------------------------------------------------------------------ */
/* Keys                                                                */
/* ------------------------------------------------------------------ */

/* Does the keyboard go to the shell? (the main loop asks before each key) */
int term_takes_keys(buffer_t *bp)
{
	term_t *t;
	if (terms == NULL) return 0;
	if (editor_turn) { editor_turn = 0; return 0; }
	t = find(bp);
	return t != NULL && !t->exited && !t->copy;
}

static void to_shell(term_t *t, const char *s, size_t n)
{
	if (backdoor_on) {             /* the key bytes, escaped */
		char shown[64];
		size_t i, k = 0;
		for (i = 0; i < n && k + 5 < sizeof shown; i++) {
			unsigned char c = (unsigned char) s[i];
			if (c >= 0x20 && c < 0x7f && c != '\\') shown[k++] = (char) c;
			else k += (size_t) snprintf(shown + k, sizeof shown - k, "\\x%02x", c);
		}
		shown[k] = '\0';
		backdoor_note("  terminal %s: %zu bytes to the shell: %s", t->bp->b_bname, n, shown);
	}
	on_output(s, n, t);
}

/* the next key byte, if one comes within MS milliseconds, or -1 */
static int next_byte(int ms)
{
	return key_bytes_waiting(ms) ? read_key_byte() : -1;
}

/* the bytes of a CSI sequence after ESC [, up to its final byte */
static int read_csi(char *s, int max)
{
	int n = 0, c;
	while (n < max - 1 && (c = next_byte(50)) >= 0) {
		s[n++] = (char) c;
		if (c >= 0x40 && c <= 0x7e) break;
	}
	s[n] = '\0';
	return n;
}

/* the editor runs the bytes S as one key, then the keyboard is the shell's again */
static void to_editor(const char *s, int n)
{
	unread_key_bytes(s, n);
	editor_turn = 1;
}

void term_take_key(void)
{
	term_t *t = find(curbp);
	char seq[64];
	int c;

	if (t == NULL) return;
	c = read_key_byte();
	if (c < 0) return;
	if (t->exited) {                /* the shell ended while we waited: the key is the editor's */
		seq[0] = (char) c;
		unread_key_bytes(seq, 1);
		return;
	}
	if (c == 0x03) {                                   /* C-c, the escape */
		msg("C-c-");
		update_display();
		c = read_key_byte();
		msg("");
		if (c == 0x03) { to_shell(t, "\x03", 1); return; }
		if (c == 0x0a) {                           /* C-c C-j: copy mode */
			t->copy = 1;
			msg("Copy mode: the editor's keys; M-w copies; C-c C-k: back to the terminal");
			return;
		}
		if (c == 0x1b || c == 0x18) {             /* C-c M-x: M-x; C-c C-x: C-x (C-c C-x C-c quits) */
			seq[0] = (char) c;
			to_editor(seq, 1);
			return;
		}
		seq[0] = 0x18;                             /* C-c KEY: C-x KEY */
		seq[1] = (char) c;
		to_editor(seq, 2);
		return;
	}
	if (c == SCR_KEY_RESIZE) { seq[0] = (char) c; to_editor(seq, 1); return; }
	if (c == 0x1b) {
		int d = next_byte(25);
		if (d < 0) { to_shell(t, "\x1b", 1); return; }        /* Esc alone */
		if (d == '[') {
			int n = read_csi(seq + 2, (int) sizeof seq - 2);
			seq[0] = 0x1b; seq[1] = '[';
			if (n > 0 && (seq[2] == '<' || seq[2] == 'M')) {   /* the mouse: the editor's */
				if (seq[2] == 'M') {                 /* X10: three bytes follow */
					int k;
					for (k = 0; k < 3 && n + 2 < (int) sizeof seq - 1; k++) {
						int b = next_byte(50);
						if (b < 0) break;
						seq[2 + n++] = (char) b;
					}
				}
				to_editor(seq, n + 2);
				return;
			}
			if (n == 4 && !memcmp(seq + 2, "200~", 4)) {       /* a paste */
				char pbuf[4096];
				int pn = 0, b;
				vterm_keyboard_start_paste(t->vt);
				while ((b = next_byte(200)) >= 0) {
					pbuf[pn++] = (char) b;
					if (pn >= 6 && !memcmp(pbuf + pn - 6, "\x1b[201~", 6)) { pn -= 6; break; }
					if (pn == (int) sizeof pbuf) { to_shell(t, pbuf, (size_t) pn); pn = 0; }
				}
				if (pn > 0) to_shell(t, pbuf, (size_t) pn);
				vterm_keyboard_end_paste(t->vt);
				return;
			}
			to_shell(t, seq, (size_t) n + 2);
			return;
		}
		seq[0] = 0x1b;                                   /* Meta-key */
		seq[1] = (char) d;
		to_shell(t, seq, 2);
		return;
	}
	seq[0] = (char) c;
	if (c >= 0xc2 && c <= 0xf4) {                      /* a whole UTF-8 character */
		int need = c >= 0xf0 ? 4 : c >= 0xe0 ? 3 : 2, n = 1, b;
		while (n < need && (b = next_byte(50)) >= 0) seq[n++] = (char) b;
		to_shell(t, seq, (size_t) n);
		return;
	}
	to_shell(t, seq, 1);
}

/* ------------------------------------------------------------------ */
/* For the display, the buffers, the quit question and the scripts    */
/* ------------------------------------------------------------------ */

/* The faces of LEN bytes of BP from START (display.c): 1 if BP is a terminal */
int term_faces(buffer_t *bp, point_t start, char_t *faces, long len)
{
	term_t *t;
	if (terms == NULL || (t = find(bp)) == NULL) return 0;
	if (t->nface != document_size(bp)) return 0;   /* edited after the shell exited */
	for (long i = 0; i < len; i++)
		faces[i] = start + i < t->nface ? t->face[start + i] : ID_COLOR_ALPHA;
	return 1;
}

/* BP is being killed (buffer.c): its shell goes too */
void term_buffer_gone(buffer_t *bp)
{
	term_t *t;
	if (terms == NULL || (t = find(bp)) == NULL) return;
	if (t->pid > 0) kill(-t->pid, SIGHUP);
	if (t->fd >= 0) close(t->fd);
	if (t->pid > 0) waitpid(t->pid, NULL, WNOHANG);
	if (t->vt) vterm_free(t->vt);
	forget(t);
}

/* How many shells still run (C-x C-c asks first) */
int term_running(void)
{
	term_t *t;
	int n = 0;
	for (t = terms; t != NULL; t = t->next) if (!t->exited) n++;
	return n;
}

/* How long the idle poll waits (term.c, gui.c) */
int term_poll_ms(void) { return term_running() ? TERM_POLL_MS : 100; }

/* (fe-term-open): "" or why not */
char *fe_term_open(void) { return (char *) term_open(); }

/* 0 BP is not a terminal, 1 the shell has the keys, 2 copy mode, 3 the
 * shell has exited (the mode line: display.c) */
int term_state(buffer_t *bp)
{
	term_t *t = terms ? find(bp) : NULL;
	if (t == NULL) return 0;
	return t->exited ? 3 : t->copy ? 2 : 1;
}

/* (fe-term-state): the same, for the current buffer */
int fe_term_state(void) { return term_state(curbp); }

/* Does the editor draw BP's cursor itself (the shell has the keys), so
 * that the screen's own cursor is hidden? (display.c) */
int term_owns_cursor(buffer_t *bp) { return term_state(bp) == 1; }

/* (fe-term-copy-mode ON): copy mode on (1) or off (0); 1 if a terminal */
int fe_term_copy_mode(int on)
{
	term_t *t = terms ? find(curbp) : NULL;
	if (t == NULL || t->exited) return 0;
	t->copy = on != 0;
	t->damaged = 1;                          /* point back to the cursor; its cell drawn or not */
	return 1;
}
#endif
