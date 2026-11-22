/*
 * check.c -- the editor checks itself (21 November 2026)
 *
 * With CHEZWEB_CHECK=1 in the environment, after every key, before and
 * after its display (main.c; SHOWN), the editor checks the invariants of every buffer and window,
 * and on the first one broken writes what broke (to standard error and to
 * the file $CHEZWEB_CHECK_FILE, when set) and aborts.  tests/fuzz-editor.sh
 * types random keys into an editor run so, under the sanitizers: a broken
 * invariant ends the run at the key that broke it.  Without the variable
 * the editor pays one test of an int per key.
 *
 *   gap     b_buf <= b_gap <= b_egap <= b_ebuf, and the sentinel after the
 *           text is 0 (gap.c)
 *   range   point, mark, page start of every buffer and window are in the
 *           text
 *   utf8    in a buffer of well-formed UTF-8 (up to 1 MB, where the check
 *           costs little), point and mark, of the buffer and of every
 *           window, are on character boundaries (Lean/utf8-cursor.lean)
 *   folds   a fold hides whole characters, and after the display the cursor
 *           is not in hidden text
 *   narrow  after the display, in a narrowed buffer, point is in the
 *           visible part
 */
#include "header.h"

int check_mode;

static void fail(buffer_t *bp, const char *what, long value)
{
	char line[1024];
	const char *file = getenv("CHEZWEB_CHECK_FILE");
	snprintf(line, sizeof line, "CHEZWEB_CHECK: %s (buffer %s, %ld; point %ld, mark %ld, size %ld, gap %ld..%ld)\n",
		what, bp ? bp->b_bname : "-", value, bp ? (long) bp->b_point : -1L, bp ? (long) bp->b_mark : -1L,
		bp ? (long) document_size(bp) : -1L, bp ? (long) (bp->b_gap - bp->b_buf) : -1L,
		bp ? (long) (bp->b_egap - bp->b_buf) : -1L);
	if (file && *file) {
		FILE *f = fopen(file, "a");
		if (f) { fputs(line, f); fclose(f); }
	}
	if (screen_active()) screen_end();
	fputs(line, stderr);
	abort();
}

static int cont(char_t c) { return (c & 0xC0) == 0x80; }

static int well_formed(buffer_t *bp)
{
	point_t size = document_size(bp), i = 0;
	while (i < size) {
		char_t c = *ptr(bp, i);
		int n = c < 0x80 ? 1 : c >= 0xC2 && c <= 0xDF ? 2 : c >= 0xE0 && c <= 0xEF ? 3 :
			c >= 0xF0 && c <= 0xF4 ? 4 : 0, k;
		if (n == 0 || i + n > size) return 0;
		for (k = 1; k < n; k++) if (!cont(*ptr(bp, i + k))) return 0;
		i += n;
	}
	return 1;
}

static int boundary(buffer_t *bp, point_t p)
{
	return p == document_size(bp) || !cont(*ptr(bp, p));
}

static void check_point(buffer_t *bp, point_t p, int wf, const char *range, const char *inside)
{
	if (p < 0 || p > document_size(bp)) fail(bp, range, (long) p);
	if (wf && !boundary(bp, p)) fail(bp, inside, (long) p);
}

void editor_check(int shown)
{
	buffer_t *bp;
	window_t *wp;
	int k;

	if (!check_mode) return;
	for (bp = bheadp; bp != NULL; bp = bp->b_next) {
		point_t size;
		int wf;
		if (bp->b_buf == NULL) continue;
		if (!(bp->b_buf <= bp->b_gap && bp->b_gap <= bp->b_egap && bp->b_egap <= bp->b_ebuf))
			fail(bp, "gap: the gap is out of the buffer", 0);
		if (*bp->b_ebuf != 0) fail(bp, "gap: the sentinel after the text was overwritten", *bp->b_ebuf);
		size = document_size(bp);
		wf = utf8_fix && size <= 1024 * 1024 && well_formed(bp);
		check_point(bp, bp->b_point, wf, "range: point outside the text", "utf8: point between the bytes of a character");
		if (bp->b_mark != NOMARK)
			check_point(bp, bp->b_mark, wf, "range: the mark outside the text", "utf8: the mark between the bytes of a character");
		if (bp->b_page < 0 || bp->b_page > size) fail(bp, "range: the page start outside the text", (long) bp->b_page);
		for (k = 0; k < bp->b_nfolds; k++) {
			fold_t *f = &bp->b_folds[k];
			if (f->a < 0 || f->b <= f->a || f->b >= size) fail(bp, "folds: a fold outside the text", (long) f->a);
			if (wf && (!boundary(bp, f->a) || !boundary(bp, f->a + 1) || !boundary(bp, f->b + 1)))
				fail(bp, "folds: a fold hides part of a character", (long) f->a);
		}
		if (shown && bp == curbp && bp->b_nfolds && fold_hidden(bp, bp->b_point))
			fail(bp, "folds: the cursor is in hidden text after the display", (long) bp->b_point);
		if (shown && bp == curbp && bp->b_narrowed &&
		    (bp->b_point < visible_start(bp) || bp->b_point > visible_end(bp)))
			fail(bp, "narrow: point outside the visible part", (long) bp->b_point);
		/* the windows that show it, other than the current one, keep their own point */
		for (wp = wheadp; wp != NULL; wp = wp->w_next) {
			if (wp->w_bufp != bp || wp == curwp) continue;
			check_point(bp, wp->w_point, wf, "range: a window's point outside the text",
				    "utf8: a window's point between the bytes of a character");
			if (wp->w_mark != NOMARK)
				check_point(bp, wp->w_mark, wf, "range: a window's mark outside the text",
					    "utf8: a window's mark between the bytes of a character");
		}
	}
}
