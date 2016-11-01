#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <assert.h>
#include "llt/llt.h"
#include "flisp.h"

extern void interface_init(void);
extern value_t fl_file(value_t *args, uint32_t nargs);
extern value_t fl_buffer(value_t *args, u_int32_t nargs);
extern value_t fl_iowrite(value_t *args, u_int32_t nargs);
extern value_t fl_ioseek(value_t *args, u_int32_t nargs);
extern value_t fl_read(value_t *args, u_int32_t nargs);
extern value_t fl_toplevel_eval(value_t expr);
extern value_t eval_sexpr(value_t e, value_t *penv, int tail, u_int32_t envend);

/* output buffer */
value_t volta_buffer(char* string)
{
	value_t barg[2];
	value_t args[2];
	value_t b = fl_buffer(barg, 0);
	args[0] = b;
	args[1] = cvalue_static_cstring(string);
	fl_iowrite(args,2);
	value_t sargs[2];
	sargs[0] = b;
	sargs[1] = 0;
	fl_ioseek(sargs,2);
	return b;
}

static char *wrp=
	"(let ((b (buffer))) \
   (with-output-to b (princ %s)) \
   (io.tostring! b))";

/* read_buffer */
value_t ler_buffer(value_t buffer) {
	return fl_read(&buffer, 1);
}

/* FIXME need to understand the implications of this limit */
/* the calling expression must be able to fit into the buffer */
#define COMMAND_BUFFER_N 2048

char *call_lisp(char *expr)
{
	char *cbuffer = NULL;

	FL_TRY_EXTERN {
		/*
		 * using malloc in here so that this function is re-entrant.
		 * so that it can be called again whilst another call is already
		 * taking place.  This can happen when keyboard macros result
		 * in a callback into the C code that again results in a call to call_lisp.
		 * a good example of this is the use of kill-hook and C-x C-u
		 */
		cbuffer = malloc(COMMAND_BUFFER_N);
		assert(cbuffer != NULL);
		sprintf(cbuffer, wrp, expr);		
		
		value_t BB = volta_buffer(cbuffer);
		value_t CC = ler_buffer(BB);
		
		CC= fl_toplevel_eval(CC);

		free(cbuffer);
		return cptr(CC);
		
	} FL_CATCH_EXTERN {
	}

	free(cbuffer);
	return "Error";
}

int init_lisp(int nheap_k)
{
	char fname_buf[1024];
	value_t args[2];

	fl_init(nheap_k*1024);
	fname_buf[0] = '\0';

	value_t str = symbol_value(symbol("*install-dir*"));
	char *exedir = (str == UNBOUND ? NULL : cvalue_data(str));

	if (exedir != NULL) {
		strcat(fname_buf, exedir);
		strcat(fname_buf, PATHSEPSTRING);
	}

	strcat(fname_buf, "femto.boot");

	fl_gc_handle(&args[0]);
	fl_gc_handle(&args[1]);

	FL_TRY_EXTERN {
		char buff[200];
		
		/* read system image file "femto.boot" */
		args[0] = cvalue_static_cstring(fname_buf);
		args[1] = symbol(":read");

		value_t f = fl_file(&args[0], 2);
		fl_free_gc_handles(2);
		fl_load_system_image(f);

		interface_init();
		(void)fl_applyn(1, symbol_value(symbol("__start")));

		/* load init.lsp */
		sprintf(buff, "(load \"%s/init.lsp\")", getenv("HOME"));
		(void)call_lisp(buff);
		/* FIXME we are no checking the output of call_lisp() here - we assume that it worked */
		
	} FL_CATCH_EXTERN {
		ios_puts("fatal error:\n", ios_stderr);
		fl_print(ios_stderr, fl_lasterror);
		ios_putc('\n', ios_stderr);
		exit(1);
	} 
  
	return 0;
}
