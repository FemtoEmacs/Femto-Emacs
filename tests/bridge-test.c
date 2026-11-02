/* bridge-test.c -- compiled Scheme and C call each other (src/bridge.c,
 * compiled/bridge.scm).  make check-bridge */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "../src/bridge.h"

static int failed;
static void check(const char *what, int ok) { printf("%s %s\n", ok ? "ok   " : "FAIL ", what); if (!ok) failed++; }
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec / 1e9; }

static void t_add(bridge_in *in, bridge_out *out) { long a = bridge_int(in), b = bridge_int(in); bridge_put_int(out, a + b); }
static void t_concat(bridge_in *in, bridge_out *out)
{
	char *a = bridge_string(in), *b = bridge_string(in), *r = malloc(strlen(a) + strlen(b) + 1);
	strcpy(r, a); strcat(r, b); bridge_put_string(out, r); free(a); free(b); free(r);
}
static void t_size(bridge_in *in, bridge_out *out) { size_t n; free(bridge_bytes(in, &n)); bridge_put_int(out, (long) n); }
static void t_names(bridge_in *in, bridge_out *out)
{
	(void) in;
	bridge_put_list(out, 3); bridge_put_string(out, "um"); bridge_put_string(out, "dois");
	bridge_put_list(out, 3); bridge_put_int(out, 3); bridge_put_bool(out, 1); bridge_put_bool(out, 0);
}
static void t_fail(bridge_in *in, bridge_out *out) { (void) in; bridge_error(out, "test-fail failed on purpose"); }
static void t_reenter(bridge_in *in, bridge_out *out)
{
	long n = bridge_int(in);
	bridge_in r; char *error = NULL;
	if (bridge_hook(2, &r, &error, "i", n)) bridge_put_int(out, bridge_int(&r));
	else { bridge_error(out, error); free(error); }
}

/* the editor's own functions are not linked in this test */
void bridge_register_editor(void)
{
	bridge_register("test-add", t_add);
	bridge_register("test-concat", t_concat);
	bridge_register("test-size", t_size);
	bridge_register("test-names", t_names);
	bridge_register("test-fail", t_fail);
	bridge_register("test-reenter", t_reenter);
}
void bridge_register_more(void) {}

int main(int argc, char **argv)
{
	FILE *f; long size; unsigned char *bytes; char *error = NULL, *value = NULL, *output = NULL;
	if (argc != 2 || !(f = fopen(argv[1], "rb"))) { fprintf(stderr, "usage: bridge-test program.wasm\n"); return 2; }
	fseek(f, 0, SEEK_END); size = ftell(f); rewind(f);
	bytes = malloc((size_t) size);
	if (fread(bytes, 1, (size_t) size, f) != (size_t) size) return 2;
	fclose(f);
	sc_module *m = sc_module_open(bytes, (size_t) size, NULL, NULL, &error);
	free(bytes);
	if (!m) { printf("FAIL cannot load: %s\n", error); return 1; }
	bridge_attach(m);
	if (!sc_module_run(m, 0, &value, &output, &error)) { printf("FAIL cannot run: %s\n%s\n", error, output); return 1; }

	bridge_in r; char *s = "";
	check("Scheme's own tests, calling C", bridge_hook(3, &r, &error, "") && (s = bridge_string(&r)) && !strcmp(s, "ok"));
	if (strcmp(s, "ok")) printf("      %s\n", s);
	check("C calls Scheme: Unicode and a number", bridge_hook(1, &r, &error, "si", "ação ☃", -7L) && (s = bridge_string(&r)) && !strcmp(s, "ação ☃/-7"));
	{
		static unsigned char big[2000000];
		check("C gives Scheme 2 MB", bridge_hook(6, &r, &error, "b", big, (int) sizeof big) && bridge_int(&r) == (long) sizeof big);
	}
	error = NULL;
	check("Scheme's error comes back as text", !bridge_hook(4, &r, &error, "") && error && strstr(error, "Scheme failed on purpose: 42"));
	if (error) printf("      %s\n", error);
	free(error); error = NULL;
	check("a raised non-error comes back too", !bridge_hook(7, &r, &error, "") && error && strstr(error, "a-symbol"));
	free(error); error = NULL;
	check("an unknown hook is an error", !bridge_hook(9, &r, &error, ""));
	free(error); error = NULL;

	double t0 = now();
	int n = 100000;
	for (int k = 0; k < n; k++) bridge_hook(2, &r, &error, "i", (long) k);
	double t1 = now();
	check("C -> Scheme -> C, 100000 hooks", bridge_int(&r) == n - 1 + 100);
	bridge_hook(5, &r, &error, "i", (long) n);
	double t2 = now();
	check("Scheme -> C, 100000 calls", bridge_int(&r) == n);
	printf("      a hook from C: %.2f us; a C call from Scheme: %.2f us\n", (t1 - t0) / n * 1e6, (t2 - t1) / n * 1e6);
	sc_module_close(m);
	printf(failed ? "%d FAILED\n" : "all passed\n", failed);
	return failed != 0;
}
