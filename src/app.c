/* C owns startup and the editor loop; Scheme supplies editor policies. */
#include "header.h"
extern int init_scheme(int);
extern char *scheme_eval(char *);
extern int scheme_error, scheme_eval_quiet;
extern void scheme_install_hooks(void);
extern int compile_scripts(const char *, const char *);
extern char *get_exename(char *, size_t);
/* this executable, for M-x compile-scripts (fe-program-path, bridge-more.c) */
char chezemax_program_path[4096];
int main(int argc, char **argv)
{
    if (!get_exename(chezemax_program_path, sizeof chezemax_program_path))
        snprintf(chezemax_program_path, sizeof chezemax_program_path, "%s", argv[0]);
    /* chezemax --compile-scripts [LOG]: the scripts, and yours, compiled
       into ~/.chezemax (compile-scripts.c); the editor does not start */
    if ((argc == 2 || argc == 3) && strcmp(argv[1], "--compile-scripts") == 0) {
        char install[4096];
        snprintf(install, sizeof install, "%s", chezemax_program_path);
        char *slash = strrchr(install, '/');
        if (slash) *slash = '\0'; else strcpy(install, ".");
        return compile_scripts(install, argc == 3 ? argv[2] : NULL);
    }
#ifndef SBEMACS_GUI
    if (argc > 1 && strcmp(argv[1], "--gui") == 0) {
        char path[4096], resolved[4096];
        if (!realpath(argv[0], resolved)) return 1;
        char *slash = strrchr(resolved, '/');
        if (!slash) return 1;
        *slash = '\0';
        snprintf(path, sizeof(path), "%s/chezemax-gui", resolved);
        argv[1] = path;
        execv(path, argv + 1);
        perror("Chezemax GUI backend"); return 1;
    }
#endif
    if (argc == 2 && strcmp(argv[1], "--version") == 0) { puts(VERSION); return 0; }
    init_scheme(1024);
    if (argc == 3 && strcmp(argv[1], "--eval") == 0) {
        /* a *scratch* buffer (no window, no screen), so that buffer
           functions work in --eval too (tests/run-bridge.sh) */
        if (curbp == NULL)
            curbp = find_buffer(str_scratch, TRUE);
        scheme_eval_quiet = 1;
        char *answer = scheme_eval(argv[2]);
        if (!scheme_error || *answer) puts(answer);
        return scheme_error ? 1 : 0;
    }
    scheme_install_hooks();
    return fe_main(argc, argv);
}
