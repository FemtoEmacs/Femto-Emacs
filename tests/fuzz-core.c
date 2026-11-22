/*
 * fuzz-core.c -- random walks over the C core, under the sanitizers
 * (make check-fuzz-core; 21 November 2026).
 *
 * The real command.c, gap.c, display.c, fold.c, narrow.c, undo.c and
 * interface.c, without a terminal and without Scheme, are driven by random
 * sequences of the commands that are C functions: typing (ASCII, Greek,
 * Korean, Chinese, emoji, combining accents, and bytes that are not UTF-8),
 * C-f, C-b, C-n, C-p, C-a, C-e, M-f, M-b, M-<, M->, DEL, C-d, C-SPC, C-w,
 * M-w, C-k, C-y, overwrite, folds, narrowing, and the region operations the
 * scripts use (fe-delete-region, fe-insert-bytes).  After every command the
 * invariants are checked:
 *
 *   gap     b_buf <= b_gap <= b_egap <= b_ebuf
 *   range   0 <= point <= size; the mark is unset or 0 <= mark <= size
 *   utf8    the text stays well-formed UTF-8, and point and the mark are on
 *           character boundaries (Lean/utf8-cursor.lean: WF, Boundary)
 *   folds   a fold hides whole characters (FoldOK); C-f, C-b, C-n and C-p
 *           never leave point in hidden text
 *   undo    the changes reported for undo (record_change), applied backward
 *           to the text, give back the text of the last checkpoint, and
 *           applied forward to that text, give the text now
 *
 * A walk that starts from text with stray bytes (as a file can have) checks
 * only gap, range and undo: there "boundary" is not defined.  The
 * sanitizers check the rest: no read or write outside the buffers.
 *
 * A failing walk is replayed in a child process and shrunk (keys are
 * removed while it still fails) to the shortest sequence that breaks, which
 * is printed with its seed.  Usage:
 *
 *   fuzz-core [-s SEED] [-n WALKS] [-k KEYS] [-t SECONDS] [-q]
 */
#include "header.h"
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#include <fcntl.h>

extern void fe_set_change_hook(void (*)(long, int, long, const char_t *, long));
extern int fe_fold(long, long);
extern void fe_unfold(long, long);
extern int fe_narrow(long, long);
extern void fe_widen(void);
extern void fe_delete_region(long, long);
extern void fe_insert_bytes(long, char *, long);

static int columns = 40;
int screen_cols(void) { return columns; }
int screen_rows(void) { return 24; }
const char *screen_unctrl(int c) { (void) c; return "^?"; }
void msg(char *s, ...) { (void) s; }
void fatal(char *s) { (void) s; abort(); }
int chez_tester_clipboard_isolated(void) { return 1; }
void screen_set_clipboard(const char *s) { (void) s; }

/* ---- random numbers: xorshift64*, reproducible from the seed ---- */
static unsigned long long rng;
static unsigned long long next(void)
{
	rng ^= rng >> 12; rng ^= rng << 25; rng ^= rng >> 27;
	return rng * 2685821657736338717ULL;
}
static unsigned below(unsigned n) { return (unsigned) (next() % n); }

/* ---- the operations ---- */
enum { TYPE, OVERWRITE, FWD, BWD, UP, DOWN, BOL, EOL, FWORD, BWORD, BOB, EOB,
       BACKSP, DEL, MARK, CUT, COPY, KILL, YANK, FOLD, UNFOLD, NARROW, WIDEN,
       DELREGION, INSBYTES, RESIZE, NOPS };
static const char *names[] = { "type", "overwrite", "C-f", "C-b", "C-p", "C-n",
	"C-a", "C-e", "M-f", "M-b", "M-<", "M->", "DEL", "C-d", "C-SPC", "C-w",
	"M-w", "C-k", "C-y", "fold", "unfold", "narrow", "widen",
	"fe-delete-region", "fe-insert-bytes", "resize" };
static const int weight[] = { 30, 1, 10, 10, 4, 4, 3, 3, 4, 4, 2, 2,
	8, 8, 4, 3, 2, 3, 3, 2, 1, 1, 1, 3, 3, 1 };
typedef struct { int op; unsigned a, b; char_t text[8]; } op_t;

/* the characters typed: one to four bytes, accents, and bytes that are
   not a character (a continuation alone, a lead without its continuation,
   an overlong C0, F5, FF) */
static const char *chars[] = {
	"a", "z", " ", "\n", "(", "\t",
	"\xce\xb1", "\xcf\x89", "\xc3\xa3",                     /* α ω ã */
	"\xea\xb0\x80", "\xed\x9e\xa3", "\xe4\xb8\xad", "\xe6\x96\x87", /* 가 힣 中 文 */
	"\xf0\x9f\x99\x82", "\xf0\x9f\x8c\x8d",                 /* 🙂 🌍 */
	"\xcc\x81", "\xcc\x83", "\xcd\x82",                     /* combining accents */
	"\x80", "\xbf", "\xc3", "\xe4\xb8", "\xf0\x9f\x99", "\xc0\xaf", "\xf5", "\xff" };
#define NCHARS (sizeof chars / sizeof *chars)

static op_t random_op(void)
{
	op_t o = { 0, 0, 0, {0} };
	unsigned total = 0, k, r;
	for (k = 0; k < NOPS; k++) total += (unsigned) weight[k];
	r = below(total);
	for (k = 0; r >= (unsigned) weight[k]; k++) r -= (unsigned) weight[k];
	o.op = (int) k;
	o.a = (unsigned) next();
	o.b = (unsigned) next();
	if (o.op == TYPE || o.op == INSBYTES) {
		const char *c = chars[below(NCHARS)];
		memcpy(o.text, c, strlen(c) + 1);
	}
	return o;
}

/* ---- the text, the checkpoint and the reported changes ---- */
static char_t *text_of(buffer_t *bp, point_t *n)
{
	point_t size = document_size(bp), i;
	char_t *t = malloc((size_t) size + 1);
	for (i = 0; i < size; i++) t[i] = *ptr(bp, i);
	*n = size;
	return t;
}

typedef struct { int kind; point_t pos; char_t *bytes; long len; } change_t;
static change_t *journal;
static int njournal, capjournal;
static char_t *base;            /* the text at the checkpoint */
static point_t nbase;
static int journal_broken;

static void change_hook_fn(long id, int kind, long pos, const char_t *bytes, long len)
{
	(void) id;
	if (kind == 'r') { journal_broken = 1; return; }   /* history erased: checkpoint again */
	if (kind != 'i' && kind != 'd') return;
	if (njournal == capjournal) {
		capjournal = capjournal ? 2 * capjournal : 64;
		journal = realloc(journal, (size_t) capjournal * sizeof *journal);
	}
	journal[njournal].kind = kind;
	journal[njournal].pos = (point_t) pos;
	journal[njournal].len = len;
	journal[njournal].bytes = malloc((size_t) len + 1);
	memcpy(journal[njournal].bytes, bytes, (size_t) len);
	njournal++;
}

static void clear_journal(void)
{
	int k;
	for (k = 0; k < njournal; k++) free(journal[k].bytes);
	njournal = 0;
	journal_broken = 0;
}

/* apply change C to T (N bytes, capacity enough), forward or backward */
static int apply(char_t *t, point_t *n, const change_t *c, int forward)
{
	int insert = (c->kind == 'i') == forward;
	if (c->pos < 0 || c->pos > *n) return 0;
	if (insert) {
		memmove(t + c->pos + c->len, t + c->pos, (size_t) (*n - c->pos));
		memcpy(t + c->pos, c->bytes, (size_t) c->len);
		*n += c->len;
	} else {
		if (c->pos + c->len > *n || memcmp(t + c->pos, c->bytes, (size_t) c->len)) return 0;
		memmove(t + c->pos, t + c->pos + c->len, (size_t) (*n - c->pos - c->len));
		*n -= c->len;
	}
	return 1;
}

static const char *check_journal(buffer_t *bp)
{
	point_t n, m, cap;
	char_t *now = text_of(bp, &n), *t;
	long total = 0;
	int k;
	const char *why = NULL;

	for (k = 0; k < njournal; k++) total += journal[k].len;
	cap = n + nbase + total + 1;
	t = malloc((size_t) cap);
	memcpy(t, now, (size_t) n); m = n;
	for (k = njournal - 1; k >= 0 && !why; k--)
		if (!apply(t, &m, &journal[k], 0)) why = "undo: a reported change does not match the text (backward)";
	if (!why && (m != nbase || memcmp(t, base, (size_t) m)))
		why = "undo: the reported changes, undone, do not give back the text of the checkpoint";
	memcpy(t, base, (size_t) nbase); m = nbase;
	for (k = 0; k < njournal && !why; k++)
		if (!apply(t, &m, &journal[k], 1)) why = "undo: a reported change does not match the text (forward)";
	if (!why && (m != n || memcmp(t, now, (size_t) m)))
		why = "undo: the reported changes, redone, do not give the text";
	free(t);
	free(base);
	base = now; nbase = n;
	clear_journal();
	return why;
}

/* ---- the invariants ---- */
static int cont(char_t c) { return (c & 0xC0) == 0x80; }
static int lead_size(char_t c)
{
	if (c < 0x80) return 1;
	if (c >= 0xC2 && c <= 0xDF) return 2;
	if (c >= 0xE0 && c <= 0xEF) return 3;
	if (c >= 0xF0 && c <= 0xF4) return 4;
	return 0;
}
static int boundary(buffer_t *bp, point_t p)
{
	return p == document_size(bp) || !cont(*ptr(bp, p));
}
static int well_formed(buffer_t *bp)
{
	point_t size = document_size(bp), i = 0;
	while (i < size) {
		int n = lead_size(*ptr(bp, i)), k;
		if (n == 0 || i + n > size) return 0;
		for (k = 1; k < n; k++) if (!cont(*ptr(bp, i + k))) return 0;
		i += n;
	}
	return 1;
}

static int strict;                       /* the walk started from well-formed text */

static const char *check(buffer_t *bp, int op)
{
	point_t size = document_size(bp);
	int k;
	if (!(bp->b_buf <= bp->b_gap && bp->b_gap <= bp->b_egap && bp->b_egap <= bp->b_ebuf))
		return "gap: the gap is out of the buffer";
	if (bp->b_point < 0 || bp->b_point > size) return "range: point outside the text";
	if (bp->b_mark != NOMARK && (bp->b_mark < 0 || bp->b_mark > size))
		return "range: the mark outside the text";
	if (strict) {
		if (!well_formed(bp)) return "utf8: the text is no longer well-formed UTF-8";
		if (!boundary(bp, bp->b_point)) return "utf8: point between the bytes of a character";
		if (bp->b_mark != NOMARK && !boundary(bp, bp->b_mark))
			return "utf8: the mark between the bytes of a character";
		for (k = 0; k < bp->b_nfolds; k++) {
			fold_t *f = &bp->b_folds[k];
			if (f->a < 0 || f->b <= f->a || f->b >= size) return "folds: a fold outside the text";
			if (!boundary(bp, f->a) || !boundary(bp, f->a + 1) || !boundary(bp, f->b + 1))
				return "folds: a fold hides part of a character";
		}
		if ((op == FWD || op == BWD || op == UP || op == DOWN) && fold_hidden(bp, bp->b_point))
			return "folds: a motion left point in hidden text";
	}
	return NULL;
}

/* ---- one walk ---- */
static char *initial_text(int clean, point_t *n)
{
	static char t[512];
	int len = (int) below(120), i = 0;
	while (i < len) {
		const char *c = chars[below(clean ? NCHARS - 8 : NCHARS)];
		size_t k = strlen(c);
		if (clean && !strcmp(c, "\xcc\x81") && i == 0) continue;
		memcpy(t + i, c, k); i += (int) k;
	}
	*n = i;
	return t;
}

/* Run OPS[0..N) on a fresh buffer; NULL, or what broke (and where) */
static const char *walk(unsigned long long seed, op_t *ops, int n, int *where)
{
	static buffer_t b;
	static window_t w;
	point_t len;
	char *t;
	const char *why = NULL;
	int i;

	rng = seed ? seed : 1;
	strict = below(4) != 0;              /* one walk in four starts with stray bytes */
	memset(&b, 0, sizeof b);
	b.b_mark = NOMARK;
	strcpy(b.b_bname, "fuzz");
	if (!growgap(&b, 1 + below(16))) return "gap: growgap failed";
	t = initial_text(strict, &len);
	if (len > 0) {
		if (b.b_egap - b.b_gap < len && !growgap(&b, len)) return "gap: growgap failed";
		memcpy(b.b_gap, t, (size_t) len);
		b.b_gap += len;
	}
	b.b_point = (point_t) below((unsigned) len + 1);
	while (strict && !boundary(&b, b.b_point)) b.b_point--;
	memset(&w, 0, sizeof w);
	w.w_bufp = &b; w.w_rows = 10;
	curbp = bheadp = &b; curwp = wheadp = &w;
	columns = 20 + (int) below(60);
	utf8_fix = 1;
	set_scrap((unsigned char *) strdup(""));
	clear_journal();
	free(base);
	base = text_of(&b, &nbase);
	fe_set_change_hook(change_hook_fn);

	for (i = 0; i < n && !why; i++) {
		op_t *o = &ops[i];
		point_t size = document_size(&b);
		*where = i;
		switch (o->op) {
		case TYPE: input = o->text; insert(); break;
		case OVERWRITE: toggle_overwrite_mode(); break;
		case FWD: forward_character(); break;
		case BWD: backward_character(); break;
		case UP: up(); break;
		case DOWN: down(); break;
		case BOL: lnbegin(); break;
		case EOL: lnend(); break;
		case FWORD: forward_word(); break;
		case BWORD: backward_word(); break;
		case BOB: beginning_of_buffer(); break;
		case EOB: end_of_buffer(); break;
		case BACKSP: backsp(); break;
		case DEL: delete(); break;
		case MARK: b.b_mark = b.b_point; break;
		case CUT: cut(); break;
		case COPY: copy(); break;
		case KILL: killtoeol(); break;
		case YANK: paste(); break;
		case FOLD: {
			point_t a = (point_t) (o->a % (unsigned) (size + 1)), z = (point_t) (o->b % (unsigned) (size + 1));
			if (a > z) { point_t s = a; a = z; z = s; }
			/* as Org folds: from a newline to the newline before the next heading */
			while (a > 0 && *ptr(&b, a) != '\n') a--;
			while (z < size && *ptr(&b, z) != '\n') z++;
			(void) fe_fold((long) a, (long) z);
			break;
		}
		case UNFOLD: fe_unfold(0, size); break;
		case NARROW: {
			point_t a = (point_t) (o->a % (unsigned) (size + 1)), z = (point_t) (o->b % (unsigned) (size + 1));
			while (a > 0 && !boundary(&b, a)) a--;
			while (z < size && !boundary(&b, z)) z++;
			(void) fe_narrow((long) (a < z ? a : z), (long) (a < z ? z : a));
			break;
		}
		case WIDEN: fe_widen(); break;
		case DELREGION: {
			point_t a = (point_t) (o->a % (unsigned) (size + 1)), z = a + (point_t) (o->b % 9);
			while (a > 0 && !boundary(&b, a)) a--;
			while (z < size && !boundary(&b, z)) z++;
			fe_delete_region((long) a, (long) z);
			break;
		}
		case INSBYTES: {
			point_t a = (point_t) (o->a % (unsigned) (size + 1));
			while (strict && a > 0 && !boundary(&b, a)) a--;
			/* the scripts insert whole characters; undo inserts any bytes */
			if (!strict || lead_size(o->text[0]) == (int) strlen((char *) o->text))
				fe_insert_bytes((long) a, (char *) o->text, (long) strlen((char *) o->text));
			break;
		}
		case RESIZE: columns = 20 + (int) (o->a % 60); break;
		}
		/* the display, between keys: point leaves hidden text (display.c) */
		if (b.b_nfolds && fold_hidden(&b, b.b_point) && o->op != FWD && o->op != BWD &&
		    o->op != UP && o->op != DOWN)
			fold_reveal(&b, b.b_point);
		why = check(&b, o->op);
		if (!why && (journal_broken || (i % 32 == 31) || i == n - 1)) {
			if (journal_broken) { free(base); base = text_of(&b, &nbase); clear_journal(); }
			else why = check_journal(&b);
		}
	}
	fe_set_change_hook(NULL);
	return why;
}

/* ---- replay in a child, shrink, print ---- */
static unsigned long long seed0;

/* Run the walk in a child process, so that a sanitizer's abort is a
 * failure like the others; LOUD lets it print what broke. */
static int run_child(op_t *ops, int n, int loud)
{
	pid_t pid;
	int status, where;
	fflush(stdout);
	pid = fork();
	if (pid == 0) {
		const char *why;
		if (!loud) {
			int devnull = open("/dev/null", O_WRONLY);
			if (devnull >= 0) { dup2(devnull, 2); dup2(devnull, 1); }
		}
		why = walk(seed0, ops, n, &where);
		if (why && loud) printf("key %d: %s\n", where + 1, why);
		fflush(stdout);
		_exit(why ? 1 : 0);
	}
	if (pid < 0 || waitpid(pid, &status, 0) < 0) return 1;
	return !(WIFEXITED(status) && WEXITSTATUS(status) == 0);
}
static int fails(op_t *ops, int n) { return run_child(ops, n, 0); }

static int shrink(op_t *ops, int n)
{
	int chunk = n / 2;
	while (chunk >= 1) {
		int i = 0, removed = 0;
		while (i < n) {
			int k = i + chunk > n ? n - i : chunk;
			op_t *trial = malloc((size_t) n * sizeof *trial);
			memcpy(trial, ops, (size_t) i * sizeof *trial);
			memcpy(trial + i, ops + i + k, (size_t) (n - i - k) * sizeof *trial);
			if (n - k > 0 && fails(trial, n - k)) {
				memcpy(ops, trial, (size_t) (n - k) * sizeof *trial);
				n -= k; removed = 1;
			} else i += k;
			free(trial);
		}
		if (!removed) chunk /= 2;
	}
	return n;
}

static void show(op_t *o)
{
	printf("  %s", names[o->op]);
	if (o->op == TYPE || o->op == INSBYTES) {
		const char_t *c;
		printf(" \"");
		for (c = o->text; *c; c++) printf("\\x%02x", *c);
		printf("\"");
	}
	if (o->op == FOLD || o->op == NARROW || o->op == DELREGION || o->op == INSBYTES || o->op == RESIZE)
		printf(" (%u %u)", o->a, o->b);
	printf("\n");
}

/*
 * The walks that found the faults of 21 November 2026, shrunk, replayed
 * first in every run: each failed before its fix.
 *   M-b stopped inside a character, or at -1 with the gap at 0;
 *   C-SPC, DEL, then typing a character put the mark inside it (the mark
 *     did not follow the text);
 *   C-k and C-f at the end of the text read a byte past the buffer;
 *   C-d on a lead byte cut short (a file that ends inside a character)
 *     moved the gap past the buffer.
 */
static const struct { unsigned long long seed; int n; op_t ops[12]; } regressions[] = {
	{ 1, 1, { { BWORD, 0, 0, {0} } } },
	{ 1, 3, { { MARK, 0, 0, {0} }, { BACKSP, 0, 0, {0} }, { TYPE, 0, 0, "\xff" } } },
	{ 1, 2, { { KILL, 0, 0, {0} }, { FWD, 0, 0, {0} } } },
	{ 32, 11, { { INSBYTES, 1824017871u, 208569902u, "\x0a" }, { BACKSP, 0, 0, {0} }, { EOL, 0, 0, {0} },
		    { DEL, 0, 0, {0} }, { DELREGION, 806333059u, 3436197984u, {0} },
		    { INSBYTES, 1490175203u, 897474353u, "\xc3" }, { KILL, 0, 0, {0} }, { BOB, 0, 0, {0} },
		    { DEL, 0, 0, {0} }, { FWD, 0, 0, {0} }, { DEL, 0, 0, {0} } } },
};

int main(int argc, char **argv)
{
	unsigned long long seed = (unsigned long long) time(NULL);
	int walks = 2000, keys = 300, quiet = 0, opt, w;
	double seconds = 0;
	time_t start = time(NULL);
	while ((opt = getopt(argc, argv, "s:n:k:t:q")) != -1) {
		if (opt == 's') seed = strtoull(optarg, NULL, 10);
		else if (opt == 'n') walks = atoi(optarg);
		else if (opt == 'k') keys = atoi(optarg);
		else if (opt == 't') seconds = atof(optarg);
		else if (opt == 'q') quiet = 1;
	}
	for (w = 0; w < (int) (sizeof regressions / sizeof *regressions); w++) {
		op_t ops[12];
		memcpy(ops, regressions[w].ops, sizeof ops);
		seed0 = regressions[w].seed;
		if (fails(ops, regressions[w].n)) {
			int i;
			printf("FAIL regression %d (seed %llu) breaks again:\n", w + 1, seed0);
			for (i = 0; i < regressions[w].n; i++) show(&ops[i]);
			(void) run_child(ops, regressions[w].n, 1);
			return 1;
		}
	}
	if (!quiet) {
		if (seconds > 0) printf("fuzz-core: seed %llu, walks of %d keys for %g seconds\n", seed, keys, seconds);
		else printf("fuzz-core: seed %llu, %d walks of %d keys\n", seed, walks, keys);
	}
	/* with -t, walks until the time is up; else WALKS walks */
	for (w = 0; seconds > 0 ? difftime(time(NULL), start) < seconds : w < walks; w++) {
		op_t *ops = malloc((size_t) keys * sizeof *ops);
		int i;
		seed0 = seed + (unsigned long long) w;
		rng = seed0 * 0x9E3779B97F4A7C15ULL + 1;
		for (i = 0; i < keys; i++) ops[i] = random_op();
		if (fails(ops, keys)) {
			int n;
			printf("FAIL walk %d (seed %llu):\n", w, seed0);
			n = shrink(ops, keys);
			printf("shortest sequence that breaks (%d keys; replay: fuzz-core -s %llu -n 1 -k %d):\n", n, seed0, keys);
			for (i = 0; i < n; i++) show(&ops[i]);
			printf("what breaks:\n");
			(void) run_child(ops, n, 1);
			free(ops);
			return 1;
		}
		free(ops);
	}
	printf("PASS fuzz-core: %d random walks of %d keys (seed %llu), every invariant after every key\n", w, keys, seed);
	return 0;
}
