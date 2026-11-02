/* Embedded femtoscheme adapter. The editor owns main; no SBCL or REPL process. */
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include "llt/llt.h"
#include "flisp.h"
extern void interface_init(void);
extern value_t fl_file(value_t *, uint32_t);
extern value_t fl_buffer(value_t *, uint32_t);
extern value_t fl_iowrite(value_t *, uint32_t);
extern value_t fl_ioseek(value_t *, uint32_t);
extern value_t fl_read(value_t *, uint32_t);
int scheme_error = 0;
/* --eval (app.c): a compiled program that raised an error has already
   printed "Error: ..."; then nothing more is printed */
int scheme_eval_quiet = 0;

/* the error is a compiled Schemer program's own raise */
static int program_raised(value_t e)
{
    if (!iscons(e) || !iscons(cdr_(e)) || !fl_isstring(car_(cdr_(e)))) return 0;
    return strstr((char *)cvalue_data(car_(cdr_(e))), "Scheme program raised an error") != NULL;
}
static char result[8192];

/* The scripts run compiled (chezemax.wasm, compiled/start.scm): then
 * femtoscheme loads none of them, and every hook and evaluation goes to the
 * compiled program.  CHEZEMAX_SCHEME=femtoscheme (or legacy) runs them in
 * femtoscheme as before; so does a program that did not load. */
int compiled_scripts = 0;
extern int compiled_scripts_running(void);
extern char *compiled_eval(const char *, int *, char **);

static char *compiled_scheme_eval(char *expr)
{
    int ok;
    char *output = NULL;
    char *text = compiled_eval(expr, &ok, &output);
    /* --eval: what it printed goes out first; in the editor it is dropped */
    if (scheme_eval_quiet && output && *output) { fputs(output, stdout); if (output[strlen(output) - 1] != '\n') fputc('\n', stdout); }
    if (ok) snprintf(result, sizeof result, "%s", text);
    else snprintf(result, sizeof result, "Error: %s", text);
    scheme_error = !ok;
    free(text);
    free(output);
    return result;
}

char *scheme_eval(char *expr)
{
    if (compiled_scripts) return compiled_scheme_eval(expr);
    {
    int compiled = symbol_value(symbol("schemer-eval-string")) != UNBOUND &&
                   symbol_value(symbol("*schemer-enabled*")) != FL_F;
    char *source = malloc(strlen(expr) * 2 + 256);
    if (!source) { scheme_error = 1; return "Out of memory"; }
    if (compiled) {
        char *quoted = malloc(strlen(expr) * 2 + 1), *q = quoted;
        if (!quoted) { free(source); scheme_error=1; return "Out of memory"; }
        for (const unsigned char *p=(const unsigned char *)expr; *p; p++) {
            if (*p=='\\' || *p=='"') { *q++='\\'; *q++=*p; }
            else if (*p=='\n') { *q++='\\'; *q++='n'; }
            else if (*p=='\r') { *q++='\\'; *q++='r'; }
            else if (*p=='\t') { *q++='\\'; *q++='t'; }
            else *q++=*p;
        }
        *q=0;
        sprintf(source, "(let ((b (open-output-string))) (write (schemer-eval-string \"%s\") b) (get-output-string b))", quoted);
        free(quoted);
    } else sprintf(source, "(let ((b (open-output-string))) (write (begin %s) b) (get-output-string b))", expr);
    scheme_error = 0;
    value_t port = FL_NIL, value = FL_NIL;
    fl_gc_handle(&port);
    fl_gc_handle(&value);
    FL_TRY_EXTERN {
        port = fl_buffer(NULL, 0);
        value_t args[2] = {port, cvalue_static_cstring(source)};
        fl_iowrite(args, 2);
        args[1] = fixnum(0);
        fl_ioseek(args, 2);
        value = fl_read(&port, 1);
        value = fl_toplevel_eval(value);
        snprintf(result, sizeof(result), "%s", (char *)cvalue_data(value));
    } FL_CATCH_EXTERN {
        scheme_error = 1;
        if (scheme_eval_quiet && compiled && program_raised(fl_lasterror)) {
            result[0] = '\0';
        } else {
            snprintf(result, sizeof(result), "Scheme evaluation failed");
            fl_print(ios_stderr, fl_lasterror);
            ios_putc('\n', ios_stderr);
        }
    }
    fl_free_gc_handles(2);
    free(source);
    return result;
    }
}

extern void compiled_program_init(const char *);

int init_scheme(int heap_k)
{
    fl_init((size_t)heap_k * 1024);
    value_t args[2];
    args[0] = FL_NIL; args[1] = FL_NIL;
    fl_gc_handle(&args[0]); fl_gc_handle(&args[1]);
    FL_TRY_EXTERN {
        value_t install = symbol_value(symbol("*install-dir*"));
        const char *directory = install == UNBOUND ? "." : cvalue_data(install);
        char path[4096];
        snprintf(path, sizeof(path), "%s/femtoscheme/femtoscheme.boot", directory);
        args[0] = cvalue_static_cstring(path);
        args[1] = symbol(":read");
        value_t file = fl_file(args, 2);
        if (fl_load_system_image(file)) exit(1);
        interface_init();
        install = symbol_value(symbol("*install-dir*"));
        directory = install == UNBOUND ? "." : cvalue_data(install);
        compiled_program_init(directory);   /* chezemax.wasm, compiled-program.c */
        {
            const char *mode = getenv("CHEZEMAX_SCHEME");
            int wanted = !mode || !*mode || strcmp(mode, "compiled") == 0;
            compiled_scripts = wanted && compiled_scripts_running();
        }
        /* the program has started: now your files (compiled/start.scm) */
        if (compiled_scripts) {
            extern int compiled_event(const char *, const char *);
            compiled_event("init", "");
        }
        if (!compiled_scripts) {
            snprintf(path, sizeof(path), "%s/scheme/init.scm", directory);
            args[0] = cvalue_static_cstring(path);
            (void)fl_applyn(1, symbol_value(symbol("load")), args[0]);
        }
    } FL_CATCH_EXTERN {
        ios_puts("femtoscheme initialization failed:\n", ios_stderr);
        fl_print(ios_stderr, fl_lasterror);
        exit(1);
    }
    fl_free_gc_handles(2);
    return 0;
}
