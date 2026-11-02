/* femtoscheme for the browser: the WebAssembly entry points.
 *
 * JavaScript calls fs_start once, then fs_eval with Scheme source text.
 * Scheme reaches the page through one primitive, (%host op json-args),
 * which calls Module.host(op, args) and returns its answer as Scheme
 * datum text; web.scm and the embedding's own Scheme code build on it.
 */
#include <stdlib.h>
#include <string.h>
#include <emscripten.h>
#include "llt.h"
#include "flisp.h"

extern value_t fl_file(value_t *args, uint32_t nargs);

/* The host returns a malloc'd UTF-8 string; never NULL. */
EM_JS(char *, fs_js_host, (const char *op, const char *payload), {
    var answer;
    try {
        answer = Module.host ? Module.host(UTF8ToString(op), UTF8ToString(payload)) : "#f";
    } catch (error) {
        answer = "(%host-error " + JSON.stringify(String(error && error.message || error)) + ")";
    }
    if (typeof answer !== "string") answer = "#f";
    var size = lengthBytesUTF8(answer) + 1;
    var pointer = _malloc(size);
    stringToUTF8(answer, pointer, size);
    return pointer;
});

static value_t copy_string(const char *text, size_t length)
{
    value_t s = cvalue_string(length);
    memcpy(cvalue_data(s), text, length);
    return s;
}

static value_t fl_host(value_t *args, uint32_t nargs)
{
    argcount("%host", nargs, 2);
    char *op = tostring(args[0], "%host");
    char *payload = tostring(args[1], "%host");
    char *answer = fs_js_host(op, payload);   /* JS cannot trigger a GC */
    value_t result = copy_string(answer, strlen(answer));
    free(answer);
    return result;
}

static builtinspec_t web_builtins[] = {
    { "%host", fl_host },
    { NULL, NULL }
};

static int started = 0;

/* 0: ready; 1: boot image unreadable; 2: error while starting. */
EMSCRIPTEN_KEEPALIVE int fs_start(void)
{
    if (started) return 0;
    fl_init(4 * 1024 * 1024);
    assign_global_builtins(web_builtins);
    value_t args[2];
    fl_gc_handle(&args[0]);
    fl_gc_handle(&args[1]);
    FL_TRY_EXTERN {
        args[0] = cvalue_static_cstring("/femtoscheme.boot");
        args[1] = symbol(":read");
        value_t f = fl_file(&args[0], 2);
        fl_free_gc_handles(2);
        if (fl_load_system_image(f)) return 1;
        (void)fl_applyn(0, symbol_value(symbol("__init_globals")));
        args[0] = cvalue_static_cstring("/web.scm");
        (void)fl_applyn(1, symbol_value(symbol("load")), args[0]);
    }
    FL_CATCH_EXTERN {
        return 2;
    }
    started = 1;
    return 0;
}

/* Evaluate every form in src. Returns JSON text owned by this module,
 * valid until the next call: {"ok", "output", "value", "error"}. */
EMSCRIPTEN_KEEPALIVE const char *fs_eval(const char *src)
{
    static char *result = NULL;
    free(result);
    result = NULL;
    if (!started) return "{\"ok\":false,\"output\":\"\",\"value\":null,\"error\":\"femtoscheme is not started\"}";
    FL_TRY_EXTERN {
        value_t source = copy_string(src, strlen(src));
        value_t answer = fl_applyn(1, symbol_value(symbol("%web-eval")), source);
        if (fl_isstring(answer)) {
            size_t length = cvalue_len(answer);
            result = malloc(length + 1);
            if (result) {
                memcpy(result, cvalue_data(answer), length);
                result[length] = '\0';
            }
        }
    }
    FL_CATCH_EXTERN {
        result = NULL;
    }
    return result ? result
        : "{\"ok\":false,\"output\":\"\",\"value\":null,\"error\":\"internal error in femtoscheme\"}";
}
