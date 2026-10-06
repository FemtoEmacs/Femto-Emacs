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

void record_change(buffer_t *bp, int kind, point_t pos, const char_t *text, long len)
{
	if (change_hook == NULL || bp == NULL)
		return;
	if ((kind == 'i' || kind == 'd') && len <= 0)
		return;
	change_hook(bp->b_id, kind, (long) pos, text, len);
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
