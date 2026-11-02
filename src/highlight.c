/*
 * highlight.c -- the tokenizers behind syntax highlighting
 *
 * The languages are defined in Scheme (scheme/highlight.scm,
 * scheme/languages/): DEFINE-LANGUAGE hands the tables -- comment
 * delimiters, strings, keywords, word characters -- to
 * fe-define-token-language, and HIGHLIGHT-OCTETS calls
 * fe-highlight-tokens.  The scanning itself is here, in C, because it runs
 * over the visible text (and 16 KB above it) at every redisplay; in
 * femtoscheme's bytecode it cost tens of milliseconds a key.  The Python and
 * Nim modes' highlighters (scheme/modes/) are here for the same reason, as
 * SBEmacs had a native Nim highlighter.
 *
 * Everything works on the raw UTF-8 bytes, so the colours stay aligned with
 * the C buffer; bytes >= 128 are word constituents.  This is a port of
 * SBEmacs's lisp/highlight.lisp and lisp/modes/{python,nim}-mode.lisp.
 */
#include <stdlib.h>
#include <string.h>
#include "llt/llt.h"
#include "flisp.h"
#include "highlight.h"

enum { F_SYMBOL = 1, F_KEYWORD = 4, F_ALPHA = 5, F_DIGITS = 6, F_COMMENT = 7,
       F_BLOCK = 8, F_STRING = 9, F_HEADING = 11, F_EMPHASIS = 12, F_LINK = 14 };

typedef unsigned char uchar;

/* ------------------------------------------------------------------ */
/* Languages defined by tables                                          */
/* ------------------------------------------------------------------ */

typedef hl_bytes bytes_t;

typedef struct {
	uchar word[256];
	bytes_t *line_comments; int n_line;
	bytes_t *block_open, *block_close; int n_block;
	bytes_t *strings; int n_strings;      /* longest first */
	int escape;                           /* a byte, or -1 */
	bytes_t char_prefix;                  /* n == 0: none */
	int backslash_commands;
	int case_insensitive;
	bytes_t *keywords[256]; int n_keywords[256];   /* by first byte, longest first */
} language_t;

static language_t **languages = NULL;
static int n_languages = 0;

static bytes_t copy_bytes(value_t v, const char *who)
{
	bytes_t b;
	if (!fl_isstring(v)) lerror(ArgError, who);
	b.n = (int) cvalue_len(v);
	b.s = malloc((size_t) b.n + 1);
	if (!b.s) lerror(MemoryError, who);
	memcpy(b.s, cvalue_data(v), (size_t) b.n);
	b.s[b.n] = 0;
	return b;
}

static int list_length(value_t l)
{
	int n = 0;
	while (iscons(l)) { n++; l = cdr_(l); }
	return n;
}

static bytes_t *string_list(value_t l, int *count, const char *who)
{
	int n = list_length(l), i = 0;
	bytes_t *v = calloc((size_t) (n ? n : 1), sizeof(bytes_t));
	if (!v) lerror(MemoryError, who);
	for (; iscons(l); l = cdr_(l)) v[i++] = copy_bytes(car_(l), who);
	*count = n;
	return v;
}

static int longer_first(const void *a, const void *b)
{
	return ((const bytes_t *) b)->n - ((const bytes_t *) a)->n;
}

/*
 * (fe-define-token-language word-chars line-comments block-comments strings
 *                           escape char-prefix backslash-commands
 *                           case-insensitive keywords)  -> an id
 */
static bytes_t dup_bytes(const bytes_t *b)
{
	bytes_t d;
	d.n = b->n;
	d.s = malloc((size_t) d.n + 1);
	if (!d.s) abort();
	if (d.n) memcpy(d.s, b->s, (size_t) d.n);
	d.s[d.n] = 0;
	return d;
}

static bytes_t *dup_list(const bytes_t *v, int n)
{
	bytes_t *d = calloc((size_t) (n ? n : 1), sizeof(bytes_t));
	if (!d) abort();
	for (int i = 0; i < n; i++) d[i] = dup_bytes(&v[i]);
	return d;
}

/* A language from its tables (copied); its id (highlight.h) */
int highlight_define_language(const hl_language_spec *spec)
{
	language_t *L = calloc(1, sizeof(language_t));
	if (!L) abort();
	for (int b = 0; b < 256; b++)
		L->word[b] = (b >= '0' && b <= '9') || (b >= 'A' && b <= 'Z') ||
			     (b >= 'a' && b <= 'z') || b == '_' || b >= 128;
	for (int i = 0; i < spec->word_chars.n; i++) L->word[(uchar) spec->word_chars.s[i]] = 1;
	L->line_comments = dup_list(spec->line_comments, spec->n_line);
	L->n_line = spec->n_line;
	L->n_block = spec->n_block;
	L->block_open = dup_list(spec->block_open, spec->n_block);
	L->block_close = dup_list(spec->block_close, spec->n_block);
	L->strings = dup_list(spec->strings, spec->n_strings);
	L->n_strings = spec->n_strings;
	qsort(L->strings, (size_t) L->n_strings, sizeof(bytes_t), longer_first);
	L->escape = spec->escape;
	if (spec->char_prefix.n > 0) L->char_prefix = dup_bytes(&spec->char_prefix);
	L->backslash_commands = spec->backslash_commands;
	L->case_insensitive = spec->case_insensitive;
	for (int k = 0; k < spec->n_keywords; k++) {
		bytes_t kw = dup_bytes(&spec->keywords[k]);
		if (kw.n == 0) { free(kw.s); continue; }
		if (L->case_insensitive)
			for (int i = 0; i < kw.n; i++)
				if (kw.s[i] >= 'A' && kw.s[i] <= 'Z') kw.s[i] += 32;
		uchar first = (uchar) kw.s[0];
		L->keywords[first] = realloc(L->keywords[first], sizeof(bytes_t) * (size_t) (L->n_keywords[first] + 1));
		L->keywords[first][L->n_keywords[first]++] = kw;
	}
	for (int b = 0; b < 256; b++)
		if (L->n_keywords[b] > 1)
			qsort(L->keywords[b], (size_t) L->n_keywords[b], sizeof(bytes_t), longer_first);
	languages = realloc(languages, sizeof(language_t *) * (size_t) (n_languages + 1));
	languages[n_languages] = L;
	return n_languages++;
}

static void free_list(bytes_t *v, int n)
{
	for (int i = 0; i < n; i++) free(v[i].s);
	free(v);
}

static value_t define_token_language(value_t *a, uint32_t n)
{
	const char *who = "fe-define-token-language";
	argcount((char *) who, n, 9);
	hl_language_spec spec;
	memset(&spec, 0, sizeof spec);
	spec.word_chars = copy_bytes(a[0], who);
	spec.line_comments = string_list(a[1], &spec.n_line, who);
	spec.n_block = list_length(a[2]);
	bytes_t *opens = calloc((size_t) (spec.n_block ? spec.n_block : 1), sizeof(bytes_t));
	bytes_t *closes = calloc((size_t) (spec.n_block ? spec.n_block : 1), sizeof(bytes_t));
	if (!opens || !closes) lerror(MemoryError, who);
	int k = 0;
	for (value_t l = a[2]; iscons(l); l = cdr_(l), k++) {
		value_t pair = car_(l);
		if (!iscons(pair)) lerror(ArgError, who);
		opens[k] = copy_bytes(car_(pair), who);
		closes[k] = copy_bytes(cdr_(pair), who);
	}
	spec.block_open = opens;
	spec.block_close = closes;
	spec.strings = string_list(a[3], &spec.n_strings, who);
	spec.escape = isfixnum(a[4]) ? (int) numval(a[4]) : -1;
	if (fl_isstring(a[5])) spec.char_prefix = copy_bytes(a[5], who);
	spec.backslash_commands = a[6] != FL_F;
	spec.case_insensitive = a[7] != FL_F;
	spec.keywords = string_list(a[8], &spec.n_keywords, who);
	int id = highlight_define_language(&spec);
	free(spec.word_chars.s);
	free_list(spec.line_comments, spec.n_line);
	free_list(opens, spec.n_block);
	free_list(closes, spec.n_block);
	free_list(spec.strings, spec.n_strings);
	free(spec.char_prefix.s);
	free_list(spec.keywords, spec.n_keywords);
	return fixnum(id);
}

static int match_at(const uchar *t, int len, int i, const bytes_t *p, int ci)
{
	if (i + p->n > len) return 0;
	for (int k = 0; k < p->n; k++) {
		int a = t[i + k], b = (uchar) p->s[k];
		if (a != b && !(ci && a >= 'A' && a <= 'Z' && a + 32 == b)) return 0;
	}
	return 1;
}

static int default_face(int b)
{
	return ((b >= '0' && b <= '9') || (b >= 'A' && b <= 'Z') || (b >= 'a' && b <= 'z') ||
		b == '_' || b >= 128) ? F_ALPHA : F_SYMBOL;
}

static void paint(uchar *c, int from, int to, int face)
{
	if (to > from) memset(c + from, face, (size_t) (to - from));
}

static int find_bytes(const uchar *t, int start, int end, const bytes_t *p)
{
	for (int i = start; i + p->n <= end; i++)
		if (!memcmp(t + i, p->s, (size_t) p->n)) return i;
	return -1;
}

static int scan_string_end(const language_t *L, const uchar *t, int len, int i, const bytes_t *delim)
{
	while (i < len) {
		if (L->escape >= 0 && t[i] == L->escape) i += 2;
		else if (match_at(t, len, i, delim, 0)) return i + delim->n;
		else i++;
	}
	return len;
}

static int is_digit(const uchar *t, int len, int j) { return j < len && t[j] >= '0' && t[j] <= '9'; }

static int scan_number(const language_t *L, const uchar *t, int len, int i)
{
	int j = i;
	if (j < len && (t[j] == '+' || t[j] == '-') && is_digit(t, len, j + 1)) j++;
	if (!is_digit(t, len, j)) return -1;
	if (t[j] == '0' && j + 1 < len && (t[j + 1] == 'x' || t[j + 1] == 'X')) {
		j += 2;
		while (j < len && ((t[j] >= '0' && t[j] <= '9') || (t[j] >= 'a' && t[j] <= 'f') ||
				   (t[j] >= 'A' && t[j] <= 'F'))) j++;
	} else {
		while (is_digit(t, len, j)) j++;
		if (j < len && t[j] == '.' && is_digit(t, len, j + 1)) {
			j++;
			while (is_digit(t, len, j)) j++;
		}
		if (j < len && (t[j] == 'e' || t[j] == 'E') &&
		    (is_digit(t, len, j + 1) ||
		     (j + 1 < len && (t[j + 1] == '+' || t[j + 1] == '-') && is_digit(t, len, j + 2)))) {
			j += 2;
			while (is_digit(t, len, j)) j++;
		}
	}
	if (j < len && L->word[t[j]]) return -1;      /* 12abc is not a number */
	return j;
}

static int scan_keyword(const language_t *L, const uchar *t, int len, int i)
{
	int b = t[i];
	if (L->case_insensitive && b >= 'A' && b <= 'Z') b += 32;
	for (int k = 0; k < L->n_keywords[b]; k++) {
		const bytes_t *kw = &L->keywords[b][k];
		int end = i + kw->n;
		if (match_at(t, len, i, kw, L->case_insensitive) &&
		    (!L->word[(uchar) kw->s[kw->n - 1]] || end >= len || !L->word[t[end]]))
			return end;
	}
	return -1;
}

static void highlight_tokens(const language_t *L, const uchar *t, int len, uchar *c)
{
	int i = 0;
	while (i < len) {
		int b = t[i], next = -1, k;
		int token_start = i == 0 || !L->word[t[i - 1]];
		for (k = 0; k < L->n_block && next < 0; k++)
			if (match_at(t, len, i, &L->block_open[k], 0)) {
				int end = find_bytes(t, i + L->block_open[k].n, len, &L->block_close[k]);
				next = end < 0 ? len : end + L->block_close[k].n;
				paint(c, i, next, F_BLOCK);
			}
		for (k = 0; k < L->n_line && next < 0; k++)
			if (match_at(t, len, i, &L->line_comments[k], 0)) {
				const uchar *nl = memchr(t + i, '\n', (size_t) (len - i));
				next = nl ? (int) (nl - t) : len;
				paint(c, i, next, F_COMMENT);
			}
		for (k = 0; k < L->n_strings && next < 0; k++)
			if (match_at(t, len, i, &L->strings[k], 0)) {
				next = scan_string_end(L, t, len, i + L->strings[k].n, &L->strings[k]);
				paint(c, i, next, F_STRING);
			}
		if (next < 0 && L->char_prefix.n && match_at(t, len, i, &L->char_prefix, 0)) {
			next = i + L->char_prefix.n + 1;
			if (next > len) next = len;
			while (next < len && L->word[t[next]]) next++;
			paint(c, i, next, F_ALPHA);
		}
		if (next < 0 && token_start && L->backslash_commands && b == '\\' && i + 1 < len &&
		    ((t[i + 1] | 32) >= 'a' && (t[i + 1] | 32) <= 'z')) {
			next = i + 1;
			while (next < len && (t[next] | 32) >= 'a' && (t[next] | 32) <= 'z') next++;
			paint(c, i, next, F_KEYWORD);
		}
		if (next < 0 && token_start && (next = scan_number(L, t, len, i)) >= 0)
			paint(c, i, next, F_DIGITS);
		if (next < 0 && token_start && (next = scan_keyword(L, t, len, i)) >= 0)
			paint(c, i, next, F_KEYWORD);
		if (next < 0 && L->word[b]) {
			/* an ordinary word, as a whole: digits inside identifiers
			   (x1, utf8) are not numbers */
			next = i + 1;
			while (next < len && L->word[t[next]]) next++;
			for (k = i; k < next; k++) c[k] = (uchar) default_face(t[k]);
		}
		if (next < 0) {
			c[i] = (uchar) default_face(b);
			next = i + 1;
		}
		i = next > i ? next : i + 1;
	}
}

static uchar *colors_of(value_t v, int len, const char *who)
{
	if (!iscvalue(v) || (int) cvalue_len(v) < len) lerror(ArgError, who);
	return (uchar *) cvalue_data(v);
}

/* (fe-highlight-tokens id text colors) */
static value_t highlight_tokens_builtin(value_t *a, uint32_t n)
{
	const char *who = "fe-highlight-tokens";
	argcount((char *) who, n, 3);
	fixnum_t id = tofixnum(a[0], (char *) who);
	if (id < 0 || id >= n_languages || !fl_isstring(a[1])) lerror(ArgError, who);
	int len = (int) cvalue_len(a[1]);
	highlight_tokens(languages[id], (const uchar *) cvalue_data(a[1]), len, colors_of(a[2], len, who));
	return FL_T;
}

int highlight_tokens_id(int id, const unsigned char *text, int len, unsigned char *colors)
{
	if (id < 0 || id >= n_languages) return 0;
	highlight_tokens(languages[id], text, len, colors);
	return 1;
}

/* ------------------------------------------------------------------ */
/* Python (scheme/modes/python-mode.scm)                               */
/* ------------------------------------------------------------------ */

enum { T_NEWLINE, T_COMMENT, T_NAME, T_STRING, T_NUMBER, T_OPERATOR };

typedef struct { int kind, start, end, prefix, quote, closed; } token_t;

typedef struct { token_t *v; int n, cap; } tokens_t;

static void push_token(tokens_t *ts, int kind, int start, int end, int prefix, int quote, int closed)
{
	if (ts->n == ts->cap) {
		ts->cap = ts->cap ? 2 * ts->cap : 256;
		ts->v = realloc(ts->v, sizeof(token_t) * (size_t) ts->cap);
		if (!ts->v) lerror(MemoryError, "highlight");
	}
	token_t *t = &ts->v[ts->n++];
	t->kind = kind; t->start = start; t->end = end;
	t->prefix = prefix; t->quote = quote; t->closed = closed;
}

static int name_start(int b) { return b == '_' || ((b | 32) >= 'a' && (b | 32) <= 'z') || b >= 128; }
static int name_part(int b) { return name_start(b) || (b >= '0' && b <= '9'); }
static int at(const uchar *s, int end, int i, const char *lit)
{
	int n = (int) strlen(lit);
	return i + n <= end && !memcmp(s + i, lit, (size_t) n);
}
static int char_end(const uchar *s, int end, int i)
{
	int b = s[i];
	int n = b < 0xC0 ? 1 : b < 0xE0 ? 2 : b < 0xF0 ? 3 : 4;
	return i + n < end ? i + n : end;
}

static int word_is(const uchar *s, int start, int end, const char *w)
{
	int n = (int) strlen(w);
	return end - start == n && !memcmp(s + start, w, (size_t) n);
}

static int word_in(const uchar *s, int start, int end, const char *const *words)
{
	for (; *words; words++)
		if (word_is(s, start, end, *words)) return 1;
	return 0;
}

static const char *const py_prefixes[] = { "r", "u", "b", "f", "br", "rb", "fr", "rf", "t", "tr", "rt", NULL };
static const char *const py_keywords[] = {
	"False", "None", "True", "and", "as", "assert", "async", "await", "break", "class",
	"continue", "def", "del", "elif", "else", "except", "finally", "for", "from", "global",
	"if", "import", "in", "is", "lambda", "nonlocal", "not", "or", "pass", "raise",
	"return", "try", "while", "with", "yield", NULL };
static const char *const py_builtins[] = {
	"abs", "all", "any", "ascii", "bin", "bool", "breakpoint", "bytearray", "bytes",
	"callable", "chr", "classmethod", "complex", "dict", "dir", "divmod", "enumerate",
	"eval", "exec", "filter", "float", "format", "frozenset", "getattr", "globals",
	"hasattr", "hash", "help", "hex", "id", "input", "int", "isinstance", "issubclass",
	"iter", "len", "list", "locals", "map", "max", "memoryview", "min", "next", "object",
	"oct", "open", "ord", "pow", "print", "property", "range", "repr", "reversed", "round",
	"set", "setattr", "slice", "sorted", "staticmethod", "str", "sum", "super", "tuple",
	"type", "vars", "zip", "__import__", NULL };

/* the end of the string opened at OPENING; *quote its delimiter's length */
static int py_string_end(const uchar *s, int end, int opening, int *quote, int *closed)
{
	int q = s[opening];
	int triple = opening + 2 < end && s[opening + 1] == q && s[opening + 2] == q;
	int dl = triple ? 3 : 1, i = opening + dl;
	*quote = dl;
	while (i < end) {
		if (s[i] == '\\') { i += 2; continue; }
		if (s[i] == q && (!triple || (i + 2 < end && s[i + 1] == q && s[i + 2] == q))) {
			*closed = 1;
			return i + dl;
		}
		if (!triple && (s[i] == '\n' || s[i] == '\r')) { *closed = 0; return i; }
		i++;
	}
	*closed = 0;
	return end;
}

static int py_number_end(const uchar *s, int end, int start)
{
	int i = start;
#define IN(set) (i < end && s[i] < 128 && strchr(set, s[i]) && s[i])
	if (start + 1 < end && s[start] == '0' && s[start + 1] && strchr("xobXOB", s[start + 1])) {
		const char *set = ((s[start + 1] | 32) == 'x') ? "0123456789abcdefABCDEF_" :
				  ((s[start + 1] | 32) == 'o') ? "01234567_" : "01_";
		i = start + 2;
		while (IN(set)) i++;
		return i;
	}
	while (IN("0123456789_")) i++;
	if (IN(".")) { i++; while (IN("0123456789_")) i++; }
	if (IN("eE")) {
		int e = i + 1;
		if (e < end && (s[e] == '+' || s[e] == '-')) e++;
		if (e < end && s[e] >= '0' && s[e] <= '9') {
			i = e + 1;
			while (IN("0123456789_")) i++;
		}
	}
	if (IN("jJ")) i++;
#undef IN
	return i;
}

static void py_lex(const uchar *s, int from, int end, tokens_t *ts)
{
	int i = from;
	while (i < end) {
		int c = s[i], start = i;
		if (c == ' ' || c == '\t' || c == '\r' || c == '\f') { i++; continue; }
		if (c == '\n') { push_token(ts, T_NEWLINE, i, i + 1, 0, 0, 1); i++; continue; }
		if (c == '#') {
			const uchar *nl = memchr(s + i, '\n', (size_t) (end - i));
			i = nl ? (int) (nl - s) : end;
			push_token(ts, T_COMMENT, start, i, 0, 0, 1);
			continue;
		}
		int opening = i, prefix = 0, word_end = -1;
		if (name_start(c)) {
			word_end = i + 1;
			while (word_end < end && name_part(s[word_end])) word_end++;
			int lower_is_prefix = 0;
			if (word_end - start <= 2) {
				char w[3] = { 0, 0, 0 };
				for (int k = start; k < word_end; k++) w[k - start] = (char) (s[k] | 32);
				for (int k = 0; py_prefixes[k]; k++)
					if (!strcmp(w, py_prefixes[k])) lower_is_prefix = 1;
			}
			if (lower_is_prefix && word_end < end && (s[word_end] == '"' || s[word_end] == '\'')) {
				opening = word_end;
				prefix = word_end - start;
			} else
				opening = -1;
		}
		if (opening < 0) {
			push_token(ts, T_NAME, start, word_end, 0, 0, 1);
			i = word_end;
		} else if (s[opening] == '"' || s[opening] == '\'') {
			int quote, closed;
			i = py_string_end(s, end, opening, &quote, &closed);
			push_token(ts, T_STRING, start, i, prefix, quote, closed);
		} else if ((c >= '0' && c <= '9') || (c == '.' && i + 1 < end && s[i + 1] >= '0' && s[i + 1] <= '9')) {
			i = py_number_end(s, end, start);
			push_token(ts, T_NUMBER, start, i, 0, 0, 1);
		} else {
			i = char_end(s, end, start);
			push_token(ts, T_OPERATOR, start, i, 0, 0, 1);
		}
	}
}

static void py_paint_tokens(const uchar *s, const token_t *v, int n, uchar *colors);

/* where the expression of an f-string field ends (*close: its closing brace) */
static int py_field_end(const uchar *s, int start, int end, int *close)
{
	char stack[256];
	int depth = 0, expression_end = end, i = start;
	while (i < end) {
		int c = s[i];
		if (c == '"' || c == '\'') { int q, cl; i = py_string_end(s, end, i, &q, &cl); continue; }
		if (c == '#') {
			const uchar *nl = memchr(s + i, '\n', (size_t) (end - i));
			i = nl ? (int) (nl - s) + 1 : end;
			continue;
		}
		if (c == '(' || c == '[' || c == '{') {
			if (depth < 255) stack[depth++] = (char) (c == '(' ? ')' : c == '[' ? ']' : '}');
		} else if (c == ')' || c == ']' || c == '}') {
			if (depth && stack[depth - 1] == c) depth--;
			else if (c == '}' && !depth) {
				*close = i;
				return expression_end < i ? expression_end : i;
			}
		} else if (!depth && (c == ':' || (c == '!' && !at(s, end, i, "!=")))) {
			if (i < expression_end) expression_end = i;
		}
		i++;
	}
	*close = end;
	return expression_end;
}

static void py_paint_fields(const uchar *s, int start, int end, uchar *colors)
{
	int i = start;
	while (i < end) {
		if (at(s, end, i, "{{") || at(s, end, i, "}}")) { i += 2; continue; }
		if (s[i] == '{') {
			int close, expr = py_field_end(s, i + 1, end, &close);
			tokens_t ts = { NULL, 0, 0 };
			colors[i] = F_SYMBOL;
			py_lex(s, i + 1, expr, &ts);
			py_paint_tokens(s, ts.v, ts.n, colors);
			free(ts.v);
			if (expr < close) {
				colors[expr] = F_SYMBOL;
				py_paint_fields(s, expr + 1, close, colors);
			}
			if (close < end) colors[close] = F_SYMBOL;
			i = close + 1 < end ? close + 1 : end;
			continue;
		}
		i++;
	}
}

static void py_paint_tokens(const uchar *s, const token_t *v, int n, uchar *colors)
{
	int *next = malloc(sizeof(int) * (size_t) (n ? n : 1));
	char *header = malloc((size_t) (n ? n : 1));
	if (!next || !header) { free(next); free(header); return; }
	/* the next significant token of each, and whether its line ends in ":" */
	int nx = -1, line_end = -1;
	for (int i = n - 1; i >= 0; i--) {
		next[i] = nx;
		if (v[i].kind == T_NEWLINE) { nx = -1; line_end = -1; }
		else if (v[i].kind != T_COMMENT) { nx = i; if (line_end < 0) line_end = i; }
		header[i] = line_end >= 0 && word_is(s, v[line_end].start, v[line_end].end, ":");
	}
	int expect = 0, decorator = 0, significant = -1;   /* index of the last significant token */
	for (int i = 0; i < n; i++) {
		const token_t *t = &v[i];
		int face = F_ALPHA, a = t->start, b = t->end;
		int nn = next[i];
		switch (t->kind) {
		case T_NEWLINE: decorator = expect = 0; significant = -1; break;
		case T_COMMENT: face = F_COMMENT; break;
		case T_STRING: face = F_STRING; break;
		case T_NUMBER: face = F_DIGITS; break;
		case T_OPERATOR:
			face = F_SYMBOL;
			if (word_is(s, a, b, "@") && significant < 0) decorator = 1;
			break;
		case T_NAME:
			if (expect) { face = F_HEADING; expect = 0; }
			else if (word_in(s, a, b, py_keywords)) {
				face = F_KEYWORD;
				expect = word_is(s, a, b, "def") || word_is(s, a, b, "class");
			} else if (significant < 0 && (word_is(s, a, b, "match") || word_is(s, a, b, "case")) && header[i])
				face = F_KEYWORD;
			else if (significant < 0 && word_is(s, a, b, "type") && nn >= 0 &&
				 !word_is(s, v[nn].start, v[nn].end, "=") && !word_is(s, v[nn].start, v[nn].end, "(") &&
				 name_start(s[v[nn].start]))
				face = F_KEYWORD;
			else if (decorator) face = F_LINK;
			else if (word_in(s, a, b, py_builtins) && nn >= 0 && word_is(s, v[nn].start, v[nn].end, "(") &&
				 !(significant >= 0 && word_is(s, v[significant].start, v[significant].end, ".")))
				face = F_EMPHASIS;
			break;
		}
		paint(colors, a, b, face);
		if (t->kind == T_STRING && t->prefix) {
			int f = 0;
			for (int k = a; k < a + t->prefix; k++) if ((s[k] | 32) == 'f' || (s[k] | 32) == 't') f = 1;
			if (f) py_paint_fields(s, a + t->prefix + t->quote, t->closed ? b - t->quote : b, colors);
		}
		if (t->kind != T_COMMENT && t->kind != T_NEWLINE) significant = i;
	}
	free(next);
	free(header);
}

/* (fe-highlight-python text colors) */
static value_t highlight_python(value_t *a, uint32_t n)
{
	const char *who = "fe-highlight-python";
	argcount((char *) who, n, 2);
	if (!fl_isstring(a[0])) lerror(ArgError, who);
	int len = (int) cvalue_len(a[0]);
	highlight_python_text((const uchar *) cvalue_data(a[0]), len, colors_of(a[1], len, who));
	return FL_T;
}

void highlight_python_text(const unsigned char *s, int len, unsigned char *colors)
{
	tokens_t ts = { NULL, 0, 0 };
	memset(colors, F_ALPHA, (size_t) len);
	py_lex(s, 0, len, &ts);
	py_paint_tokens(s, ts.v, ts.n, colors);
	free(ts.v);
}

/* ------------------------------------------------------------------ */
/* Nim (scheme/modes/nim-mode.scm)                                     */
/* ------------------------------------------------------------------ */

static const char *const nim_keywords[] = {
	"addr", "and", "as", "asm", "bind", "block", "break", "case", "cast", "concept",
	"const", "continue", "converter", "defer", "discard", "distinct", "div", "do",
	"elif", "else", "end", "enum", "except", "export", "finally", "for", "from",
	"func", "if", "import", "in", "include", "interface", "is", "isnot", "iterator",
	"let", "macro", "method", "mixin", "mod", "nil", "not", "notin", "object",
	"of", "or", "out", "proc", "ptr", "raise", "ref", "return", "shl", "shr",
	"static", "template", "try", "tuple", "type", "using", "var", "when", "while",
	"xor", "yield", NULL };
static const char *const nim_definers[] = {
	"proc", "func", "method", "iterator", "converter", "macro", "template", NULL };

static void nim_lex(const uchar *s, int end, tokens_t *ts)
{
	int i = 0;
	while (i < end) {
		int c = s[i], start = i;
		if (c == ' ' || c == '\t' || c == '\r') { i++; continue; }
		if (c == '\n') { push_token(ts, T_NEWLINE, i, i + 1, 0, 0, 1); i++; continue; }
		if (at(s, end, i, "#[") || at(s, end, i, "##[")) {
			const char *stack[64];
			int depth = 0;
			stack[depth++] = at(s, end, i, "##[") ? "]##" : "]#";
			i += at(s, end, i, "##[") ? 3 : 2;
			while (i < end && depth) {
				if (at(s, end, i, "##[")) { if (depth < 64) stack[depth++] = "]##"; i += 3; }
				else if (at(s, end, i, "#[")) { if (depth < 64) stack[depth++] = "]#"; i += 2; }
				else if (at(s, end, i, stack[depth - 1])) i += (int) strlen(stack[--depth]);
				else i++;
			}
			push_token(ts, T_COMMENT, start, i, 0, 0, depth == 0);
			continue;
		}
		if (c == '#') {
			const uchar *nl = memchr(s + i, '\n', (size_t) (end - i));
			i = nl ? (int) (nl - s) : end;
			push_token(ts, T_COMMENT, start, i, 0, 0, 1);
			continue;
		}
		if (c == '`') {
			const uchar *q = memchr(s + i + 1, '`', (size_t) (end - i - 1));
			i = q ? (int) (q - s) + 1 : end;
			push_token(ts, T_NAME, start, i, 0, 0, 1);
			continue;
		}
		if (c >= '0' && c <= '9') {
			i++;
			while (i < end && (name_part(s[i]) || s[i] == '\'' ||
					   (s[i] == '.' && !at(s, end, i, "..")) ||
					   ((s[i] == '+' || s[i] == '-') && (s[i - 1] | 32) == 'e'))) i++;
			push_token(ts, T_NUMBER, start, i, 0, 0, 1);
			continue;
		}
		int opening = i, raw = 0;
		if (name_start(c)) {
			int w = i + 1;
			while (w < end && name_part(s[w])) w++;
			if (w < end && s[w] == '"') { opening = w; raw = 1; }
			else { push_token(ts, T_NAME, start, w, 0, 0, 1); i = w; continue; }
		}
		if (s[opening] == '"' || s[opening] == '\'') {
			int q = s[opening];
			int dl = (q == '"' && at(s, end, opening, "\"\"\"")) ? 3 : 1, closed = 0;
			i = opening + dl;
			while (i < end) {
				if (raw && dl == 1 && at(s, end, i, "\"\"")) { i += 2; continue; }
				if ((dl == 3 && at(s, end, i, "\"\"\"")) || (dl == 1 && s[i] == q)) { i += dl; closed = 1; break; }
				if (!raw && dl == 1 && s[i] == '\\') { i = i + 2 < end ? i + 2 : end; continue; }
				if (dl == 1 && s[i] == '\n') break;
				i++;
			}
			push_token(ts, T_STRING, start, i, 0, dl, closed);
			continue;
		}
		i = char_end(s, end, i);
		push_token(ts, T_OPERATOR, start, i, 0, 0, 1);
	}
}

/* is the Nim name S[a, b) WORD, comparing as Nim does? */
static int nim_word_is(const uchar *s, int a, int b, const char *word)
{
	if (a >= b || s[a] != (uchar) word[0]) return 0;
	const char *w = word + 1;
	for (int k = a + 1; k < b; k++) {
		int c = s[k];
		if (c == '_') continue;
		if (c >= 'A' && c <= 'Z') c += 32;
		if (*w != c) return 0;
		w++;
	}
	return *w == 0;
}

static int nim_word_in(const uchar *s, int a, int b, const char *const *words)
{
	for (; *words; words++) if (nim_word_is(s, a, b, *words)) return 1;
	return 0;
}

/* (fe-highlight-nim text colors) */
static value_t highlight_nim(value_t *a, uint32_t n)
{
	const char *who = "fe-highlight-nim";
	argcount((char *) who, n, 2);
	if (!fl_isstring(a[0])) lerror(ArgError, who);
	int len = (int) cvalue_len(a[0]);
	highlight_nim_text((const uchar *) cvalue_data(a[0]), len, colors_of(a[1], len, who));
	return FL_T;
}

void highlight_nim_text(const unsigned char *s, int len, unsigned char *colors)
{
	tokens_t ts = { NULL, 0, 0 };
	memset(colors, F_ALPHA, (size_t) len);
	nim_lex(s, len, &ts);
	int expect = 0;
	for (int i = 0; i < ts.n; i++) {
		const token_t *t = &ts.v[i];
		int face = F_ALPHA;
		switch (t->kind) {
		case T_COMMENT: face = F_COMMENT; break;
		case T_STRING: face = F_STRING; break;
		case T_NUMBER: face = F_DIGITS; break;
		case T_OPERATOR: face = F_SYMBOL; break;
		case T_NEWLINE: expect = 0; break;
		case T_NAME:
			if (expect) { face = F_HEADING; expect = 0; }
			else if (nim_word_in(s, t->start, t->end, nim_keywords)) {
				face = F_KEYWORD;
				expect = nim_word_in(s, t->start, t->end, nim_definers);
			} else if (nim_word_is(s, t->start, t->end, "true") || nim_word_is(s, t->start, t->end, "false"))
				face = F_KEYWORD;
			break;
		}
		paint(colors, t->start, t->end, face);
	}
	free(ts.v);
}

/* ------------------------------------------------------------------ */
/* Markdown (scheme/languages/markdown.scm)                            */
/* ------------------------------------------------------------------ */

enum { F_STRONG = 13 };

static int md_skip_spaces(const uchar *t, int i, int end)
{
	while (i < end && t[i] == ' ') i++;
	return i;
}

/* after a list marker (- * + 1. 1)) and its spaces, or -1 */
static int md_list_marker_end(const uchar *t, int i, int end)
{
	if (i >= end) return -1;
	int b = t[i], j;
	if (b == '-' || b == '*' || b == '+') j = i + 1;
	else if (b >= '0' && b <= '9') {
		j = i;
		while (j < end && t[j] >= '0' && t[j] <= '9' && j - i < 9) j++;
		if (!(j < end && (t[j] == '.' || t[j] == ')'))) return -1;
		j++;
	} else
		return -1;
	if (j == end || t[j] == ' ' || t[j] == '\t') return md_skip_spaces(t, j, end);
	return -1;
}

/* a code fence (``` or ~~~, up to 3 spaces in): its byte; *n its length */
static int md_fence(const uchar *t, int ls, int le, int *n)
{
	int i = md_skip_spaces(t, ls, le);
	if (i - ls > 3 || i + 2 >= le) return 0;
	int b = t[i];
	if (b != '`' && b != '~') return 0;
	int j = i;
	while (j < le && t[j] == b) j++;
	if (j - i < 3) return 0;
	*n = j - i;
	return b;
}

static int md_rule_p(const uchar *t, int ls, int le)
{
	int i = md_skip_spaces(t, ls, le), n = 0;
	if (i >= le) return 0;
	int b = t[i];
	if (b != '-' && b != '*' && b != '_') return 0;
	for (int k = i; k < le; k++) {
		if (t[k] == b) n++;
		else if (t[k] != ' ' && t[k] != '\t') return 0;
	}
	return n >= 3;
}

static int md_setext_underline_p(const uchar *t, int ls, int le)
{
	int i = md_skip_spaces(t, ls, le);
	if (i >= le || i - ls > 3 || (t[i] != '=' && t[i] != '-')) return 0;
	int b = t[i], j = i;
	while (j < le && t[j] == b) j++;
	return md_skip_spaces(t, j, le) == le;
}

static int md_blank_p(const uchar *t, int ls, int le)
{
	for (int k = ls; k < le; k++)
		if (t[k] != ' ' && t[k] != '\t' && t[k] != '\r') return 0;
	return 1;
}

static int md_word(int b) { return (b >= '0' && b <= '9') || ((b | 32) >= 'a' && (b | 32) <= 'z') || b >= 128; }
static int md_space(int b) { return b == ' ' || b == '\t' || b == '\n' || b == '\r'; }

static int md_run_at(const uchar *t, int k, int b, int n)
{
	for (int m = 0; m < n; m++) if (t[k + m] != b) return 0;
	return 1;
}

static int md_closing_delimiter(const uchar *t, int start, int end, int b, int n)
{
	for (int k = start; k <= end - n; k++)
		if (md_run_at(t, k, b, n) && !md_space(t[k - 1]) &&
		    (k + n >= end || t[k + n] != b) &&
		    (b != '_' || k + n >= end || !md_word(t[k + n])))
			return k;
	return -1;
}

static int md_find(const uchar *t, int start, int end, const char *lit)
{
	int n = (int) strlen(lit);
	for (int i = start; i + n <= end; i++)
		if (!memcmp(t + i, lit, (size_t) n)) return i;
	return -1;
}

static int md_find_byte(const uchar *t, int start, int end, int b)
{
	for (int i = start; i < end; i++) if (t[i] == b) return i;
	return -1;
}

static void md_inline(const uchar *t, int start, int end, uchar *c)
{
	int i = start;
	while (i < end) {
		int b = t[i], next = i + 1;
		if (b == '\\' && i + 1 < end)                   /* \* is a literal star */
			next = i + 2;
		else if (b == '`') {                            /* `code`, ``code with ` `` */
			int j = i;
			while (j < end && t[j] == '`') j++;
			int n = j - i, close = -1;
			for (int k = j; k <= end - n; k++)
				if (md_run_at(t, k, '`', n) && (k + n == end || t[k + n] != '`')) { close = k; break; }
			if (close >= 0) { paint(c, i, close + n, F_STRING); next = close + n; }
			else next = j;
		} else if (b == '[' || (b == '!' && i + 1 < end && t[i + 1] == '[')) {
			int open = b == '!' ? i + 1 : i;
			int close = md_find_byte(t, open, end, ']');
			if (close < 0) next = open + 1;
			else {
				paint(c, i, close + 1, F_LINK);
				next = close + 1;
				if (next < end && (t[next] == '(' || t[next] == '[')) {
					int stop = md_find_byte(t, next, end, t[next] == '(' ? ')' : ']');
					if (stop >= 0) { paint(c, next, stop + 1, F_COMMENT); next = stop + 1; }
				}
			}
		} else if (b == '<') {                          /* <https://...>, <!-- x -->, <tag> */
			int close = md_find_byte(t, i, end, '>');
			if (close >= 0) {
				if (i + 3 < end && t[i + 1] == '!') { paint(c, i, close + 1, F_BLOCK); next = close + 1; }
				else if (md_find(t, i, close, "://") >= 0) { paint(c, i, close + 1, F_LINK); next = close + 1; }
			}
		} else if (b == 'h' && (i == start || !md_word(t[i - 1])) &&
			   (at(t, end, i, "https://") || at(t, end, i, "http://"))) {
			int stop = i;
			while (stop < end && !md_space(t[stop]) && t[stop] != ')' && t[stop] != '>') stop++;
			paint(c, i, stop, F_LINK);
			next = stop;
		} else if (b == '~' && i + 1 < end && t[i + 1] == '~') {   /* ~~strike~~ */
			int close = md_find(t, i + 2, end, "~~");
			if (close >= 0) { paint(c, i, close + 2, F_COMMENT); next = close + 2; }
		} else if (b == '*' || b == '_') {              /* *emphasis*, **strong** */
			int j = i;
			while (j < end && t[j] == b && j - i < 3) j++;
			int n = j - i;
			next = j;
			if (j < end && !md_space(t[j]) && (b != '_' || i == start || !md_word(t[i - 1]))) {
				int close = md_closing_delimiter(t, j + 1, end, b, n);
				if (close >= 0) {
					paint(c, i, close + n, n >= 2 ? F_STRONG : F_EMPHASIS);
					md_inline(t, j, close, c);      /* marks inside **strong `code`** */
					if (n >= 2)
						for (int k = j; k < close; k++) if (c[k] == F_ALPHA) c[k] = F_STRONG;
					next = close + n;
				}
			}
		}
		i = next > i ? next : i + 1;
	}
}

static int md_heading_p(const uchar *t, int ls, int le)
{
	int i = md_skip_spaces(t, ls, le);
	if (i - ls > 3 || i >= le || t[i] != '#') return 0;
	int j = i;
	while (j < le && t[j] == '#') j++;
	return j - i <= 6 && (j == le || t[j] == ' ');
}

/*
 * (fe-highlight-markdown text colors): colour TEXT as Markdown.  The blocks
 * of code are painted as strings; the result lists them as (start end info),
 * so that Scheme can colour those whose info string names a language.
 */
int highlight_markdown_text(const unsigned char *t, int len, unsigned char *c, hl_block **found)
{
	hl_block *blocks = NULL;
	int n_blocks = 0, cap = 0;
	int fence = 0, fence_len = 0, code_start = 0, info_start = 0, info_end = 0;
	int comment = 0, prev_ls = -1, prev_paragraph = 0;
	memset(c, F_ALPHA, (size_t) len);
#define FINISH_CODE(stop) do { \
		paint(c, code_start, (stop), F_STRING); \
		if (n_blocks == cap) { \
			cap = cap ? 2 * cap : 16; \
			blocks = realloc(blocks, sizeof(hl_block) * (size_t) cap); \
			if (!blocks) abort(); \
		} \
		blocks[n_blocks].start = code_start; blocks[n_blocks].end = (stop); \
		blocks[n_blocks].info_start = info_start; blocks[n_blocks].info_end = info_end; \
		n_blocks++; \
	} while (0)
	for (int ls = 0; ls < len; ) {
		const uchar *nl = memchr(t + ls, '\n', (size_t) (len - ls));
		int le = nl ? (int) (nl - t) : len, paragraph = 0, n, b;
		if (fence) {                                     /* inside ```code``` */
			b = md_fence(t, ls, le, &n);
			if (b == fence && n >= fence_len &&
			    md_skip_spaces(t, md_skip_spaces(t, ls, le) + n, le) == le) {
				FINISH_CODE(ls);
				paint(c, ls, le, F_COMMENT);
				fence = 0;
			}
		} else if (comment) {                            /* a <!-- comment --> over lines */
			int close = md_find(t, ls, le, "-->");
			if (close >= 0) {
				paint(c, ls, close + 3, F_BLOCK);
				comment = 0;
				md_inline(t, close + 3, le, c);
			} else
				paint(c, ls, le, F_BLOCK);
		} else if ((b = md_fence(t, ls, le, &n))) {      /* ``` opens a block of code */
			int i = md_skip_spaces(t, ls, le) + n;
			while (i < le && t[i] == ' ') i++;
			int e = le;
			while (e > i && (t[e - 1] == ' ' || t[e - 1] == '\r')) e--;
			fence = b; fence_len = n;
			code_start = le + 1 < len ? le + 1 : len;
			info_start = i; info_end = e;
			paint(c, ls, le, F_COMMENT);
		} else if (prev_paragraph && md_setext_underline_p(t, ls, le))
			paint(c, prev_ls, le, F_HEADING);
		else if (md_rule_p(t, ls, le))
			paint(c, ls, le, F_COMMENT);
		else if (md_heading_p(t, ls, le)) {
			paint(c, ls, le, F_HEADING);
			md_inline(t, ls, le, c);
			for (int k = ls; k < le; k++) if (c[k] != F_STRING) c[k] = F_HEADING;
		} else {
			int i = md_skip_spaces(t, ls, le), after;
			if (i < le && t[i] == '>')                   /* > quotation */
				paint(c, ls, le, F_COMMENT);
			else if (i + 3 < le && at(t, le, i, "<!--") && md_find(t, i, le, "-->") < 0) {
				paint(c, ls, le, F_BLOCK);
				comment = 1;
			} else if ((after = md_list_marker_end(t, i, le)) >= 0) {
				paint(c, i, after, F_KEYWORD);
				if (after + 2 < le && t[after] == '[' && t[after + 2] == ']' &&
				    (t[after + 1] == ' ' || (t[after + 1] | 32) == 'x')) {
					paint(c, after, after + 3, F_KEYWORD);
					md_inline(t, after + 3, le, c);
				} else
					md_inline(t, after, le, c);
			} else if (i < le && t[i] == '|') {           /* | table | row | */
				int rule = 1;
				for (int k = ls; k < le; k++)
					if (!strchr("|-: \t\r", t[k])) { rule = 0; break; }
				if (rule) paint(c, ls, le, F_COMMENT);
				else {
					md_inline(t, ls, le, c);
					for (int k = ls; k < le; k++) if (t[k] == '|') c[k] = F_KEYWORD;
				}
			} else if (!md_blank_p(t, ls, le)) {
				paragraph = 1;
				md_inline(t, ls, le, c);
			}
		}
		prev_ls = ls;
		prev_paragraph = paragraph;
		ls = le + 1;
	}
	/* a block of code still open at the end of the visible text */
	if (fence && code_start < len) FINISH_CODE(len);
#undef FINISH_CODE
	*found = blocks;
	return n_blocks;
}

/* the femtoscheme builtin: the blocks, last first, as (start end info) */
static value_t highlight_markdown(value_t *a, uint32_t nargs)
{
	const char *who = "fe-highlight-markdown";
	argcount((char *) who, nargs, 2);
	if (!fl_isstring(a[0])) lerror(ArgError, who);
	int len = (int) cvalue_len(a[0]);
	colors_of(a[1], len, who);
	uchar *t = malloc((size_t) len + 1), *c = malloc((size_t) len + 1);
	if (!t || !c) lerror(MemoryError, who);
	memcpy(t, cvalue_data(a[0]), (size_t) len);
	hl_block *found;
	int n = highlight_markdown_text(t, len, c, &found);
	memcpy(cvalue_data(a[1]), c, (size_t) len);
	value_t blocks = FL_NIL, info = FL_NIL, block = FL_NIL;
	fl_gc_handle(&blocks); fl_gc_handle(&info); fl_gc_handle(&block);
	for (int k = 0; k < n; k++) {
		info = cvalue_string((size_t) (found[k].info_end - found[k].info_start));
		memcpy(cvalue_data(info), t + found[k].info_start, (size_t) (found[k].info_end - found[k].info_start));
		block = fl_cons(info, FL_NIL);
		block = fl_cons(fixnum(found[k].end), block);
		block = fl_cons(fixnum(found[k].start), block);
		blocks = fl_cons(block, blocks);
	}
	fl_free_gc_handles(3);
	free(found); free(t); free(c);
	return blocks;
}

void highlight_init(void)
{
	static builtinspec_t functions[] = {
		{ "fe-define-token-language", define_token_language },
		{ "fe-highlight-tokens", highlight_tokens_builtin },
		{ "fe-highlight-python", highlight_python },
		{ "fe-highlight-nim", highlight_nim },
		{ "fe-highlight-markdown", highlight_markdown },
		{ NULL, NULL }
	};
	assign_global_builtins(functions);
}
