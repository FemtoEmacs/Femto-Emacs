/*
 * compiled-eval.c -- M-:, C-x C-e and --eval compiled by Schemer
 *
 * (eval-compiled SOURCE GLOBALS) compiles SOURCE, Scheme text, into a small
 * program of its own and runs it at full speed (compiled/eval.scm decides
 * what is compiled).  The compiler runs here, in the editor's process, from
 * its saved machine code (schemer/compiler.cwasm): under a second, where
 * starting schemer-compile translated the compiler first (some 17 s).
 *
 * The program cannot change the editor: it calls the editor's procedures
 * by name, with data, as text -- "(insert \"Hello\")" -- and the answer
 * comes back as text ("ok VALUE", "error MESSAGE"), through the compiled
 * editor's hook BRIDGE_HOOK_REQUEST (compiled/eval.scm).  GLOBALS are the
 * editor's variables it reads.  Answers (ok VALUE OUTPUT) or
 * (#f ERROR OUTPUT).
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include "bridge.h"

extern const char *bridge_install_dir(void);

static unsigned char *compiler_bytes;   /* compiler.wasm, read once */
static sc_module *compiler;             /* the compiler, kept */
static int compiler_warm;               /* it has compiled: call it again (call0) */
static size_t compiler_size;

static char *read_whole(const char *path, size_t *size)
{
	FILE *f = fopen(path, "rb");
	char *s;
	long n;
	if (!f) return NULL;
	fseek(f, 0, SEEK_END);
	n = ftell(f);
	rewind(f);
	s = malloc((size_t) n + 1);
	if (!s || fread(s, 1, (size_t) n, f) != (size_t) n) { fclose(f); free(s); return NULL; }
	fclose(f);
	s[n] = 0;
	*size = (size_t) n;
	return s;
}

/* the compiler's request: (SOURCE (GLOBAL ...) () #f #t), the last #t
 * letting names it does not know be the editor's procedures (link.scm) */
static char *request_text(const char *source, char **globals, long nglobals)
{
	size_t n = strlen(source) * 2 + 64;
	for (long k = 0; k < nglobals; k++) n += strlen(globals[k]) + 1;
	char *r = malloc(n), *p = r;
	if (!r) abort();
	*p++ = '(';
	*p++ = '"';
	for (const char *s = source; *s; s++) {
		if (*s == '"' || *s == '\\') { *p++ = '\\'; *p++ = *s; }
		else if (*s == '\n') { *p++ = '\\'; *p++ = 'n'; }
		else if (*s == '\r') { *p++ = '\\'; *p++ = 'r'; }
		else if (*s == '\t') { *p++ = '\\'; *p++ = 't'; }
		else *p++ = *s;
	}
	*p++ = '"';
	*p++ = ' ';
	*p++ = '(';
	for (long k = 0; k < nglobals; k++) {
		if (k) *p++ = ' ';
		strcpy(p, globals[k]);
		p += strlen(globals[k]);
	}
	strcpy(p, ") () #f #t)");
	return r;
}

static int nibble(char c)
{
	if (c >= '0' && c <= '9') return c - '0';
	if (c >= 'a' && c <= 'f') return c - 'a' + 10;
	return -1;
}

/* compiler.wasm, read once */
static int load_compiler(void)
{
	char path[4200];
	if (!compiler_bytes) {
		snprintf(path, sizeof path, "%s/schemer/compiler.wasm", bridge_install_dir());
		compiler_bytes = (unsigned char *) read_whole(path, &compiler_size);
	}
	return compiler_bytes != NULL;
}

/* SOURCE compiled: the bytes of its program, or NULL and *ERROR */
static unsigned char *compile_source(const char *request, size_t *size, char **error)
{
	char code[4200], *value = NULL, *output = NULL;
	const char *install = bridge_install_dir();
	unsigned char *wasm = NULL;
	if (!load_compiler()) { *error = strdup("cannot read schemer/compiler.wasm beside the editor"); return NULL; }
	/* one compiler, kept: after its first request it compiles the next
	 * ones without expanding the library again (schemer/compiler-main.scm) */
	if (!compiler) {
		snprintf(code, sizeof code, "%s/schemer/compiler.cwasm", install);
		compiler = sc_module_open_code(compiler_bytes, compiler_size, code, NULL, NULL, error);
		if (!compiler) return NULL;
		compiler_warm = 0;
	}
	sc_module_set_input(compiler, request);
	if (!sc_module_run(compiler, compiler_warm, &value, &output, error)) {
		/* the compiler's own "Error: ..." is in its output */
		if (output && *output) { free(*error); *error = output; output = NULL; }
	} else {
		size_t n = strlen(output);
		compiler_warm = 1;
		if (n < 16 || (n & 1) || strncmp(output, "0061736d", 8)) {
			*error = strdup("the compiler did not make a program");
		} else {
			wasm = malloc(n / 2);
			if (!wasm) abort();
			for (size_t k = 0; k < n; k += 2) wasm[k / 2] = (unsigned char) (nibble(output[k]) * 16 + nibble(output[k + 1]));
			*size = n / 2;
		}
	}
	free(value);
	free(output);
	return wasm;
}

/* the program calls the editor: the request goes to the compiled editor */
static char *editor_request(const char *text, void *user)
{
	bridge_in r;
	char *error = NULL;
	(void) user;
	if (!bridge_hook(BRIDGE_HOOK_REQUEST, &r, &error, "s", text)) {
		size_t n = strlen(error ? error : "failed") + 8;
		char *reply = malloc(n);
		snprintf(reply, n, "error %s", error ? error : "failed");
		free(error);
		return reply;
	}
	return bridge_string(&r);
}

/* FNV-1a, 64 bits */
static unsigned long long fnv(const unsigned char *p, size_t n, unsigned long long h)
{
	for (size_t k = 0; k < n; k++) { h ^= p[k]; h *= 1099511628211ULL; }
	return h;
}

/* Your files are compiled once: the program, and its machine code, kept in
 * ~/.chezemax/cache under the fingerprint of the request and the compiler;
 * the next start finds them there */
static void cache_paths(const char *request, char *wasm, char *code, size_t size)
{
	const char *home = getenv("HOME");
	char dir[4096];
	unsigned long long h = fnv((const unsigned char *) request, strlen(request), 1469598103934665603ULL);
	h = fnv(compiler_bytes, compiler_size, h);
	snprintf(dir, sizeof dir, "%s/.chezemax", home && *home ? home : ".");
	mkdir(dir, 0755);
	snprintf(dir, sizeof dir, "%s/.chezemax/cache", home && *home ? home : ".");
	mkdir(dir, 0755);
	snprintf(wasm, size, "%s/%016llx.wasm", dir, h);
	snprintf(code, size, "%s/%016llx.cwasm", dir, h);
}

/* (eval-compiled source (global-name ...) cache?) */
static void b_eval_compiled(bridge_in *in, bridge_out *out)
{
	char *source = bridge_string(in), *error = NULL, *value = NULL, *output = NULL;
	long nglobals = bridge_list(in);
	char **globals = calloc((size_t) (nglobals > 0 ? nglobals : 1), sizeof *globals);
	size_t size = 0;
	unsigned char *wasm = NULL;
	char cached[4200], code[4200];
	for (long k = 0; k < nglobals; k++) globals[k] = bridge_string(in);
	int cache = (int) bridge_int(in);
	char *request = request_text(source, globals, nglobals);
	code[0] = 0;
	if (cache) {
		load_compiler();
		cache_paths(request, cached, code, sizeof cached);
		wasm = (unsigned char *) read_whole(cached, &size);
	}
	if (!wasm) {
		wasm = compile_source(request, &size, &error);
		if (wasm && cache) {
			char temp[4300];
			FILE *f;
			snprintf(temp, sizeof temp, "%s.tmp", cached);
			f = fopen(temp, "wb");
			if (f) {
				int ok = fwrite(wasm, 1, size, f) == size;
				if (fclose(f) == 0 && ok) rename(temp, cached); else remove(temp);
			}
			char *e = NULL;
			if (!sc_code_save(wasm, size, code, &e)) free(e);
		}
	}
	free(request);
	free(source);
	for (long k = 0; k < nglobals; k++) free(globals[k]);
	free(globals);
	if (!wasm) {
		bridge_put_list(out, 3);
		bridge_put_bool(out, 0);
		bridge_put_string(out, error ? error : "compilation failed");
		bridge_put_string(out, "");
		free(error);
		return;
	}
	sc_module *m = sc_module_open_code(wasm, size, code[0] ? code : NULL, editor_request, NULL, &error);
	free(wasm);
	int ok = m && sc_module_run(m, 0, &value, &output, &error);
	bridge_put_list(out, 3);
	bridge_put_bool(out, ok);
	bridge_put_string(out, ok ? (value ? value : "") : (error ? error : "failed"));
	bridge_put_string(out, output ? output : "");
	if (m) sc_module_close(m);
	free(value);
	free(output);
	free(error);
}

void bridge_register_eval(void)
{
	bridge_register("eval-compiled", b_eval_compiled);
}
