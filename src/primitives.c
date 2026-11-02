/*
 * primitives.c -- what the Scheme scripts need beyond the fe_* editor API
 *
 * Buffer text in bulk (as strings of raw UTF-8 bytes: femtoscheme strings
 * are byte arrays, so AREF reads a byte), exact byte insertion for undo,
 * the C core's command and hint tables, the mouse, files, and running a
 * program with a timeout.  Errors are reported with lerror, which the
 * callers in hooks.c turn into messages: nothing here exits.
 */
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/utsname.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#include "llt/llt.h"
#include "flisp.h"
#include "system.h"

extern long fe_buffer_size(void);
extern long fe_copy_text(long start, long len, char *out);
extern void fe_insert_bytes(long p, char *bytes, long len);
extern void fe_add_command_name(char *name);
extern void fe_set_buffer_hint(char *name, char *hint);
extern void fe_set_modeline_hints(char *help, char *tail);
extern void editor_mouse_event(void);
extern int fe_buffer_read_only(void);
extern void fe_set_read_only(int on);
extern int getcommand(char *, int);

static value_t bytes_string(const char *data, size_t len)
{
	value_t s = cvalue_string(len);
	if (len) memcpy(cvalue_data(s), data, len);
	return s;
}

/* (buffer-substring start end): the bytes of the current buffer */
static value_t buffer_substring(value_t *a, uint32_t n)
{
	argcount("buffer-substring", n, 2);
	long size = fe_buffer_size();
	long start = tofixnum(a[0], "buffer-substring");
	long end = tofixnum(a[1], "buffer-substring");
	if (start < 0) start = 0;
	if (end > size) end = size;
	if (end <= start) return bytes_string("", 0);
	value_t s = cvalue_string((size_t) (end - start));
	fe_copy_text(start, end - start, (char *) cvalue_data(s));
	return s;
}

/* (fe-insert-bytes pos string): exactly these bytes, NULs included */
static value_t insert_bytes(value_t *a, uint32_t n)
{
	argcount("fe-insert-bytes", n, 2);
	long p = tofixnum(a[0], "fe-insert-bytes");
	if (!fl_isstring(a[1])) lerror(ArgError, "fe-insert-bytes: expected a string");
	fe_insert_bytes(p, (char *) cvalue_data(a[1]), (long) cvalue_len(a[1]));
	return FL_T;
}

static value_t add_command_name(value_t *a, uint32_t n)
{
	argcount("fe-add-command-name", n, 1);
	fe_add_command_name(tostring(a[0], "fe-add-command-name"));
	return FL_T;
}

static value_t set_buffer_hint(value_t *a, uint32_t n)
{
	argcount("fe-set-buffer-hint", n, 2);
	fe_set_buffer_hint(tostring(a[0], "fe-set-buffer-hint"), tostring(a[1], "fe-set-buffer-hint"));
	return FL_T;
}

static value_t set_modeline_hints(value_t *a, uint32_t n)
{
	argcount("fe-set-modeline-hints", n, 2);
	fe_set_modeline_hints(tostring(a[0], "fe-set-modeline-hints"),
			      tostring(a[1], "fe-set-modeline-hints"));
	return FL_T;
}

/* the mouse event GET-KEY just read (a menu reading keys passes it on) */
static value_t mouse_event(value_t *a, uint32_t n)
{
	(void) a;
	argcount("fe-mouse-event", n, 0);
	editor_mouse_event();
	return FL_T;
}

/* (file-attributes path): #f, or (directory? size mtime) */
static value_t file_info(value_t *a, uint32_t n)
{
	argcount("file-attributes", n, 1);
	int is_dir;
	long long size, when;
	if (!sys_file_info(tostring(a[0], "file-attributes"), &is_dir, &size, &when)) return FL_F;
	return fl_cons(is_dir ? FL_T : FL_F, fl_list2(fixnum((fixnum_t) size), fixnum((fixnum_t) when)));
}

static value_t file_executable(value_t *a, uint32_t n)
{
	argcount("file-executable?", n, 1);
	return sys_file_executable(tostring(a[0], "file-executable?")) ? FL_T : FL_F;
}

static value_t real_path(value_t *a, uint32_t n)
{
	argcount("real-path", n, 1);
	char *out = sys_real_path(tostring(a[0], "real-path"));
	if (!out) return FL_F;
	value_t s = bytes_string(out, strlen(out));
	free(out);
	return s;
}

/* (format-time seconds): local "YYYY-MM-DD HH:MM" */
static value_t format_time(value_t *a, uint32_t n)
{
	argcount("format-time", n, 1);
	/* Browser Wasm uses 29-bit fixnums; ordinary Unix timestamps are
	 * boxed int32/int64 values returned by file-attributes. */
	int64_t seconds;
	if (isfixnum(a[0])) seconds = (int64_t) numval(a[0]);
	else if (iscprim(a[0]) && cp_numtype((cprim_t *)ptr(a[0])) < T_FLOAT) {
		cprim_t *number = (cprim_t *)ptr(a[0]);
		if (cp_numtype(number) == T_UINT64 &&
		    conv_to_uint64(cp_data(number), T_UINT64) > INT64_MAX)
			lerror(ArgError, "format-time: timestamp out of range");
		seconds = conv_to_int64(cp_data(number), cp_numtype(number));
	} else {
		type_error("format-time", "integer", a[0]);
		return FL_F;
	}
	char out[32];
	if (!sys_format_time((long long) seconds, out))
		lerror(ArgError, "format-time: timestamp out of range");
	return bytes_string(out, strlen(out));
}

static value_t delete_file(value_t *a, uint32_t n)
{
	argcount("delete-file", n, 1);
	return unlink(tostring(a[0], "delete-file")) == 0 ? FL_T : FL_F;
}

/* read a whole file into a string of bytes, or #f */
static value_t read_file_bytes(const char *path)
{
	size_t size;
	char *data = sys_read_file(path, &size);
	if (!data) return FL_F;
	value_t s = bytes_string(data, size);
	free(data);
	return s;
}

static value_t file_contents(value_t *a, uint32_t n)
{
	argcount("file-contents", n, 1);
	return read_file_bytes(tostring(a[0], "file-contents"));
}

/* (run-program program args input timeout directory): (stdout stderr
 * status), see system.h */
static int string_args(value_t l, char **argv, const char *who)
{
	int argc = 0;
	while (iscons(l)) {
		if (argc >= SYS_MAX_ARGS) lerror(ArgError, "too many arguments");
		argv[argc++] = tostring(car_(l), (char *) who);
		l = cdr_(l);
	}
	return argc;
}

static value_t run_program(value_t *a, uint32_t n)
{
	argcount("run-program", n, 5);
	const char *program = tostring(a[0], "run-program");
	char *argv[SYS_MAX_ARGS];
	int argc = string_args(a[1], argv, "run-program");
	long timeout = tofixnum(a[3], "run-program");
	const char *dir = a[4] == FL_F ? NULL : tostring(a[4], "run-program");
	int has_input = a[2] != FL_F && fl_isstring(a[2]);
	sys_run_result r;
	const char *failed = sys_run_program(program, argv, argc,
					     has_input ? (const char *) cvalue_data(a[2]) : NULL,
					     has_input ? cvalue_len(a[2]) : 0, timeout, dir, &r);
	if (failed) lerror(IOError, failed);
	value_t so = FL_NIL, se = FL_NIL, result = FL_NIL;
	fl_gc_handle(&so); fl_gc_handle(&se); fl_gc_handle(&result);
	so = bytes_string(r.out, r.out_len);
	se = bytes_string(r.err, r.err_len);
	result = fl_cons(so, fl_list2(se, fixnum((fixnum_t) r.status)));
	fl_free_gc_handles(3);
	sys_run_result_free(&r);
	return result;
}

/* (spawn-program program args): #t when it started, otherwise why not */
static value_t spawn_program(value_t *a, uint32_t n)
{
	argcount("spawn-program", n, 2);
	const char *program = tostring(a[0], "spawn-program");
	char *argv[SYS_MAX_ARGS];
	int argc = string_args(a[1], argv, "spawn-program");
	const char *why = sys_spawn_program(program, argv, argc);
	if (why) return bytes_string(why, strlen(why));
	return FL_T;
}

/* (buffer-read-only?) and (set-buffer-read-only! flag): the current buffer */
static value_t buffer_read_only(value_t *a, uint32_t n)
{
	(void) a;
	argcount("buffer-read-only?", n, 0);
	return fe_buffer_read_only() ? FL_T : FL_F;
}

static value_t set_buffer_read_only(value_t *a, uint32_t n)
{
	argcount("set-buffer-read-only!", n, 1);
	fe_set_read_only(a[0] != FL_F);
	return a[0] != FL_F ? FL_T : FL_F;
}

/* (os-name): "darwin", "linux", ... (uname, lower case) */
static value_t os_name(value_t *a, uint32_t n)
{
	(void) a;
	argcount("os-name", n, 0);
	char name[SYS_NAME_SIZE];
	sys_os_name(name);
	return bytes_string(name, strlen(name));
}

/* (getpid): this process's id, to name temporary files */
static value_t get_pid(value_t *a, uint32_t n)
{
	(void) a;
	argcount("getpid", n, 0);
	return fixnum((fixnum_t) getpid());
}

static value_t command_prompt(value_t *a, uint32_t n)
{
    (void)a; argcount("command-prompt", n, 0);
    char command[4096] = "";
    if (!getcommand(command, sizeof(command))) return FL_F;
    return bytes_string(command, strlen(command));
}

void primitives_init(void)
{
	static builtinspec_t functions[] = {
		{ "buffer-substring", buffer_substring },
        { "command-prompt", command_prompt },
		{ "fe-insert-bytes", insert_bytes },
		{ "fe-add-command-name", add_command_name },
		{ "fe-set-buffer-hint", set_buffer_hint },
		{ "fe-set-modeline-hints", set_modeline_hints },
		{ "fe-mouse-event", mouse_event },
		{ "file-attributes", file_info },
		{ "file-executable?", file_executable },
		{ "real-path", real_path },
		{ "format-time", format_time },
		{ "delete-file", delete_file },
		{ "file-contents", file_contents },
		{ "run-program", run_program },
		{ "spawn-program", spawn_program },
		{ "os-name", os_name },
		{ "buffer-read-only?", buffer_read_only },
		{ "set-buffer-read-only!", set_buffer_read_only },
		{ "getpid", get_pid },
		{ NULL, NULL }
	};
	assign_global_builtins(functions);
}
