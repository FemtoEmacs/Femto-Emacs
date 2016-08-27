/*
  Extra femtoLisp builtin functions
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
#define FWD_SEARCH 1

/*Interface to the editor */

typedef long point_t;
typedef char *msg_t;
extern msg_t m_sprompt;

char dbg[30];


extern int msgflag;
extern char msgline[];


static value_t msg_lisp(value_t *args, u_int32_t nargs) {
  int i=0;
  argcount("message", nargs, 1);
  value_t a= args[0]; /*Learn: pick an arg */
  char *str= cptr(a); /*Learn: string Lisp -> string C  */
  while (i<80 && str[i] != 0) {
    msgline[i] = str[i];
    i++ ;}
  msgline[i]=0;
  msgflag= 1;
  return FL_T;}


extern void insert_string(char *);
static value_t insrt(value_t *args, u_int32_t nargs) {
  argcount("insert", nargs, 1);
  value_t a= args[0]; /*Learn: pick an arg */
  char *str= cptr(a); /*Learn: string Lisp -> string C  */
  insert_string(str);
  return FL_NIL;}

extern void left(void);
extern void right(void);
extern void backsp(void);

void ibchar(long int n) {
  long int i;
  for (i=0; i < n; i++) {
    left();
  }
}

void ifchar(long int n) {
  long int i;
  for (i=0; i < n; i++) {
    right();
  }
}

void ibacksp(long int n) {
  long int i;
  for (i=0; i < n; i++) {
    backsp();
  }
}

static value_t bkwrd(value_t *args, u_int32_t nargs) {
  argcount("backward", nargs, 1);
  value_t a= args[0];
  ibchar(numval(a));  /*Learn: Lisp num -> C int*/
  return FL_NIL;}

int keywrdcolor = 1 ;

static value_t forwrd(value_t *args, u_int32_t nargs) {
  argcount("forward", nargs, 1);
  value_t a= args[0];
  ifchar(numval(a));   /*Learn: Lisp num -> C int*/
  return FL_NIL;}

static value_t backspace(value_t *args, u_int32_t nargs) {
  argcount("backwards-delete-char", nargs, 1);
  value_t a= args[0];
  ibacksp(numval(a));   /*Learn: Lisp num -> C int*/
  return FL_NIL;}

extern void lnbegin (void);
extern void lnend (void);

static value_t linebegin(value_t *args, u_int32_t nargs) {
  argcount("beginning-of-line", nargs, 0);
  lnbegin();  
  return FL_NIL;}

static value_t lineend(value_t *args, u_int32_t nargs) {
  argcount("end-of-line", nargs, 0);
  lnend();
  return FL_NIL;}


extern void copy(void);

static value_t copy_region(value_t *args, u_int32_t nargs) {
  argcount("copy-region", nargs, 0);
  copy();
  return FL_T;}


extern void  delete_other_windows(void);

static value_t del_other_windows(value_t *args, u_int32_t nargs) {
  argcount("delete-other-windows", nargs, 0);
  delete_other_windows();
  return FL_T;}


extern void goto_line(int line);

static value_t gotoln(value_t *args, u_int32_t nargs) {
  argcount("goto-line", nargs, 1);
  value_t a= args[0];
  goto_line(numval(a));   /*Learn: Lisp num -> C int*/
  return FL_T;}


extern void cut(void);

static value_t kill_region (value_t *args ,u_int32_t nargs){
  argcount("kill-region",nargs,0);
  cut();
  return FL_T;
  

}


extern void list_buffers(void);

static value_t lst_buffers(value_t *args, u_int32_t nargs){  
  argcount("list-buffers",nargs,0);
  list_buffers();
  return FL_T;

}


extern void down(void);
static value_t next_line(value_t *args, u_int32_t nargs){
  argcount("next-line",nargs,0);
  down();
  return FL_T;

}

extern void up(void);
static value_t previous_line(value_t *args, u_int32_t nargs){
  argcount("previous-line",nargs,0);
  up();
  return FL_T;

}



extern point_t search_forward(char *);
extern void display_search_result(point_t, int, char *, char *);
extern point_t search_backwards(char *);

static value_t src_forward(value_t *args,u_int32_t nargs){

  point_t founded ;
  argcount("search-forward", nargs, 1);
  value_t a= args[0];
  char *str= cptr(a);
  founded = search_forward(str);
  display_search_result(founded, FWD_SEARCH, m_sprompt,str);
  return FL_T;
}


static value_t src_backwards(value_t *args,u_int32_t nargs){

  point_t founded ;
  argcount("search-backwards", nargs, 1);
  value_t a= args[0];
  char *str= cptr(a);
  founded = search_backwards(str);
  display_search_result(founded, 2, m_sprompt,str);
  return FL_T;
}



extern void iblock(void);
static value_t set_mark (value_t *args ,u_int32_t nargs){
  argcount("set-mark",nargs,0);
  iblock();
  return FL_T;

}



extern void split_window(void);
static value_t split_current_window(value_t *args,
				    u_int32_t nargs){

  argcount("split-current-window",nargs,0);
  split_window();
  return FL_T;
  
  }

extern void paste(void);
static value_t yank(value_t *args,u_int32_t nargs){

  argcount("yank",nargs,0);
  paste();
  return FL_T;
  


}

int nLangs= 0;
int thisLanguage= -1;
char LangCode[10][5];
int numWords[100];
char hiLite[10][100][30];


int kwrd(char_t *p) {
  int i, j;
  if (thisLanguage > -1) {
    for (i=0; i < numWords[thisLanguage]; i++) {
      for (j= 0; j <= strlen(hiLite[thisLanguage][i]); j++) {
        if (j == strlen(hiLite[thisLanguage][i])) return j;
        else if ( *(p+j) != (char_t) hiLite[thisLanguage][i][j]) break;}}}
  return 0;}


void setLanguage(char *extension) {
  int i;
  thisLanguage= -1;
  for (i=0; i<nLangs; i++) 
    if (strcmp(LangCode[i], extension)== 0) {
      thisLanguage= i;}}

static value_t fl_newlanguage(value_t *args, u_int32_t nargs)
{  
    argcount("newlanguage", nargs, 1);
    value_t a = args[0];
     int code = nLangs;
     char *str = cptr(a);
     int sz= strlen(str);
     int i;
     for (i=0; i < sz; i++){
      LangCode[code][i]= str[i];}
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
    int nw= numWords[code];
    char *str = cptr(a);
     int sz= strlen(str);
     int i;
     for (i=0; i < sz; i++){
       hiLite[code][nw][i]= str[i];}
     hiLite[code][nw][i]='\0';
     numWords[code]= numWords[code]+1;
    return a;
}




/* END_OF Interface to the editor */


extern void stringfuncs_init(void);
extern void table_init(void);
extern void iostream_init(void);

static builtinspec_t builtin_info[] = {

    /*Interface to the editor*/

    {"insert", insrt},
    {"backward-delete-char", backspace},
    {"backward-character", bkwrd},
    {"forward-character", forwrd},
    {"beginning-of-line", linebegin},
    {"end-of-line", lineend},
    {"copy-region", copy_region},
    {"message", msg_lisp},
    {"delete-other-windows", del_other_windows},
    {"goto-line", gotoln},
    {"kill-region",kill_region},
    {"list-buffers",lst_buffers},
    {"next-line",next_line},
    {"previous-line",previous_line},
    {"search-forward",src_forward},
    {"search-backwards",src_backwards},
    {"set-mark",set_mark},
    {"split-current-window",split_current_window},
    {"yank",yank},
    { "keyword", fl_keyword},
    { "newlanguage", fl_newlanguage}, 

    /*End Interface*/
    { NULL, NULL }
};

void interface_init(void)
{
    assign_global_builtins(builtin_info);
}
