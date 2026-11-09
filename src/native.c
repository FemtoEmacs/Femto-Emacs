/* Generated typed adapters for the sbcl branch's C API. */
#include <string.h>
#include "llt/llt.h"
#include "flisp.h"
extern int fe_set_color(int id, long fg, long bg, int attr);
static value_t wrap_fe_set_color(value_t *a, uint32_t n) {
 argcount("fe_set_color", n, 4);
 return fixnum(fe_set_color(tofixnum(a[0], "fe_set_color"), tofixnum(a[1], "fe_set_color"), tofixnum(a[2], "fe_set_color"), tofixnum(a[3], "fe_set_color")));
}
extern int fe_set_theme_face(int id, long fg, long bg, int attr);
static value_t wrap_fe_set_theme_face(value_t *a, uint32_t n) {
 argcount("fe_set_theme_face", n, 4);
 return fixnum(fe_set_theme_face(tofixnum(a[0], "fe_set_theme_face"), tofixnum(a[1], "fe_set_theme_face"), tofixnum(a[2], "fe_set_theme_face"), tofixnum(a[3], "fe_set_theme_face")));
}
extern int fe_colors(void);
static value_t wrap_fe_colors(value_t *a, uint32_t n) {
 argcount("fe_colors", n, 0);
 return fixnum(fe_colors());
}
extern void fe_reapply_colors(void);
static value_t wrap_fe_reapply_colors(value_t *a, uint32_t n) {
 argcount("fe_reapply_colors", n, 0);
 fe_reapply_colors(); return FL_T;
}
extern void fe_backward_char(int n);
static value_t wrap_fe_backward_char(value_t *a, uint32_t n) {
 argcount("fe_backward_char", n, 1);
 fe_backward_char(tofixnum(a[0], "fe_backward_char")); return FL_T;
}
extern void fe_forward_char(int n);
static value_t wrap_fe_forward_char(value_t *a, uint32_t n) {
 argcount("fe_forward_char", n, 1);
 fe_forward_char(tofixnum(a[0], "fe_forward_char")); return FL_T;
}
extern void fe_backward_word(int n);
static value_t wrap_fe_backward_word(value_t *a, uint32_t n) {
 argcount("fe_backward_word", n, 1);
 fe_backward_word(tofixnum(a[0], "fe_backward_word")); return FL_T;
}
extern void fe_forward_word(int n);
static value_t wrap_fe_forward_word(value_t *a, uint32_t n) {
 argcount("fe_forward_word", n, 1);
 fe_forward_word(tofixnum(a[0], "fe_forward_word")); return FL_T;
}
extern void fe_backward_page(int n);
static value_t wrap_fe_backward_page(value_t *a, uint32_t n) {
 argcount("fe_backward_page", n, 1);
 fe_backward_page(tofixnum(a[0], "fe_backward_page")); return FL_T;
}
extern void fe_forward_page(int n);
static value_t wrap_fe_forward_page(value_t *a, uint32_t n) {
 argcount("fe_forward_page", n, 1);
 fe_forward_page(tofixnum(a[0], "fe_forward_page")); return FL_T;
}
extern void fe_next_line(int n);
static value_t wrap_fe_next_line(value_t *a, uint32_t n) {
 argcount("fe_next_line", n, 1);
 fe_next_line(tofixnum(a[0], "fe_next_line")); return FL_T;
}
extern void fe_previous_line(int n);
static value_t wrap_fe_previous_line(value_t *a, uint32_t n) {
 argcount("fe_previous_line", n, 1);
 fe_previous_line(tofixnum(a[0], "fe_previous_line")); return FL_T;
}
extern void fe_beginning_of_line(void);
static value_t wrap_fe_beginning_of_line(value_t *a, uint32_t n) {
 argcount("fe_beginning_of_line", n, 0);
 fe_beginning_of_line(); return FL_T;
}
extern void fe_end_of_line(void);
static value_t wrap_fe_end_of_line(value_t *a, uint32_t n) {
 argcount("fe_end_of_line", n, 0);
 fe_end_of_line(); return FL_T;
}
extern void fe_beginning_of_buffer(void);
static value_t wrap_fe_beginning_of_buffer(value_t *a, uint32_t n) {
 argcount("fe_beginning_of_buffer", n, 0);
 fe_beginning_of_buffer(); return FL_T;
}
extern void fe_end_of_buffer(void);
static value_t wrap_fe_end_of_buffer(value_t *a, uint32_t n) {
 argcount("fe_end_of_buffer", n, 0);
 fe_end_of_buffer(); return FL_T;
}
extern void fe_goto_line(int n);
static value_t wrap_fe_goto_line(value_t *a, uint32_t n) {
 argcount("fe_goto_line", n, 1);
 fe_goto_line(tofixnum(a[0], "fe_goto_line")); return FL_T;
}
extern long fe_get_point(void);
static value_t wrap_fe_get_point(value_t *a, uint32_t n) {
 argcount("fe_get_point", n, 0);
 return fixnum(fe_get_point());
}
extern long fe_get_mark(void);
static value_t wrap_fe_get_mark(value_t *a, uint32_t n) {
 argcount("fe_get_mark", n, 0);
 return fixnum(fe_get_mark());
}
extern long fe_buffer_size(void);
static value_t wrap_fe_buffer_size(value_t *a, uint32_t n) {
 argcount("fe_buffer_size", n, 0);
 return fixnum(fe_buffer_size());
}
extern void fe_set_mark(void);
static value_t wrap_fe_set_mark(value_t *a, uint32_t n) {
 argcount("fe_set_mark", n, 0);
 fe_set_mark(); return FL_T;
}
extern void fe_set_mark_at(long p);
static value_t wrap_fe_set_mark_at(value_t *a, uint32_t n) {
 argcount("fe_set_mark_at", n, 1);
 fe_set_mark_at(tofixnum(a[0], "fe_set_mark_at")); return FL_T;
}
extern int fe_mark_active(void);
static value_t wrap_fe_mark_active(value_t *a, uint32_t n) {
 argcount("fe_mark_active", n, 0);
 return fixnum(fe_mark_active());
}
extern void fe_set_mark_active(int on);
static value_t wrap_fe_set_mark_active(value_t *a, uint32_t n) {
 argcount("fe_set_mark_active", n, 1);
 fe_set_mark_active(tofixnum(a[0], "fe_set_mark_active")); return FL_T;
}
extern void fe_set_point(long p);
static value_t wrap_fe_set_point(value_t *a, uint32_t n) {
 argcount("fe_set_point", n, 1);
 fe_set_point(tofixnum(a[0], "fe_set_point")); return FL_T;
}
extern int fe_char_at(long p);
static value_t wrap_fe_char_at(value_t *a, uint32_t n) {
 argcount("fe_char_at", n, 1);
 return fixnum(fe_char_at(tofixnum(a[0], "fe_char_at")));
}
extern long fe_line_start(long p);
static value_t wrap_fe_line_start(value_t *a, uint32_t n) {
 argcount("fe_line_start", n, 1);
 return fixnum(fe_line_start(tofixnum(a[0], "fe_line_start")));
}
extern void fe_read_mode(int mode);
static value_t wrap_fe_read_mode(value_t *a, uint32_t n) {
 argcount("fe_read_mode", n, 1);
 fe_read_mode(tofixnum(a[0], "fe_read_mode")); return FL_T;
}
extern int fe_read_state(char *name);
static value_t wrap_fe_read_state(value_t *a, uint32_t n) {
 argcount("fe_read_state", n, 1);
 return fixnum(fe_read_state(tostring(a[0], "fe_read_state")));
}
extern int fe_read_key(char *key);
static value_t wrap_fe_read_key(value_t *a, uint32_t n) {
 argcount("fe_read_key", n, 1);
 return fixnum(fe_read_key(tostring(a[0], "fe_read_key")));
}
extern void fe_insert(char *s);
static value_t wrap_fe_insert(value_t *a, uint32_t n) {
 argcount("fe_insert", n, 1);
 fe_insert(tostring(a[0], "fe_insert")); return FL_T;
}
extern void fe_backward_delete_char(int n);
static value_t wrap_fe_backward_delete_char(value_t *a, uint32_t n) {
 argcount("fe_backward_delete_char", n, 1);
 fe_backward_delete_char(tofixnum(a[0], "fe_backward_delete_char")); return FL_T;
}
extern void fe_delete_char(int n);
static value_t wrap_fe_delete_char(value_t *a, uint32_t n) {
 argcount("fe_delete_char", n, 1);
 fe_delete_char(tofixnum(a[0], "fe_delete_char")); return FL_T;
}
extern void fe_kill_region(void);
static value_t wrap_fe_kill_region(value_t *a, uint32_t n) {
 argcount("fe_kill_region", n, 0);
 fe_kill_region(); return FL_T;
}
extern void fe_copy_region(void);
static value_t wrap_fe_copy_region(value_t *a, uint32_t n) {
 argcount("fe_copy_region", n, 0);
 fe_copy_region(); return FL_T;
}
extern void fe_yank(void);
static value_t wrap_fe_yank(value_t *a, uint32_t n) {
 argcount("fe_yank", n, 0);
 fe_yank(); return FL_T;
}
extern void fe_kill_line(void);
static value_t wrap_fe_kill_line(value_t *a, uint32_t n) {
 argcount("fe_kill_line", n, 0);
 fe_kill_line(); return FL_T;
}
extern void fe_undo(void);
static value_t wrap_fe_undo(value_t *a, uint32_t n) {
 argcount("fe_undo", n, 0);
 fe_undo(); return FL_T;
}
extern long fe_buffer_id(void);
static value_t wrap_fe_buffer_id(value_t *a, uint32_t n) {
 argcount("fe_buffer_id", n, 0);
 return fixnum(fe_buffer_id());
}
extern void fe_set_modified(int on);
static value_t wrap_fe_set_modified(value_t *a, uint32_t n) {
 argcount("fe_set_modified", n, 1);
 fe_set_modified(tofixnum(a[0], "fe_set_modified")); return FL_T;
}
extern void fe_delete_region(long start, long end);
static value_t wrap_fe_delete_region(value_t *a, uint32_t n) {
 argcount("fe_delete_region", n, 2);
 fe_delete_region(tofixnum(a[0], "fe_delete_region"), tofixnum(a[1], "fe_delete_region")); return FL_T;
}
extern void fe_discard_undo_history(void);
static value_t wrap_fe_discard_undo_history(value_t *a, uint32_t n) {
 argcount("fe_discard_undo_history", n, 0);
 fe_discard_undo_history(); return FL_T;
}
extern char * fe_get_clipboard(void);
static value_t wrap_fe_get_clipboard(value_t *a, uint32_t n) {
 argcount("fe_get_clipboard", n, 0);
 const char *s = fe_get_clipboard(); return string_from_cstrn((char *)(s ? s : ""), s ? strlen(s) : 0);
}
extern void fe_set_scrap(char *str);
static value_t wrap_fe_set_scrap(value_t *a, uint32_t n) {
 argcount("fe_set_scrap", n, 1);
 fe_set_scrap(tostring(a[0], "fe_set_scrap")); return FL_T;
}
extern void fe_set_clipboard(char *str);
static value_t wrap_fe_set_clipboard(value_t *a, uint32_t n) {
 argcount("fe_set_clipboard", n, 1);
 fe_set_clipboard(tostring(a[0], "fe_set_clipboard")); return FL_T;
}
extern char * fe_clipboard_tool(void);
static value_t wrap_fe_clipboard_tool(value_t *a, uint32_t n) {
 argcount("fe_clipboard_tool", n, 0);
 const char *s = fe_clipboard_tool(); return string_from_cstrn((char *)(s ? s : ""), s ? strlen(s) : 0);
}
extern void fe_set_system_clipboard(char *str);
static value_t wrap_fe_set_system_clipboard(value_t *a, uint32_t n) {
 argcount("fe_set_system_clipboard", n, 1);
 fe_set_system_clipboard(tostring(a[0], "fe_set_system_clipboard")); return FL_T;
}
extern char * fe_get_system_clipboard(void);
static value_t wrap_fe_get_system_clipboard(value_t *a, uint32_t n) {
 argcount("fe_get_system_clipboard", n, 0);
 const char *s = fe_get_system_clipboard(); return string_from_cstrn((char *)(s ? s : ""), s ? strlen(s) : 0);
}
extern int fe_search_forward(char *str);
static value_t wrap_fe_search_forward(value_t *a, uint32_t n) {
 argcount("fe_search_forward", n, 1);
 return fixnum(fe_search_forward(tostring(a[0], "fe_search_forward")));
}
extern int fe_search_backward(char *str);
static value_t wrap_fe_search_backward(value_t *a, uint32_t n) {
 argcount("fe_search_backward", n, 1);
 return fixnum(fe_search_backward(tostring(a[0], "fe_search_backward")));
}
extern int fe_buffer_count(void);
static value_t wrap_fe_buffer_count(value_t *a, uint32_t n) {
 argcount("fe_buffer_count", n, 0);
 return fixnum(fe_buffer_count());
}
extern char * fe_buffer_name(void);
static value_t wrap_fe_buffer_name(value_t *a, uint32_t n) {
 argcount("fe_buffer_name", n, 0);
 const char *s = fe_buffer_name(); return string_from_cstrn((char *)(s ? s : ""), s ? strlen(s) : 0);
}
extern char * fe_buffer_filename(void);
static value_t wrap_fe_buffer_filename(value_t *a, uint32_t n) {
 argcount("fe_buffer_filename", n, 0);
 const char *s = fe_buffer_filename(); return string_from_cstrn((char *)(s ? s : ""), s ? strlen(s) : 0);
}
extern int fe_buffer_modified(void);
static value_t wrap_fe_buffer_modified(value_t *a, uint32_t n) {
 argcount("fe_buffer_modified", n, 0);
 return fixnum(fe_buffer_modified());
}
extern int fe_select_buffer(char *name);
static value_t wrap_fe_select_buffer(value_t *a, uint32_t n) {
 argcount("fe_select_buffer", n, 1);
 return fixnum(fe_select_buffer(tostring(a[0], "fe_select_buffer")));
}
extern int fe_kill_buffer(char *name);
static value_t wrap_fe_kill_buffer(value_t *a, uint32_t n) {
 argcount("fe_kill_buffer", n, 1);
 return fixnum(fe_kill_buffer(tostring(a[0], "fe_kill_buffer")));
}
extern int fe_save_buffer(char *name);
static value_t wrap_fe_save_buffer(value_t *a, uint32_t n) {
 argcount("fe_save_buffer", n, 1);
 return fixnum(fe_save_buffer(tostring(a[0], "fe_save_buffer")));
}
extern void fe_find_file(char *fname);
static value_t wrap_fe_find_file(value_t *a, uint32_t n) {
 argcount("fe_find_file", n, 1);
 fe_find_file(tostring(a[0], "fe_find_file")); return FL_T;
}
extern void fe_list_buffers(void);
static value_t wrap_fe_list_buffers(value_t *a, uint32_t n) {
 argcount("fe_list_buffers", n, 0);
 fe_list_buffers(); return FL_T;
}
extern char * fe_rename_buffer(char *name);
static value_t wrap_fe_rename_buffer(value_t *a, uint32_t n) {
 argcount("fe_rename_buffer", n, 1);
 const char *s = fe_rename_buffer(tostring(a[0], "fe_rename_buffer")); return string_from_cstrn((char *)(s ? s : ""), s ? strlen(s) : 0);
}
extern void fe_delete_other_windows(void);
static value_t wrap_fe_delete_other_windows(value_t *a, uint32_t n) {
 argcount("fe_delete_other_windows", n, 0);
 fe_delete_other_windows(); return FL_T;
}
extern void fe_other_window(void);
static value_t wrap_fe_other_window(value_t *a, uint32_t n) {
 argcount("fe_other_window", n, 0);
 fe_other_window(); return FL_T;
}
extern void fe_split_window(void);
static value_t wrap_fe_split_window(value_t *a, uint32_t n) {
 argcount("fe_split_window", n, 0);
 fe_split_window(); return FL_T;
}
extern void fe_update_display(void);
static value_t wrap_fe_update_display(value_t *a, uint32_t n) {
 argcount("fe_update_display", n, 0);
 fe_update_display(); return FL_T;
}
extern void fe_refresh(void);
static value_t wrap_fe_refresh(value_t *a, uint32_t n) {
 argcount("fe_refresh", n, 0);
 fe_refresh(); return FL_T;
}
extern void fe_delete_window(void);
static value_t wrap_fe_delete_window(value_t *a, uint32_t n) {
 argcount("fe_delete_window", n, 0);
 fe_delete_window(); return FL_T;
}
extern int fe_window_count(void);
static value_t wrap_fe_window_count(value_t *a, uint32_t n) {
 argcount("fe_window_count", n, 0);
 return fixnum(fe_window_count());
}
extern int fe_window_rows(void);
static value_t wrap_fe_window_rows(value_t *a, uint32_t n) {
 argcount("fe_window_rows", n, 0);
 return fixnum(fe_window_rows());
}
extern void fe_recenter(void);
static value_t wrap_fe_recenter(value_t *a, uint32_t n) {
 argcount("fe_recenter", n, 0);
 fe_recenter(); return FL_T;
}
extern void fe_set_window_start(long p);
static value_t wrap_fe_set_window_start(value_t *a, uint32_t n) {
 argcount("fe_set_window_start", n, 1);
 fe_set_window_start(tofixnum(a[0], "fe_set_window_start")); return FL_T;
}
extern int fe_line_number(long p);
static value_t wrap_fe_line_number(value_t *a, uint32_t n) {
 argcount("fe_line_number", n, 1);
 return fixnum(fe_line_number(tofixnum(a[0], "fe_line_number")));
}
extern char *fe_key_command(char *name);
static value_t wrap_fe_key_command(value_t *a, uint32_t n) {
 argcount("fe_key_command", n, 1);
 const char *s = fe_key_command(tostring(a[0], "fe_key_command"));
 return string_from_cstrn((char *)s, strlen(s));
}
extern int fe_run_c_key(char *name);
static value_t wrap_fe_run_c_key(value_t *a, uint32_t n) {
 argcount("fe_run_c_key", n, 1);
 return fixnum(fe_run_c_key(tostring(a[0], "fe_run_c_key")));
}
extern int fe_execute_command(char *name);
static value_t wrap_fe_execute_command(value_t *a, uint32_t n) {
 argcount("fe_execute_command", n, 1);
 return fixnum(fe_execute_command(tostring(a[0], "fe_execute_command")));
}
extern char * fe_command_name(int i);
static value_t wrap_fe_command_name(value_t *a, uint32_t n) {
 argcount("fe_command_name", n, 1);
 const char *s = fe_command_name(tofixnum(a[0], "fe_command_name")); return string_from_cstrn((char *)(s ? s : ""), s ? strlen(s) : 0);
}
extern void fe_unfold_everywhere(void);
static value_t wrap_fe_unfold_everywhere(value_t *a, uint32_t n) {
 argcount("fe_unfold_everywhere", n, 0);
 fe_unfold_everywhere(); return FL_T;
}
extern int fe_fold(long a, long b);
static value_t wrap_fe_fold(value_t *a, uint32_t n) {
 argcount("fe_fold", n, 2);
 return fixnum(fe_fold(tofixnum(a[0], "fe_fold"), tofixnum(a[1], "fe_fold")));
}
extern void fe_unfold(long from, long to);
static value_t wrap_fe_unfold(value_t *a, uint32_t n) {
 argcount("fe_unfold", n, 2);
 fe_unfold(tofixnum(a[0], "fe_unfold"), tofixnum(a[1], "fe_unfold")); return FL_T;
}
extern long fe_folded_at(long a);
static value_t wrap_fe_folded_at(value_t *a, uint32_t n) {
 argcount("fe_folded_at", n, 1);
 return fixnum(fe_folded_at(tofixnum(a[0], "fe_folded_at")));
}
extern int fe_hidden_p(long p);
static value_t wrap_fe_hidden_p(value_t *a, uint32_t n) {
 argcount("fe_hidden_p", n, 1);
 return fixnum(fe_hidden_p(tofixnum(a[0], "fe_hidden_p")));
}
extern char * fe_mouse_kind(void);
static value_t wrap_fe_mouse_kind(value_t *a, uint32_t n) {
 argcount("fe_mouse_kind", n, 0);
 const char *s = fe_mouse_kind(); return string_from_cstrn((char *)(s ? s : ""), s ? strlen(s) : 0);
}
extern int fe_narrow(long from, long to);
static value_t wrap_fe_narrow(value_t *a, uint32_t n) {
 argcount("fe_narrow", n, 2);
 return fixnum(fe_narrow(tofixnum(a[0], "fe_narrow"), tofixnum(a[1], "fe_narrow")));
}
extern void fe_widen(void);
static value_t wrap_fe_widen(value_t *a, uint32_t n) {
 argcount("fe_widen", n, 0);
 fe_widen(); return FL_T;
}
extern long fe_narrow_start(void);
static value_t wrap_fe_narrow_start(value_t *a, uint32_t n) {
 argcount("fe_narrow_start", n, 0);
 return fixnum(fe_narrow_start());
}
extern long fe_narrow_end(void);
static value_t wrap_fe_narrow_end(value_t *a, uint32_t n) {
 argcount("fe_narrow_end", n, 0);
 return fixnum(fe_narrow_end());
}
extern int fe_char_width(long cp);
static value_t wrap_fe_char_width(value_t *a, uint32_t n) {
 argcount("fe_char_width", n, 1);
 return fixnum(fe_char_width(tofixnum(a[0], "fe_char_width")));
}
extern void fe_backdoor_note(char *s);
static value_t wrap_fe_backdoor_note(value_t *a, uint32_t n) {
 argcount("fe_backdoor_note", n, 1);
 fe_backdoor_note(tostring(a[0], "fe_backdoor_note")); return FL_T;
}
extern void fe_message(char *s);
static value_t wrap_fe_message(value_t *a, uint32_t n) {
 argcount("fe_message", n, 1);
 fe_message(tostring(a[0], "fe_message")); return FL_T;
}
extern void fe_clear_message_line(void);
static value_t wrap_fe_clear_message_line(value_t *a, uint32_t n) {
 argcount("fe_clear_message_line", n, 0);
 fe_clear_message_line(); return FL_T;
}
extern void fe_log_debug(char *s);
static value_t wrap_fe_log_debug(value_t *a, uint32_t n) {
 argcount("fe_log_debug", n, 1);
 fe_log_debug(tostring(a[0], "fe_log_debug")); return FL_T;
}
extern void fe_log_message(char *s);
static value_t wrap_fe_log_message(value_t *a, uint32_t n) {
 argcount("fe_log_message", n, 1);
 fe_log_message(tostring(a[0], "fe_log_message")); return FL_T;
}
extern char * fe_get_key(void);
static value_t wrap_fe_get_key(value_t *a, uint32_t n) {
 argcount("fe_get_key", n, 0);
 const char *s = fe_get_key(); return string_from_cstrn((char *)(s ? s : ""), s ? strlen(s) : 0);
}
extern char * fe_get_key_name(void);
static value_t wrap_fe_get_key_name(value_t *a, uint32_t n) {
 argcount("fe_get_key_name", n, 0);
 const char *s = fe_get_key_name(); return string_from_cstrn((char *)(s ? s : ""), s ? strlen(s) : 0);
}
extern char * fe_get_key_binding(void);
static value_t wrap_fe_get_key_binding(value_t *a, uint32_t n) {
 argcount("fe_get_key_binding", n, 0);
 const char *s = fe_get_key_binding(); return string_from_cstrn((char *)(s ? s : ""), s ? strlen(s) : 0);
}
extern char * fe_prompt(char *prompt, char *initial);
static value_t wrap_fe_prompt(value_t *a, uint32_t n) {
 argcount("fe_prompt", n, 2);
 const char *s = fe_prompt(tostring(a[0], "fe_prompt"), tostring(a[1], "fe_prompt")); return string_from_cstrn((char *)(s ? s : ""), s ? strlen(s) : 0);
}
extern void fe_shell_command(char *cmd);
static value_t wrap_fe_shell_command(value_t *a, uint32_t n) {
 argcount("fe_shell_command", n, 1);
 fe_shell_command(tostring(a[0], "fe_shell_command")); return FL_T;
}
extern int fe_add_mode_global(char *mode);
static value_t wrap_fe_add_mode_global(value_t *a, uint32_t n) {
 argcount("fe_add_mode_global", n, 1);
 return fixnum(fe_add_mode_global(tostring(a[0], "fe_add_mode_global")));
}
extern char * fe_version(void);
static value_t wrap_fe_version(value_t *a, uint32_t n) {
 argcount("fe_version", n, 0);
 const char *s = fe_version(); return string_from_cstrn((char *)(s ? s : ""), s ? strlen(s) : 0);
}
extern void fe_quit(void);
static value_t wrap_fe_quit(value_t *a, uint32_t n) {
 argcount("fe_quit", n, 0);
 fe_quit(); return FL_T;
}
extern int fe_screen_rows(void);
static value_t wrap_fe_screen_rows(value_t *a, uint32_t n) {
 argcount("fe_screen_rows", n, 0);
 return fixnum(fe_screen_rows());
}
extern int fe_screen_cols(void);
static value_t wrap_fe_screen_cols(value_t *a, uint32_t n) {
 argcount("fe_screen_cols", n, 0);
 return fixnum(fe_screen_cols());
}
extern int fe_screen_probe(void);
static value_t wrap_fe_screen_probe(value_t *a, uint32_t n) {
 argcount("fe_screen_probe", n, 0);
 return fixnum(fe_screen_probe());
}
extern const char * fe_backend(void);
static value_t wrap_fe_backend(value_t *a, uint32_t n) {
 argcount("fe_backend", n, 0);
 const char *s = fe_backend(); return string_from_cstrn((char *)(s ? s : ""), s ? strlen(s) : 0);
}
extern void fe_gui_set_font(char *path, int points);
static value_t wrap_fe_gui_set_font(value_t *a, uint32_t n) {
 argcount("fe_gui_set_font", n, 2);
 fe_gui_set_font(tostring(a[0], "fe_gui_set_font"), tofixnum(a[1], "fe_gui_set_font")); return FL_T;
}
extern void fe_gui_set_colors(long fg, long bg, long cursor);
static value_t wrap_fe_gui_set_colors(value_t *a, uint32_t n) {
 argcount("fe_gui_set_colors", n, 3);
 fe_gui_set_colors(tofixnum(a[0], "fe_gui_set_colors"), tofixnum(a[1], "fe_gui_set_colors"), tofixnum(a[2], "fe_gui_set_colors")); return FL_T;
}
extern void fe_gui_set_option(char *name, int value);
static value_t wrap_fe_gui_set_option(value_t *a, uint32_t n) {
 argcount("fe_gui_set_option", n, 2);
 fe_gui_set_option(tostring(a[0], "fe_gui_set_option"), tofixnum(a[1], "fe_gui_set_option")); return FL_T;
}
extern void fe_tester_history_stats(long a, long b, long c, long d, long e, long f, long g, long h);
static value_t wrap_fe_tester_history_stats(value_t *a, uint32_t n) {
 argcount("fe_tester_history_stats", n, 8);
 fe_tester_history_stats(tofixnum(a[0],"tester"),tofixnum(a[1],"tester"),tofixnum(a[2],"tester"),tofixnum(a[3],"tester"),tofixnum(a[4],"tester"),tofixnum(a[5],"tester"),tofixnum(a[6],"tester"),tofixnum(a[7],"tester")); return FL_T;
}
static builtinspec_t editor_builtins[] = {
 {"fe-set-color", wrap_fe_set_color},
 {"fe-set-theme-face", wrap_fe_set_theme_face},
 {"fe-colors", wrap_fe_colors},
 {"fe-reapply-colors", wrap_fe_reapply_colors},
 {"fe-backward-char", wrap_fe_backward_char},
 {"fe-forward-char", wrap_fe_forward_char},
 {"fe-backward-word", wrap_fe_backward_word},
 {"fe-forward-word", wrap_fe_forward_word},
 {"fe-backward-page", wrap_fe_backward_page},
 {"fe-forward-page", wrap_fe_forward_page},
 {"fe-next-line", wrap_fe_next_line},
 {"fe-previous-line", wrap_fe_previous_line},
 {"fe-beginning-of-line", wrap_fe_beginning_of_line},
 {"fe-end-of-line", wrap_fe_end_of_line},
 {"fe-beginning-of-buffer", wrap_fe_beginning_of_buffer},
 {"fe-end-of-buffer", wrap_fe_end_of_buffer},
 {"fe-goto-line", wrap_fe_goto_line},
 {"fe-get-point", wrap_fe_get_point},
 {"fe-get-mark", wrap_fe_get_mark},
 {"fe-buffer-size", wrap_fe_buffer_size},
 {"fe-set-mark", wrap_fe_set_mark},
 {"fe-set-mark-at", wrap_fe_set_mark_at},
 {"fe-mark-active", wrap_fe_mark_active},
 {"fe-set-mark-active", wrap_fe_set_mark_active},
 {"fe-set-point", wrap_fe_set_point},
 {"fe-char-at", wrap_fe_char_at},
 {"fe-line-start", wrap_fe_line_start},
 {"fe-read-mode", wrap_fe_read_mode},
 {"fe-read-state", wrap_fe_read_state},
 {"fe-read-key", wrap_fe_read_key},
 {"fe-insert", wrap_fe_insert},
 {"fe-backward-delete-char", wrap_fe_backward_delete_char},
 {"fe-delete-char", wrap_fe_delete_char},
 {"fe-kill-region", wrap_fe_kill_region},
 {"fe-copy-region", wrap_fe_copy_region},
 {"fe-yank", wrap_fe_yank},
 {"fe-kill-line", wrap_fe_kill_line},
 {"fe-undo", wrap_fe_undo},
 {"fe-buffer-id", wrap_fe_buffer_id},
 {"fe-set-modified", wrap_fe_set_modified},
 {"fe-delete-region", wrap_fe_delete_region},
 {"fe-discard-undo-history", wrap_fe_discard_undo_history},
 {"fe-get-clipboard", wrap_fe_get_clipboard},
 {"fe-set-scrap", wrap_fe_set_scrap},
 {"fe-set-clipboard", wrap_fe_set_clipboard},
 {"fe-clipboard-tool", wrap_fe_clipboard_tool},
 {"fe-set-system-clipboard", wrap_fe_set_system_clipboard},
 {"fe-get-system-clipboard", wrap_fe_get_system_clipboard},
 {"fe-search-forward", wrap_fe_search_forward},
 {"fe-search-backward", wrap_fe_search_backward},
 {"fe-buffer-count", wrap_fe_buffer_count},
 {"fe-buffer-name", wrap_fe_buffer_name},
 {"fe-buffer-filename", wrap_fe_buffer_filename},
 {"fe-buffer-modified", wrap_fe_buffer_modified},
 {"fe-select-buffer", wrap_fe_select_buffer},
 {"fe-kill-buffer", wrap_fe_kill_buffer},
 {"fe-save-buffer", wrap_fe_save_buffer},
 {"fe-find-file", wrap_fe_find_file},
 {"fe-list-buffers", wrap_fe_list_buffers},
 {"fe-rename-buffer", wrap_fe_rename_buffer},
 {"fe-tester-history-stats", wrap_fe_tester_history_stats},
 {"fe-delete-other-windows", wrap_fe_delete_other_windows},
 {"fe-other-window", wrap_fe_other_window},
 {"fe-split-window", wrap_fe_split_window},
 {"fe-update-display", wrap_fe_update_display},
 {"fe-refresh", wrap_fe_refresh},
 {"fe-delete-window", wrap_fe_delete_window},
 {"fe-window-count", wrap_fe_window_count},
 {"fe-window-rows", wrap_fe_window_rows},
 {"fe-recenter", wrap_fe_recenter},
 {"fe-set-window-start", wrap_fe_set_window_start},
 {"fe-line-number", wrap_fe_line_number},
 {"fe-key-command", wrap_fe_key_command},
 {"fe-run-c-key", wrap_fe_run_c_key},
 {"fe-execute-command", wrap_fe_execute_command},
 {"fe-command-name", wrap_fe_command_name},
 {"fe-backdoor-note", wrap_fe_backdoor_note},
 {"fe-mouse-kind", wrap_fe_mouse_kind},
 {"fe-fold", wrap_fe_fold},
 {"fe-unfold-everywhere", wrap_fe_unfold_everywhere},
 {"fe-unfold", wrap_fe_unfold},
 {"fe-folded-at", wrap_fe_folded_at},
 {"fe-hidden-p", wrap_fe_hidden_p},
 {"fe-narrow", wrap_fe_narrow},
 {"fe-widen", wrap_fe_widen},
 {"fe-narrow-start", wrap_fe_narrow_start},
 {"fe-narrow-end", wrap_fe_narrow_end},
 {"fe-char-width", wrap_fe_char_width},
 {"fe-message", wrap_fe_message},
 {"fe-clear-message-line", wrap_fe_clear_message_line},
 {"fe-log-debug", wrap_fe_log_debug},
 {"fe-log-message", wrap_fe_log_message},
 {"fe-get-key", wrap_fe_get_key},
 {"fe-get-key-name", wrap_fe_get_key_name},
 {"fe-get-key-binding", wrap_fe_get_key_binding},
 {"fe-prompt", wrap_fe_prompt},
 {"fe-shell-command", wrap_fe_shell_command},
 {"fe-add-mode-global", wrap_fe_add_mode_global},
 {"fe-version", wrap_fe_version},
 {"fe-quit", wrap_fe_quit},
 {"fe-screen-rows", wrap_fe_screen_rows},
 {"fe-screen-cols", wrap_fe_screen_cols},
 {"fe-screen-probe", wrap_fe_screen_probe},
 {"fe-backend", wrap_fe_backend},
 {"fe-gui-set-font", wrap_fe_gui_set_font},
 {"fe-gui-set-colors", wrap_fe_gui_set_colors},
 {"fe-gui-set-option", wrap_fe_gui_set_option},
 {NULL, NULL}};
extern void assistant_init(void);
extern void extra_init(void);
extern void primitives_init(void);
extern void highlight_init(void);
extern void compiled_init(void);
void interface_init(void) { compiled_init(); assign_global_builtins(editor_builtins); assistant_init(); extra_init(); primitives_init(); highlight_init(); }
