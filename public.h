/*
 * public.h, Femto Emacs, Hugh Barney, 2016
 * Public editor functions made available to femtolisp
 */

#define ID_TOKEN_NONE      0
#define ID_TOKEN_KEYWORD   1
#define ID_TOKEN_DIGITS    2
#define ID_TOKEN_COMMENTS  3
#define ID_TOKEN_QUOTED    4
#define ID_TOKEN_ALPHA     5

#ifndef FEMTO_POINT_T
typedef long point_t;
#endif

extern void insert_string(char *);
extern void left(void);
extern void right(void);
extern void backsp(void);
extern void lnbegin(void);
extern void lnend(void);
extern void beginning_of_buffer(void);
extern void end_of_buffer(void);
extern void backward_word(void);
extern void forward_word(void);
extern void backward_page(void);
extern void forward_page(void);
extern void copy(void);
extern void delete_other_windows(void);
extern void other_window(void);
extern void goto_line(int line);
extern void cut(void);
extern void list_buffers(void);
extern void down(void);
extern void up(void);
extern point_t search_forward(char *);
extern void move_to_search_result(point_t);
extern point_t search_backwards(char *);
extern void i_set_mark(void);
extern void split_window(void);
extern void paste(void);
extern void eval_block(void);
extern char *get_version_string(void);
extern int count_buffers(void);
extern void update_display(void);
extern char *fe_get_input_key(void);
extern char *get_key_binding(void);
extern char *get_key_name(void);
extern int delete_buffer_byname(char *);
extern int select_buffer(char *);
extern int save_buffer_byname(char *);
extern void msg(char *, ...);
extern void clear_message_line(void);
extern char *string_trim(char *);
extern char *get_current_bufname();
extern void log_debug(char *);
extern void set_scrap(unsigned char *);
extern unsigned char *get_scrap(void);
extern void log_message(char *);
extern int add_mode_global(char *);
extern void discard_undo_history(void);
extern void shell_command(char *);
