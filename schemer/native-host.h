#ifndef SCHEMER_NATIVE_HOST_H
#define SCHEMER_NATIVE_HOST_H
#include <stddef.h>
typedef struct sc_module sc_module;
typedef char *(*sc_editor_fn)(const char *, void *);
sc_module *sc_module_open(const unsigned char *, size_t, sc_editor_fn, void *, char **);
/* Machine code made once (make): sc_code_save translates the WebAssembly
 * and saves its machine code in a file; sc_module_open_code uses that file
 * when it was made from the same WebAssembly, or translates it as
 * sc_module_open does (CODE_PATH NULL: always). */
int sc_code_save(const unsigned char *, size_t, const char *code_path, char **);
sc_module *sc_module_open_code(const unsigned char *, size_t, const char *code_path, sc_editor_fn, void *, char **);
void sc_module_set_input(sc_module *, const char *);
int sc_module_run(sc_module *, int, char **, char **, char **);
void sc_module_close(sc_module *);
/* The bridge to C (Chezemax): a compiled program that reads and writes the
 * host's memory ((%mem-u8 a), (%mem-u8-set! a b)) gets one, and (%editor N)
 * with a number N calls the host's c-call function with N; arguments and
 * results travel in that memory (compiled/bridge.scm, src/bridge.c). */
typedef int (*sc_ccall_fn)(sc_module *, int, void *);
void sc_module_set_ccall(sc_module *, sc_ccall_fn, void *);
unsigned char *sc_module_memory(sc_module *, size_t *);
int sc_module_reserve(sc_module *, size_t);
/* Call the program's value (a procedure of three numbers, kept after
 * sc_module_run) with A B C: its numeric result, or 0 and *error. */
int sc_module_call3(sc_module *, int, int, int, int *, char **);
#endif
