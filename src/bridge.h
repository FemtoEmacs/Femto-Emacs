/*
 * bridge.h -- the C core and compiled Scheme (compiled/bridge.scm)
 *
 * Compiled Scheme calls a C function of this table by number, with its
 * arguments in the memory the two share; C calls Scheme's hooks the same
 * way.  The encoding is described in compiled/bridge.scm.
 */
#ifndef CHEZEMAX_BRIDGE_H
#define CHEZEMAX_BRIDGE_H
#include <stddef.h>
#include "../schemer/native-host.h"

/* the arguments of a call, read in order */
typedef struct {
	const unsigned char *p, *end;
	int count, bad;
} bridge_in;

/* the result, written in a buffer of its own, then into the memory */
typedef struct {
	unsigned char *data;      /* small[] until it grows */
	size_t len, cap;
	int count;
	char *error;
	unsigned char small[256];
} bridge_out;
#define BRIDGE_OUT_INIT(o) do { (o).data = (o).small; (o).len = 0; (o).cap = sizeof (o).small; \
	(o).count = 0; (o).error = NULL; } while (0)
#define BRIDGE_OUT_FREE(o) do { if ((o).data != (o).small) free((o).data); free((o).error); } while (0)

/* the kind of the next value, without reading it */
enum { BRIDGE_FALSE, BRIDGE_TRUE, BRIDGE_INT, BRIDGE_STRING, BRIDGE_BYTES, BRIDGE_LIST, BRIDGE_NOTHING };
int bridge_kind(const bridge_in *);
long bridge_int(bridge_in *);                       /* an integer (#f is 0, #t 1) */
char *bridge_string(bridge_in *);                   /* malloc'd, NUL-terminated */
unsigned char *bridge_bytes(bridge_in *, size_t *); /* malloc'd */
long bridge_list(bridge_in *);                      /* a list: its length, then its values */
void bridge_skip(bridge_in *);                      /* the next value, unread */

void bridge_put_int(bridge_out *, long);
void bridge_put_bool(bridge_out *, int);
void bridge_put_string(bridge_out *, const char *);   /* NULL: "" */
void bridge_put_string_n(bridge_out *, const char *, size_t);   /* UTF-8 bytes, NULs too */
void bridge_put_bytes(bridge_out *, const unsigned char *, size_t);
void bridge_put_nothing(bridge_out *);
void bridge_put_list(bridge_out *, int count);        /* then COUNT values */
void bridge_error(bridge_out *, const char *);

typedef void (*bridge_fn)(bridge_in *, bridge_out *);
/* Make a C function callable from Scheme under NAME (a Scheme name,
 * fe-insert); the table also holds the editor's own (bridge-functions.c). */
void bridge_register(const char *name, bridge_fn);
void bridge_register_more(void);                    /* bridge-more.c */
void bridge_set_install_dir(const char *);          /* for (fe-install-dir) */

/* Install the bridge on a module that runs compiled Scheme. */
void bridge_attach(sc_module *);

/* Call Scheme's hook N with the arguments described by FORMAT, one letter
 * each: i long, s string (char *), b bytes (const unsigned char *, int).
 * Returns 1 and the result in *RESULT (bridge_result_* read it), or 0 and
 * an error message in *ERROR (malloc'd). */
int bridge_hook(int n, bridge_in *result, char **error, const char *format, ...);

/* The hooks' numbers, as compiled/editor.scm registers them */
enum { BRIDGE_HOOK_EVENT = 1, BRIDGE_HOOK_HIGHLIGHT, BRIDGE_HOOK_MODELINE,
       BRIDGE_HOOK_CHANGE, BRIDGE_HOOK_WRAP, BRIDGE_HOOK_EVAL,
       BRIDGE_HOOK_REQUEST };
#endif
