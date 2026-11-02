/*
 * compile-scripts.c -- chezemax --compile-scripts [LOG]
 *
 * Compiles the editor's scripts, and your own code under
 * ~/.chezemax/users/, into ~/.chezemax/chezemax.wasm and its machine code
 * (~/.chezemax/chezemax.cwasm), which the editor uses from its next start
 * (compiled-program.c).  The files and their order are those of
 * compiled/PROGRAM in the installation folder, as for make; nothing in that
 * folder is written, so it works where the folder cannot be written to.
 *
 * Schemer compiles a whole program at once (it has no linker), so every
 * script is compiled again: a few minutes.  M-x compile-scripts runs this
 * in the background with a LOG file; the log's last line, in the file
 * LOG.status, says "ok" or "failed".
 *
 * No shell is used: the compiler is started with its arguments directly.
 */
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

static FILE *out;                  /* the log, or stderr */

static void say(const char *format, ...)
{
	va_list ap;
	va_start(ap, format);
	vfprintf(out, format, ap);
	va_end(ap);
	fputc('\n', out);
	fflush(out);
}

/* the user's folder for Chezemax, ~/.chezemax */
static void config_path(char *buf, size_t size, const char *name)
{
	const char *home = getenv("HOME");
	snprintf(buf, size, "%s/.chezemax%s%s", home && *home ? home : ".", *name ? "/" : "", name);
}

/* ------------------------------------------------------------------ */
/* the list of files                                                  */
/* ------------------------------------------------------------------ */

typedef struct { char **items; int n, cap; } list;

static void push(list *l, const char *s)
{
	if (l->n == l->cap) {
		l->cap = l->cap ? 2 * l->cap : 64;
		l->items = realloc(l->items, (size_t) l->cap * sizeof *l->items);
		if (!l->items) abort();
	}
	l->items[l->n++] = strdup(s);
}

static int by_name(const void *a, const void *b)
{
	return strcmp(*(char *const *) a, *(char *const *) b);
}

/* every .scm file under DIR, sorted by path, subfolders included */
static void scheme_files_under(const char *dir, list *files)
{
	DIR *d = opendir(dir);
	struct dirent *e;
	list here = {0};
	if (!d) return;
	while ((e = readdir(d))) {
		char path[4096];
		struct stat st;
		if (e->d_name[0] == '.') continue;
		snprintf(path, sizeof path, "%s/%s", dir, e->d_name);
		if (stat(path, &st) != 0) continue;
		if (S_ISDIR(st.st_mode)) push(&here, path);
		else {
			size_t n = strlen(e->d_name);
			if (n > 4 && !strcmp(e->d_name + n - 4, ".scm")) push(&here, path);
		}
	}
	closedir(d);
	qsort(here.items, (size_t) here.n, sizeof *here.items, by_name);
	for (int k = 0; k < here.n; k++) {
		struct stat st;
		if (stat(here.items[k], &st) == 0 && S_ISDIR(st.st_mode)) scheme_files_under(here.items[k], files);
		else push(files, here.items[k]);
		free(here.items[k]);
	}
	free(here.items);
}

/* the lines of FILE that name files, without comments and blanks */
static int read_names(const char *file, list *names)
{
	FILE *f = fopen(file, "r");
	char line[4096];
	if (!f) return 0;
	while (fgets(line, sizeof line, f)) {
		char *s = line, *end;
		while (*s == ' ' || *s == '\t') s++;
		end = s + strcspn(s, " \t\r\n");
		*end = '\0';
		if (*s && *s != '#') push(names, s);
	}
	fclose(f);
	return 1;
}

/* the files of the program: compiled/PROGRAM, expanded */
static int program_files(const char *install, list *files, int *users)
{
	char path[4096];
	list names = {0};
	*users = 0;
	snprintf(path, sizeof path, "%s/compiled/PROGRAM", install);
	if (!read_names(path, &names)) { say("Cannot read %s", path); return 0; }
	for (int k = 0; k < names.n; k++) {
		if (!strcmp(names.items[k], "<ORDER>")) {
			list order = {0};
			snprintf(path, sizeof path, "%s/compiled/scripts/ORDER", install);
			if (!read_names(path, &order)) { say("Cannot read %s", path); return 0; }
			for (int j = 0; j < order.n; j++) {
				char full[4096];
				snprintf(full, sizeof full, "%s/%s", install, order.items[j]);
				push(files, full);
			}
		} else if (!strcmp(names.items[k], "<USERS>")) {
			int before = files->n;
			config_path(path, sizeof path, "users");
			scheme_files_under(path, files);
			*users = files->n - before;
		} else {
			char full[4096];
			snprintf(full, sizeof full, "%s/%s", install, names.items[k]);
			push(files, full);
		}
	}
	return 1;
}

/* ------------------------------------------------------------------ */
/* compiling                                                          */
/* ------------------------------------------------------------------ */

/* PROGRAM's files, one after the other, then the program's value */
static int write_source(list *files, const char *source, long *lines)
{
	FILE *s = fopen(source, "wb");
	*lines = 0;
	if (!s) { say("Cannot write %s: %s", source, strerror(errno)); return 0; }
	for (int k = 0; k < files->n; k++) {
		FILE *f = fopen(files->items[k], "rb");
		char buf[8192];
		size_t n;
		if (!f) { say("Cannot read %s", files->items[k]); fclose(s); return 0; }
		while ((n = fread(buf, 1, sizeof buf, f)) > 0) {
			for (size_t j = 0; j < n; j++) if (buf[j] == '\n') (*lines)++;
			fwrite(buf, 1, n, s);
		}
		fclose(f);
		fputc('\n', s);
	}
	fputs("bridge-dispatch\n", s);
	return fclose(s) == 0;
}

/* run the compiler with ARGV, its messages into the log; 1 when it succeeded */
static int run(char *const argv[])
{
	pid_t pid;
	int status;
	fflush(out);
	pid = fork();
	if (pid < 0) { say("Cannot start %s", argv[0]); return 0; }
	if (pid == 0) {
		int fd = fileno(out);
		dup2(fd, 1);
		dup2(fd, 2);
		execv(argv[0], argv);
		fprintf(stderr, "Cannot start %s: %s\n", argv[0], strerror(errno));
		_exit(127);
	}
	while (waitpid(pid, &status, 0) < 0)
		if (errno != EINTR) return 0;
	return WIFEXITED(status) && WEXITSTATUS(status) == 0;
}

static int compile(const char *install)
{
	char dir[4096], source[4200], wasm[4200], code[4200], wasm_new[4200], code_new[4200], compiler[4200];
	list files = {0};
	int users, ok;
	long lines;

	if (!program_files(install, &files, &users)) return 0;
	config_path(dir, sizeof dir, "");
	mkdir(dir, 0755);
	snprintf(source, sizeof source, "%s/chezemax-program.scm", dir);
	snprintf(wasm, sizeof wasm, "%s/chezemax.wasm", dir);
	snprintf(code, sizeof code, "%s/chezemax.cwasm", dir);
	snprintf(wasm_new, sizeof wasm_new, "%s/chezemax.wasm.new", dir);
	snprintf(code_new, sizeof code_new, "%s/chezemax.cwasm.new", dir);
	snprintf(compiler, sizeof compiler, "%s/schemer-compile", install);

	if (!write_source(&files, source, &lines)) return 0;
	say("Compiling %d files, %ld lines (%d of yours, from %s/users): a few minutes.",
	    files.n, lines, users, dir);
	{
		char *argv[] = { compiler, "--source", "--strict", source, wasm_new, (char *) install, NULL };
		ok = run(argv);
	}
	if (ok) {
		say("Making its machine code.");
		char *argv[] = { compiler, "--machine-code", wasm_new, code_new, NULL };
		ok = run(argv);
	}
	remove(source);
	if (!ok) {
		remove(wasm_new);
		remove(code_new);
		say("The scripts were not compiled: see the messages above.  The editor keeps the program it has.");
		return 0;
	}
	/* the program first, then its machine code: a machine code that is not
	 * the program's is never used (its fingerprint, native-host.c) */
	if (rename(wasm_new, wasm) != 0 || rename(code_new, code) != 0) {
		say("Cannot put the compiled program in %s: %s", dir, strerror(errno));
		return 0;
	}
	say("Compiled into %s.  Restart Chezemax to use it.", wasm);
	return 1;
}

/* chezemax --compile-scripts [LOG]: 0 when compiled */
int compile_scripts(const char *install, const char *log)
{
	int ok;
	out = stderr;
	if (log) {
		out = fopen(log, "w");
		if (!out) { fprintf(stderr, "Cannot write %s\n", log); return 1; }
	}
	ok = compile(install);
	if (log) {
		char status[4200], temp[4300];
		FILE *f;
		fclose(out);
		/* LOG.status, written whole: the editor waits for it */
		snprintf(status, sizeof status, "%s.status", log);
		snprintf(temp, sizeof temp, "%s.tmp", status);
		f = fopen(temp, "w");
		if (f) { fputs(ok ? "ok\n" : "failed\n", f); fclose(f); rename(temp, status); }
	}
	return ok ? 0 : 1;
}
