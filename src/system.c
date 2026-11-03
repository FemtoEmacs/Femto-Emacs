/*
 * system.c -- files, programs and the system, for the scripts
 *
 * Plain C, for both runtimes: the femtoscheme builtins (primitives.c,
 * extra.c) and the functions of compiled Scheme (bridge-more.c) are thin
 * wrappers around these.  Nothing here exits or longjmps: failures are
 * returned.
 */
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/utsname.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#include "system.h"

int sys_file_info(const char *path, int *is_dir, long long *size, long long *mtime)
{
	struct stat st;
	if (stat(path, &st) != 0) return 0;
	*is_dir = S_ISDIR(st.st_mode) ? 1 : 0;
	*size = (long long) st.st_size;
	*mtime = (long long) st.st_mtime;
	return 1;
}

int sys_file_executable(const char *path)
{
	struct stat st;
	return stat(path, &st) == 0 && S_ISREG(st.st_mode) && access(path, X_OK) == 0;
}

int sys_path_exists(const char *path)
{
	struct stat st;
	return stat(path, &st) == 0;
}

char *sys_real_path(const char *path)
{
	char out[PATH_MAX];
	if (!realpath(path, out)) return NULL;
	return strdup(out);
}

int sys_format_time(long long seconds, char out[32])
{
	time_t t = (time_t) seconds;
	struct tm tm;
	if ((long long) t != seconds) return 0;
	if (!localtime_r(&t, &tm) || !strftime(out, 32, "%Y-%m-%d %H:%M", &tm)) return 0;
	return 1;
}

char *sys_read_file(const char *path, size_t *len)
{
	FILE *f = fopen(path, "rb");
	long size;
	char *s;
	if (!f) return NULL;
	fseek(f, 0, SEEK_END);
	size = ftell(f);
	rewind(f);
	if (size < 0 || size > 64L * 1024 * 1024) { fclose(f); return NULL; }
	s = malloc((size_t) size + 1);
	if (!s) { fclose(f); return NULL; }
	if (fread(s, 1, (size_t) size, f) != (size_t) size) { fclose(f); free(s); return NULL; }
	fclose(f);
	s[size] = '\0';
	*len = (size_t) size;
	return s;
}

void sys_os_name(char out[SYS_NAME_SIZE])
{
	struct utsname u;
	size_t i;
	if (uname(&u) != 0) { strcpy(out, "unknown"); return; }
	for (i = 0; u.sysname[i] && i + 1 < SYS_NAME_SIZE; i++)
		out[i] = (char) ((u.sysname[i] >= 'A' && u.sysname[i] <= 'Z') ? u.sysname[i] + 32 : u.sysname[i]);
	out[i] = '\0';
}

/* (run-program program args input timeout directory): see system.h */
const char *sys_run_program(const char *program, char *const *args, int nargs,
			    const char *input, size_t input_len, long timeout,
			    const char *dir, sys_run_result *r)
{
	char *argv[SYS_MAX_ARGS + 2];
	int argc = 0;
	static char why[160];
	memset(r, 0, sizeof *r);
	if (nargs > SYS_MAX_ARGS) return "run-program: too many arguments";
	argv[argc++] = (char *) program;
	for (int k = 0; k < nargs; k++) argv[argc++] = args[k];
	argv[argc] = NULL;

	char tmpl[] = "/tmp/chezemax-run-XXXXXX";
	char *tmp = mkdtemp(tmpl);
	if (!tmp) return "run-program: cannot create a temporary folder";
	char in[300], out[300], err[300];
	snprintf(in, sizeof(in), "%s/in", tmp);
	snprintf(out, sizeof(out), "%s/out", tmp);
	snprintf(err, sizeof(err), "%s/err", tmp);
	FILE *f = fopen(in, "wb");
	if (f) {
		if (input && input_len) fwrite(input, 1, input_len, f);
		fclose(f);
	}

	int status = 0, done = 0, killed = 0;
	pid_t pid = fork();
	if (pid == 0) {
		int fi = open(in, O_RDONLY), fo = open(out, O_WRONLY | O_CREAT | O_TRUNC, 0600),
		    fe = open(err, O_WRONLY | O_CREAT | O_TRUNC, 0600);
		if (fi < 0 || fo < 0 || fe < 0) _exit(126);
		dup2(fi, 0); dup2(fo, 1); dup2(fe, 2);
		close(fi); close(fo); close(fe);
		if (dir && chdir(dir) != 0) {
			fprintf(stderr, "cannot enter %s: %s\n", dir, strerror(errno));
			_exit(126);
		}
		execvp(program, argv);
		fprintf(stderr, "%s: %s\n", program, strerror(errno));
		_exit(127);
	}
	int fork_errno = errno;
	if (pid > 0) {
		struct timespec tick = { 0, 20 * 1000 * 1000 };
		long ticks = timeout * 50;
		for (long i = 0; i <= ticks; i++) {
			pid_t w = waitpid(pid, &status, WNOHANG);
			if (w == pid) { done = 1; break; }
			if (w < 0 && errno != EINTR) break;
			nanosleep(&tick, NULL);
		}
		if (!done) {
			kill(pid, SIGTERM);
			nanosleep(&tick, NULL);
			if (waitpid(pid, &status, WNOHANG) != pid) {
				kill(pid, SIGKILL);
				waitpid(pid, &status, 0);
			}
			killed = 1;
		}
	}
	r->out = sys_read_file(out, &r->out_len);
	if (!r->out) { r->out = strdup(""); r->out_len = 0; }
	if (pid < 0) {
		r->err = strdup(strerror(fork_errno));
		r->err_len = strlen(r->err);
	} else if (killed) {
		snprintf(why, sizeof(why), "no answer after %ld seconds", timeout);
		r->err = strdup(why);
		r->err_len = strlen(why);
	} else {
		r->err = sys_read_file(err, &r->err_len);
		if (!r->err) { r->err = strdup(""); r->err_len = 0; }
	}
	r->status = (pid < 0 || killed) ? -1 :
		WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
	unlink(in); unlink(out); unlink(err); rmdir(tmp);
	return NULL;
}

void sys_run_result_free(sys_run_result *r)
{
	free(r->out);
	free(r->err);
	r->out = r->err = NULL;
}

/* start PROGRAM and do not wait (see system.h): NULL, or why not */
const char *sys_spawn_program(const char *program, char *const *args, int nargs)
{
	char *argv[SYS_MAX_ARGS + 2];
	int argc = 0, fds[2];
	if (nargs > SYS_MAX_ARGS) return "spawn-program: too many arguments";
	argv[argc++] = (char *) program;
	for (int k = 0; k < nargs; k++) argv[argc++] = args[k];
	argv[argc] = NULL;
	if (pipe(fds) != 0) return "spawn-program: pipe failed";
	fcntl(fds[1], F_SETFD, FD_CLOEXEC);
	pid_t pid = fork();
	if (pid < 0) {
		close(fds[0]); close(fds[1]);
		return "spawn-program: fork failed";
	}
	if (pid == 0) {
		close(fds[0]);
		setsid();
		if (fork() != 0) _exit(0);
		int null = open("/dev/null", O_RDWR);
		if (null >= 0) { dup2(null, 0); dup2(null, 1); dup2(null, 2); if (null > 2) close(null); }
		execvp(program, argv);
		int e = errno;
		if (write(fds[1], &e, sizeof(e)) < 0) { /* nothing more to say */ }
		_exit(127);
	}
	close(fds[1]);
	int status, err = 0;
	waitpid(pid, &status, 0);
	ssize_t got = read(fds[0], &err, sizeof(err));
	close(fds[0]);
	if (got == (ssize_t) sizeof(err)) return strerror(err);
	return NULL;
}

/* the names in DIRECTORY (malloc'd, *COUNT of them), or NULL */
char **sys_directory_files(const char *directory, int *count)
{
	DIR *dir = opendir(directory);
	struct dirent *entry;
	char **names = NULL;
	int n = 0, cap = 0;
	*count = 0;
	if (!dir) return NULL;
	while ((entry = readdir(dir))) {
		if (n == cap) {
			cap = cap ? 2 * cap : 64;
			char **more = realloc(names, sizeof(char *) * (size_t) cap);
			if (!more) break;
			names = more;
		}
		names[n++] = strdup(entry->d_name);
	}
	closedir(dir);
	if (!names) names = malloc(sizeof(char *));
	*count = n;
	return names;
}

/* completions of a typed file name; the typed folder is kept, ~/ is
 * expanded only to read the folder */
char **sys_file_completions(const char *typed, int *count)
{
	char prefix[4096], directory[4096], path[8192], candidate[8192];
	const char *slash = strrchr(typed, '/'), *base = slash ? slash + 1 : typed;
	size_t plen = slash ? (size_t) (slash - typed) + 1 : 0;
	char **names = NULL;
	int n = 0, cap = 0;
	*count = 0;
	if (strlen(typed) >= sizeof(prefix) || plen >= sizeof(prefix)) return NULL;
	memcpy(prefix, typed, plen);
	prefix[plen] = 0;
	if (prefix[0] == '~' && prefix[1] == '/')
		snprintf(directory, sizeof(directory), "%s/%s", getenv("HOME") ? getenv("HOME") : "", prefix + 2);
	else
		snprintf(directory, sizeof(directory), "%s", plen ? prefix : ".");
	DIR *dir = opendir(directory);
	if (!dir) return NULL;
	struct dirent *entry;
	while ((entry = readdir(dir))) {
		if (!strcmp(entry->d_name, ".") || !strcmp(entry->d_name, "..")) continue;
		if (entry->d_name[0] == '.' && base[0] != '.') continue;
		if (strncmp(entry->d_name, base, strlen(base))) continue;
		snprintf(path, sizeof(path), "%s/%s", directory, entry->d_name);
		struct stat st;
		int is_dir = stat(path, &st) == 0 && S_ISDIR(st.st_mode);
		snprintf(candidate, sizeof(candidate), "%s%s%s", prefix, entry->d_name, is_dir ? "/" : "");
		/* the screen's completion protocol separates names with newlines */
		if (strchr(candidate, '\n')) continue;
		if (n == cap) {
			cap = cap ? 2 * cap : 64;
			char **more = realloc(names, sizeof(char *) * (size_t) cap);
			if (!more) break;
			names = more;
		}
		names[n++] = strdup(candidate);
	}
	closedir(dir);
	if (!names) names = malloc(sizeof(char *));
	*count = n;
	return names;
}

void sys_free_names(char **names, int count)
{
	if (!names) return;
	for (int k = 0; k < count; k++) free(names[k]);
	free(names);
}
