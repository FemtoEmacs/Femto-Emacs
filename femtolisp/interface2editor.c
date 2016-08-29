/*
 * Interface functions for femtoLisp to FemtoEmacs
 */

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <setjmp.h>
#include <stdarg.h>
#include <assert.h>
#include <ctype.h>
#include <sys/types.h>
#include <sys/time.h>
#include <sys/stat.h>
#include <errno.h>
#include "llt/llt.h"
#include "flisp.h"
#include "llt/random.h"

/* Interface to the editor */

typedef long point_t;

typedef char *msg_t;

extern msg_t m_sprompt;

char dbg[30];
<<<<<<< HEAD

=======
>>>>>>> ad31afbb113b537fc0936867fab9d630acedf468
extern int msgflag;

<<<<<<< HEAD
extern char msgline[];

static value_t msg_lisp(value_t *args, u_int32_t nargs)
{
  int i=0;
  argcount("message", nargs, 1);
  value_t a= args[0]; /*Learn: pick an arg */
  char *str= cptr(a); /*Learn: string Lisp -> string C  */
  while (i<80 && str[i] != 0) {
    msgline[i] = str[i];
    i++ ;
  }
    msgline[i]=0;
    msgflag= 1;
  return FL_T;

}

extern void insert_string(char *);

static value_t insrt(value_t *args, u_int32_t nargs)
{
  argcount("insert", nargs, 1);
  value_t a= args[0]; /*Learn: pick an arg */
  char *str= cptr(a); /*Learn: string Lisp -> string C  */
  insert_string(str);
  return FL_NIL;

}

=======
/* internal Editor function prototypes, we will eventually load from header file
 */

extern void insert_string(char *);
>>>>>>> ad31afbb113b537fc0936867fab9d630acedf468
extern void left(void);

extern void right(void);
extern void backsp(void);
extern void lnbegin(void);
extern void lnend(void);
extern void copy(void);
extern void delete_other_windows(void);
extern void goto_line(int line);
extern void cut(void);
extern void list_buffers(void);
extern void down(void);
extern void up(void);
extern point_t search_forward(char *);
extern void move_to_search_result(point_t);
extern point_t search_backwards(char *);
extern void iblock(void);
extern void split_window(void);
extern void paste(void);
extern void eval_block(void);
extern char *get_version_string(void);
extern int count_buffers(void);

<<<<<<< HEAD
void ibchar(long int n)
{
  long int i;
  for (i=0; i < n; i++) {
    left();
  }
  
}

void ifchar(long int n)
{
  long int i;
  for (i=0; i < n; i++) {
    right();
  }
  
}

static value_t bkwrd(value_t *args, u_int32_t nargs)
{
  argcount("backward", nargs, 1);
  value_t a = args[0];
  ibchar(numval(a));  /*Learn: Lisp num -> C int*/
  return FL_T;

}
int keywrdcolor = 1 ;

static value_t forwrd(value_t *args, u_int32_t nargs) {

  argcount("forward", nargs, 1);
  value_t a = args[0];
  ifchar(numval(a));   /*Learn: Lisp num -> C int*/
  return FL_T;

}

extern void lnbegin (void);

extern void lnend (void);

static value_t linebegin(value_t *args, u_int32_t nargs)
{
  argcount("beginning-of-line", nargs, 0); /* Learn: Take no Args */
  lnbegin();  /* Learn: C funcion call to lisp */ 
  return FL_T;

}

static value_t lineend(value_t *args, u_int32_t nargs)
{
  argcount("end-of-line", nargs, 0);
  lnend();
  return FL_T;

}

extern void copy(void);

static value_t copy_region(value_t *args, u_int32_t nargs)
{
  argcount("copy_region", nargs, 0);
  copy();
  return FL_T;

=======

/*
 * interface to editor functions of form
 *     void func(void)
 */

static value_t bkwrd(value_t *args, u_int32_t nargs) {
	argcount("backward", nargs, 1);
	value_t a = args[0];
	long int n = numval(a); /*Learn: Lisp num -> C int*/
	while (n-- > 0)
		left();
	return FL_T;
}

static value_t forwrd(value_t *args, u_int32_t nargs) {
	argcount("forward", nargs, 1);
	value_t a = args[0];
	long int n = numval(a); /*Learn: Lisp num -> C int*/
	while (n-- > 0)
		right();
	return FL_T;
}

static value_t backspace(value_t *args, u_int32_t nargs) {
	argcount("backwards-delete-char", nargs, 1);
	value_t a = args[0];
	long int n = numval(a); /*Learn: Lisp num -> C int*/
	while (n-- > 0)
		backsp();
	return FL_T;
}

static value_t linebegin(value_t *args, u_int32_t nargs) {
	argcount("beginning-of-line", nargs, 0);
	lnbegin();
	return FL_T;
}

static value_t lineend(value_t *args, u_int32_t nargs) {
	argcount("end-of-line", nargs, 0);
	lnend();
	return FL_T;
}

static value_t copy_region(value_t *args, u_int32_t nargs) {
	argcount("copy-region", nargs, 0);
	copy();
	return FL_T;
>>>>>>> ad31afbb113b537fc0936867fab9d630acedf468
}

static value_t eval_blk(value_t *args, u_int32_t nargs) {
	argcount("eval-block", nargs, 0);
	eval_block();
	return FL_T;
}

<<<<<<< HEAD
static value_t del_other_windows(value_t *args, u_int32_t nargs)
{
  argcount("copy_region", nargs, 0);
  delete_other_windows();
  return FL_T;

}

extern void goto_line(int line);

static value_t gotoln(value_t *args, u_int32_t nargs)
{
  argcount("goto-line", nargs, 1);
  value_t a = args[0]; /*Learn: Take arg from Lisp */
  goto_line(numval(a));   /*Learn: Lisp num -> C int*/
  return FL_T;

}

extern void cut(void);

static value_t kill_region (value_t *args ,u_int32_t nargs)
{
  argcount("kill-region", nargs, 0);
  cut();
  return FL_T; 

}

extern void list_buffers(void);

static value_t lst_buffers(value_t *args, u_int32_t nargs)
{  
  argcount("list-buffers",nargs,0);
  list_buffers();
  return FL_T;

}

extern void down(void);

static value_t next_line(value_t *args, u_int32_t nargs)
{
  argcount("next-line", nargs, 0);
  down();
  return FL_T;

}

extern void up(void);

static value_t previous_line(value_t *args, u_int32_t nargs)
{
  argcount("previous-line", nargs, 0);
  up();
  return FL_T;

}

extern point_t search_forward(char *);

extern void display_search_result(point_t, int, char *, char *);

extern point_t search_backwards(char *);

static value_t src_forward(value_t *args,u_int32_t nargs)
{
  point_t founded ;
  argcount("search-forward", nargs, 1);
  value_t a = args[0];
  char *str = cptr(a);
  founded = search_forward(str);
  display_search_result(founded, FWD_SEARCH, m_sprompt,str);
  return FL_T;

}

static value_t src_backwards(value_t *args,u_int32_t nargs)
{
  point_t founded ;
  argcount("search-backwards", nargs, 1);
  value_t a = args[0];
  char *str = cptr(a);
  founded = search_backwards(str);
  display_search_result(founded, 2, m_sprompt,str);
  return FL_T;

}

extern void iblock(void);

static value_t set_mark (value_t *args ,u_int32_t nargs)
{
  argcount("set-mark", nargs, 0);
  iblock();
  return FL_T;
=======
static value_t del_other_windows(value_t *args, u_int32_t nargs) {
	argcount("delete-other-windows", nargs, 0);
	delete_other_windows();
	return FL_T;
}

static value_t gotoln(value_t *args, u_int32_t nargs) {
	argcount("goto-line", nargs, 1);
	value_t a = args[0];
	goto_line(numval(a)); /*Learn: Lisp num -> C int*/
	return FL_T;
}

static value_t kill_region(value_t *args, u_int32_t nargs) {
	argcount("kill-region", nargs, 0);
	cut();
	return FL_T;
}

static value_t lst_buffers(value_t *args, u_int32_t nargs) {
	argcount("list-buffers", nargs, 0);
	list_buffers();
	return FL_T;
}

static value_t next_line(value_t *args, u_int32_t nargs) {
	argcount("next-line", nargs, 0);
	down();
	return FL_T;
}

static value_t previous_line(value_t *args, u_int32_t nargs) {
	argcount("previous-line", nargs, 0);
	up();
	return FL_T;
}

static value_t set_mark(value_t *args, u_int32_t nargs) {
	argcount("set-mark", nargs, 0);
	iblock();
	return FL_T;
}

static value_t split_current_window(value_t *args, u_int32_t nargs) {
	argcount("split-current-window", nargs, 0);
	split_window();
	return FL_T;
}

static value_t yank(value_t *args, u_int32_t nargs) {
	argcount("yank", nargs, 0);
	paste();
	return FL_T;
}

static value_t fl_get_version_string(value_t *args, u_int32_t nargs) {
	argcount("get-version-string", nargs, 0);
	return (string_from_cstr(get_version_string()));
}

static value_t fl_count_buffers(value_t *args, u_int32_t nargs) {
	argcount("get-buffer-count", nargs, 0);
	return (mk_uint32(count_buffers()));
}

/*
 * interface to editor functions of form func(char *)
 */
>>>>>>> ad31afbb113b537fc0936867fab9d630acedf468

static value_t msg_lisp(value_t *args, u_int32_t nargs) {
	int i = 0;
	argcount("message", nargs, 1);
	value_t a = args[0]; /*Learn: pick an arg */
	char *str = cptr(a); /*Learn: string Lisp -> string C  */
	while (i < 80 && str[i] != 0) {
		msgline[i] = str[i];
		i++;
	}
	msgline[i] = 0;
	msgflag = 1;
	return FL_T;
}

<<<<<<< HEAD
extern void split_window(void);

static value_t split_current_window(value_t *args,
				    u_int32_t nargs)
{
  argcount("split-current-window", nargs, 0);
  split_window();
  return FL_T;
  
}

extern void paste(void);

static value_t yank(value_t *args,u_int32_t nargs)
{
  argcount("yank", nargs, 0);
  paste();
  return FL_T;
=======
static value_t insrt(value_t *args, u_int32_t nargs) {
	argcount("insert", nargs, 1);
	value_t a = args[0]; /*Learn: pick an arg */
	char *str = cptr(a); /*Learn: string Lisp -> string C  */
	insert_string(str);
	return FL_T;
}

static value_t src_forward(value_t *args, u_int32_t nargs) {
	point_t founded;
	argcount("search-forward", nargs, 1);
	value_t a = args[0];
	char *str = cptr(a);
	founded = search_forward(str);
	move_to_search_result(founded);
	return (founded == -1 ? FL_F : FL_T);
}

static value_t src_backwards(value_t *args, u_int32_t nargs) {
	point_t founded;
	argcount("search-backwards", nargs, 1);
	value_t a = args[0];
	char *str = cptr(a);
	founded = search_backwards(str);
	move_to_search_result(founded);
	return (founded == -1 ? FL_NIL : FL_T);
}

/*
 * code for syntax highlighting
 */

int nLangs = 0;
int thisLanguage = -1;
char LangCode[10][5];
int numWords[100];
char hiLite[10][100][30];
char line_comment[10][8];
char begin_comment[10][8];
char end_comment[10][8];

int notsep(char_t *p) {

	/* what is the purpose of this check, also p is a pointer ? */
	if (p < 1)
		return 0;
>>>>>>> ad31afbb113b537fc0936867fab9d630acedf468

	char_t c = *p;
	return ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
		(c >= '0' && c <= '9') || (c == '_'));
}

int is_dgt(char c) { return ((c >= '0') && (c <= '9')); }

/* seq checks wether *p points to the sequence of chars given by str */
int seq(char_t *p, char *str) {
	int i;
	for (i = 0; i < strlen(str); i++) {
		if (*(p + i) != str[i])
			return 0;
	}
	return 1;
}

/* keywrd implements a finite automaton */
int negative_prefix(char_t *p) { return (*p == '-' && is_dgt(*(p + 1))); }

int number_prefix(char_t *p, int *j) {
	/* Numbers start with a digit or
	   with '-' followed by a digit */
	if (is_dgt(*p)) {
		*j = *j + 1;
		return 1;
	}
	if (negative_prefix(p)) {
		*j = *j + 2;
		return 2;
	}
	return 0;
}

int exponent_prefix(char_t *p, int *j) {
	int jvalue = *j;
	if (*(p + jvalue) != 'e')
		return 0;
	if (is_digit(*(p + jvalue + 1))) {
		*j = *j + 2;
		return 1;
	}
	if (*(p + jvalue + 1) != '-')
		return 0;
	if (is_digit(*(p + jvalue + 2))) {
		*j = *j + 3;
		return 1;
	}
}

/*
 * check if in a class of token , return legth of token
 * 
 */
int kwrd(char_t *p, int *k) {

	int i; /* what is i ?, suggest rename to something more meaningful */
	int j; /* what is j ?, suggest rename to something more meaningful */
	
	/*
	 * All tokens are preceded by a separator.  Therefore, if
	 * there is not a separator at (p - 1), tokenizer fails.
	 */
	
	if (notsep(p - 1))
		return 0;

	/*
	 * In a deterministic finite automaton, a given
	 *  prefix determines the token class.
	 */
	j = 0;
	if (number_prefix(p, &j)) {
		while (is_dgt(*(p + j))) {
			j = j + 1;
		}
		if (*(p + j) == '.') {
			j = j + 1;
			while (is_dgt(*(p + j))) {
				j = j + 1;
			}
		}
		if (exponent_prefix(p, &j)) {
			while (is_digit(*(p + j))) {
				j = j + 1;
			}
		}
		if (!notsep(p + j)) {
			*k = 2;
			return j;
		}
		*k = 0;
		return 0;
	}

	/* If automaton has not number prefix,
	   it tries to recognize a keyword */
	if (thisLanguage < 0) {
		*k = 0;
		return 0;
	}
	j = 0; /* Reset j */
	for (i = 0; i < numWords[thisLanguage]; i++) {
		if (seq(p, hiLite[thisLanguage][i])) {
			*k = 1;
			return strlen(hiLite[thisLanguage][i]);
		}
	}
	*k = 0;
	return 0;
}

void cmmt(char_t *p, int *c, int *lc) {
	if (thisLanguage < 0)
		return;
	if ((*lc == 0) && seq(p, line_comment[thisLanguage]))
		*lc = 1;
	if ((*lc == 1) && (*p == '\n'))
		*lc = 0;
	if ((*c == 0) && seq(p, begin_comment[thisLanguage]))
		*c = 1;
	if ((*c == 1) && seq(p, end_comment[thisLanguage]))
		*c = 0;
	return;
}

<<<<<<< HEAD
int kwrd(char_t *p)
{
  int i, j;
  if (thisLanguage > -1) {
    for (i=0; i < numWords[thisLanguage]; i++) {
      for (j= 0; j <= strlen(hiLite[thisLanguage][i]); j++) {
        if (j == strlen(hiLite[thisLanguage][i]))
	  return j;
        else if ( *(p+j) != (char_t) hiLite[thisLanguage][i][j])
	  break;
      }
    }
  }
  return 0;

=======
void setLanguage(char *extension) {
	int i;
	thisLanguage = -1;
	for (i = 0; i < nLangs; i++) {
		if (strcmp(LangCode[i], extension) == 0) {
			thisLanguage = i;
		}
	}
>>>>>>> ad31afbb113b537fc0936867fab9d630acedf468
}

static value_t fl_newlanguage(value_t *args, u_int32_t nargs) {
	/* Check the number of arguments */
	argcount("newlanguage", nargs, 4);
	value_t a = args[0];
	int code = nLangs;
	char *str = cptr(a);
	int sz = strlen(str);
	int i;
	for (i = 0; i < sz; i++) {
		LangCode[code][i] = str[i];
	}
	LangCode[code][i] = '\0';
	numWords[code] = 0;
	nLangs = nLangs + 1;

	/* Lisp string for line comment prefix */
	value_t linec = args[1];
	/* Lisp string for block comment begin */
	value_t beginc = args[2];
	/* Lisp string for block comment end */
	value_t endc = args[3];

	/* femtolisp has a python style macro to
	   transform lisp-type into c-pointer */
	char *ln_cmm = cptr(linec);
	char *begin_cmm = cptr(beginc);
	char *end_cmm = cptr(endc);

	/* Copy the strings into the comment vectors
	   to avoid the  garbage collector */

	for (i = 0; i < strlen(ln_cmm); i++) {
		line_comment[code][i] = ln_cmm[i];
	}
	line_comment[code][i] = '\0';

	for (i = 0; i < strlen(begin_cmm); i++) {
		begin_comment[code][i] = begin_cmm[i];
	}
	begin_comment[code][i] = '\0';

	for (i = 0; i < strlen(end_cmm); i++) {
		end_comment[code][i] = end_cmm[i];
	}
	end_comment[code][i] = '\0';

	return FL_T;
}

<<<<<<< HEAD
void setLanguage(char *extension)
{
  int i;
  thisLanguage= -1;
  for (i=0; i<nLangs; i++) 
    if (strcmp(LangCode[i], extension)== 0) {
      thisLanguage= i;
    }

}

static value_t fl_newlanguage(value_t *args, u_int32_t nargs)
{  
     argcount("newlanguage", nargs, 1);
     value_t a = args[0];
     int code = nLangs;
     char *str = cptr(a);
     int sz= strlen(str);
     int i;
     for (i=0; i < sz; i++){
          LangCode[code][i]= str[i];
     }
     LangCode[code][i]='\0';
     numWords[code]= 0;
     nLangs= nLangs+1;
     return a;

}

static value_t fl_keyword(value_t *args, u_int32_t nargs)
{  
    argcount("keyword", nargs, 1);
    value_t a = args[0];
    int code = nLangs-1;
    int nw = numWords[code];
    char *str = cptr(a);
    int sz = strlen(str);
    int i;
    for (i=0; i < sz; i++){
       hiLite[code][nw][i]= str[i];
    }
     hiLite[code][nw][i] ='\0';
     numWords[code] = numWords[code]+1;
    return a;

}

/* END_OF Interface to the editor */
=======
static value_t fl_keyword(value_t *args, u_int32_t nargs) {
	argcount("keyword", nargs, 1);
	value_t a = args[0];
	int code = nLangs - 1;
	int nw = numWords[code];
	char *str = cptr(a);
	int sz = strlen(str);
	int i;
	for (i = 0; i < sz; i++) {
		hiLite[code][nw][i] = str[i];
	}
	hiLite[code][nw][i] = '\0';
	numWords[code] = numWords[code] + 1;
	return a;
}
>>>>>>> ad31afbb113b537fc0936867fab9d630acedf468

/* end of interface to the editor */

extern void stringfuncs_init(void);

extern void table_init(void);

extern void iostream_init(void);

static builtinspec_t builtin_info[] ={

	/*Interface to the editor*/

	{"insert", insrt},
	{"backward-delete-char", backspace},
	{"backward-character", bkwrd},
	{"forward-character", forwrd},
	{"beginning-of-line", linebegin},
	{"end-of-line", lineend},
	{"copy-region", copy_region},
	{"eval-block", eval_blk},
	{"message", msg_lisp},
	{"delete-other-windows", del_other_windows},
	{"goto-line", gotoln},
	{"kill-region", kill_region},
	{"list-buffers", lst_buffers},
	{"next-line", next_line},
	{"previous-line", previous_line},
	{"search-forward", src_forward},
	{"search-backwards", src_backwards},
	{"set-mark", set_mark},
	{"split-current-window", split_current_window},
	{"yank", yank},
	{"get-version-string", fl_get_version_string},
	{"get-buffer-count", fl_count_buffers},
	{"keyword", fl_keyword},
	{"newlanguage", fl_newlanguage},

	/*End Interface*/
	{NULL, NULL}
};

void interface_init(void)
{
<<<<<<< HEAD
    assign_global_builtins(builtin_info);
    
=======
	assign_global_builtins(builtin_info);
>>>>>>> ad31afbb113b537fc0936867fab9d630acedf468
}
