/* undo.c, Femto Emacs, Hugh Barney, Public Domain, 2016 */

#include "header.h"

undo_tt *new_undo()
{
	undo_tt *up = (undo_tt *)malloc(sizeof(undo_tt));

	assert(up != NULL);

	up->u_prev = NULL;
	up->u_point = 0;
	up->u_string = NULL;
	up->u_type = UNDO_T_NONE;

	return up;
}

/*
 * called by specific functions to register details so that they can be reversed
 * later by calling the equal and opposite function.
 */
void add_undo(buffer_t *bp, char type, point_t p, char_t *str)
{
	int len = 1;
	assert(bp != NULL);

	/* do nothing if undo mode is not active for this buffer */
	if (!(bp->b_flags & B_UNDO))
		return;

	assert(bp->b_gap <= bp->b_egap);
	assert(bp->b_buf <= bp->b_gap);
	assert(bp->b_egap <= bp->b_ebuf);
	assert(str != NULL);
	len = strlen((char *)str);

	/* handle insert, accumulate inserts as long as they are next to the last insert */
	if (bp->b_utail != NULL && bp->b_utail->u_type == type && type == UNDO_T_INSERT && (bp->b_utail->u_point + 1) == p) {

		bp->b_utail->u_point = p; /* update it */
		append_undo_string(bp->b_utail, str);
		//debug_undo("ADD-i", bp->b_utail, bp);

	/* handle backspace, accumulate backspaces as long as they are next to the last backspace */
	} else if (bp->b_utail != NULL && bp->b_utail->u_type == type && type == UNDO_T_BACKSPACE && (bp->b_utail->u_point - len) == p) {

		bp->b_utail->u_point = p; /* update it */
		append_undo_string(bp->b_utail, str);
		//debug_undo("ADD-bs", bp->b_utail, bp);

	/* handle delete-char, accumulate deletes as long as they are at the point of the last delete */
	} else if (bp->b_utail != NULL && bp->b_utail->u_type == type && type == UNDO_T_DELETE && (bp->b_utail->u_point) == p) {

		bp->b_utail->u_point = p; /* update it */
		append_undo_string(bp->b_utail, str);
		//debug_undo("ADD-del", bp->b_utail, bp);

	/* handle insert_at(), accumulate insert_at()s as long as they are next to the last insert_at() */
	} else if (bp->b_utail != NULL && bp->b_utail->u_type == type && type == UNDO_T_INSAT && (bp->b_utail->u_point) == p) {

		bp->b_utail->u_point = p; /* update it */
		append_undo_string(bp->b_utail, str);
		//debug_undo("ADD-at", bp->b_utail, bp);

	} else {
		undo_tt *up = new_undo();

		assert(up != NULL);
		up->u_prev = bp->b_utail;
		bp->b_utail = up;
		up->u_type = type;
		up->u_point = p;

		up->u_string = (char_t *)strdup((char *)str);
		//debug_undo("ADD-new", up, bp);
	}
}

/*
 * this is where the actual undo work takes place
 *
 */
undo_tt *execute_undo(undo_tt *up)
{
	int len;
	int sz;
	int i;
	int before, after;
	char_t the_char[7]; /* the deleted char, allow 6 unsigned chars plus a null */

	assert(up != NULL);
	len = strlen((char *)up->u_string);
	assert(curbp->b_ucnt <= len);
	assert(curbp->b_ucnt > -2);

	if (curbp->b_ucnt == -1) curbp->b_ucnt = len;

	//debug_undo("EXEC", up, curbp);

	switch(up->u_type) {
	case UNDO_T_INSERT:
		curbp->b_point = up->u_point - (len - curbp->b_ucnt);
		before = curbp->b_point;
		backsp();
		after = curbp->b_point;
		/*
		 * we could have backspaced over a multibyte UTF8 char so we need
		 * to calculate the delta based on point which is set inside the backspace
		 * function.
		 */
		sz = before - after;
		curbp->b_ucnt -= sz;
		assert(sz > 0 && sz < 5); /* should be between 1 and 4 */
		if (curbp->b_ucnt > 0)
			return up; /* more left to undo on this undo string */
	        break;

	case UNDO_T_BACKSPACE:
		/* load up insert with char at u_string[b_ucnt-1] */
		curbp->b_point = up->u_point + (len - curbp->b_ucnt);
		sz = get_buf_utf8_size(up->u_string, curbp->b_ucnt - 1);
		assert(sz > 0 && sz < 5); /* should be between 1 and 4 */

		/* inserting back, highest byte first, for UTF8 char (as if entered at the keyboard) */
		for (i = 0; i < sz; i++) {
			the_char[0] = up->u_string[curbp->b_ucnt - sz + i];
			the_char[1] = '\0';
			input = the_char;
			insert();
		}
		curbp->b_ucnt -= sz;
		if (curbp->b_ucnt > 0)
			return up; /* more left to undo on this undo string */
	        break;


	case UNDO_T_DELETE:
		/* load up insert_at() with char at u_string[b_ucnt-1] */
		curbp->b_point = up->u_point; /* point should always be the same */
		sz = get_buf_utf8_size(up->u_string, curbp->b_ucnt - 1);
		assert(sz > 0 && sz < 5); /* should be between 1 and 4 */
		//debug("DEL: sz=%d\n", sz);

		/*
		 * As we are using insert_at we must insert lowest byte first
		 * (the opposite of insert) for a multibyte UTF8 char.
		 * This has a strange effect on the list-undos report as the
		 * bytes are backwards and so dont get recognised as the UTF8 chars they represent
		 */
		for (i = 1; i <= sz; i++) {
			the_char[0] = up->u_string[curbp->b_ucnt - i];
			the_char[1] = '\0';
			input = the_char;
			insert_at();
		}

		curbp->b_ucnt -= sz;
		assert(curbp->b_ucnt > -1);
		if (curbp->b_ucnt > 0)
			return up; /* more left to undo on this undo string */
	        break;

	case UNDO_T_INSAT:
		curbp->b_point = up->u_point; /* point should always be the same */
		before = document_size(curbp);
		delete();
		/*
		 * we could have deleted a multibyte UTF8 char so we need to calculate the delta.
		 * this can not be done using b_point as it does not changes for DEL and INSAT.
		 * hence why we use document_size() to get the before and after sizes.
		 */
		after = document_size(curbp);
		assert(before > after);
		sz = before - after;
		assert(sz > 0 && sz < 5); /* should be between 1 and 4 */
		curbp->b_ucnt -= sz;
		assert(curbp->b_ucnt > -1);
		//debug("IAT: sz=%d\n", sz);

		if (curbp->b_ucnt > 0)
			return up; /* more left to undo on this undo string */
	        break;

	/* opposite of a kill-region is a yank (paste) */
	case UNDO_T_KILL:
		curbp->b_point = up->u_point;
		insert_string((char *)up->u_string);
		break;

	/* opposite of a yank (paste) is a kill-region (cut) */
	case UNDO_T_YANK:
		curbp->b_point = up->u_point;
		curbp->b_mark  = up->u_point + strlen((char *)up->u_string);
		cut();
		break;
	}

	curbp->b_ucnt = -1;
	return up->u_prev;
}



/* the undo command called by the keyboard binding C-u */
void undo_command()
{
	int continue_undo = 1;
	undo_tt *up = curbp->b_utail;
	curbp->b_ucnt = -1;

	/* do old style undo if we have not enabled global_undo_mode in init.lsp */
	if (global_undo_mode == 0) {
		undo();
		return;
	}

	if (up == NULL) {
		msg("No undo recorded for this buffer");
		return;
	}

	while (continue_undo) {
		//debug("\n========UNDO=======\n");
		assert(curbp->b_gap <= curbp->b_egap);
		assert(curbp->b_buf <= curbp->b_gap);
		assert(curbp->b_egap <= curbp->b_ebuf);

		up = execute_undo(up);
		assert(curbp->b_gap <= curbp->b_egap);
		assert(curbp->b_buf <= curbp->b_gap);
		assert(curbp->b_egap <= curbp->b_ebuf);

		redraw();
		if (up == NULL) {
			msg("Out of Undo");
			//debug("\n====OUT OF UNDO====\n");
			curbp->b_ucnt = -1;
			return;
		}
		continue_undo = get_undo_again();
	}

	curbp->b_ucnt = -1;
}

/*
 * wait for next key, if undo return TRUE
 * otherwise handle the key and return FALSE
 */
int get_undo_again()
{
	input = get_key(key_map, &key_return);

	if (key_return != NULL) {
		whatKey= key_return->key_name;
		if (key_return->func == undo_command) {
			return TRUE;
		} else {
			(key_return->func)();
			return FALSE;
		}
	} else {
		/*
		 * if first char of input is a control char then
		 * key is not bound, except TAB and NEWLINE
		 */
		if (*input > 31 || *input == 0x0A || *input == 0x09)
			insert();
		else
			msg(str_not_bound);
	}
	return FALSE;
}

/* append a string to the undo structure member u_string */
void append_undo_string(undo_tt *up, char_t *str)
{
	char_t *newbuf;
	int newlen, buflen;
	int len = strlen((char *)str);

	/* if undo string is not yet created, malloc enough memory and copy it in */
	if (up->u_string == NULL) {
		up->u_string = (char_t*)malloc((size_t)len + 1);
		memcpy(up->u_string, str, len);
		up->u_string[len] = '\0';
		return;
	}

	/* undo string already exists, adjust memory and append str onto it */
	buflen = strlen((char *)up->u_string);
	newlen = buflen + len + 1;
	newbuf = (char_t*)realloc(up->u_string, (size_t)newlen);
	up->u_string = newbuf;
	memcpy((up->u_string + buflen), str, len);
	up->u_string[newlen - 1] = '\0';
}


/*
 * look back 1,2,3 chars in buf, starting at position pos
 * and determine utf8 size otherwise default to 1 byte
 *
 * if ptr points to buf[1] and buf[0] shows that it is a 2 byte UTF8 return 2
 * if ptr points to buf[2] and buf[0] shows that it is a 3 byte UTF8 return 3 etc
 *
 */
int get_buf_utf8_size(char_t *buf, int pos)
{
	int n;
	for (n=1;n<4;n++)
		if (-1 < pos - n && (utf8_size(buf[pos - n])) == n + 1)
			return (n + 1);
	return 1;
}

void discard_undo_history()
{
	discard_buffer_undo_history(curbp);
}

void discard_buffer_undo_history(buffer_t *bp)
{
	assert(bp != NULL);
	if (bp->b_utail == NULL) return;
	free_undos(bp->b_utail);
	bp->b_utail = NULL;
}

/* free all the undos linked to this undo */
void free_undos(undo_tt *up)
{
	undo_tt *prev = up;
	undo_tt *u;

	while (prev != NULL) {
		if (prev->u_string != NULL) free(prev->u_string);
		u = prev;
		prev = prev->u_prev;
		free(u);
	}
}

/* count the number of undo structures on this buffer */
int count_undos(buffer_t *bp)
{
	undo_tt *prev;
	int i = 0;

	assert(bp != NULL);
	prev = bp->b_utail;

	while (prev != NULL) {
		i++;
		prev = prev->u_prev;
	}

	return i;
}

/* work out the total memory footprint of all the undo structures on this buffer */
int get_total_undo_size(buffer_t *bp)
{
	undo_tt *prev;
	int sz = 0;

	assert(bp != NULL);
	prev = bp->b_utail;

	while (prev != NULL) {
		sz += get_undo_size(prev);
		prev = prev->u_prev;
	}

	return sz;
}

/* return the footprint of this undo structure */
int get_undo_size(undo_tt *up)
{
	if (up->u_string != NULL) return ((int)sizeof(undo_tt) + strlen((char *)up->u_string));
	return (int)sizeof(undo_tt);

}

void debug_undo(char *msg, undo_tt *up, buffer_t *bp) {
	int len = 0;
	char str[41];

	if (up->u_string != NULL) {
		/*
		 * make a summary of the string, we do not want
		 * to cause a SEGFAULT by overrunning the debug buffer 
		 */
		len = strlen((char *)up->u_string);
		safe_strncpy((char *)str, (char *)up->u_string, 40);
	} else {
		strcpy(str,"");
	}

	debug("%s: typ=%s pt=%ld str='%s' len=%d ucnt=%d\n", 
		msg, get_undo_type_name(up), up->u_point, str, len, bp->b_ucnt);
}

/* translate the type into a string for the list-undos command */
char *get_undo_type_name(undo_tt *up)
{
	assert(up != NULL);

	switch (up->u_type) {
	case UNDO_T_INSERT:
		return STR_T_INSERT;
	case UNDO_T_BACKSPACE:
		return STR_T_BACKSP;
	case UNDO_T_KILL:
		return STR_T_KILL;
	case UNDO_T_YANK:
		return STR_T_YANK;
	case UNDO_T_DELETE:
		return STR_T_DELETE;
	case UNDO_T_INSAT:
		return STR_T_INSAT;
	}

	return STR_T_NONE;
}

void list_undos()
{
	dump_undos(curbp);
}

/* show the undo data associated with this buffer */
void dump_undos(buffer_t *bp)
{
	char_t *str;
	int count = 0;
	int size = 0;
	char_t line[41];
	char report_line[90];
	undo_tt *prev;
	buffer_t *list_bp = find_buffer("*undos*", TRUE);

	disassociate_b(curwp); /* we are leaving the old buffer for a new one */
	curbp = list_bp;
	associate_b2w(curbp, curwp);
	clear_buffer(); /* throw away previous content */

	/*             123 123456 123456789 1234 1234567890123456789012345678901234567890 */
	insert_string("Num Type   Point     Size String\n");
	insert_string("--- ------ --------- ---- ----------------------------------------\n");

	prev = bp->b_utail;

	while (prev != NULL) {
		str = (prev->u_string != NULL ? prev->u_string : (char_t *)" ");
		size = get_undo_size(prev);
		safe_strncpy((char *)line, (char *)str, 40);
		remove_control_chars(line);
		sprintf(report_line, "%03d %6s %9ld %4d %s\n",  ++count, get_undo_type_name(prev), prev->u_point, size, line);
		insert_string(report_line);
		prev = prev->u_prev;
	}
}

/* show the undo data for ALL the buffers */
void list_undo_stats()
{
	buffer_t *bp;
	buffer_t *list_bp;
	char blank[] = " ";
	char report_line[90];
	char *bn;
	int count;
	int size;

	list_bp = find_buffer("*undos*", TRUE);

	disassociate_b(curwp); /* we are leaving the old buffer for a new one */
	curbp = list_bp;
	associate_b2w(curbp, curwp);
	clear_buffer(); /* throw away previous content */

	/*             1234567890123456 1234 123456789 */
	insert_string("Buffer            Num      Size\n");
	insert_string("---------------- ---- ---------\n");

	bp = bheadp;
	while (bp != NULL) {
		if (bp != list_bp) {
			bn = (bp->b_bname[0] != '\0' ? bp->b_bname : blank);
			count = count_undos(bp);
			size = get_total_undo_size(bp);

			sprintf(report_line, "%-16s %4d %9d\n",  bn, count, size);
			insert_string(report_line);
		}
		bp = bp->b_next;
	}
}
