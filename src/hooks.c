/*
 * hooks.c -- the C core's callbacks into Scheme
 *
 * The C core (src/interface.c, display.c, undo.c) calls out through these
 * hooks; each one calls a Scheme procedure:
 *
 *   evaluate   Esc-; and Esc-]            (scheme_eval, flcall.c)
 *   event      keys, commands, clicks     (editor-event kind arg)
 *   highlight  faces for visible text     (highlight-buffer-text file text colors buffer start)
 *   modeline   each window's mode line    (mode-line-pieces name file buffer line flags cols)
 *   change     every change to a text     (record-change id kind pos text)
 *   wrap       visual rows of prose       (markdown-wrap-row file text cols)
 *
 * A Scheme error never unwinds through C: each hook catches it and falls
 * back to the C core's own behaviour.
 */
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include "llt/llt.h"
#include "flisp.h"
extern char *scheme_eval(char *);
extern int scheme_error;
extern void fe_message(char *);
extern void fe_set_hooks(int (*)(const char *, char *, int), int (*)(const char *, const char *), void (*)(const char *, const char *, long, const unsigned char *, int, unsigned char *));
extern void fe_set_modeline_hook(int (*)(const char *, const char *, const char *, int, int, int, char *, int));
extern void fe_set_change_hook(void (*)(long, int, long, const unsigned char *, long));
extern void fe_set_wrap_hook(int (*)(const char *, const unsigned char *, int, int));

static value_t bytes(const void *data, size_t len)
{
	value_t s = cvalue_string(len);
	if (len) memcpy(cvalue_data(s), data, len);
	return s;
}

static value_t procedure(const char *name)
{
	return symbol_value(symbol((char *) name));
}

static int evaluate(const char *expr, char *out, int size)
{
	snprintf(out, (size_t) size, "%s", scheme_eval((char *) expr));
	return !scheme_error;
}

/* compiled-program.c: the compiled program answers first, when it has
 * registered the hook; the femtoscheme scripts answer otherwise */
extern int compiled_event(const char *, const char *);
extern int compiled_highlight(const char *, const char *, long, const unsigned char *, int, unsigned char *);
extern int compiled_modeline(const char *, const char *, const char *, int, int, int, char *, int);
extern int compiled_change(long, int, long, const unsigned char *, long);
extern int compiled_wrap(const char *, const unsigned char *, int, int, int *);

/* flcall.c: the scripts are compiled, femtoscheme runs none of them */
extern int compiled_scripts;

extern int read_mode_event(const char *, const char *);

static int event(const char *kind, const char *arg)
{
	int handled = 0;
	if (read_mode_event(kind, arg)) return 1;
	/* the compiled program first; the femtoscheme scripts get the rest */
	if (compiled_event(kind, arg))
		return 1;
	if (compiled_scripts) return 0;
	value_t a = FL_NIL, b = FL_NIL;
	fl_gc_handle(&a); fl_gc_handle(&b);
	FL_TRY_EXTERN {
		a = cvalue_static_cstring(kind);
		b = bytes(arg, strlen(arg));
		value_t result = fl_applyn(2, procedure("editor-event"), a, b);
		handled = result != FL_F && result != FL_NIL;
	} FL_CATCH_EXTERN {
		fe_message("Scheme command failed; buffer preserved");
		/* a failing key binding must not run the C binding as well */
		handled = strcmp(kind, "self-insert") != 0;
	}
	fl_free_gc_handles(2);
	return handled;
}

static int modeline(const char *name, const char *file, const char *buffer, int line,
		    int flags, int cols, char *out, int size)
{
	int ok = 0;
	value_t a = FL_NIL, f = FL_NIL, b = FL_NIL, r = FL_NIL;
	if (compiled_modeline(name, file, buffer, line, flags, cols, out, size))
		return 1;
	if (compiled_scripts) return 0;
	fl_gc_handle(&a); fl_gc_handle(&f); fl_gc_handle(&b); fl_gc_handle(&r);
	FL_TRY_EXTERN {
		a = bytes(name, strlen(name));
		f = bytes(file ? file : "", file ? strlen(file) : 0);
		b = bytes(buffer ? buffer : "", buffer ? strlen(buffer) : 0);
		r = fl_applyn(6, procedure("mode-line-pieces"),
			      a, f, b, fixnum(line), fixnum(flags), fixnum(cols));
		if (fl_isstring(r)) {
			size_t n = cvalue_len(r);
			if (n >= (size_t) size) {
				n = (size_t) size - 1;
				/* never cut a UTF-8 character in two */
				while (n > 0 && (((unsigned char *) cvalue_data(r))[n] & 0xC0) == 0x80)
					n--;
			}
			memcpy(out, cvalue_data(r), n);
			out[n] = '\0';
			ok = 1;
		}
	} FL_CATCH_EXTERN { }
	fl_free_gc_handles(4);
	return ok;
}

static void changed(long id, int kind, long pos, const unsigned char *text, long len)
{
	value_t value = FL_NIL;
	if (compiled_change(id, kind, pos, text, len) || compiled_scripts)
		return;
	fl_gc_handle(&value);
	FL_TRY_EXTERN {
		value = bytes(text, text ? (size_t) len : 0);
		(void) fl_applyn(4, procedure("record-change"), fixnum(id), fixnum(kind), fixnum(pos), value);
	} FL_CATCH_EXTERN { fe_message("Undo recording failed"); }
	fl_free_gc_handles(1);
}

/* faces for N bytes of S, which start at offset START of the buffer; on
 * any error the default face stays */
static void highlight(const char *file, const char *buffer, long start,
		      const unsigned char *s, int n, unsigned char *colors)
{
	value_t f = FL_NIL, t = FL_NIL, c = FL_NIL, b = FL_NIL;
	memset(colors, 5, (size_t) n);
	if (compiled_highlight(file, buffer, start, s, n, colors) || compiled_scripts)
		return;
	fl_gc_handle(&f); fl_gc_handle(&t); fl_gc_handle(&c); fl_gc_handle(&b);
	FL_TRY_EXTERN {
		f = bytes(file ? file : "", file ? strlen(file) : 0);
		t = bytes(s, (size_t) n);
		c = cvalue_from_data(get_array_type(uint8sym), colors, (size_t) n);
		b = bytes(buffer ? buffer : "", buffer ? strlen(buffer) : 0);
		(void) fl_applyn(5, procedure("highlight-buffer-text"), f, t, c, b, fixnum(start));
		memcpy(colors, cvalue_data(c), (size_t) n);
	} FL_CATCH_EXTERN { }
	fl_free_gc_handles(4);
}

/* bytes in the first visual row of TEXT; -1 "this file wraps"; 0 no wrapping */
static int wrap_row(const char *file, const unsigned char *text, int len, int cols)
{
	int result = 0;
	value_t f = FL_NIL, t = FL_NIL;
	if (compiled_wrap(file, text, len, cols, &result))
		return result;
	if (compiled_scripts) return 0;
	fl_gc_handle(&f); fl_gc_handle(&t);
	FL_TRY_EXTERN {
		f = bytes(file ? file : "", file ? strlen(file) : 0);
		t = text ? bytes(text, (size_t) len) : FL_F;
		value_t r = fl_applyn(3, procedure("markdown-wrap-row"), f, t, fixnum(cols));
		if (isfixnum(r)) result = (int) numval(r);
	} FL_CATCH_EXTERN { result = 0; }
	fl_free_gc_handles(2);
	return result;
}

void scheme_install_hooks(void)
{
	fe_set_hooks(evaluate, event, highlight);
	fe_set_modeline_hook(modeline);
	fe_set_change_hook(changed);
	fe_set_wrap_hook(wrap_row);
}
