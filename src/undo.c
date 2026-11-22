/*
 * undo.c, SBEmacs
 *
 * Undo lives in Lisp (lisp/undo.lisp).  The C core's only part is to
 * report every change to the text, as it happens, through one hook:
 *
 *   kind 'i'  LEN bytes TEXT were inserted at POS
 *   kind 'd'  LEN bytes TEXT were deleted at POS
 *   kind 'r'  the whole text was replaced (a file was loaded): forget
 *   kind 's'  the buffer was saved (undo can tell when it is unmodified)
 *   kind 'o'  a change larger than undo keeps: its bytes are not sent
 *             (undo_limit below), and the history is dropped
 *
 * Every function that changes a buffer calls record_change(), so nothing
 * escapes the history: typing, deleting, killing, yanking, replacing,
 * inserting a file, and whatever Lisp does through fe_insert and
 * fe_delete_region.  Buffers are known by b_id, which is never reused, so
 * a new buffer with an old name does not inherit an old history.
 */

#include "header.h"

typedef void (*fe_change_hook_t)(long id, int kind, long pos, const char_t *text, long len);

static fe_change_hook_t change_hook = NULL;

void fe_set_change_hook(fe_change_hook_t hook)
{
	change_hook = hook;
}

/*
 * Is undo recording?  The scripts set it from *undo-mode* (core.scm,
 * sync-undo-recording, before each event): off, an insertion's or a
 * deletion's bytes are not sent to undo.scm, which would discard them
 * (19 November 2026).  'r' and 's' always go: they concern the history.
 */
int undo_recording = 1;

/* (fe-undo-recording ON): 1 on, 0 off, -1 leaves it; the setting */
long fe_undo_recording(long on)
{
	if (on >= 0) undo_recording = on != 0;
	return undo_recording;
}

/*
 * The most bytes one change may have and still be sent to undo.scm: its
 * *undo-limit*, told by the scripts (undo.scm, before every key); -1, no
 * limit (femtoscheme's scripts, which do not tell).  A larger change
 * cannot be undone: undo.scm dropped it, and the history with it
 * (Lean/undo-visit.lean, trim_oversized), but only after its bytes had
 * been copied into the compiled program, where a byte of a bytevector
 * takes four.  A 20 MB yank raised the editor's memory by some 330 MB
 * that stayed (tests/endurance.sh, 22 November 2026).  Now 'o' goes
 * instead, and undo.scm does what it did, without the bytes.
 */
long undo_limit = -1;

/* (fe-undo-limit N): N >= 0 sets it, -1 none, -2 leaves it; the setting */
long fe_undo_limit(long n)
{
	if (n >= -1) undo_limit = n;
	return undo_limit;
}

/*
 * The mark follows the text, as Emacs's mark does: text inserted before it
 * moves it on, text deleted before it moves it back, and a deletion around
 * it leaves it where the deletion was.  Text inserted at the mark goes
 * after it.  The commands of command.c (typing, DEL, C-d, C-y) did not move
 * it: after C-SPC and DEL, typing a character could put the mark inside
 * it, and C-w then cut half a character (tests/fuzz-core.c, 21 November
 * 2026).  Every change comes here, as it does to the folds.
 */
static void follow(point_t *p, int kind, point_t pos, long len)
{
	if (*p == NOMARK || *p <= pos || len <= 0) return;
	if (kind == 'i') *p += len;
	else if (kind == 'd') *p = *p >= pos + len ? *p - len : pos;
}

/*
 * The other windows on the buffer follow the text the same way: their
 * point, their mark and the start and end of their page.  The display
 * used to shift them by the change of size since it last drew, as if
 * every edit had been at the cursor; a C-w of a region that ended at the
 * cursor put the point of another window on the same text at -7
 * (tests/fuzz-editor.sh with CHEZWEB_CHECK, 21 November 2026).  The
 * current window's point is the buffer's (b_point); its copy in the window
 * is taken again before it is used (b2w, display.c).
 */
static void mark_change(buffer_t *bp, int kind, point_t pos, long len)
{
	window_t *wp;
	if (len <= 0 || (kind != 'i' && kind != 'd')) return;
	follow(&bp->b_mark, kind, pos, len);
	/* the page of the current window too: after C-w of the whole text, the
	   display read the text from a page start far past its end (a
	   heap-use-after-free under AddressSanitizer, tests/fuzz-editor.sh) */
	follow(&bp->b_page, kind, pos, len);
	follow(&bp->b_epage, kind, pos, len);
	for (wp = wheadp; wp != NULL; wp = wp->w_next) {
		if (wp->w_bufp != bp || (wp == curwp && bp == curbp)) continue;
		follow(&wp->w_point, kind, pos, len);
		follow(&wp->w_mark, kind, pos, len);
		follow(&wp->w_page, kind, pos, len);
		follow(&wp->w_epage, kind, pos, len);
	}
}

void record_change(buffer_t *bp, int kind, point_t pos, const char_t *text, long len)
{
	/* display.c: b_epage, and what it knows of a long line, are stale --
	   unless the text was only saved */
	if (bp != NULL && kind != 's') bp->b_changes++;
	if (bp != NULL) mark_change(bp, kind, pos, len);
	if (bp != NULL && bp->b_nfolds > 0)     /* fold.c: folds follow the text */
		fold_change(bp, kind, pos, len);
	if (change_hook == NULL || bp == NULL)
		return;
	if ((kind == 'i' || kind == 'd') && (len <= 0 || !undo_recording))
		return;
	if ((kind == 'i' || kind == 'd') && undo_limit >= 0 && len > undo_limit) {
		change_hook(bp->b_id, 'o', (long) pos, NULL, 0);
		return;
	}
	change_hook(bp->b_id, kind, (long) pos, text, len);
}

/* The change for the display and the folds only: its bytes are not sent
 * to Scheme (C-x i with undo off, command.c) */
void record_change_unreported(buffer_t *bp, int kind, point_t pos, long len)
{
	if (bp == NULL) return;
	bp->b_changes++;
	mark_change(bp, kind, pos, len);
	if (bp->b_nfolds > 0) fold_change(bp, kind, pos, len);
}

/* the undo command of the C table (C-u, Esc-x undo): Lisp does the work */
void undo_command()
{
	if (!call_lisp_event("command", "undo"))
		msg("Undo is not available");
}

void discard_undo_history()
{
	record_change(curbp, 'r', 0, NULL, 0);
}

/* kept for the command table */
void list_undos()       { call_lisp_event("command", "undo-status"); }
void list_undo_stats()  { call_lisp_event("command", "undo-status"); }
