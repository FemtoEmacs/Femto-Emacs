/*
 * system.h -- files, programs and the system, for the scripts (system.c)
 */
#ifndef CHEZEMAX_SYSTEM_H
#define CHEZEMAX_SYSTEM_H
#include <stddef.h>

#define SYS_MAX_ARGS 256
#define SYS_NAME_SIZE 65

/* 1 and (directory? size mtime), or 0 when PATH is not there */
int sys_file_info(const char *path, int *is_dir, long long *size, long long *mtime);
int sys_file_executable(const char *path);
int sys_path_exists(const char *path);
char *sys_real_path(const char *path);                 /* malloc'd, or NULL */
int sys_format_time(long long seconds, char out[32]);  /* local "YYYY-MM-DD HH:MM" */
char *sys_read_file(const char *path, size_t *len);    /* malloc'd, or NULL */
void sys_os_name(char out[SYS_NAME_SIZE]);             /* "darwin", "linux" ... */

/*
 * Run PROGRAM (looked up on the PATH when it has no slash) with ARGS,
 * INPUT on its standard input, in DIRECTORY (NULL: here).  Its output and
 * errors go to temporary files, so a big output cannot deadlock it.  After
 * TIMEOUT seconds it is killed.  The status is -1 when it could not run or
 * was killed (the errors then say why).  NULL, or a message when it could
 * not even be tried.
 */
typedef struct { char *out, *err; size_t out_len, err_len; int status; } sys_run_result;
const char *sys_run_program(const char *program, char *const *args, int nargs,
			    const char *input, size_t input_len, long timeout,
			    const char *directory, sys_run_result *result);
void sys_run_result_free(sys_run_result *);

/* Start PROGRAM (looked up on PATH when it has no slash) with ARGS and do not wait for it (a viewer window): in a
 * session of its own, with no terminal, so it survives the editor and never
 * draws on its screen.  NULL when it started, otherwise why not. */
const char *sys_spawn_program(const char *program, char *const *args, int nargs);

/* malloc'd lists of malloc'd names (sys_free_names), or NULL */
char **sys_directory_files(const char *directory, int *count);
char **sys_file_completions(const char *typed, int *count);
void sys_free_names(char **names, int count);
#endif
