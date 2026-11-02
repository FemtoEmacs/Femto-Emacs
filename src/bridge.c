/*
 * bridge.c -- the C core and compiled Scheme (see bridge.h and
 * compiled/bridge.scm)
 */
#include <stdarg.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "bridge.h"

enum { T_FALSE, T_TRUE, T_INT, T_STRING, T_BYTES, T_LIST, T_NOTHING };

/* ------------------------------------------------------------------ */
/* reading                                                            */
/* ------------------------------------------------------------------ */

static long get32(bridge_in *in)
{
	if (in->end - in->p < 4) {
		in->bad = 1;
		return 0;
	}
	uint32_t u = (uint32_t) in->p[0] | (uint32_t) in->p[1] << 8 |
		     (uint32_t) in->p[2] << 16 | (uint32_t) in->p[3] << 24;
	in->p += 4;
	return (long) (int32_t) u;
}

static int tag(bridge_in *in)
{
	if (in->p >= in->end) {
		in->bad = 1;
		return T_NOTHING;
	}
	return *in->p++;
}

static void skip(bridge_in *in, int t)
{
	long n;
	switch (t) {
	case T_INT: get32(in); break;
	case T_STRING: case T_BYTES:
		n = get32(in);
		if (n < 0 || n > in->end - in->p) { in->bad = 1; in->p = in->end; }
		else in->p += n;
		break;
	case T_LIST:
		n = get32(in);
		while (n-- > 0 && !in->bad)
			skip(in, tag(in));
		break;
	default: break;
	}
}

int bridge_kind(const bridge_in *in)
{
	return in->p < in->end ? *in->p : T_NOTHING;
}

long bridge_int(bridge_in *in)
{
	int t = tag(in);
	if (t == T_INT) return get32(in);
	if (t == T_TRUE) return 1;
	if (t != T_FALSE && t != T_NOTHING) { skip(in, t); in->bad = 1; }
	return 0;
}

unsigned char *bridge_bytes(bridge_in *in, size_t *size)
{
	int t = tag(in);
	unsigned char *b;
	long n = 0;
	if (t == T_STRING || t == T_BYTES) {
		n = get32(in);
		if (n < 0 || n > in->end - in->p) { in->bad = 1; n = 0; }
	} else {
		skip(in, t);
		if (t != T_FALSE) in->bad = 1;
	}
	b = malloc((size_t) n + 1);
	if (!b) abort();
	if (n) memcpy(b, in->p, (size_t) n);
	b[n] = 0;
	in->p += n;
	if (size) *size = (size_t) n;
	return b;
}

char *bridge_string(bridge_in *in)
{
	return (char *) bridge_bytes(in, NULL);
}

long bridge_list(bridge_in *in)
{
	int t = tag(in);
	if (t == T_LIST) {
		long n = get32(in);
		if (n < 0) { in->bad = 1; return 0; }
		return n;
	}
	if (t != T_FALSE && t != T_NOTHING) { skip(in, t); in->bad = 1; }
	return 0;
}

void bridge_skip(bridge_in *in)
{
	skip(in, tag(in));
}

/* ------------------------------------------------------------------ */
/* writing                                                            */
/* ------------------------------------------------------------------ */

static void room(bridge_out *out, size_t n)
{
	if (out->len + n > out->cap) {
		size_t cap = (out->len + n) * 2 + 64;
		unsigned char *d = out->data == out->small ? malloc(cap) : realloc(out->data, cap);
		if (!d) abort();
		if (out->data == out->small) memcpy(d, out->small, out->len);
		out->data = d;
		out->cap = cap;
	}
}

static void put8(bridge_out *out, int b) { room(out, 1); out->data[out->len++] = (unsigned char) b; }

static void put32(bridge_out *out, long v)
{
	uint32_t u = (uint32_t) v;
	room(out, 4);
	for (int k = 0; k < 4; k++) out->data[out->len++] = (unsigned char) (u >> (8 * k));
}

void bridge_put_int(bridge_out *out, long v) { out->count++; put8(out, T_INT); put32(out, v); }
void bridge_put_bool(bridge_out *out, int v) { out->count++; put8(out, v ? T_TRUE : T_FALSE); }
void bridge_put_nothing(bridge_out *out) { out->count++; put8(out, T_NOTHING); }
void bridge_put_list(bridge_out *out, int count) { out->count++; put8(out, T_LIST); put32(out, count); out->count -= count; }

void bridge_put_bytes(bridge_out *out, const unsigned char *s, size_t n)
{
	out->count++;
	put8(out, T_BYTES);
	put32(out, (long) n);
	room(out, n);
	if (n) memcpy(out->data + out->len, s, n);
	out->len += n;
}

void bridge_put_string(bridge_out *out, const char *s)
{
	bridge_put_string_n(out, s ? s : "", s ? strlen(s) : 0);
}

void bridge_put_string_n(bridge_out *out, const char *s, size_t n)
{
	bridge_put_bytes(out, (const unsigned char *) s, n);
	out->data[out->len - n - 5] = T_STRING;
}

void bridge_error(bridge_out *out, const char *message)
{
	free(out->error);
	out->error = strdup(message ? message : "C function failed");
}

/* the count, then the values, into the mailbox; 0 if it does not fit */
static int deliver(sc_module *m, bridge_out *out)
{
	size_t size;
	unsigned char *mem;
	if (!sc_module_reserve(m, out->len + 4)) return 0;
	mem = sc_module_memory(m, &size);
	if (!mem || size < out->len + 4) return 0;
	for (int k = 0; k < 4; k++) mem[k] = (unsigned char) ((uint32_t) out->count >> (8 * k));
	if (out->len) memcpy(mem + 4, out->data, out->len);
	return 1;
}

/* ------------------------------------------------------------------ */
/* the table of C functions                                           */
/* ------------------------------------------------------------------ */

typedef struct { char *name; bridge_fn fn; } entry;
static entry *table;
static int ntable, ctable;

void bridge_register(const char *name, bridge_fn fn)
{
	for (int k = 0; k < ntable; k++)
		if (!strcmp(table[k].name, name)) { table[k].fn = fn; return; }
	if (ntable == ctable) {
		ctable = ctable ? 2 * ctable : 256;
		table = realloc(table, (size_t) ctable * sizeof *table);
		if (!table) abort();
	}
	table[ntable].name = strdup(name);
	table[ntable].fn = fn;
	ntable++;
}

extern void bridge_register_editor(void);   /* bridge-functions.c */
static int registered;

/* Scheme called C function N; its arguments are in the mailbox */
static int ccall(sc_module *m, int n, void *user)
{
	size_t size;
	unsigned char *mem = sc_module_memory(m, &size), *copy, local[512];
	bridge_in in;
	bridge_out out;
	int status = 0;
	long count;
	(void) user;
	BRIDGE_OUT_INIT(out);

	if (!mem || size < 4) return 1;
	if (n == -1) {          /* room for this many bytes; the new size */
		long want = (long) ((uint32_t) mem[0] | (uint32_t) mem[1] << 8 |
				    (uint32_t) mem[2] << 16 | (uint32_t) mem[3] << 24);
		sc_module_reserve(m, (size_t) want);
		sc_module_memory(m, &size);
		return size > 0x3fffffff ? 0x3fffffff : (int) size;
	}
	/* copy the arguments out first: the function may call Scheme again */
	{
		bridge_in head = { mem, mem + size, 0, 0 };
		count = get32(&head);
		bridge_in probe = { mem + 4, mem + size, 0, 0 };
		for (long k = 0; k < count && !probe.bad; k++) skip(&probe, tag(&probe));
		size_t len = (size_t) (probe.p - (mem + 4));
		copy = len < sizeof local ? local : malloc(len + 1);
		if (!copy) abort();
		memcpy(copy, mem + 4, len);
		in.p = copy; in.end = copy + len; in.count = (int) count; in.bad = probe.bad;
	}
	if (n == 0) {           /* the number of the function named by the string */
		char *name = bridge_string(&in);
		int found = 0;
		for (int k = 0; k < ntable; k++)
			if (!strcmp(table[k].name, name)) { found = k + 1; break; }
		free(name);
		bridge_put_int(&out, found);
	} else if (n > 0 && n <= ntable && !in.bad) {
		table[n - 1].fn(&in, &out);
		if (in.bad && !out.error) bridge_error(&out, "a C function got an argument of the wrong type");
	} else {
		bridge_error(&out, "no such C function");
	}
	if (copy != local) free(copy);
	if (out.error) {
		bridge_out e;
		BRIDGE_OUT_INIT(e);
		bridge_put_string(&e, out.error);
		deliver(m, &e);
		BRIDGE_OUT_FREE(e);
		status = 1;
	} else if (!deliver(m, &out)) {
		status = 1;
	}
	BRIDGE_OUT_FREE(out);
	return status;
}

static sc_module *attached;

void bridge_attach(sc_module *m)
{
	if (!registered) { registered = 1; bridge_register_editor(); bridge_register_more(); }
	attached = m;
	sc_module_set_ccall(m, ccall, NULL);
}

/* ------------------------------------------------------------------ */
/* calling Scheme's hooks                                             */
/* ------------------------------------------------------------------ */

static unsigned char *last_result;   /* the last hook's result, copied */
static size_t last_cap;

int bridge_hook(int n, bridge_in *result, char **error, const char *format, ...)
{
	bridge_out out;
	va_list ap;
	int status = 1, answer;
	size_t size;
	unsigned char *mem;

	if (!attached) { *error = strdup("No compiled Scheme program"); return 0; }
	BRIDGE_OUT_INIT(out);
	va_start(ap, format);
	for (const char *f = format; *f; f++) {
		if (*f == 'i') bridge_put_int(&out, va_arg(ap, long));
		else if (*f == 's') bridge_put_string(&out, va_arg(ap, const char *));
		else if (*f == 'b') {
			const unsigned char *b = va_arg(ap, const unsigned char *);
			int len = va_arg(ap, int);
			bridge_put_bytes(&out, b, (size_t) len);
		}
	}
	va_end(ap);
	if (!deliver(attached, &out)) {
		BRIDGE_OUT_FREE(out);
		*error = strdup("No room in the bridge's memory");
		return 0;
	}
	BRIDGE_OUT_FREE(out);
	/* the depth of hooks running: at 0 the program starts afresh, even
	 * after a call that a trap ended in the middle (compiled/bridge.scm) */
	{
		static int depth;
		int ok;
		depth++;
		ok = sc_module_call3(attached, n, depth - 1, 0, &answer, error);
		depth--;
		if (!ok) return 0;
	}
	/* copy the result out at once: the next call reuses the mailbox */
	mem = sc_module_memory(attached, &size);
	{
		bridge_in head = { mem, mem + size, 0, 0 };
		long count = get32(&head);
		bridge_in probe = { mem + 4, mem + size, 0, 0 };
		for (long k = 0; k < count && !probe.bad; k++) skip(&probe, tag(&probe));
		size_t len = (size_t) (probe.p - (mem + 4));
		if (len + 1 > last_cap) {
			free(last_result);
			last_cap = 2 * len + 256;
			last_result = malloc(last_cap);
			if (!last_result) abort();
		}
		memcpy(last_result, mem + 4, len);
		result->p = last_result; result->end = last_result + len;
		result->count = (int) count; result->bad = probe.bad;
	}
	if (answer != 0) {
		char *message = bridge_string(result);
		*error = message;
		status = 0;
	}
	return status;
}
