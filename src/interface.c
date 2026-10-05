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

/* generic notification: ("key" "C-x C-b"), ("kill" "*scratch*"), ("startup" "") */
typedef void (*fe_event_hook_t)(const char *event, const char *arg);

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

void call_lisp_event(char *event, char *arg)
{
	if (event_hook != NULL)
		event_hook(event, arg == NULL ? "" : arg);
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

#define FE_MAX_COLOR 16
static short color_fg[FE_MAX_COLOR + 1];
static short color_bg[FE_MAX_COLOR + 1];
static int colors_set = 0;

static void default_colors(void)
{
	int i;
	for (i = 0; i <= FE_MAX_COLOR; i++) {
		color_fg[i] = COLOR_WHITE;
		color_bg[i] = COLOR_BLACK;
	}
	color_fg[ID_COLOR_SYMBOL]   = COLOR_WHITE;
	color_fg[ID_COLOR_MODELINE] = COLOR_BLACK;  color_bg[ID_COLOR_MODELINE] = COLOR_WHITE;
	color_fg[ID_COLOR_BRACE]    = COLOR_BLACK;  color_bg[ID_COLOR_BRACE]    = COLOR_CYAN;
	color_fg[ID_COLOR_KEYWORD]  = COLOR_MAGENTA;
	color_fg[ID_COLOR_ALPHA]    = COLOR_CYAN;
	color_fg[ID_COLOR_DIGITS]   = COLOR_YELLOW;
	color_fg[ID_COLOR_COMMENTS] = COLOR_GREEN;
	color_fg[ID_COLOR_BLOCK]    = COLOR_GREEN;
	color_fg[ID_COLOR_STRING]   = COLOR_YELLOW;
	colors_set = 1;
}

/* (set-color :keyword :red :black) ends up here; colours are curses numbers 0-7 */
int fe_set_color(int id, int fg, int bg)
{
	if (!colors_set) default_colors();
	if (id < 1 || id > FE_MAX_COLOR) return 0;
	color_fg[id] = (short) fg;
	color_bg[id] = (short) bg;
	if (curscr != NULL && has_colors())
		init_pair((short) id, color_fg[id], color_bg[id]);
	return 1;
}

void init_colors(void)
{
	int i;
	if (!colors_set) default_colors();
	start_color();
	for (i = 1; i <= ID_COLOR_STRING; i++)
		init_pair((short) i, color_fg[i], color_bg[i]);
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

/* editing */
void fe_insert(char *s)         { insert_string(s); }
void fe_backward_delete_char(int n) { while (n-- > 0) backsp(); }
void fe_delete_char(int n)      { while (n-- > 0) delete(); }
void fe_kill_region(void)       { cut(); }
void fe_copy_region(void)       { copy(); }
void fe_yank(void)              { paste(); }
void fe_kill_line(void)         { killtoeol(); }
void fe_undo(void)              { undo_command(); }
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
void fe_update_display(void)         { if (curscr != NULL && curwp != NULL) update_display(); }
void fe_refresh(void)                { if (curscr != NULL) redraw(); }

/* message line */
void fe_message(char *s)             { msg("%s", s); }
void fe_clear_message_line(void)     { if (curscr != NULL) clear_message_line(); }
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
int   fe_screen_rows(void)           { return LINES; }
int   fe_screen_cols(void)           { return COLS; }
