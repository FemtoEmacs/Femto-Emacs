/* CI diagnosis of the real ConPTY transport, with and without an outer PTY. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "terminal-windows.h"

static void activate_wasmtime(const char *path)
{
    HMODULE dll = LoadLibraryA(path);
    if (!dll) { fprintf(stderr, "LoadLibrary: %lu\n", GetLastError()); exit(2); }
    void *(*engine_new)(void) = (void *)GetProcAddress(dll, "wasm_engine_new");
    void *(*module_new)(void *, const unsigned char *, size_t, void **) =
        (void *)GetProcAddress(dll, "wasmtime_module_new");
    if (!engine_new || !module_new) exit(2);
    static const unsigned char wasm[] = {0,97,115,109,1,0,0,0};
    void *engine = engine_new(), *module = NULL;
    if (!engine || module_new(engine, wasm, sizeof wasm, &module)) exit(2);
    puts("Wasmtime activated before ConPTY");
}

int main(int argc, char **argv)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    if (argc < 2) return 2;
    activate_wasmtime(argv[1]);
    setenv("PROMPT", "TRANSPORT-PROMPT>", 1);
    windows_terminal *term;
    const char *error = windows_terminal_open(&term, 24, 80);
    if (error) { fprintf(stderr, "%s (%lu)\n", error, GetLastError()); return 2; }
    puts("ConPTY opened");
    char seen[65536] = {0}, bytes[16384];
    size_t have = 0;
    int state = 0, code = 0;
    ULONGLONG end = GetTickCount64() + 20000;
    while (GetTickCount64() < end) {
        int n = windows_terminal_read(term, bytes, sizeof bytes);
        if (n > 0) {
            if (have + (size_t)n >= sizeof seen) have = 0;
            memcpy(seen + have, bytes, n); have += n; seen[have] = 0;
        }
        if (state == 0 && strstr(seen, "TRANSPORT-PROMPT>")) {
            puts("Shell prompt received");
            if (argc > 2 && !strcmp(argv[2], "outer")) {
                char line[20]; puts("OUTER-INPUT-READY");
                if (!fgets(line, sizeof line, stdin)) return 3;
                puts("Outer PTY input received");
            }
            const char *command = "set \"PROBE_TAIL=-OK\"\recho PROBE-CON%PROBE_TAIL%\r";
            if (!windows_terminal_send(term, command, strlen(command))) return 4;
            puts("Command queued"); state = 1;
        }
        if (state == 1 && strstr(seen, "PROBE-CON-OK")) {
            puts("Command result received");
            if (!windows_terminal_send(term, "exit 7\r", 7)) return 4;
            state = 2;
        }
        if (state == 2 && windows_terminal_status(term, &code)) {
            printf("Shell exit status: %d\n", code);
            windows_terminal_close(term);
            if (code != 7) return 5;
            puts("PASS transport probe"); return 0;
        }
        if (n < 0 && state != 2) break;
        Sleep(10);
    }
    fprintf(stderr, "Transport stalled at state %d; last output:\n%s\n", state, seen);
    return 6;
}
