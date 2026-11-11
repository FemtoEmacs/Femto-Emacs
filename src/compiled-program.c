/*
 * compiled-program.c -- Chezemax's compiled Scheme program in the editor
 *
 * `make` compiles the files of compiled/ into chezemax.wasm (PORT-TO-SCHEMER.md).
 * At start-up, before the femtoscheme scripts are loaded, the program is
 * loaded into Wasmtime and joined to the C core by the bridge (bridge.c):
 * it calls the C core's functions, and the C core gives it every event
 * first (hooks.c); what it does not handle goes on to the scripts.
 *
 * CHEZEMAX_PROGRAM=file.wasm loads another program (the tests do);
 * CHEZEMAX_PROGRAM= (empty) loads none.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include "llt/llt.h"
#include "flisp.h"
#include "bridge.h"

extern void fe_message(char *);
static sc_module *program;
static char *problem;              /* why the program is not running, if it is not */

/* The hooks the program has registered (bit N: hook N); the others are
 * never called, so that they cost nothing (compiled/editor.scm) */
static unsigned long hooks;
static void c_hook_set(bridge_in *in, bridge_out *out)
{
	long n = bridge_int(in), on = bridge_int(in);
	if (n >= 0 && n < (long) (8 * sizeof hooks)) {
		if (on) hooks |= 1UL << n;
		else hooks &= ~(1UL << n);
	}
	bridge_put_nothing(out);
}
static int hooked(int n) { return program && (hooks & (1UL << n)); }

/* The text of the hook running now, given only when Scheme asks for it
 * ((hook-text)): a highlighter that does not colour this file never
 * receives the window's text */
static const unsigned char *hook_text;
static size_t hook_len;
static void c_hook_text(bridge_in *in, bridge_out *out)
{
	(void) in;
	bridge_put_bytes(out, hook_text ? hook_text : (const unsigned char *) "", hook_text ? hook_len : 0);
}

static unsigned char *read_file(const char *path, long *size)
{
	FILE *f = fopen(path, "rb");
	unsigned char *bytes;
	if (!f) return NULL;
	fseek(f, 0, SEEK_END);
	*size = ftell(f);
	rewind(f);
	bytes = malloc((size_t) *size + 1);
	if (!bytes || fread(bytes, 1, (size_t) *size, f) != (size_t) *size) {
		free(bytes);
		fclose(f);
		return NULL;
	}
	fclose(f);
	return bytes;
}

/* Load and run the program at PATH (its machine code beside it, when it
 * is this program's); 1 when it runs, else 0 and PROBLEM says why */
static int load_program(const char *path)
{
	char *error = NULL, *value = NULL, *output = NULL;
	unsigned char *bytes;
	long size;

	free(problem);
	problem = NULL;
	hooks = 0;
	bytes = read_file(path, &size);
	if (!bytes) {
		problem = malloc(strlen(path) + 32);
		sprintf(problem, "cannot read %s", path);
		return 0;
	}
	{
		char code[4200];
		size_t n = strlen(path);
		if (n > 5 && !strcmp(path + n - 5, ".wasm")) snprintf(code, sizeof code, "%.*s.cwasm", (int) (n - 5), path);
		else snprintf(code, sizeof code, "%s.cwasm", path);
		program = sc_module_open_code(bytes, (size_t) size, code, NULL, NULL, &error);
	}
	free(bytes);
	if (!program) { problem = error; return 0; }
	bridge_attach(program);
	if (!sc_module_run(program, 0, &value, &output, &error)) {
		problem = error;
		sc_module_close(program);
		program = NULL;
		hooks = 0;
	}
	free(value);
	free(output);
	return program != NULL;
}

/* Something to tell the user once the editor is up ((startup-notice),
 * compiled/start.scm): why their own compiled scripts were not used */
static char *notice;
static void c_startup_notice(bridge_in *in, bridge_out *out)
{
	(void) in;
	bridge_put_string(out, notice ? notice : "");
}

static long modified(const char *path)
{
	struct stat st;
	return stat(path, &st) == 0 ? (long) st.st_mtime : -1;
}

/* The program: CHEZEMAX_PROGRAM's; else the scripts you compiled
 * (chezemax --compile-scripts: ~/.chezemax/chezemax.wasm) when they are not
 * older than Chezemax's own; else Chezemax's own (make), beside the editor */
void compiled_program_start(const char *directory)
{
	const char *env = getenv("CHEZEMAX_PROGRAM"), *home = getenv("HOME");
	char installed[4096], yours[4096];

	if (env && !*env) return;
	bridge_register("bridge-hook-set!", c_hook_set);
	bridge_register("hook-text", c_hook_text);
	bridge_register("startup-notice", c_startup_notice);
	if (env) { load_program(env); return; }
	snprintf(installed, sizeof installed, "%s/chezemax.wasm", directory);
	snprintf(yours, sizeof yours, "%s/.chezemax/chezemax.wasm", home && *home ? home : ".");
	if (modified(yours) >= 0) {
		if (modified(yours) < modified(installed)) {
			notice = strdup("Your compiled scripts (~/.chezemax/chezemax.wasm) are older than this Chezemax: "
					"Chezemax's own are used.  M-x compile-scripts compiles yours again.");
		} else if (load_program(yours)) {
			return;
		} else {
			size_t n = strlen(problem ? problem : "") + 200;
			notice = malloc(n);
			snprintf(notice, n, "Your compiled scripts (~/.chezemax/chezemax.wasm) did not start (%s): "
				 "Chezemax's own are used", problem ? problem : "failed");
		}
	}
	if (!load_program(installed) && notice) {
		free(notice);
		notice = NULL;
	}
}

/* A hook failed: say so once in a while, never unwind into the C core */
extern void note_runtime_failure(void);

static void failed(const char *what, char *error)
{
	note_runtime_failure();
	char message[512];
	snprintf(message, sizeof message, "Compiled Scheme (%s): %s", what, error ? error : "failed");
	fe_message(message);
	free(error);
}

/* The whole editor is compiled (chezemax.wasm with the scripts,
 * compiled/start.scm): it has registered the evaluation hook, which a test
 * program does not.  Then femtoscheme runs no script. */
int compiled_scripts_running(void)
{
	return hooked(BRIDGE_HOOK_EVAL);
}

/* Evaluate EXPR in the compiled program (compiled/eval.scm): its value
 * written, or the error (*OK 0); what it printed in *OUTPUT.  The strings
 * are the caller's to free. */
char *compiled_eval(const char *expr, int *ok, char **output)
{
	bridge_in r;
	char *error = NULL, *text;
	*output = strdup("");
	*ok = 0;
	if (!hooked(BRIDGE_HOOK_EVAL)) return strdup("No compiled program");
	if (!bridge_hook(BRIDGE_HOOK_EVAL, &r, &error, "s", expr))
		return error ? error : strdup("Compiled Scheme failed");
	if (bridge_list(&r) != 3) return strdup("Compiled Scheme: a bad answer from eval");
	*ok = bridge_int(&r) != 0;
	text = bridge_string(&r);
	free(*output);
	*output = bridge_string(&r);
	return text;
}

/* The event to the compiled program: 1 when it handled it */
int compiled_event(const char *kind, const char *arg)
{
	bridge_in r;
	char *error = NULL;
	if (!hooked(BRIDGE_HOOK_EVENT)) return 0;
	if (!bridge_hook(BRIDGE_HOOK_EVENT, &r, &error, "ss", kind, arg)) {
		note_runtime_failure();
		char message[512];
		snprintf(message, sizeof message, "Compiled Scheme: %s", error ? error : "failed");
		fe_message(message);
		free(error);
		/* a failing key binding must not run another binding as well */
		return strcmp(kind, "key") == 0 || strcmp(kind, "command") == 0;
	}
	return bridge_int(&r) != 0;
}

/* For the femtoscheme scripts while they are ported, and for the tests:
 * (fe-compiled-event kind arg) and (fe-compiled-status) */
static value_t fl_compiled_event(value_t *args, uint32_t nargs)
{
	argcount("fe-compiled-event", nargs, 2);
	return compiled_event(tostring(args[0], "fe-compiled-event"),
			      tostring(args[1], "fe-compiled-event")) ? FL_T : FL_F;
}

static value_t fl_compiled_status(value_t *args, uint32_t nargs)
{
	const char *s = program ? "running" : problem ? problem : "no compiled program";
	(void) args;
	argcount("fe-compiled-status", nargs, 0);
	return string_from_cstrn((char *) s, strlen(s));
}

void compiled_program_test_init(void);

void compiled_program_init(const char *directory)
{
	static builtinspec_t builtins[] = {
		{"fe-compiled-event", fl_compiled_event},
		{"fe-compiled-status", fl_compiled_status},
		{NULL, NULL}
	};
	assign_global_builtins(builtins);
	compiled_program_test_init();
	bridge_set_install_dir(directory);
	compiled_program_start(directory);
}

/* Colours for N bytes of S at offset START of BUFFER (FILE): 1 when the
 * program coloured them (COLORS filled), 0 to leave them to the scripts */
int compiled_highlight(const char *file, const char *buffer, long start,
		       const unsigned char *s, int n, unsigned char *colors)
{
	bridge_in r;
	char *error = NULL;
	int done = 0;
	if (!hooked(BRIDGE_HOOK_HIGHLIGHT)) return 0;
	hook_text = s; hook_len = (size_t) n;
	if (!bridge_hook(BRIDGE_HOOK_HIGHLIGHT, &r, &error, "ssii", file ? file : "", buffer ? buffer : "", start, (long) n))
		failed("colours", error);
	else if (bridge_kind(&r) == BRIDGE_BYTES) {
		size_t got;
		unsigned char *c = bridge_bytes(&r, &got);
		if (got == (size_t) n) { memcpy(colors, c, got); done = 1; }
		free(c);
	}
	hook_text = NULL;
	return done;
}

/* The mode line of a window: 1 when the program wrote it in OUT */
int compiled_modeline(const char *name, const char *file, const char *buffer, int line,
		      int flags, int cols, char *out, int size)
{
	bridge_in r;
	char *error = NULL;
	if (!hooked(BRIDGE_HOOK_MODELINE)) return 0;
	if (!bridge_hook(BRIDGE_HOOK_MODELINE, &r, &error, "sssiii", name, file ? file : "",
			 buffer ? buffer : "", (long) line, (long) flags, (long) cols)) {
		failed("mode line", error);
		return 0;
	}
	if (bridge_kind(&r) != BRIDGE_STRING) return 0;
	char *line_text = bridge_string(&r);
	size_t n = strlen(line_text);
	if (n >= (size_t) size) {
		n = (size_t) size - 1;
		while (n > 0 && (((unsigned char *) line_text)[n] & 0xC0) == 0x80) n--;   /* whole characters */
	}
	memcpy(out, line_text, n);
	out[n] = '\0';
	free(line_text);
	return 1;
}

/* A change to a text (for undo): 1 when the program recorded it */
int compiled_change(long id, int kind, long pos, const unsigned char *text, long len)
{
	bridge_in r;
	char *error = NULL;
	if (!hooked(BRIDGE_HOOK_CHANGE)) return 0;
	if (!bridge_hook(BRIDGE_HOOK_CHANGE, &r, &error, "iiib", id, (long) kind, pos,
			 text ? text : (const unsigned char *) "", text ? (int) len : 0)) {
		failed("undo", error);
		return 0;
	}
	return bridge_kind(&r) != BRIDGE_FALSE && bridge_kind(&r) != BRIDGE_NOTHING;
}

/* Word wrap (display.c): TEXT NULL asks whether FILE wraps (-1: yes);
 * otherwise the bytes of TEXT in its first visual row.  1 when the program
 * answered, in *RESULT */
int compiled_wrap(const char *file, const unsigned char *text, int len, int cols, int *result)
{
	bridge_in r;
	char *error = NULL;
	int done = 0;
	if (!hooked(BRIDGE_HOOK_WRAP)) return 0;
	hook_text = text; hook_len = text ? (size_t) len : 0;
	if (!bridge_hook(BRIDGE_HOOK_WRAP, &r, &error, "sii", file ? file : "", (long) (text ? len : -1), (long) cols))
		failed("word wrap", error);
	else if (bridge_kind(&r) == BRIDGE_INT) {
		*result = (int) bridge_int(&r);
		done = 1;
	}
	hook_text = NULL;
	return done;
}

/* For the tests: the same calls as hooks.c makes, from --eval */
static value_t fl_compiled_highlight(value_t *args, uint32_t nargs)
{
	argcount("fe-compiled-highlight", nargs, 3);
	char *file = tostring(args[0], "fe-compiled-highlight"), *buffer = tostring(args[1], "fe-compiled-highlight");
	char *text = tostring(args[2], "fe-compiled-highlight");
	int n = (int) cvalue_len(args[2]);
	unsigned char *colors = calloc((size_t) n + 1, 1);
	value_t r = FL_F;
	if (compiled_highlight(file, buffer, 0, (unsigned char *) text, n, colors)) {
		r = FL_NIL;
		for (int k = n - 1; k >= 0; k--) r = fl_cons(fixnum(colors[k]), r);
	}
	free(colors);
	return r;
}

static value_t fl_compiled_modeline(value_t *args, uint32_t nargs)
{
	char out[512];
	argcount("fe-compiled-mode-line", nargs, 3);
	if (!compiled_modeline(tostring(args[0], "fe-compiled-mode-line"), tostring(args[1], "fe-compiled-mode-line"),
			       tostring(args[0], "fe-compiled-mode-line"), 1, 0, (int) tofixnum(args[2], "fe-compiled-mode-line"), out, sizeof out)) return FL_F;
	return string_from_cstrn(out, strlen(out));
}

static value_t fl_compiled_change(value_t *args, uint32_t nargs)
{
	argcount("fe-compiled-change", nargs, 2);
	char *text = tostring(args[1], "fe-compiled-change");
	return compiled_change(7, (int) tofixnum(args[0], "fe-compiled-change"), 0,
			       (unsigned char *) text, (long) cvalue_len(args[1])) ? FL_T : FL_F;
}

static value_t fl_compiled_wrap(value_t *args, uint32_t nargs)
{
	int result = 0;
	argcount("fe-compiled-wrap", nargs, 3);
	char *text = fl_isstring(args[1]) ? tostring(args[1], "fe-compiled-wrap") : NULL;
	if (!compiled_wrap(tostring(args[0], "fe-compiled-wrap"), (unsigned char *) text,
			   text ? (int) cvalue_len(args[1]) : 0, (int) tofixnum(args[2], "fe-compiled-wrap"), &result))
		return FL_F;
	return fixnum(result);
}

void compiled_program_test_init(void)
{
	static builtinspec_t builtins[] = {
		{"fe-compiled-highlight", fl_compiled_highlight},
		{"fe-compiled-mode-line", fl_compiled_modeline},
		{"fe-compiled-change", fl_compiled_change},
		{"fe-compiled-wrap", fl_compiled_wrap},
		{NULL, NULL}
	};
	assign_global_builtins(builtins);
}
