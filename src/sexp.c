/*
 * sexp.c -- Lisp expressions in the C core, as Emacs's scan-sexps and
 * scan-lists (26 November 2026)
 *
 * C-M-f, C-M-b, C-M-k, C-M-SPC (emacs-keys.scm, through fe-scan-sexp) and
 * the paren highlight (command.c, match_parens) read the text as Lisp:
 * a paren in a string, in a ; comment, in a #| |# comment (nested), in a
 * |symbol| or written as a character (#\( #\)) is not a paren.  Before,
 * the scans went from the cursor only: C-M-b stopped on a ) in a comment,
 * #| |# was not known, and the highlight matched parens in strings.
 *
 * Knowing whether a place is in a string or a comment means reading from
 * the start of the text.  Emacs keeps, for that, the list of the open
 * parens around each place (syntax-ppss): on 10 MB of ( never closed, a
 * list of ten million, and seconds a key.  Here the state is five numbers
 * (in what, how deep the #| |#, how deep the parens, an escape), kept
 * every 64 KB at a newline or a paren (checkpoints): reading starts from
 * the last one before the place, so at most some 64 KB more.  A change
 * drops the checkpoints after it (record_change calls sexp_changed).
 *
 * Which buffers are Lisp: their file's extension, as the languages of
 * scheme/languages say (Scheme, Common Lisp, VHDL Lisp).
 */
#include "header.h"

#define CK_EVERY 65536

enum { M_CODE, M_STRING, M_LINE, M_BLOCK, M_BAR };

typedef struct {
	long off;               /* the state just before this offset */
	long depth;             /* parens open (may go below 0: unbalanced) */
	int mode, bdepth, esc;
} ckpt_t;

typedef struct {
	long id;                /* buffer_t b_id, 0 = free */
	ckpt_t *v;
	int n, cap;
	unsigned long used;
} cache_t;

#define NCACHE 8
static cache_t caches[NCACHE];
static unsigned long uses;

static int is_space(int c) { return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f' || c == '\v'; }
static int is_open(int c) { return c == '(' || c == '[' || c == '{'; }
static int is_close(int c) { return c == ')' || c == ']' || c == '}'; }
static int is_prefix(int c) { return c == '\'' || c == '`' || c == ','; }
/* what ends a symbol */
static int is_delim(int c) { return is_space(c) || is_open(c) || is_close(c) || c == '"' || c == ';' || is_prefix(c); }

/* the byte at I (0 <= I < size), past the gap */
static inline int at(buffer_t *bp, long i)
{
	long gap = bp->b_gap - bp->b_buf;
	return i < gap ? bp->b_buf[i] : bp->b_egap[i - gap];
}

int sexp_lisp_buffer(buffer_t *bp)
{
	static const char *ext[] = { ".scm", ".ss", ".lsp", ".sld", ".lisp", ".cl", ".asd", ".el", ".vlsp", NULL };
	const char *dot, *name = bp->b_fname[0] ? bp->b_fname : bp->b_bname;
	int k;
	if ((dot = strrchr(name, '.')) == NULL) return 0;
	for (k = 0; ext[k]; k++) if (strcmp(dot, ext[k]) == 0) return 1;
	return 0;
}

static cache_t *cache_of(buffer_t *bp)
{
	cache_t *c, *oldest = &caches[0];
	int k;
	for (k = 0; k < NCACHE; k++) {
		c = &caches[k];
		if (c->id == bp->b_id) { c->used = ++uses; return c; }
		if (c->used < oldest->used) oldest = c;
	}
	oldest->id = bp->b_id;
	oldest->n = 0;
	oldest->used = ++uses;
	return oldest;
}

/* record_change: the text changed at POS; what is known after it goes */
void sexp_changed(buffer_t *bp, long pos)
{
	int k;
	if (bp == NULL) return;
	for (k = 0; k < NCACHE; k++) {
		cache_t *c = &caches[k];
		if (c->id != bp->b_id) continue;
		while (c->n > 0 && c->v[c->n - 1].off > pos) c->n--;
	}
}

void sexp_buffer_gone(buffer_t *bp)
{
	int k;
	for (k = 0; k < NCACHE; k++)
		if (caches[k].id == bp->b_id) { caches[k].id = 0; caches[k].n = 0; caches[k].used = 0; }
}

static void add_ckpt(cache_t *c, long off, long depth, int mode, int bdepth, int esc)
{
	if (c->n > 0 && off < c->v[c->n - 1].off + CK_EVERY) return;
	if (c->n == c->cap) {
		int cap = c->cap ? 2 * c->cap : 64;
		ckpt_t *v = realloc(c->v, (size_t) cap * sizeof *v);
		if (v == NULL) return;
		c->v = v;
		c->cap = cap;
	}
	c->v[c->n].off = off;
	c->v[c->n].depth = depth;
	c->v[c->n].mode = mode;
	c->v[c->n].bdepth = bdepth;
	c->v[c->n].esc = esc;
	c->n++;
}

/*
 * The lexer.  It reads [from, to) from state S and leaves the state at
 * TO in S.  Element starts at depth WANT are watched (WANT < 0: none): the
 * start of the last one before TO is *LAST (prefixes ' ` , #' included),
 * -1 when none, or when the depth went below WANT after it.  *BELOW: the
 * depth went below WANT.  A byte that a token took past TO (#\( at TO-2)
 * leaves *PAST > TO.  CACHE: checkpoints are added as it goes.  STOP >= 0:
 * it stops after the close that brings the depth back to STOP (*PAST: the
 * offset after it).
 */
typedef struct {
	long depth;
	int mode, bdepth, esc;
} lex_t;

static void lex(buffer_t *bp, long from, long to, lex_t *s, long want, long *last, int *below,
		long *past, cache_t *cache, long stop)
{
	long i = from, pending = -1, size = document_size(bp);
	int atom = 0;

	if (last) *last = -1;
	if (below) *below = 0;
	while (i < to) {
		int c = at(bp, i);
		long here = i++;
		switch (s->mode) {
		case M_STRING:
			if (s->esc) s->esc = 0;
			else if (c == '\\') s->esc = 1;
			else if (c == '"') { s->mode = M_CODE; atom = 0; }
			break;
		case M_BAR:
			if (s->esc) s->esc = 0;
			else if (c == '\\') s->esc = 1;
			else if (c == '|') { s->mode = M_CODE; atom = 1; }
			break;
		case M_LINE:
			if (c == '\n') s->mode = M_CODE;
			break;
		case M_BLOCK:
			if (c == '|' && i < size && at(bp, i) == '#') { i++; if (--s->bdepth == 0) s->mode = M_CODE; }
			else if (c == '#' && i < size && at(bp, i) == '|') { i++; s->bdepth++; }
			break;
		default: {
			int next = i < size ? at(bp, i) : -1;
			long start = -1;              /* an element starts here */
			if (c == ';') { s->mode = M_LINE; atom = 0; pending = -1; break; }
			if (c == '#' && next == '|' && !atom) { s->mode = M_BLOCK; s->bdepth = 1; i++; break; }
			if (is_space(c)) { atom = 0; break; }
			if (is_prefix(c) && !atom) {
				if (pending < 0) pending = here;
				if (c == ',' && next == '@') i++;
				break;
			}
			if (c == '#' && !atom && (next == '(' || next == '\'' || next == ';' || next == '`' || next == ',')) {
				if (pending < 0) pending = here;      /* #( #' #; ... */
				if (next != '(') i++;
				break;
			}
			if (is_open(c)) {
				start = here;
				if (want >= 0 && s->depth == want && last) *last = pending >= 0 ? pending : start;
				pending = -1;
				s->depth++;
				atom = 0;
				break;
			}
			if (is_close(c)) {
				s->depth--;
				atom = 0;
				pending = -1;
				if (want >= 0 && s->depth < want) { if (last) *last = -1; if (below) *below = 1; }
				if (stop >= 0 && s->depth == stop) { if (past) *past = i; return; }
				break;
			}
			if (!atom) {
				start = here;
				if (want >= 0 && s->depth == want && last) *last = pending >= 0 ? pending : start;
				pending = -1;
			}
			if (c == '"') { s->mode = M_STRING; atom = 0; break; }
			if (c == '|') { s->mode = M_BAR; break; }
			if (c == '#' && next == '\\') {          /* #\x: x is any character */
				i++;
				if (i < size) {
					i++;
					while (i < size && (at(bp, i) & 0xC0) == 0x80) i++;
				}
				atom = 1;
				break;
			}
			if (c == '\\') { if (i < size) i++; atom = 1; break; }
			atom = 1;
			break;
		}
		}
		/* a checkpoint: after a newline, or a paren in code; never inside
		   a symbol nor after a prefix */
		if (cache && (c == '\n' || (s->mode == M_CODE && (is_open(c) || is_close(c)))) &&
		    !atom && pending < 0 && i == here + 1)
			add_ckpt(cache, i, s->depth, s->mode, s->bdepth, s->esc);
	}
	if (past) *past = i;
}

/* the state just before POS: from the last checkpoint at or before it */
static long state_at(buffer_t *bp, cache_t *c, long pos, lex_t *s, long *past)
{
	int lo = 0, hi = c->n - 1, k = -1;
	long from = 0;

	while (lo <= hi) {
		int mid = (lo + hi) / 2;
		if (c->v[mid].off <= pos) { k = mid; lo = mid + 1; } else hi = mid - 1;
	}
	s->depth = 0; s->mode = M_CODE; s->bdepth = 0; s->esc = 0;
	if (k >= 0) {
		from = c->v[k].off;
		s->depth = c->v[k].depth; s->mode = c->v[k].mode;
		s->bdepth = c->v[k].bdepth; s->esc = c->v[k].esc;
	}
	lex(bp, from, pos, s, -1, NULL, NULL, past, c, -1);
	return from;
}

/* forward from I, in code: past white space and comments */
static long skip_blank(buffer_t *bp, long i, long size)
{
	while (i < size) {
		int c = at(bp, i);
		if (is_space(c)) { i++; continue; }
		if (c == ';') { while (i < size && at(bp, i) != '\n') i++; continue; }
		if (c == '#' && i + 1 < size && at(bp, i + 1) == '|') {
			int d = 1;
			i += 2;
			while (i < size && d > 0) {
				int a = at(bp, i);
				if (a == '|' && i + 1 < size && at(bp, i + 1) == '#') { d--; i += 2; }
				else if (a == '#' && i + 1 < size && at(bp, i + 1) == '|') { d++; i += 2; }
				else i++;
			}
			continue;
		}
		break;
	}
	return i;
}

/* The end of the expression after FROM (in code): -1 none (the end of a
 * list, or of the text), -2 not closed */
static long sexp_end(buffer_t *bp, long from)
{
	long size = document_size(bp), i = skip_blank(bp, from, size), dummy;
	lex_t s;
	int c;

	/* prefixes: 'x `x ,x ,@x #'x #( */
	while (i < size) {
		c = at(bp, i);
		if (is_prefix(c)) { i += (c == ',' && i + 1 < size && at(bp, i + 1) == '@') ? 2 : 1; continue; }
		if (c == '#' && i + 1 < size && (at(bp, i + 1) == '\'' || at(bp, i + 1) == '`' || at(bp, i + 1) == ';')) { i += 2; continue; }
		if (c == '#' && i + 1 < size && at(bp, i + 1) == '(') { i++; break; }
		break;
	}
	i = skip_blank(bp, i, size);
	if (i >= size) return -1;
	c = at(bp, i);
	if (is_close(c)) return -1;
	if (is_open(c)) {                       /* to the close that brings depth back */
		s.depth = 0; s.mode = M_CODE; s.bdepth = 0; s.esc = 0;
		dummy = -1;
		lex(bp, i, size, &s, -1, NULL, NULL, &dummy, NULL, 0);
		return s.depth == 0 && s.mode == M_CODE && dummy <= size ? dummy : -2;
	}
	if (c == '"') {
		long j = i + 1;
		while (j < size) {
			int a = at(bp, j);
			if (a == '\\') { j += 2; continue; }
			if (a == '"') return j + 1;
			j++;
		}
		return -2;
	}
	if (c == '|') {                         /* |a b|: a symbol, that may go on */
		long j = i + 1;
		while (j < size && at(bp, j) != '|') j += at(bp, j) == '\\' ? 2 : 1;
		if (j >= size) return -2;
		i = j + 1;
	}
	/* a symbol, a number, #\x */
	if (i + 1 < size && at(bp, i) == '#' && at(bp, i + 1) == '\\') {
		i += 2;
		if (i < size) { i++; while (i < size && (at(bp, i) & 0xC0) == 0x80) i++; }
	}
	while (i < size) {
		c = at(bp, i);
		if (c == '\\') { i += 2; continue; }
		if (c == '|') {
			i++;
			while (i < size && at(bp, i) != '|') i += at(bp, i) == '\\' ? 2 : 1;
			i++;
			continue;
		}
		if (is_delim(c)) break;
		i++;
	}
	return i > size ? size : i;
}

/*
 * The start of the expression before POS: -1 none (the start of a list,
 * or of the text).  Read forward from checkpoints: the last element that
 * starts at the depth of POS; when none starts after a checkpoint and the
 * depth there was not below, it is before it: the checkpoint before.
 */
static long sexp_start(buffer_t *bp, cache_t *c, long pos, long want)
{
	int k;
	lex_t s;
	long last, past;
	int below;

	long to = pos;

	/* the checkpoint at or before POS; then the one before, each read up
	   to where the next began (read again to POS each time, C-M-b over
	   a definition of 6 MB took a second) */
	for (k = c->n - 1; k >= 0 && c->v[k].off > pos; k--) ;
	for (;;) {
		long from = k >= 0 ? c->v[k].off : 0;
		s.depth = k >= 0 ? c->v[k].depth : 0;
		s.mode = k >= 0 ? c->v[k].mode : M_CODE;
		s.bdepth = k >= 0 ? c->v[k].bdepth : 0;
		s.esc = k >= 0 ? c->v[k].esc : 0;
		lex(bp, from, to, &s, want, &last, &below, &past, NULL, -1);
		/* found; or the list around POS opens here; or the text begins */
		if (last >= 0 || below || k < 0) return last;
		if (k >= 0 && c->v[k].depth < want && c->v[k].mode == M_CODE) return last;
		to = from;                      /* no element after FROM: before it */
		k--;
	}
}

/*
 * (fe-scan-sexp FROM DIR): in a Lisp buffer, the other end of the
 * expression after FROM (DIR 1) or before it (DIR -1); -1 none there, -2
 * not closed, -3 FROM is in a string or a comment (the caller reads it as
 * text, as before).
 */
long fe_scan_sexp(long from, long dir)
{
	buffer_t *bp = curbp;
	cache_t *c = cache_of(bp);
	long size = document_size(bp), past;
	lex_t s;

	if (from < 0) from = 0;
	if (from > size) from = size;
	(void) state_at(bp, c, from, &s, &past);
	if (s.mode != M_CODE || past > from) return -3;
	if (dir > 0) return sexp_end(bp, from);
	return sexp_start(bp, c, from, s.depth);
}

/*
 * command.c, match_parens, in a Lisp buffer: the paren at OFF (an open or
 * a close) and its match, read as Lisp.  1 when OFF is a paren of the
 * code and its match is found (*MATCH), 0 otherwise.
 */
int sexp_match_paren(buffer_t *bp, long off, long *match)
{
	cache_t *c = cache_of(bp);
	long past, size = document_size(bp), r;
	lex_t s;
	int ch;

	if (off < 0 || off >= size) return 0;
	(void) state_at(bp, c, off, &s, &past);
	if (s.mode != M_CODE || past > off) return 0;          /* in a string, a comment, #\( */
	ch = at(bp, off);
	if (is_open(ch)) {
		r = sexp_end(bp, off);
		if (r < 0) return 0;
		*match = r - 1;
		return 1;
	}
	if (is_close(ch)) {
		long start = sexp_start(bp, c, off + 1, s.depth - 1);
		while (start >= 0 && start < off && !is_open(at(bp, start))) start++;   /* past 'x #( */
		if (start < 0 || start >= off) return 0;
		*match = start;
		return 1;
	}
	return 0;
}
