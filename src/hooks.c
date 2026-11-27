/*
 * hooks.c -- the C core's callbacks into Scheme
 *
 * The C core (src/interface.c, display.c, undo.c) calls out through these
 * hooks; each one goes to the compiled program (compiled-program.c,
 * compiled/start.scm):
 *
 *   evaluate   M-:, C-x C-e, --eval        (scheme_eval)
 *   event      keys, commands, clicks
 *   highlight  faces for visible text
 *   modeline   each window's mode line
 *   change     every change to a text (undo)
 *   wrap       visual rows of prose
 *
 * A Scheme error never unwinds through C: each hook says so and the C core
 * carries on with its own behaviour.  Until 27 November 2026 femtoscheme
 * answered what the compiled program left; it is gone.
 */
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include "header.h"

extern void fe_set_hooks(int (*)(const char *, char *, int), int (*)(const char *, const char *), void (*)(const char *, const char *, long, const unsigned char *, int, unsigned char *));
extern void fe_set_modeline_hook(int (*)(const char *, const char *, const char *, int, int, int, char *, int));
extern void fe_set_change_hook(void (*)(long, int, long, const unsigned char *, long));
extern void fe_set_wrap_hook(int (*)(const char *, const unsigned char *, int, int));

extern int compiled_event(const char *, const char *);
extern int compiled_highlight(const char *, const char *, long, const unsigned char *, int, unsigned char *);
extern int compiled_modeline(const char *, const char *, const char *, int, int, int, char *, int);
extern int compiled_change(long, int, long, const unsigned char *, long);
extern int compiled_wrap(const char *, const unsigned char *, int, int, int *);
extern char *compiled_eval(const char *, int *, char **);
extern int read_mode_event(const char *, const char *);

static unsigned long failures;
void note_runtime_failure(void) { ++failures; }
unsigned long runtime_failure_serial(void) { return failures; }

/* M-:, C-x C-e, --eval: the value written, or "Error: ..." (scheme_error) */
int scheme_error = 0;
/* --eval (app.c): what the expression printed goes to the standard output */
int scheme_eval_quiet = 0;
static char result[8192];

char *scheme_eval(char *expr)
{
	int ok;
	char *output = NULL;
	char *text = compiled_eval(expr, &ok, &output);
	if (scheme_eval_quiet && output && *output) {
		fputs(output, stdout);
		if (output[strlen(output) - 1] != '\n') fputc('\n', stdout);
	}
	if (ok) snprintf(result, sizeof result, "%s", text);
	else snprintf(result, sizeof result, "Error: %s", text);
	scheme_error = !ok;
	free(text);
	free(output);
	return result;
}

static int evaluate(const char *expr, char *out, int size)
{
	snprintf(out, (size_t) size, "%s", scheme_eval((char *) expr));
	return !scheme_error;
}

static int event(const char *kind, const char *arg)
{
	if (read_mode_event(kind, arg)) return 1;
	return compiled_event(kind, arg);
}

static int mode_line(const char *name, const char *file, const char *buffer, int line,
		    int flags, int cols, char *out, int size)
{
	return compiled_modeline(name, file, buffer, line, flags, cols, out, size);
}

static void changed(long id, int kind, long pos, const unsigned char *text, long len)
{
	(void) compiled_change(id, kind, pos, text, len);
}

/* faces for N bytes of S, which start at offset START of the buffer; on
 * any error the default face stays */
static void highlight(const char *file, const char *buffer, long start,
		      const unsigned char *s, int n, unsigned char *colors)
{
	memset(colors, 5, (size_t) n);
	(void) compiled_highlight(file, buffer, start, s, n, colors);
}

/* bytes in the first visual row of TEXT; -1 "this file wraps"; 0 no wrapping */
static int wrap_row(const char *file, const unsigned char *text, int len, int cols)
{
	int result = 0;
	if (compiled_wrap(file, text, len, cols, &result)) return result;
	return 0;
}

void scheme_install_hooks(void)
{
	fe_set_hooks(evaluate, event, highlight);
	fe_set_modeline_hook(mode_line);
	fe_set_change_hook(changed);
	fe_set_wrap_hook(wrap_row);
}
