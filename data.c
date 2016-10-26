/*
 * data.c, Femto Emacs, Hugh Barney, Public Domain, 2016
 * Derived from: Anthony's Editor January 93, (Public Domain 1991, 1993 by Anthony Howe)
 */

#include "header.h"

int done;
int result;
int global_undo_mode = 0;
point_t nscrap;
char_t *scrap;
char_t *input;
int msgflag;
char msgline[TEMPBUF];
char temp[TEMPBUF];
char searchtext[STRBUF_M];
char replace[STRBUF_M];
char *prog_name;
char lisp_result[LISP_IN_OUT];
char lisp_query[LISP_IN_OUT];

keymap_t *key_return;
keymap_t *key_map;

buffer_t *curbp;			/* current buffer */
buffer_t *bheadp;			/* head of list of buffers */
window_t *curwp;
window_t *wheadp;

char *f_ok = "%s: Terminated successfully.\n";
char *f_error = "%s: Unspecified error.\n";
char *f_usage = "usage: %s [-f <config>] [file]\n";
char *f_initscr = "%s: Failed to initialize the screen.\n";
char *f_alloc = "%s: Failed to allocate required memory.\n";
char *m_ok = "Ok.";
char *m_version = VERSION;
char *m_alloc = "No more memory available.";
char *m_toobig = "File \"%s\" is too big to load.";
char *m_empty = "Nothing to insert.";
char *m_stat = "Failed to find file \"%s\".";
char *m_open = "Failed to open file \"%s\".";
char *m_close = "Failed to close file \"%s\".";
char *m_write = "Failed to write file \"%s\".";
char *m_badname = "Not a portable POSIX file name.";
char *m_file = "File \"%s\" %ld bytes.";
char *m_saved = "File \"%s\" %ld bytes saved.";
char *m_loaded = "File \"%s\" %ld bytes read.";
char *m_copied = "%ld bytes copied.";
char *m_cut = "%ld bytes cut.";
char *m_newfile = "New file %s";
char *m_line = "Line %d";
char *m_lnot_found = "Line %d, not found";
char *m_replace = "Query replace: ";
char *m_with = "With: ";
char *m_goto = "Goto line: ";
char *m_sprompt = "Search: ";
char *m_qreplace = "Replace '%s' with '%s' ? ";
char *m_rephelp = "(y)es, (n)o, (!)do the rest, (q)uit";
char *m_nomark ="No mark set";
char *m_noregion = "No region defined, mark and point are the same place";

char *str_notsaved = "Discard changes (y/n) ?";
char *str_modified_buffers = "Modified buffers exist; really exit (y/n) ?";
char *str_read = "Find file: ";
char *str_insert_file ="Insert file: ";
char *str_write = "Write file: ";
char *str_yes = " y\b";
char *str_no = " n\b";
char *str_mark = "Mark set";
char *str_pos = "Char = %s 0x%x  Line = %d/%d  Point = %d/%d";
char *str_endpos = "[EOB] Line = %d/%d  Point = %d/%d";
char *str_scratch = "*scratch*";
char *str_output = "*output*";
char *str_shell_cmd = "Shell Command: ";
char *str_buffers = "*buffers*";
char *str_clip_too_big = "Region exceeds lisp clipboard limit of %d bytes";
char *str_not_bound  = "Not bound";
char *str_help_buf = "*help*";
char *str_completions = "*completions*";
char *str_apropos = "apropos: ";
char *str_exec_command = "Execute command: ";
