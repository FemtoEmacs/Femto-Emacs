#ifndef CHEZWEB_PROCESS_WINDOWS_H
#define CHEZWEB_PROCESS_WINDOWS_H
#ifdef __CYGWIN__
#include "system.h"
typedef struct win_child *win_process;
const char *win_process_start(const char *, char *const [], const char *,
 const char *, const char *, const char *, win_process *);
/* 1: exited, 0: timeout/still running, -1: wait failed; -1 ms waits forever. */
int win_process_wait(win_process, long, int *);
void win_process_kill(win_process);
void win_process_close(win_process);
const char *win_run_program(const char *, char *const *, int, const char *,
 size_t, long, const char *, sys_run_result *);
#endif
#endif
