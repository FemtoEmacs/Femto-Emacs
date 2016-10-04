/*
 * header.h, Femto Emacs, Hugh Barney, 2016
 * Derived from: Anthony's Editor January 93, (Public Domain 1991, 1993 by Anthony Howe)
 */

#include <locale.h>
#include <stdlib.h>
#include <stdarg.h>
#include <assert.h>
#include <curses.h>
#include <stdio.h>
#include <sys/types.h>
#include <ctype.h>
#include <limits.h>
#include <string.h>
#include <unistd.h>

#undef _
#define _(x)    x

#define VERSION	 "FemtoEmacs 1.5, Public Domain, 2016"
#define EXIT_OK         0               /* Success */
#define EXIT_ERROR      1               /* Unknown error. */
#define EXIT_USAGE      2               /* Usage */
#define EXIT_FAIL       3               /* Known failure. */
#define B_MODIFIED	0x01		/* modified buffer */
#define B_OVERWRITE	0x02		/* overwite mode */
#define MSGLINE         (LINES-1)
#define NOMARK          -1
#define NOPAREN         -1
#define CHUNK           8096L
#define K_BUFFER_LENGTH 256
#define TEMPBUF         512
#define STRBUF_L        256
#define STRBUF_M        64
#define STRBUF_S        16
#define NBUFN           17              /* size of buffer name 16 chars + null terminator */
#define LISP_IN_OUT     2048
//#define MAX_FL_CLIPBD   2048
#define MIN_GAP_EXPAND  512
#define FWD_SEARCH      1
#define REV_SEARCH      2
#define TEMPFILE        "/tmp/feXXXXXX"

#define ID_COLOR_SYMBOL    1
#define ID_COLOR_MODELINE  2
#define ID_COLOR_BRACE     3
#define ID_COLOR_KEYWORD   4
#define ID_COLOR_ALPHA     5
#define ID_COLOR_DIGITS    6
#define ID_COLOR_COMMENTS  7

typedef unsigned char char_t;
typedef long point_t;
#define FEMTO_POINT_T      1

/* stack structure for tracking scraps */
typedef struct pscrap_t {
        char_t *scrap;
        struct pscrap_t *next;
} pscrap_t;	

typedef struct string_list_t
{
	struct string_list_t *next;
	char *string;
} string_list_t;

typedef struct keymap_t {
	char *key_name;			/* the name of the key, for exmaple 'C-x a' */
	char *key_desc;                 /* binding description */
	char *key_bytes;		/* the string of bytes when this key is pressed */
	void (*func) _((void));
} keymap_t;

typedef struct command_t {
        char *name;
	void (*func) (void);
} command_t;

typedef struct undo_t {
	point_t u_point;
	point_t u_gap;
	point_t u_egap;
	char u_flags;
} undo_t;

typedef struct buffer_t
{
	struct buffer_t *b_next;  /* Link to next buffer_t */

	point_t b_mark;	     	  /* the mark */
	point_t b_point;          /* the point */
	point_t b_paren;          /* matching paren to the point */
	point_t b_cpoint;         /* the original current point, used for mutliple window displaying */
	point_t b_page;           /* start of page */
	point_t b_epage;          /* end of page */
	int b_cnt;                /* count of windows referencing this buffer */
	int b_size;               /* current size of text being edited (not including gap) */
	int b_psize;              /* previous size */
	char_t *b_buf;            /* start of buffer */
	char_t *b_ebuf;           /* end of buffer */
	char_t *b_gap;            /* start of gap */
	char_t *b_egap;           /* end of gap */
	int b_row;                /* cursor row */
	int b_col;                /* cursor col */
	char b_fname[NAME_MAX + 1]; /* filename */
	char b_bname[NBUFN];      /* buffer name */
	char b_flags;             /* buffer flags */
	undo_t b_ubuf;            /* undoset */
} buffer_t;

typedef struct window_t
{
	struct window_t *w_next;   /* Next window */
	struct buffer_t *w_bufp;   /* Buffer displayed in window */
	point_t w_point;
	point_t w_mark;
	point_t w_page;
	point_t w_epage;
	char w_top;	        /* Origin 0 top row of window */
	char w_rows;        /* no. of rows of text in window */
	int w_row;          /* cursor row */
	int w_col;          /* cursor col */
	int w_update;
	char w_name[STRBUF_S];
} window_t;

extern buffer_t *curbp;			/* current buffer */
extern buffer_t *bheadp;		/* head of list of buffers */
extern window_t *curwp;
extern window_t *wheadp;

/*
 * Some compilers define size_t as a unsigned 16 bit number while
 * point_t and off_t might be defined as a signed 32 bit number.  
 * malloc(), realloc(), fread(), and fwrite() take size_t parameters,
 * which means there will be some size limits because size_t is too
 * small of a type.
 */
#define MAX_SIZE_T      ((unsigned long) (size_t) ~0)

extern int done;                /* Quit flag. */
extern int msgflag;             /* True if msgline should be displayed. */
extern int result;
extern point_t nscrap;          /* Length of scrap buffer. */
extern char_t *scrap;           /* Allocated scrap buffer. */
extern char_t *input;
extern char msgline[];          /* Message line input/output buffer. */
extern char temp[];             /* Temporary buffer. */
extern char searchtext[];
extern char replace[];
extern char lisp_query[];
extern char lisp_result[];
extern char *prog_name;         /* Name used to invoke editor. */
extern keymap_t *key_map;       /* Command key mappings. */
extern keymap_t keymap[];
extern keymap_t *key_return;    /* Command key return */
extern command_t commands[];

/* fatal() messages. */
extern char *f_ok;              /* EXIT_OK */
extern char *f_error;           /* EXIT_ERROR */
extern char *f_usage;           /* EXIT_USAGE */
extern char *f_initscr;         /* EXIT_FAILURE ... */
extern char *f_alloc;

/* Messages. */
extern char *m_ok;
extern char *m_version;
extern char *m_alloc;
extern char *m_toobig;
extern char *m_empty;
extern char *m_stat;
extern char *m_open;
extern char *m_close;
extern char *m_read;
extern char *m_write;
extern char *m_copied;
extern char *m_cut;
extern char *m_badname;
extern char *m_saved;
extern char *m_loaded;
extern char *m_newfile;
extern char *m_line;
extern char *m_lnot_found;
extern char *m_replace;
extern char *m_with;
extern char *m_sprompt;
extern char *m_qreplace;
extern char *m_rephelp;
extern char *m_goto;
extern char *str_mark;
extern char *str_pos;
extern char *str_endpos;
extern char *str_not_bound;

/* Prompts */
extern char *str_notsaved;
extern char *str_modified_buffers;
extern char *str_read;
extern char *str_insert_file;
extern char *str_write;
extern char *str_yes;
extern char *str_no;
extern char *str_scratch;
extern char *str_output;
extern char *str_shell_cmd;
extern char *str_buffers;
extern char *str_clip_too_big;


void free_string_list(string_list_t *);
string_list_t *match_functions(const char *);
void apropos_command(void);
extern void fatal _((char *));
extern char *get_file_extension(char *);
extern void display_char(buffer_t *, char_t *,int ,int);
extern void display (window_t *, int);
extern int utf8_size(char_t);
extern int prev_utf8_char_size(void);
extern void display_utf8(buffer_t *, char_t, int);
extern void dispmsg(void);
extern void modeline(window_t *);
extern point_t lnstart (buffer_t *, point_t);
extern point_t lncolumn (buffer_t *, point_t, int);
extern point_t segstart (buffer_t *, point_t, point_t);
extern point_t segnext (buffer_t *, point_t, point_t);
extern point_t upup (buffer_t *, point_t);
extern point_t dndn (buffer_t *, point_t);
extern char_t *get_key _((keymap_t *, keymap_t **));
extern char *fe_get_input_key(void);
extern int getinput _((char *, char *, int));
extern int growgap (buffer_t *, point_t);
extern point_t movegap (buffer_t *, point_t);
extern point_t pos (buffer_t *, char_t *);
extern char_t *ptr (buffer_t *, point_t);
extern int posix_file _((char *));
extern int save_buffer(buffer_t *,char *);
extern int load_file _((char *));
extern int insert_file (char *, int);
extern void append_string(buffer_t *, char *);
extern void undoset _((void));
extern void undo _((void));
extern void backsp _((void));
extern void block _((void));
extern void iblock _((void));
extern void copy_cut _((int));
extern void delete _((void));
extern void toggle_overwrite_mode(void);
extern void down _((void));
extern void insert _((void));
extern void paste _((void));
extern void quit _((void));
extern int yesno _((int));
extern void quit_ask _((void));
extern void redraw _((void));
extern void readfile _((void));
extern void insertfile _((void));
extern void right _((void));
extern void version _((void));
extern char *get_version_string();
extern void writefile _((void));
extern void savebuffer _((void));
extern void clear_buffer(void);
extern void zero_buffer(buffer_t *);
extern void debug(char *, ...);
extern void debug_stats(char *);
extern void showpos(void);
extern void killtoeol(void);
extern void i_gotoline(void);
extern void i_describe_key(void);
extern void goto_line(int);
extern void search(void);
extern void query_replace(void);
extern point_t line_to_point(int);
extern void update_search_prompt(char *, char *);
extern void display_search_result(point_t, int, char *, char *);
extern void move_to_search_result(point_t);
extern buffer_t* find_buffer (char *, int);
extern void buffer_init(buffer_t *);
extern int delete_buffer(buffer_t *);
extern void next_buffer(void);
extern int count_buffers(void);
extern int modified_buffers(void);
extern void killbuffer(void);
extern char* get_buffer_name(buffer_t *);
extern char* get_buffer_modeline_name(buffer_t *);
extern void get_line_stats(int *, int *);
extern void query_replace(void);
extern window_t *new_window();
extern void one_window(window_t *);
extern void free_other_windows();
extern void w2b(window_t *);
extern void b2w(window_t *);
extern void b2w_all_windows(buffer_t *);
extern void mark_all_windows(void);
extern void associate_b2w(buffer_t *, window_t *);
extern void disassociate_b(window_t *);
extern int getfilename(char *, char *, int);
extern void display_prompt_and_response(char *, char *);
extern void shell_command(char *);
extern void i_shell_command(void);
extern char* get_temp_file(void);
extern void match_parens(void);
extern void match_paren_forwards(buffer_t *, char, char);
extern void match_paren_backwards(buffer_t *, char, char);

extern void initLisp(int argc, char *[]);
extern void callLisp(char *ans, char *);
extern int scan_for_keywords(char_t *, int *);
extern void scan_for_comments(char_t *, int *, int *);
extern void setLanguage(char* extension);
extern void keyboardDefinition(void);
extern void run_kill_hook(char *);
extern void chkPar(void);
extern char *whatKey;
extern void repl(void);
extern void eval_block();
extern void remove_control_chars(char_t *);
extern void mk_buffer_name(char *, char *);
extern void safe_strncpy(char *, char *, int);
extern void resize_terminal();

/* functions to pscrap_t */
extern void ps_push(pscrap_t *p, char_t *scrap);
extern void ps_pop(pscrap_t *p);
extern char_t* ps_top(pscrap_t *st);
extern int ps_size(pscrap_t *st);

/*
 * include public Femto interface functions definitions 
 */
#include "public.h"

