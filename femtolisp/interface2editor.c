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


/*Interface to the editor */

char dbg[30];

extern void insert_string(char *);
static value_t insrt(value_t *args, u_int32_t nargs) {
  argcount("insert", nargs, 1);
  value_t a= args[0]; /*Learn: pick an arg */
  char *str= cptr(a); /*Learn: string Lisp -> string C  */
  insert_string(str);
  return FL_NIL;}

extern void left(void);
extern void right(void);

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
    {"backward", bkwrd},
    {"forward", forwrd},
    {"beginning-of-line", linebegin},
    {"end-of-line", lineend},
    { "keyword", fl_keyword},
    { "newlanguage", fl_newlanguage}, 

    /*End Interface*/
    { NULL, NULL }
};

void interface_init(void)
{
    assign_global_builtins(builtin_info);
}
