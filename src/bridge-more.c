/*
 * bridge-more.c -- the C functions of the scripts that are not in
 * src/native.c's table (bridge-functions.c): buffer text in bulk, the
 * command and hint tables, files, programs, the system, the highlighters
 * and the assistants.  Each is a wrapper, for compiled Scheme, around the
 * same C as femtoscheme's builtin of the same name (primitives.c, extra.c,
 * highlight.c, assistant.c, system.c); compiled/system.scm gives them the
 * scripts' signatures.
 */
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <string.h>
#include <unistd.h>
#include "bridge.h"
#include "highlight.h"
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
extern int getfilename(char *, char *, int);
extern void fe_set_completions(char *);
extern char *assistant_ask(const char *provider, const char *prompt, const char **error);
extern char *assistant_textify(const char *provider, const char *path, const char *range,
			       const char *guidelines, const char **error);

static char *install_dir;
const char *bridge_install_dir(void) { return install_dir ? install_dir : "."; }
void bridge_set_install_dir(const char *directory)
{
	free(install_dir);
	install_dir = strdup(directory ? directory : ".");
}

static void put_names(bridge_out *out, char **names, int count)
{
	bridge_put_list(out, count);
	for (int k = 0; k < count; k++) bridge_put_string(out, names[k]);
	sys_free_names(names, count);
}

/* a list of strings, as a NULL-terminated array (free_strings) */
static char **get_strings(bridge_in *in, int *count)
{
	long n = bridge_list(in);
	char **v = calloc((size_t) n + 1, sizeof(char *));
	if (!v) abort();
	for (long k = 0; k < n; k++) v[k] = bridge_string(in);
	*count = (int) n;
	return v;
}

static void free_strings(char **v, int count)
{
	for (int k = 0; k < count; k++) free(v[k]);
	free(v);
}

/* ------------------------------------------------------------------ */
/* buffer text, commands, hints, the mouse                             */
/* ------------------------------------------------------------------ */

static void b_buffer_substring(bridge_in *in, bridge_out *out)
{
	long start = bridge_int(in), end = bridge_int(in), size = fe_buffer_size();
	if (start < 0) start = 0;
	if (end > size) end = size;
	if (end <= start) { bridge_put_string(out, ""); return; }
	char *s = malloc((size_t) (end - start) + 1);
	if (!s) abort();
	fe_copy_text(start, end - start, s);
	bridge_put_string_n(out, (const char *) s, (size_t) (end - start));
	free(s);
}

/* (buffer-bytes start end): the same bytes, as a bytevector */
static void b_buffer_bytes(bridge_in *in, bridge_out *out)
{
	long start = bridge_int(in), end = bridge_int(in), size = fe_buffer_size();
	if (start < 0) start = 0;
	if (end > size) end = size;
	if (end <= start) { bridge_put_bytes(out, (const unsigned char *) "", 0); return; }
	char *s = malloc((size_t) (end - start) + 1);
	if (!s) abort();
	fe_copy_text(start, end - start, s);
	bridge_put_bytes(out, (unsigned char *) s, (size_t) (end - start));
	free(s);
}

static void b_buffer_string(bridge_in *in, bridge_out *out)
{
	(void) in;
	long size = fe_buffer_size();
	char *s = malloc((size_t) size + 1);
	if (!s) abort();
	fe_copy_text(0, size, s);
	s[size] = 0;
	bridge_put_string_n(out, (const char *) s, (size_t) size);
	free(s);
}

static void b_insert_bytes(bridge_in *in, bridge_out *out)
{
	long p = bridge_int(in);
	size_t n;
	unsigned char *b = bridge_bytes(in, &n);
	fe_insert_bytes(p, (char *) b, (long) n);
	free(b);
	bridge_put_bool(out, 1);
}

static void b_add_command_name(bridge_in *in, bridge_out *out)
{
	char *name = bridge_string(in);
	fe_add_command_name(name);
	free(name);
	bridge_put_bool(out, 1);
}

static void b_set_buffer_hint(bridge_in *in, bridge_out *out)
{
	char *name = bridge_string(in), *hint = bridge_string(in);
	fe_set_buffer_hint(name, hint);
	free(name); free(hint);
	bridge_put_bool(out, 1);
}

static void b_set_modeline_hints(bridge_in *in, bridge_out *out)
{
	char *help = bridge_string(in), *tail = bridge_string(in);
	fe_set_modeline_hints(help, tail);
	free(help); free(tail);
	bridge_put_bool(out, 1);
}

static void b_mouse_event(bridge_in *in, bridge_out *out)
{
	(void) in;
	editor_mouse_event();
	bridge_put_bool(out, 1);
}

static void b_command_prompt(bridge_in *in, bridge_out *out)
{
	(void) in;
	char command[4096] = "";
	if (!getcommand(command, sizeof(command))) bridge_put_bool(out, 0);
	else bridge_put_string(out, command);
}

static void b_buffer_read_only(bridge_in *in, bridge_out *out)
{
	(void) in;
	bridge_put_bool(out, fe_buffer_read_only());
}

static void b_set_buffer_read_only(bridge_in *in, bridge_out *out)
{
	int on = bridge_int(in) != 0;
	fe_set_read_only(on);
	bridge_put_bool(out, on);
}

static void b_set_completions(bridge_in *in, bridge_out *out)
{
	char *names = bridge_string(in);
	fe_set_completions(names);
	free(names);
	bridge_put_bool(out, 1);
}

static void b_file_prompt(bridge_in *in, bridge_out *out)
{
	char *prompt = bridge_string(in);
	char path[4096] = "";
	if (!getfilename(prompt, path, sizeof(path) - 1)) path[0] = 0;
	free(prompt);
	bridge_put_string(out, path);
}

/* ------------------------------------------------------------------ */
/* files, programs, the system                                         */
/* ------------------------------------------------------------------ */

static void b_file_attributes(bridge_in *in, bridge_out *out)
{
	char *path = bridge_string(in);
	int is_dir;
	long long size, when;
	if (!sys_file_info(path, &is_dir, &size, &when)) bridge_put_bool(out, 0);
	else {
		bridge_put_list(out, 3);
		bridge_put_bool(out, is_dir);
		bridge_put_int(out, (long) size);
		bridge_put_int(out, (long) when);
	}
	free(path);
}

static void b_file_executable(bridge_in *in, bridge_out *out)
{
	char *path = bridge_string(in);
	bridge_put_bool(out, sys_file_executable(path));
	free(path);
}

static void b_path_exists(bridge_in *in, bridge_out *out)
{
	char *path = bridge_string(in);
	bridge_put_bool(out, sys_path_exists(path));
	free(path);
}

static void b_real_path(bridge_in *in, bridge_out *out)
{
	char *path = bridge_string(in), *real = sys_real_path(path);
	if (real) bridge_put_string(out, real); else bridge_put_bool(out, 0);
	free(path); free(real);
}

static void b_format_time(bridge_in *in, bridge_out *out)
{
	char text[32];
	if (!sys_format_time((long long) bridge_int(in), text)) bridge_error(out, "format-time: timestamp out of range");
	else bridge_put_string(out, text);
}

static void b_file_contents(bridge_in *in, bridge_out *out)
{
	char *path = bridge_string(in);
	size_t n;
	char *data = sys_read_file(path, &n);
	if (!data) bridge_put_bool(out, 0);
	else {
		bridge_put_string_n(out, (const char *) data, n);
	}
	free(path); free(data);
}

static void b_directory_files(bridge_in *in, bridge_out *out)
{
	char *path = bridge_string(in);
	int count;
	char **names = sys_directory_files(path, &count);
	free(path);
	if (!names) bridge_error(out, "Cannot read directory");
	else put_names(out, names, count);
}

static void b_file_completions(bridge_in *in, bridge_out *out)
{
	char *typed = bridge_string(in);
	int count;
	char **names = sys_file_completions(typed, &count);
	free(typed);
	if (!names) bridge_put_list(out, 0);
	else put_names(out, names, count);
}

static void b_run_program(bridge_in *in, bridge_out *out)
{
	char *program = bridge_string(in);
	int argc;
	char **argv = get_strings(in, &argc);
	size_t input_len = 0;
	unsigned char *input = NULL;
	if (bridge_kind(in) == BRIDGE_FALSE) bridge_skip(in);
	else input = bridge_bytes(in, &input_len);
	long timeout = bridge_int(in);
	char *dir = NULL;
	if (bridge_kind(in) == BRIDGE_FALSE) bridge_skip(in);
	else dir = bridge_string(in);
	sys_run_result r;
	const char *failed = sys_run_program(program, argv, argc, (char *) input, input_len, timeout, dir, &r);
	if (failed) bridge_error(out, failed);
	else {
		bridge_put_list(out, 3);
		bridge_put_string_n(out, (const char *) r.out, r.out_len);
		bridge_put_string_n(out, (const char *) r.err, r.err_len);
		bridge_put_int(out, r.status);
		sys_run_result_free(&r);
	}
	free(program); free_strings(argv, argc); free(input); free(dir);
}

static void b_spawn_program(bridge_in *in, bridge_out *out)
{
	char *program = bridge_string(in);
	int argc;
	char **argv = get_strings(in, &argc);
	const char *why = sys_spawn_program(program, argv, argc);
	if (why) bridge_put_string(out, why); else bridge_put_bool(out, 1);
	free(program); free_strings(argv, argc);
}

static void b_os_name(bridge_in *in, bridge_out *out)
{
	(void) in;
	char name[SYS_NAME_SIZE];
	sys_os_name(name);
	bridge_put_string(out, name);
}

static void b_getpid(bridge_in *in, bridge_out *out)
{
	(void) in;
	bridge_put_int(out, (long) getpid());
}

/* (current-jiffy): milliseconds since the editor started, for TIME */
static void b_jiffy(bridge_in *in, bridge_out *out)
{
	static struct timespec start;
	struct timespec now;
	(void) in;
	clock_gettime(CLOCK_MONOTONIC, &now);
	if (start.tv_sec == 0 && start.tv_nsec == 0) start = now;
	bridge_put_int(out, (long) ((now.tv_sec - start.tv_sec) * 1000L + (now.tv_nsec - start.tv_nsec) / 1000000L));
}

static void b_getenv(bridge_in *in, bridge_out *out)
{
	char *name = bridge_string(in);
	const char *value = getenv(name);
	if (value) bridge_put_string(out, value); else bridge_put_bool(out, 0);
	free(name);
}

/* (os.setenv name value): VALUE #f unsets it */
static void b_setenv(bridge_in *in, bridge_out *out)
{
	char *name = bridge_string(in);
	int ok;
	if (bridge_kind(in) == BRIDGE_FALSE) { bridge_skip(in); ok = unsetenv(name) == 0; }
	else { char *value = bridge_string(in); ok = setenv(name, value, 1) == 0; free(value); }
	free(name);
	bridge_put_bool(out, ok);
}

/* (path.cwd [directory]): the current directory; with DIRECTORY, go there */
static void b_cwd(bridge_in *in, bridge_out *out)
{
	if (in->count > 0 && bridge_kind(in) == BRIDGE_STRING) {
		char *dir = bridge_string(in);
		int ok = chdir(dir) == 0;
		free(dir);
		if (!ok) { bridge_error(out, "path.cwd: cannot change directory"); return; }
	}
	char here[4096];
	if (!getcwd(here, sizeof(here))) bridge_error(out, "path.cwd: cannot read the current directory");
	else bridge_put_string(out, here);
}

/* (fe-program-path): this executable (app.c) */
extern char chezemax_program_path[];
static void b_program_path(bridge_in *in, bridge_out *out)
{
	(void) in;
	bridge_put_string(out, chezemax_program_path);
}

static void b_install_dir(bridge_in *in, bridge_out *out)
{
	(void) in;
	bridge_put_string(out, install_dir ? install_dir : ".");
}

/* ------------------------------------------------------------------ */
/* highlighters: the text in, its colours out                          */
/* ------------------------------------------------------------------ */

static hl_bytes *get_byte_strings(bridge_in *in, int *count)
{
	long n = bridge_list(in);
	hl_bytes *v = calloc((size_t) (n ? n : 1), sizeof(hl_bytes));
	if (!v) abort();
	for (long k = 0; k < n; k++) {
		size_t len;
		v[k].s = (char *) bridge_bytes(in, &len);
		v[k].n = (int) len;
	}
	*count = (int) n;
	return v;
}

static void free_byte_strings(hl_bytes *v, int n)
{
	for (int k = 0; k < n; k++) free(v[k].s);
	free(v);
}

/* (fe-define-token-language word-chars line-comments ((open close) ...)
 *   strings escape char-prefix backslash-commands case-insensitive keywords) */
static void b_define_token_language(bridge_in *in, bridge_out *out)
{
	hl_language_spec spec;
	size_t n;
	memset(&spec, 0, sizeof spec);
	spec.word_chars.s = (char *) bridge_bytes(in, &n);
	spec.word_chars.n = (int) n;
	spec.line_comments = get_byte_strings(in, &spec.n_line);
	spec.n_block = (int) bridge_list(in);
	spec.block_open = calloc((size_t) (spec.n_block ? spec.n_block : 1), sizeof(hl_bytes));
	spec.block_close = calloc((size_t) (spec.n_block ? spec.n_block : 1), sizeof(hl_bytes));
	if (!spec.block_open || !spec.block_close) abort();
	for (int k = 0; k < spec.n_block; k++) {
		if (bridge_list(in) != 2) { in->bad = 1; break; }
		spec.block_open[k].s = (char *) bridge_bytes(in, &n); spec.block_open[k].n = (int) n;
		spec.block_close[k].s = (char *) bridge_bytes(in, &n); spec.block_close[k].n = (int) n;
	}
	spec.strings = get_byte_strings(in, &spec.n_strings);
	spec.escape = bridge_kind(in) == BRIDGE_INT ? (int) bridge_int(in) : (bridge_skip(in), -1);
	if (bridge_kind(in) == BRIDGE_STRING || bridge_kind(in) == BRIDGE_BYTES) {
		spec.char_prefix.s = (char *) bridge_bytes(in, &n);
		spec.char_prefix.n = (int) n;
	} else bridge_skip(in);
	spec.backslash_commands = bridge_int(in) != 0;
	spec.case_insensitive = bridge_int(in) != 0;
	spec.keywords = get_byte_strings(in, &spec.n_keywords);
	if (!in->bad) bridge_put_int(out, highlight_define_language(&spec));
	free(spec.word_chars.s);
	free_byte_strings(spec.line_comments, spec.n_line);
	free_byte_strings(spec.block_open, spec.n_block);
	free_byte_strings(spec.block_close, spec.n_block);
	free_byte_strings(spec.strings, spec.n_strings);
	free(spec.char_prefix.s);
	free_byte_strings(spec.keywords, spec.n_keywords);
}

static void b_highlight_tokens(bridge_in *in, bridge_out *out)
{
	int id = (int) bridge_int(in);
	size_t n;
	unsigned char *text = bridge_bytes(in, &n), *colors = calloc(n + 1, 1);
	if (!colors) abort();
	if (!highlight_tokens_id(id, text, (int) n, colors)) bridge_error(out, "fe-highlight-tokens: no such language");
	else bridge_put_bytes(out, colors, n);
	free(text); free(colors);
}

static void b_highlight_python(bridge_in *in, bridge_out *out)
{
	size_t n;
	unsigned char *text = bridge_bytes(in, &n), *colors = calloc(n + 1, 1);
	if (!colors) abort();
	highlight_python_text(text, (int) n, colors);
	bridge_put_bytes(out, colors, n);
	free(text); free(colors);
}

static void b_highlight_nim(bridge_in *in, bridge_out *out)
{
	size_t n;
	unsigned char *text = bridge_bytes(in, &n), *colors = calloc(n + 1, 1);
	if (!colors) abort();
	highlight_nim_text(text, (int) n, colors);
	bridge_put_bytes(out, colors, n);
	free(text); free(colors);
}

/* (fe-highlight-markdown text): (colours ((start end info) ...)), the
 * blocks of code last first, as femtoscheme's builtin gives them */
static void b_highlight_markdown(bridge_in *in, bridge_out *out)
{
	size_t n;
	unsigned char *text = bridge_bytes(in, &n), *colors = calloc(n + 1, 1);
	hl_block *found;
	if (!colors) abort();
	int count = highlight_markdown_text(text, (int) n, colors, &found);
	bridge_put_list(out, 2);
	bridge_put_bytes(out, colors, n);
	bridge_put_list(out, count);
	for (int k = count - 1; k >= 0; k--) {
		bridge_put_list(out, 3);
		bridge_put_int(out, found[k].start);
		bridge_put_int(out, found[k].end);
		size_t len = (size_t) (found[k].info_end - found[k].info_start);
		bridge_put_string_n(out, (const char *) text + found[k].info_start, len);
	}
	free(found); free(text); free(colors);
}

/* ------------------------------------------------------------------ */
/* the assistants                                                      */
/* ------------------------------------------------------------------ */

static void put_answer(bridge_out *out, char *answer, const char *error)
{
	if (!answer) bridge_error(out, error);
	else { bridge_put_string(out, answer); free(answer); }
}

static void b_assistant_request(bridge_in *in, bridge_out *out)
{
	char *provider = bridge_string(in), *prompt = bridge_string(in);
	const char *error = "";
	put_answer(out, assistant_ask(provider, prompt, &error), error);
	free(provider); free(prompt);
}

static void b_ttfy_request(bridge_in *in, bridge_out *out)
{
	char *provider = bridge_string(in), *path = bridge_string(in),
	     *range = bridge_string(in), *guidelines = bridge_string(in);
	const char *error = "";
	put_answer(out, assistant_textify(provider, path, range, guidelines, &error), error);
	free(provider); free(path); free(range); free(guidelines);
}

void bridge_register_more(void)
{
	extern void bridge_register_eval(void);   /* compiled-eval.c */
	bridge_register_eval();
	static const struct { const char *name; bridge_fn fn; } fns[] = {
		{ "buffer-substring", b_buffer_substring },
		{ "buffer-bytes", b_buffer_bytes },
		{ "buffer-string", b_buffer_string },
		{ "fe-insert-bytes", b_insert_bytes },
		{ "fe-add-command-name", b_add_command_name },
		{ "fe-set-buffer-hint", b_set_buffer_hint },
		{ "fe-set-modeline-hints", b_set_modeline_hints },
		{ "fe-mouse-event", b_mouse_event },
		{ "command-prompt", b_command_prompt },
		{ "buffer-read-only?", b_buffer_read_only },
		{ "set-buffer-read-only!", b_set_buffer_read_only },
		{ "fe-set-completions", b_set_completions },
		{ "file-prompt", b_file_prompt },
		{ "file-attributes", b_file_attributes },
		{ "file-executable?", b_file_executable },
		{ "path.exists?", b_path_exists },
		{ "real-path", b_real_path },
		{ "format-time", b_format_time },
		{ "file-contents", b_file_contents },
		{ "directory-files", b_directory_files },
		{ "file-completions", b_file_completions },
		{ "run-program", b_run_program },
		{ "spawn-program", b_spawn_program },
		{ "os-name", b_os_name },
		{ "getpid", b_getpid },
		{ "current-jiffy", b_jiffy },
		{ "os.getenv", b_getenv },
		{ "os.setenv", b_setenv },
		{ "path.cwd", b_cwd },
		{ "fe-install-dir", b_install_dir },
		{ "fe-program-path", b_program_path },
		{ "fe-define-token-language", b_define_token_language },
		{ "fe-highlight-tokens", b_highlight_tokens },
		{ "fe-highlight-python", b_highlight_python },
		{ "fe-highlight-nim", b_highlight_nim },
		{ "fe-highlight-markdown", b_highlight_markdown },
		{ "assistant-request", b_assistant_request },
		{ "ttfy-request", b_ttfy_request },
	};
	for (size_t k = 0; k < sizeof fns / sizeof fns[0]; k++)
		bridge_register(fns[k].name, fns[k].fn);
}
