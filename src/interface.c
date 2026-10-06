/*
 * interface.c, SBEmacs
 *
 * The bridge between the C editor core and SBCL.
 *
 * In the original FemtoEmacs the editor embedded femtolisp.  Here the roles
 * are reversed: SBCL is the host process.  It loads this library with
 * sb-alien:load-shared-object, installs three callbacks with fe_set_hooks()
 * and then calls fe_main().
 *
 *   Lisp -> C : every function in this file whose name starts with fe_
 *   C -> Lisp : the three hooks below
 *
 * Only fe_* symbols are meant to be called from Lisp; the editor's internal
 * names (left, right, copy, ...) are too generic to look up safely in a
 * process that also contains the SBCL runtime.
 */

#include "header.h"

/* ------------------------------------------------------------------ */
/* Hooks installed by Lisp                                             */
/* ------------------------------------------------------------------ */

/* evaluate EXPR, write the printed result (NUL terminated) into OUT */
typedef int (*fe_eval_hook_t)(const char *expr, char *out, int outlen);

/*
 * generic notification: ("key" "C-x C-b"), ("kill" "*scratch*"),
 * ("startup" ""), ("colors" "256"), ("self-insert" "\t").  Returns
 * non-zero when Lisp handled the event (for self-insert: the key was
 * consumed, e.g. TAB indented the line, so C must not insert it).
 */
typedef int (*fe_event_hook_t)(const char *event, const char *arg);

/*
 * syntax highlighting: given the buffer's file name and LEN bytes of text,
 * fill COLORS[0..LEN-1] with one of the ID_COLOR_* values
 */
typedef void (*fe_highlight_hook_t)(const char *fname, const char *bname,
				    const char_t *text, int len, char_t *colors);

static fe_eval_hook_t      eval_hook      = NULL;
static fe_event_hook_t     event_hook     = NULL;
static fe_highlight_hook_t highlight_hook = NULL;

void fe_set_hooks(fe_eval_hook_t ev, fe_event_hook_t evt, fe_highlight_hook_t hl)
{
	eval_hook = ev;
	event_hook = evt;
	highlight_hook = hl;
}

/* evaluate a string of Lisp; result goes to out */
void call_lisp(char *expr, char *out, int outlen)
{
	if (outlen <= 0) return;
	out[0] = '\0';
	if (eval_hook == NULL) {
		safe_strncpy(out, "Lisp not available", outlen);
		return;
	}
	(void) eval_hook(expr, out, outlen);
	out[outlen - 1] = '\0';
}

int call_lisp_event(char *event, char *arg)
{
	if (event_hook != NULL)
		return event_hook(event, arg == NULL ? "" : arg);
	return 0;
}

/*
 * Ask Lisp for the colours of LEN bytes of TEXT.  Returns 0 when there is no
 * highlighter, in which case the caller uses the default colour.
 */
int call_lisp_highlight(buffer_t *bp, char_t *text, int len, char_t *colors)
{
	if (highlight_hook == NULL || len <= 0)
		return 0;
	highlight_hook(bp->b_fname, bp->b_bname, text, len, colors);
	return 1;
}

/* ------------------------------------------------------------------ */
/* Colours, settable from Lisp before fe_main() starts curses           */
/* ------------------------------------------------------------------ */

/*
 * Each face (ID_COLOR_*) has a foreground, a background and attributes.
 * -1 means the terminal's own default colour.  Using the terminal's
 * background (instead of forcing black, as FemtoEmacs did) keeps the
 * terminal's cursor visible on light and dark themes alike.
 *
 * The default theme is chosen when curses starts, because only then do we
 * know whether the terminal has 256 colours.  Faces set from Lisp before
 * that are remembered and applied on top of it.
 */

#define FE_MAX_COLOR 16

/* attribute bits used by fe_set_color: the same as SCR_* in screen.h */
#define FE_BOLD      SCR_BOLD
#define FE_UNDERLINE SCR_UNDERLINE
#define FE_REVERSE   SCR_REVERSE
#define FE_DIM       SCR_DIM
#define FE_ITALIC    SCR_ITALIC

/* basic colour numbers (the xterm palette) */
enum { C_BLACK, C_RED, C_GREEN, C_YELLOW, C_BLUE, C_MAGENTA, C_CYAN, C_WHITE };

static long  color_fg[FE_MAX_COLOR + 1];
static long  color_bg[FE_MAX_COLOR + 1];
static int   color_attr[FE_MAX_COLOR + 1];
static long  user_fg[FE_MAX_COLOR + 1];
static long  user_bg[FE_MAX_COLOR + 1];
static int   user_attr[FE_MAX_COLOR + 1];
static int   user_set[FE_MAX_COLOR + 1];
static int   colors_ready = 0;

static void face(int id, long fg, long bg, int attr)
{
	color_fg[id] = fg;
	color_bg[id] = bg;
	color_attr[id] = attr;
}

/* a fallback in case lisp/theme.lisp is missing or broken */
static void default_theme(int many_colors)
{
	int i;
	for (i = 0; i <= FE_MAX_COLOR; i++)
		face(i, -1, -1, 0);

	face(ID_COLOR_MODELINE, -1, -1, FE_REVERSE);
	face(ID_COLOR_BRACE, C_BLACK, C_CYAN, 0);
	face(ID_COLOR_REGION, -1, -1, FE_REVERSE);
	face(ID_COLOR_HEADING, -1, -1, FE_BOLD);
	face(ID_COLOR_EMPHASIS, -1, -1, FE_ITALIC);
	face(ID_COLOR_STRONG, -1, -1, FE_BOLD);
	face(ID_COLOR_LINK, -1, -1, FE_UNDERLINE);

	if (many_colors) {
		face(ID_COLOR_KEYWORD,  127, -1, FE_BOLD);  /* purple */
		face(ID_COLOR_DIGITS,   166, -1, 0);        /* orange */
		face(ID_COLOR_COMMENTS, 244, -1, 0);        /* grey   */
		face(ID_COLOR_BLOCK,    244, -1, 0);
		face(ID_COLOR_STRING,    64, -1, 0);        /* olive green */
	} else {
		face(ID_COLOR_KEYWORD,  C_MAGENTA, -1, FE_BOLD);
		face(ID_COLOR_DIGITS,   C_RED,     -1, 0);
		face(ID_COLOR_COMMENTS, C_BLUE,    -1, 0);
		face(ID_COLOR_BLOCK,    C_BLUE,    -1, 0);
		face(ID_COLOR_STRING,   C_GREEN,   -1, 0);
	}
}

static void install_face(int id)
{
	screen_set_face(id, color_fg[id], color_bg[id], color_attr[id]);
}

/* draw with a face from now on */
void face_on(int id)
{
	screen_face(id);
}

/*
 * (set-color :keyword :red) ends up here.  Colours are 0-255 or -1 for
 * the terminal default; attr is a combination of the FE_* bits.
 */
int fe_set_color(int id, long fg, long bg, int attr)
{
	if (id < 1 || id > FE_MAX_COLOR) return 0;
	user_fg[id] = fg;
	user_bg[id] = bg;
	user_attr[id] = attr;
	user_set[id] = 1;
	if (colors_ready) {
		face(id, fg, bg, attr);
		install_face(id);
	}
	return 1;
}

/*
 * Used by the Lisp colour theme (lisp/theme.lisp) while init_colors runs:
 * like fe_set_color, but it sets the theme's face, which the user's own
 * set-color calls still override.
 */
int fe_set_theme_face(int id, long fg, long bg, int attr)
{
	if (id < 1 || id > FE_MAX_COLOR) return 0;
	face(id, fg, bg, attr);
	return 1;
}

/* number of colours the terminal supports (0 before curses starts) */
int fe_colors(void)
{
	return colors_ready ? screen_colors() : 0;
}

/* built-in fallback, then the Lisp theme, then the user's own faces */
static void apply_faces(void)
{
	int i;
	char ncolors[16];

	default_theme(screen_colors() >= 256);
	colors_ready = 1;
	snprintf(ncolors, sizeof(ncolors), "%d", screen_colors());
	call_lisp_event("colors", ncolors);
	for (i = 1; i <= FE_MAX_COLOR; i++) {
		if (user_set[i])
			face(i, user_fg[i], user_bg[i], user_attr[i]);
		install_face(i);
	}
}

void init_colors(void)
{
	apply_faces();
}

/* re-run the theme, e.g. after lisp/theme.lisp was edited and reloaded */
void fe_reapply_colors(void)
{
	if (!colors_ready) return;
	apply_faces();
	redraw();
}

/* ------------------------------------------------------------------ */
/* Functions called from Lisp                                          */
/* ------------------------------------------------------------------ */

/* movement */
void fe_backward_char(int n)    { while (n-- > 0) left(); }
void fe_forward_char(int n)     { while (n-- > 0) right(); }
void fe_backward_word(int n)    { while (n-- > 0) backward_word(); }
void fe_forward_word(int n)     { while (n-- > 0) forward_word(); }
void fe_backward_page(int n)    { while (n-- > 0) backward_page(); }
void fe_forward_page(int n)     { while (n-- > 0) forward_page(); }
void fe_next_line(int n)        { while (n-- > 0) down(); }
void fe_previous_line(int n)    { while (n-- > 0) up(); }
void fe_beginning_of_line(void) { lnbegin(); }
void fe_end_of_line(void)       { lnend(); }
void fe_beginning_of_buffer(void) { beginning_of_buffer(); }
void fe_end_of_buffer(void)     { end_of_buffer(); }
void fe_goto_line(int n)        { goto_line(n); }

/* point and mark */
long fe_get_point(void)         { return curbp->b_point; }
long fe_get_mark(void)          { return curbp->b_mark; }
long fe_buffer_size(void)       { return document_size(curbp); }
void fe_set_mark(void)          { i_set_mark(); }

/* the mark at offset P (negative: no mark), without touching the region state */
void fe_set_mark_at(long p)
{
	long size = document_size(curbp);
	if (p > size) p = size;
	curbp->b_mark = p < 0 ? NOMARK : p;
}

/* is the region active (shaded)?  Set it with fe_set_mark_active */
int  fe_mark_active(void)       { return mark_active && curbp->b_mark != NOMARK; }
void fe_set_mark_active(int on) { mark_active = on ? 1 : 0; }

void fe_set_point(long p)
{
	long size = document_size(curbp);
	if (p < 0) p = 0;
	if (p > size) p = size;
	curbp->b_point = p;
}

/* the character (byte) at the given offset, or -1 */
int fe_char_at(long p)
{
	if (p < 0 || p >= document_size(curbp)) return -1;
	return *ptr(curbp, p);
}

/*
 * Copy up to LEN bytes of the current buffer, starting at offset START,
 * into OUT.  Returns the number of bytes copied.  Used by the Lisp side to
 * read text in bulk (indentation, scanning) instead of byte by byte.
 */
long fe_copy_text(long start, long len, char *out)
{
	long size = document_size(curbp);
	long i;

	if (start < 0) start = 0;
	if (start + len > size) len = size - start;
	for (i = 0; i < len; i++)
		out[i] = (char) *ptr(curbp, start + i);
	return len < 0 ? 0 : len;
}

/* offset of the start of the logical line containing P */
long fe_line_start(long p)
{
	long size = document_size(curbp);
	if (p < 0) p = 0;
	if (p > size) p = size;
	return lnstart(curbp, p);
}

/* editing */
void fe_insert(char *s)         { insert_string(s); }
void fe_backward_delete_char(int n) { while (n-- > 0) backsp(); }
void fe_delete_char(int n)      { while (n-- > 0) delete(); }
void fe_kill_region(void)       { cut(); }
void fe_copy_region(void)       { copy(); }
void fe_yank(void)              { paste(); }
void fe_kill_line(void)         { killtoeol(); }
void fe_undo(void)              { undo_command(); }

/* the current buffer's id (see b_id), and its modified flag */
long fe_buffer_id(void)         { return curbp->b_id; }
void fe_set_modified(int on)
{
	if (on) add_mode(curbp, B_MODIFIED);
	else delete_mode(curbp, B_MODIFIED);
}

/* delete the bytes from START to END exactly (undo uses it) */
void fe_delete_region(long start, long end)
{
	long size = document_size(curbp);
	long len;

	if (start < 0) start = 0;
	if (end > size) end = size;
	if (end <= start) return;
	len = end - start;
	curbp->b_point = movegap(curbp, start);
	/* the bytes are now at the end of the gap; report them before dropping them */
	record_change(curbp, 'd', start, curbp->b_egap, len);
	curbp->b_egap += len;
	curbp->b_point = start;
	if (curbp->b_mark > start)
		curbp->b_mark = curbp->b_mark >= end ? curbp->b_mark - len : start;
	add_mode(curbp, B_MODIFIED);
}

/* insert LEN bytes exactly, at P (undo uses it: the bytes need not be UTF-8) */
void fe_insert_bytes(long p, char *bytes, long len)
{
	long size = document_size(curbp);

	if (len <= 0) return;
	if (p < 0) p = 0;
	if (p > size) p = size;
	if (len >= curbp->b_egap - curbp->b_gap && !growgap(curbp, len))
		return;
	curbp->b_point = movegap(curbp, p);
	memcpy(curbp->b_gap, bytes, len);
	curbp->b_gap += len;
	record_change(curbp, 'i', p, (char_t *) bytes, len);
	curbp->b_point = p + len;
	if (curbp->b_mark >= p && curbp->b_mark != NOMARK)
		curbp->b_mark += len;
	add_mode(curbp, B_MODIFIED);
}
void fe_discard_undo_history(void) { discard_undo_history(); }

/* clipboard */
char *fe_get_clipboard(void)
{
	static char empty[] = "";
	char *p = (char *) get_scrap();
	return p == NULL ? empty : p;
}

void fe_set_clipboard(char *str)
{
	/*
	 * the string belongs to Lisp, take a malloc'd copy so that the
	 * editor can later free() it like any other scrap
	 */
	size_t len = strlen(str);
	unsigned char *p = malloc(len + 1);
	assert(p != NULL);
	memcpy(p, str, len + 1);
	set_scrap(p);
	/* Keep Lisp-originated copies and the GUI's system clipboard in sync. */
	screen_set_clipboard(str);
}

/* searching: returns 1 when found (and moves there), 0 otherwise */
int fe_search_forward(char *str)
{
	point_t found = search_forward(str);
	move_to_search_result(found);
	return found != -1;
}

int fe_search_backward(char *str)
{
	point_t found = search_backwards(str);
	move_to_search_result(found);
	return found != -1;
}

/* buffers */
int   fe_buffer_count(void)          { return count_buffers(); }
char *fe_buffer_name(void)           { return get_current_bufname(); }
char *fe_buffer_filename(void)       { return curbp->b_fname; }
int   fe_buffer_modified(void)       { return (curbp->b_flags & B_MODIFIED) != 0; }
int   fe_select_buffer(char *name)   { return select_buffer(name); }
int   fe_kill_buffer(char *name)     { return delete_buffer_byname(name); }
int   fe_save_buffer(char *name)     { return save_buffer_byname(name); }
void  fe_find_file(char *fname)      { readfile(fname); }
void  fe_list_buffers(void)          { list_buffers(); }
char *fe_rename_buffer(char *name)   { return rename_current_buffer(name); }

/* windows and display */
void fe_delete_other_windows(void)   { delete_other_windows(); }
void fe_other_window(void)           { other_window(); }
void fe_split_window(void)           { split_window(); }
void fe_update_display(void)         { if (screen_active() && curwp != NULL) update_display(); }
void fe_refresh(void)                { if (screen_active()) redraw(); }
void fe_delete_window(void)          { delete_window(); }
int  fe_window_count(void)           { return count_windows(); }
int  fe_window_rows(void)            { return curwp == NULL ? 0 : curwp->w_rows; }
void fe_recenter(void)               { if (screen_active()) recenter(); }

/* show the selected window from offset P (the start of a line) */
void fe_set_window_start(long p)
{
	if (p < 0) p = 0;
	if (p > document_size(curbp)) p = document_size(curbp);
	curbp->b_page = p;
	if (curbp->b_point < p)
		curbp->b_point = p;
}
int  fe_line_number(long p)          { return line_number(curbp, p); }

/*
 * Run a command of the C core by name ("query-replace", "exec-lisp-command"
 * ...).  Returns 0 when there is no such command.
 */
int fe_execute_command(char *name)
{
	command_t *fn;
	for (fn = commands; fn->name != NULL; fn++)
		if (strcmp(fn->name, name) == 0) {
			whatKey = fn->name;
			(fn->func)();
			return 1;
		}
	return 0;
}

/* the name of the C command number I, or NULL after the last one */
char *fe_command_name(int i)
{
	int n;
	for (n = 0; n < i && commands[n].name != NULL; n++)
		;
	return commands[n].name;
}

/* message line */
void fe_message(char *s)             { msg("%s", s); }
void fe_clear_message_line(void)     { if (screen_active()) clear_message_line(); }
void fe_log_debug(char *s)           { debug("%s", s); }
void fe_log_message(char *s)         { log_message(s); }

/* keyboard */
char *fe_get_key(void)               { return fe_get_input_key(); }

char *fe_get_key_name(void)
{
	return key_return == NULL ? "" : key_return->key_name;
}

char *fe_get_key_binding(void)
{
	return key_return == NULL ? "" : key_return->key_desc;
}

/* prompt on the message line; returns a static buffer */
char *fe_prompt(char *prompt, char *initial)
{
	static char response[TEMPBUF];
	safe_strncpy(response, initial, TEMPBUF);
	if (!getinput(prompt, response, TEMPBUF - 1, F_NONE))
		response[0] = '\0';
	return response;
}

/* misc */
void  fe_shell_command(char *cmd)    { shell_command(cmd); }
int   fe_add_mode_global(char *mode) { return add_mode_global(mode); }
char *fe_version(void)               { return get_version_string(); }
void  fe_quit(void)                  { done = 1; }
int   fe_screen_rows(void)           { return screen_active() ? screen_rows() : 0; }
int   fe_screen_cols(void)           { return screen_active() ? screen_cols() : 0; }

/* can this back end start here?  (the GUI needs a display) */
int fe_screen_probe(void)            { return screen_probe(); }

/* which back end this library was built with: "terminal" or "gui" */
const char *fe_backend(void)         { return screen_backend(); }

/*
 * GUI settings, given by lisp/gui.lisp before fe_main (no-ops in the
 * terminal library).  Colours as in fe_set_color.
 */
void fe_gui_set_font(char *path, int points)          { screen_set_font(path, points); }
void fe_gui_set_colors(long fg, long bg, long cursor) { screen_set_default_colors(fg, bg, cursor); }
void fe_gui_set_option(char *name, int value)         { screen_set_option(name, value); }
