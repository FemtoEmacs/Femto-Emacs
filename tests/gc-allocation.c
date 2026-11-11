/* Exercise many separate C -> Scheme calls in one store, without forced GC. */
#include "../schemer/native-host.h"
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv)
{
    if (argc != 2) return 2;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 2;
    if (fseek(f, 0, SEEK_END)) { fclose(f); return 2; }
    long size = ftell(f);
    if (size <= 0 || fseek(f, 0, SEEK_SET)) { fclose(f); return 2; }
    unsigned char *bytes = malloc((size_t)size);
    if (!bytes) { fclose(f); return 2; }
    int read_ok = fread(bytes, 1, (size_t)size, f) == (size_t)size;
    fclose(f);
    if (!read_ok) { free(bytes); return 2; }
    char *error = NULL, *value = NULL, *output = NULL;
    sc_module *module = sc_module_open(bytes, (size_t)size, NULL, NULL, &error);
    free(bytes);
    int ok = module && sc_module_run(module, 0, &value, &output, &error);
    unsigned call = 0;
    for (; ok && call < 100000; call++) {
        int result = 0;
        ok = sc_module_call3(module, 0, 0, 0, &result, &error);
        if (ok && result != 24000) { fprintf(stderr, "Unexpected length: %d\n", result); ok = 0; }
    }
    if (!ok) fprintf(stderr, "GC regression at call %u: %s\n", call, error ? error : "startup/length failure");
    else puts("PASS recursive closure semantics and 100000 allocations in one store (no forced GC)");
    sc_module_close(module);
    free(error); free(value); free(output);
    return ok ? 0 : 1;
}
