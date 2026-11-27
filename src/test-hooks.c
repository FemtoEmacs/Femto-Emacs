/*
 * test-hooks.c -- chezemax --test STEP...: the compiled program's hooks
 * called one by one, as the C core calls them, without a screen (tests:
 * run-bridge.sh, run-scripts.sh).  The steps run in order; each prints a
 * line:
 *
 *   event KIND ARG          #t when the program handled it, else #f
 *   highlight FILE TEXT     the colours, (5 5 4), or #f
 *   mode-line NAME FILE COLS   the mode line written, or #f
 *   change KIND TEXT        #t when the program recorded it, else #f
 *   wrap FILE TEXT|-  COLS  bytes in the first row (-1: the file wraps), or #f
 *   status                  "running", or why not
 *   text                    the text of the buffer
 *
 * Strings print between double quotes, with \ before " and \, and a
 * newline as \n, as Scheme's write prints them.  Until 27
 * November 2026 the tests did this in femtoscheme (fe-compiled-event ...).
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "header.h"

extern int compiled_event(const char *, const char *);
extern int compiled_highlight(const char *, const char *, long, const unsigned char *, int, unsigned char *);
extern int compiled_modeline(const char *, const char *, const char *, int, int, int, char *, int);
extern int compiled_change(long, int, long, const unsigned char *, long);
extern int compiled_wrap(const char *, const unsigned char *, int, int, int *);
extern const char *compiled_program_status(void);

static void print_string(const char *s, size_t n)
{
	size_t i;
	putchar('"');
	for (i = 0; i < n; i++) {
		if (s[i] == '\n') { fputs("\\n", stdout); continue; }
		if (s[i] == '"' || s[i] == '\\') putchar('\\');
		putchar(s[i]);
	}
	puts("\"");
}

static int need(int k, int n, int argc, const char *step)
{
	if (k + n < argc) return 1;
	fprintf(stderr, "--test %s: %d argument(s)\n", step, n);
	exit(2);
}

int test_hooks(int argc, char **argv)
{
	int k = 0;
	while (k < argc) {
		const char *step = argv[k];
		if (strcmp(step, "event") == 0 && need(k, 2, argc, step)) {
			puts(compiled_event(argv[k + 1], argv[k + 2]) ? "#t" : "#f");
			k += 3;
		} else if (strcmp(step, "highlight") == 0 && need(k, 2, argc, step)) {
			int n = (int) strlen(argv[k + 2]), i;
			unsigned char *colors = calloc((size_t) n + 1, 1);
			if (compiled_highlight(argv[k + 1], "", 0, (unsigned char *) argv[k + 2], n, colors)) {
				putchar('(');
				for (i = 0; i < n; i++) printf(i ? " %d" : "%d", colors[i]);
				puts(")");
			} else puts("#f");
			free(colors);
			k += 3;
		} else if (strcmp(step, "mode-line") == 0 && need(k, 3, argc, step)) {
			char out[512];
			if (compiled_modeline(argv[k + 1], argv[k + 2], argv[k + 1], 1, 0, atoi(argv[k + 3]), out, sizeof out))
				print_string(out, strlen(out));
			else puts("#f");
			k += 4;
		} else if (strcmp(step, "change") == 0 && need(k, 2, argc, step)) {
			puts(compiled_change(7, atoi(argv[k + 1]), 0, (unsigned char *) argv[k + 2], (long) strlen(argv[k + 2])) ? "#t" : "#f");
			k += 3;
		} else if (strcmp(step, "wrap") == 0 && need(k, 3, argc, step)) {
			int result = 0, none = strcmp(argv[k + 2], "-") == 0;
			if (compiled_wrap(argv[k + 1], none ? NULL : (unsigned char *) argv[k + 2],
					  none ? 0 : (int) strlen(argv[k + 2]), atoi(argv[k + 3]), &result))
				printf("%d\n", result);
			else puts("#f");
			k += 4;
		} else if (strcmp(step, "status") == 0) {
			const char *s = compiled_program_status();
			print_string(s, strlen(s));
			k += 1;
		} else if (strcmp(step, "text") == 0) {
			point_t size = document_size(curbp), i;
			char *t = malloc((size_t) size + 1);
			for (i = 0; i < size; i++) t[i] = (char) *ptr(curbp, i);
			print_string(t, (size_t) size);
			free(t);
			k += 1;
		} else {
			fprintf(stderr, "--test: unknown step %s\n", step);
			return 2;
		}
	}
	return 0;
}
