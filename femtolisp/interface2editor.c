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
#include <math.h>
#include "../public.h"

/* Interface to the editor */
extern int is_digit(char_t c);


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

static value_t fe_forward_word(value_t *args, u_int32_t nargs) {
	argcount("forward-word", nargs, 1);
	value_t a = args[0];
	long int n = numval(a);
	while (n-- > 0)
		forward_word();
	return FL_T;
}

static value_t fe_backward_word(value_t *args, u_int32_t nargs) {
	argcount("backward-word", nargs, 1);
	value_t a = args[0];
	long int n = numval(a);
	while (n-- > 0)
		backward_word();
	return FL_T;
}

static value_t fe_forward_page(value_t *args, u_int32_t nargs) {
	argcount("forward-page", nargs, 1);
	value_t a = args[0];
	long int n = numval(a);
	while (n-- > 0)
		forward_page();
	return FL_T;
}

static value_t fe_backward_page(value_t *args, u_int32_t nargs) {
	argcount("backward-page", nargs, 1);
	value_t a = args[0];
	long int n = numval(a);
	while (n-- > 0)
		backward_page();
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

static value_t fe_beginning_of_buffer(value_t *args, u_int32_t nargs) {
	argcount("beginning-of-buffer", nargs, 0);
	beginning_of_buffer();
	return FL_T;
}

static value_t fe_end_of_buffer(value_t *args, u_int32_t nargs) {
	argcount("end-of-buffer", nargs, 0);
	end_of_buffer();
	return FL_T;
}

static value_t fe_clr_msg_line(value_t *args, u_int32_t nargs) {
	argcount("clear-message-line", nargs, 0);
	clear_message_line();
	return FL_T;
}

static value_t fe_get_clipboard(value_t *args, u_int32_t nargs) {
	argcount("get-clipboard", nargs, 0);
	static char empty_string[] = "";
	char *ptr = (char *)get_scrap();

	if (ptr == NULL) ptr = empty_string;

	/*
	 * it is safe to pass our scrap pointer to string_from_cstr()
	 * as the function will call memcpy making and managing its cown copy
	 */
	return (string_from_cstr(ptr));
}

static value_t eval_blk(value_t *args, u_int32_t nargs) {
	argcount("eval-block", nargs, 0);
	eval_block();
	return FL_T;
}

static value_t del_other_windows(value_t *args, u_int32_t nargs) {
	argcount("delete-other-windows", nargs, 0);
	delete_other_windows();
	return FL_T;
}

static value_t fe_other_window(value_t *args, u_int32_t nargs) {
	argcount("other-window", nargs, 0);
	other_window();
	return FL_T;
}

static value_t fe_split_window(value_t *args, u_int32_t nargs) {
	argcount("split-window", nargs, 0);
	split_window();
	return FL_T;
}

static value_t gotoln(value_t *args, u_int32_t nargs) {
	argcount("goto-line", nargs, 1);
	value_t a = args[0];
	goto_line(numval(a)); /*Learn: Lisp num -> C int*/
	return FL_T;
}

static value_t fe_kill_region(value_t *args, u_int32_t nargs) {
	argcount("kill-region", nargs, 0);
	cut();
	return FL_T;
}

static value_t fe_copy_region(value_t *args, u_int32_t nargs) {
	argcount("copy-region", nargs, 0);
	copy();
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
        i_set_mark();
	return FL_T;
}

static value_t fe_update_display(value_t *args, u_int32_t nargs) {
	argcount("update-display", nargs, 0);
	update_display();
	return FL_T;
}

static value_t yank(value_t *args, u_int32_t nargs) {
	argcount("yank", nargs, 0);
	paste();
	return FL_T;
}


/*
 *  functions returning int
 */

static value_t fe_count_buffers(value_t *args, u_int32_t nargs) {
	argcount("get-buffer-count", nargs, 0);
	return (mk_uint32(count_buffers()));
}


/*
 * functions returning a char *
 */

static value_t fe_get_version_string(value_t *args, u_int32_t nargs) {
	argcount("get-version-string", nargs, 0);
	return (string_from_cstr(get_version_string()));
}

static value_t fe_get_key(value_t *args, u_int32_t nargs) {
	argcount("get-key", nargs, 0);
	return string_from_cstr(fe_get_input_key());
}

static value_t fe_get_key_name(value_t *args, u_int32_t nargs) {
	argcount("get-key-name", nargs, 0);
	return string_from_cstr(get_key_name());
}

static value_t fe_get_key_binding(value_t *args, u_int32_t nargs) {
	argcount("get-key-binding", nargs, 0);
	return string_from_cstr(get_key_binding());
}

static value_t fe_get_buffer_name(value_t *args, u_int32_t nargs) {
	argcount("get-buffer-name", nargs, 0);
	return string_from_cstr(get_current_bufname());
}


/*
 * interface to editor functions of form
 *   char *func(char *)
 */

static value_t fe_trim(value_t *args, u_int32_t nargs) {
	argcount("trim", nargs, 1);
	value_t a = args[0];
	char *str = cptr(a);
	return string_from_cstr(string_trim(str));
}


/*
 * interface to editor functions of form func(char *)
 */

static value_t msg_lisp(value_t *args, u_int32_t nargs) {
	argcount("message", nargs, 1);
	value_t a = args[0]; /*Learn: pick an arg */
	char *str = cptr(a); /*Learn: string Lisp -> string C  */
	msg(str);
	return FL_T;
}

/* log a string to debug.out  */
static value_t fe_log_debug(value_t *args, u_int32_t nargs) {
	argcount("log-debug", nargs, 1);
	value_t a = args[0]; /*Learn: pick an arg */
	char *str = cptr(a); /*Learn: string Lisp -> string C  */
	log_debug(str);
	return FL_T;
}

static value_t fe_log_message(value_t *args, u_int32_t nargs) {
	argcount("log-message", nargs, 1);
	value_t a = args[0];
	char *str = cptr(a);
	log_message(str);
	return FL_T;
}

/* set the contents of the scrap (clipboard) pointer */
static value_t fe_set_clipboard(value_t *args, u_int32_t nargs) {
	argcount("set-clipboard", nargs, 1);
	value_t a = args[0];
	char *str = cptr(a);

	/*
	 * str is a pointer to memory malloc'd and managed by femtolisp
	 * we must make a copy of it first before setting the scrap pointer with it.
	 * This is so that when the clipboard is next used we can safely call free()
	 * on that pointer in the copy_cut() function, as if Femto had malloc'd
	 * the memory as a result of calling copy_cut().
	 *
	 */

	int len = strlen(str);
	unsigned char *ptr = malloc(len + 1);
	assert(ptr != NULL);
	
	(void)memcpy(ptr, str, len * sizeof (unsigned char));
	*(ptr + len) = '\0';  /* everything in scrap must always be null terminated */

	/*
	 * now set the scrap pointer as if copy_cut() had been called
	 * note that set_scrap does a free(scrap) if the old scrap is not NULL
	 */
	set_scrap(ptr);
	return FL_T;
}


/*
 * interface to functions of form
 *    int func(char *)
 *
 */

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

static value_t fe_select_buffer(value_t *args, u_int32_t nargs) {
	argcount("select-buffer", nargs, 1);
	value_t a = args[0];
	char *str = cptr(a);
	int result = select_buffer(str);
	return (result ? FL_T : FL_NIL);
}

static value_t fe_delete_buffer(value_t *args, u_int32_t nargs) {
	argcount("kill-buffer", nargs, 1);
	value_t a = args[0];
	char *str = cptr(a);
	int result = delete_buffer_byname(str);
	return (result ? FL_T : FL_NIL);
}

static value_t fe_save_buffer(value_t *args, u_int32_t nargs) {
	argcount("save-buffer", nargs, 1);
	value_t a = args[0];
	char *str = cptr(a);
	int result = save_buffer_byname(str);
	return (result ? FL_T : FL_NIL);
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

	/* p is a pointer not an offset so checking less than 1 does not work */
	//if (p < 1)
	//	return 0;


	/*
	 * there is a clash of typedefs with char_t in FemtoEmacs and femtolisp
	 * hence casting to char for this check to avoid a warning
	 */
	char c = (char)*p;
	return ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
		(c >= '0' && c <= '9') || (c == '_'));
}


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
int negative_prefix(char_t *p) { return (*p == '-' && is_digit(*(p + 1))); }

int number_prefix(char_t *p, int *j) {
	/* Numbers start with a digit or with '-' followed by a digit */
	if (is_digit(*p)) {
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
	return 0;
}

/*
 * check if in a class of token , return legth of token
 * 
 */
int scan_for_keywords(char_t *p, int *token_type) {

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
		while (is_digit(*(p + j))) {
			j = j + 1;
		}
		if (*(p + j) == '.') {
			j = j + 1;
			while (is_digit(*(p + j))) {
				j = j + 1;
			}
		}
		if (exponent_prefix(p, &j)) {
			while (is_digit(*(p + j))) {
				j = j + 1;
			}
		}
		if (!notsep(p + j)) {
			*token_type = ID_TOKEN_DIGITS;
			return j;
		}
		*token_type = ID_TOKEN_NONE;
		return 0;
	}

	/* If automaton has not number prefix, it tries to recognize a keyword */
	if (thisLanguage < 0) {
		*token_type = ID_TOKEN_NONE;
		return 0;
	}
	
	j = 0; /* Reset j */
	for (i = 0; i < numWords[thisLanguage]; i++) {
		if (seq(p, hiLite[thisLanguage][i])) {
			*token_type = ID_TOKEN_KEYWORD;
			return strlen(hiLite[thisLanguage][i]);
		}
	}
	*token_type = ID_TOKEN_NONE;
	return 0;
}

/*
 * check for comments based on previous status of comments
 */
void scan_for_comments(char_t *p, int *blk_comment, int *ln_comment) {
	if (thisLanguage < 0)
		return;
	if ((*ln_comment == 0) && seq(p, line_comment[thisLanguage]))
		*ln_comment = 1;
	if ((*ln_comment == 1) && (*p == '\n'))
		*ln_comment = 0;
	if ((*blk_comment== 0) && seq(p, begin_comment[thisLanguage]))
		*blk_comment= 1;
	if ((*blk_comment== 1) && seq(p, end_comment[thisLanguage]))
		*blk_comment= 0;
	return;
}

void setLanguage(char *extension) {
	int i;
	thisLanguage = -1;
	for (i = 0; i < nLangs; i++) {
		if (strcmp(LangCode[i], extension) == 0) {
			thisLanguage = i;
		}
	}
}

static value_t fe_newlanguage(value_t *args, u_int32_t nargs) {
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

static value_t fe_keyword(value_t *args, u_int32_t nargs) {
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

static int num2ptr(value_t a, fixnum_t *pi, numerictype_t *pt, void **pp)
{
	cprim_t *cp;
	if (isfixnum(a)) {
		*pi = numval(a);
		*pp = pi;
		*pt = T_FIXNUM;
	}
	else if (iscprim(a)) {
		cp = (cprim_t*)ptr(a);
		*pp = cp_data(cp);
		*pt = cp_numtype(cp);
	}
	else {
		return 0;
	}
	return 1;
}


static value_t fl_pow(value_t *args, u_int32_t nargs)
{   argcount("expt", nargs, 2);
	value_t a= args[0];
	value_t b= args[1];
	double da, db;
	int_t ai, bi;
	numerictype_t ta, tb;
	void *aptr, *bptr;

	if (!num2ptr(a, &ai, &ta, &aptr))
		type_error("pow", "number", a);
	if (!num2ptr(b, &bi, &tb, &bptr))
		type_error("pow", "number", b);

	da = conv_to_double(aptr, ta);
	db = conv_to_double(bptr, tb);

	da = pow( da, db);

	if (ta < T_FLOAT && tb < T_FLOAT && (double)(int64_t)da == da)
		return return_from_int64((int64_t)da);
	return mk_double(da);
}


static value_t fl_sin(value_t *args, u_int32_t nargs) {
	argcount("sin", nargs, 1);
	value_t a= args[0];
	double da;
	int_t ai;
	numerictype_t ta;
	void *aptr;
	if (!num2ptr(a, &ai, &ta, &aptr))
		type_error("sin", "number", a);
	da= conv_to_double(aptr, ta);
	da= sin(da);
	if (ta < T_FLOAT && (double)(int64_t)da == da)
		return return_from_int64((int64_t)da);
	return (mk_double(da));
}

static value_t fl_cos(value_t *args, u_int32_t nargs) {
	argcount("cos", nargs, 1);
	value_t a= args[0];
	double da;
	int_t ai;
	numerictype_t ta;
	void *aptr;
	if (!num2ptr(a, &ai, &ta, &aptr))
		type_error("cos", "number", a);
	da= conv_to_double(aptr, ta);
	da= cos(da);
	if (ta < T_FLOAT && (double)(int64_t)da == da)
		return return_from_int64((int64_t)da);
	return (mk_double(da));
}


static value_t fl_tan(value_t *args, u_int32_t nargs) {
	argcount("tan", nargs, 1);
	value_t a= args[0];
	double da;
	int_t ai;
	numerictype_t ta;
	void *aptr;
	if (!num2ptr(a, &ai, &ta, &aptr))
		type_error("tan", "number", a);
	da= conv_to_double(aptr, ta);
	da= tan(da);
	if (ta < T_FLOAT && (double)(int64_t)da == da)
		return return_from_int64((int64_t)da);
	return (mk_double(da));
}


static value_t fl_atan(value_t *args, u_int32_t nargs) {
	argcount("atan", nargs, 1);
	value_t a= args[0];
	double da;
	int_t ai;
	numerictype_t ta;
	void *aptr;
	if (!num2ptr(a, &ai, &ta, &aptr))
		type_error("atan", "number", a);
	da= conv_to_double(aptr, ta);
	da= atan(da);
	if (ta < T_FLOAT && (double)(int64_t)da == da)
		return return_from_int64((int64_t)da);
	return (mk_double(da));
}


static value_t fl_asin(value_t *args, u_int32_t nargs) {
	argcount("asin", nargs, 1);
	value_t a= args[0];
	double da;
	int_t ai;
	numerictype_t ta;
	void *aptr;
	if (!num2ptr(a, &ai, &ta, &aptr))
		type_error("asin", "number", a);
	da= conv_to_double(aptr, ta);
	da= asin(da);
	if (ta < T_FLOAT && (double)(int64_t)da == da)
		return return_from_int64((int64_t)da);
	return (mk_double(da));
}

static value_t fl_acos(value_t *args, u_int32_t nargs) {
	argcount("acos", nargs, 1);
	value_t a= args[0];
	double da;
	int_t ai;
	numerictype_t ta;
	void *aptr;
	if (!num2ptr(a, &ai, &ta, &aptr))
		type_error("acos", "number", a);
	da= conv_to_double(aptr, ta);
	da= acos(da);
	if (ta < T_FLOAT && (double)(int64_t)da == da)
		return return_from_int64((int64_t)da);
	return (mk_double(da));
}


static value_t fl_exp(value_t *args, u_int32_t nargs) {
	argcount("exp", nargs, 1);
	value_t a= args[0];
	double da;
	int_t ai;
	numerictype_t ta;
	void *aptr;
	if (!num2ptr(a, &ai, &ta, &aptr))
		type_error("exp", "number", a);
	da= conv_to_double(aptr, ta);
	da= exp(da);
	if (ta < T_FLOAT && (double)(int64_t)da == da)
		return return_from_int64((int64_t)da);
	return (mk_double(da));
}


static value_t fl_log(value_t *args, u_int32_t nargs) {
	argcount("log", nargs, 1);
	value_t a= args[0];
	double da;
	int_t ai;
	numerictype_t ta;
	void *aptr;
	if (!num2ptr(a, &ai, &ta, &aptr))
		type_error("log", "number", a);
	da= conv_to_double(aptr, ta);
	da= log(da);
	if (ta < T_FLOAT && (double)(int64_t)da == da)
		return return_from_int64((int64_t)da);
	return (mk_double(da));
}


static value_t fl_log2(value_t *args, u_int32_t nargs) {
	argcount("log2", nargs, 1);
	value_t a= args[0];
	double da;
	int_t ai;
	numerictype_t ta;
	void *aptr;
	if (!num2ptr(a, &ai, &ta, &aptr))
		type_error("log2", "number", a);
	da= conv_to_double(aptr, ta);
	da= log2(da);
	if (ta < T_FLOAT && (double)(int64_t)da == da)
		return return_from_int64((int64_t)da);
	return (mk_double(da));
}


static value_t fl_log10(value_t *args, u_int32_t nargs) {
	argcount("log10", nargs, 1);
	value_t a= args[0];
	double da;
	int_t ai;
	numerictype_t ta;
	void *aptr;
	if (!num2ptr(a, &ai, &ta, &aptr))
		type_error("log10", "number", a);
	da= conv_to_double(aptr, ta);
	da= log10(da);
	if (ta < T_FLOAT && (double)(int64_t)da == da)
		return return_from_int64((int64_t)da);
	return (mk_double(da));
}


/* end of interface to the editor */
extern void stringfuncs_init(void);
extern void table_init(void);
extern void iostream_init(void);


/*
 *
 * NOTE The emacs compatible interface names for the clipboard are:
 *
 * (copy-region)      copy the region into the clipboard
 * (kill-region)      kill the region into the clipboard
 * (yank)             yank the clipboard and paste it into the buffer
 * (get-clipboard)    return a string containing the clipboard
 * (set-clipboard s)  set the contents of the clipboard to s
 *
 */

/*
 * Femto inteface bultin functions
 *
 * see file in docs/interface-bindings.txt for names of current and
 * future interface names for GNU Emacs compatibility
 */

static builtinspec_t builtin_info[] = {
	{"insert", insrt},
	{"backward-delete-char", backspace},
	{"backward-char", bkwrd},
	{"forward-char", forwrd},
	{"backward-word", fe_backward_word},
	{"forward-word", fe_forward_word},
	{"backward-page", fe_backward_page},
	{"forward-page", fe_forward_page},
	{"beginning-of-line", linebegin},
	{"end-of-line", lineend},
	{"beginning-of-buffer", fe_beginning_of_buffer},
	{"end-of-buffer", fe_end_of_buffer},
	{"copy-region", fe_copy_region},
	{"clear-message-line", fe_clr_msg_line},
	{"eval-block", eval_blk},
	{"get-key", fe_get_key},
	{"log-debug", fe_log_debug},
	{"log-message", fe_log_message},
	{"message", msg_lisp},
	{"delete-other-windows", del_other_windows},
	{"kill-buffer", fe_delete_buffer},
	{"goto-line", gotoln},
	{"kill-region", fe_kill_region},
	{"list-buffers", lst_buffers},
	{"next-line", next_line},
	{"previous-line", previous_line},
	{"other-window", fe_other_window},
	{"save-buffer", fe_save_buffer},
	{"search-forward", src_forward},
	{"search-backwards", src_backwards},
	{"set-mark", set_mark},
	{"select-buffer", fe_select_buffer},
	{"split-window", fe_split_window},
	{"trim", fe_trim},
	{"update-display", fe_update_display},
	{"yank", yank},
	{"get-version-string", fe_get_version_string},
	{"get-buffer-count", fe_count_buffers},
	{"get-buffer-name", fe_get_buffer_name},
	{"get-key-name", fe_get_key_name},
	{"get-key-binding", fe_get_key_binding},
	{"get-clipboard", fe_get_clipboard},
	{"set-clipboard", fe_set_clipboard},
	{"keyword", fe_keyword},
	{"newlanguage", fe_newlanguage},

	/* these should be in a seperate builtins module */
	{"expt", fl_pow},
	{"sin", fl_sin},
	{"cos", fl_cos},
	{"tan", fl_tan},
	{"asin", fl_asin},
	{"acos", fl_acos},
	{"atan", fl_atan},
	{"exp", fl_exp},
	{"log", fl_log},
	{"log2", fl_log2},
	{"log10", fl_log10},
	/*End Interface*/
	{NULL, NULL}
};

void interface_init(void)
{
	assign_global_builtins(builtin_info);
}
