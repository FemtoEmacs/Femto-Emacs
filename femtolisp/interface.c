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

static value_t qua(value_t *args, u_int32_t nargs) {
  argcount("quadrado", nargs, 1);
  value_t a= args[0];
  printf("%d\n", (int) (numval(a)*numval(a)));
  return FL_NIL;}

static builtinspec_t builtin_info[] = {
  {"quadrado", qua},
  /*End Interface*/
  { NULL, NULL }
};

void interface_init(void)
{
    assign_global_builtins(builtin_info);
}
