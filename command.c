/*
 * command.c, Femto Emacs, Hugh Barney, Public Domain, 2016
 * Derived from: Anthony's Editor January 93, (Public Domain 1991, 1993 by Anthony Howe)
 */

#include "header.h"

void beginning_of_buffer()
{
	curbp->b_point = 0;
	curwp->w_point = curbp->b_point;
}

void end_of_buffer()
{
	curbp->b_epage = curbp->b_point = pos(curbp, curbp->b_ebuf);
	curwp->w_point = curbp->b_point;
}

void quit_ask()
{
	if (modified_buffers() > 0) {
		mvaddstr(MSGLINE, 0, str_modified_buffers);
		clrtoeol();
		if (!yesno(FALSE))
			return;
	}
	quit();
}

/* flag = default answer, FALSE=n, TRUE=y */
int yesno(int flag)
{
	int ch;

	addstr(flag ? str_yes : str_no);
	refresh();
	ch = getch();
	if (ch == '\r' || ch == '\n')
		return (flag);
	return (tolower(ch) == str_yes[1]);
}

void quit()
{
	done = 1;
}

void redraw()
{
	clear();
	mark_all_windows();
	update_display();
}

void left()
{
	int n = prev_utf8_char_size();

	while (0 < curbp->b_point && n-- > 0)
		--curbp->b_point;
}

void right()
{
	int n = utf8_size(*ptr(curbp,curbp->b_point));

	while ((curbp->b_point < pos(curbp, curbp->b_ebuf)) && n-- > 0)
		++curbp->b_point;
}

/* look back 2,3,4 chars and determine utf8 size otherwise default to 1 byte */
/*
int prev_utf8_char_size()
{
	int n;
	for (n=2;n<5;n++)
		if (0 < curbp->b_point - n && (utf8_size(*(ptr(curbp, curbp->b_point - n))) == n))
			return n;
	return 1;
}
*/

int prev_utf8_char_size()
{
	int n;
	for (n=2;n<5;n++)
		if (-1 < curbp->b_point - n && (utf8_size(*(ptr(curbp, curbp->b_point - n))) == n))
			return n;

	return 1;
}

void up()
{
	curbp->b_point = lncolumn(curbp, upup(curbp, curbp->b_point),curbp->b_col);
}

void down()
{
	curbp->b_point = lncolumn(curbp, dndn(curbp, curbp->b_point),curbp->b_col);
}

void xdown() {
  static char_t xcx;
  xcx = (unsigned) getch();
  if (xcx == 97) down();
  if (xcx == 96) up();
  xcx = (unsigned) getch();
  xcx = (unsigned) getch();
}

void xanymouse() {
  static char_t xcx;
  xcx = (unsigned) getch();
 // printf("[%d, ", xcx);
  xcx = (unsigned) getch();
 // printf("%d, ", xcx);
  xcx = (unsigned) getch();
 // printf("%d]", xcx);
}

void lnbegin()
{
	curbp->b_point = segstart(curbp, lnstart(curbp,curbp->b_point), curbp->b_point);
}

void lnend()
{
	curbp->b_point = dndn(curbp, curbp->b_point);
	left();
}

void backward_word()
{
	char_t *p;
	while (!isspace(*(p = ptr(curbp, curbp->b_point))) && curbp->b_buf < p)
		--curbp->b_point;
	while (isspace(*(p = ptr(curbp, curbp->b_point))) && curbp->b_buf < p)
		--curbp->b_point;
}

void forward_page()
{
	curbp->b_page = curbp->b_point = upup(curbp, curbp->b_epage);
	while (0 < curbp->b_row--)
		down();
	curbp->b_epage = pos(curbp, curbp->b_ebuf);
}

void backward_page()
{
	int i = curwp->w_rows;
	while (0 < --i) {
		curbp->b_page = upup(curbp, curbp->b_page);
		up();
	}
}

void forward_word()
{
	char_t *p;
	while (!isspace(*(p = ptr(curbp, curbp->b_point))) && p < curbp->b_ebuf)
		++curbp->b_point;
	while (isspace(*(p = ptr(curbp, curbp->b_point))) && p < curbp->b_ebuf)
		++curbp->b_point;
}

/* standard insert at the keyboard */
void insert()
{
	char_t the_char[2]; /* the inserted char plus a null */
	assert(curbp->b_gap <= curbp->b_egap);

	if (curbp->b_gap == curbp->b_egap && !growgap(curbp, CHUNK))
		return;
	curbp->b_point = movegap(curbp, curbp->b_point);


	/* overwrite if mid line, not EOL or EOF, CR will insert as normal */
	if ((curbp->b_flags & B_OVERWRITE) && *input != '\r' && *(ptr(curbp, curbp->b_point)) != '\n' && curbp->b_point < pos(curbp,curbp->b_ebuf) ) {
		*(ptr(curbp, curbp->b_point)) = *input;
		if (curbp->b_point < pos(curbp, curbp->b_ebuf))
			++curbp->b_point;
		/* FIXME - overwite mode not handled properly for undo yet */
	} else {
		the_char[0] = *input == '\r' ? '\n' : *input;
		the_char[1] = '\0'; /* null terminate */
		*curbp->b_gap++ = the_char[0]; 
		curbp->b_point = pos(curbp, curbp->b_egap);
		/* the point is set so that and undo will backspace over the char */
		add_undo(curbp, UNDO_T_INSERT, curbp->b_point, the_char);
	}
	add_mode(curbp, B_MODIFIED);
}

/*
 * A special insert used as the undo of delete char (C-d or DEL)
 * this is where the char is inserted at the point and the cursor
 * is NOT moved on 1 char.  This MUST be a seperate function so that
 *   INSERT + BACKSPACE are matching undo pairs
 *   INSERT_AT + DELETE are matching undo pairs
 * Note: This function is only ever called by execute_undo to undo a DEL.
 */
void insert_at()
{
	char_t the_char[2]; /* the inserted char plus a null */
	assert(curbp->b_gap <= curbp->b_egap);

	if (curbp->b_gap == curbp->b_egap && !growgap(curbp, CHUNK))
		return;
	curbp->b_point = movegap(curbp, curbp->b_point);


	/* overwrite if mid line, not EOL or EOF, CR will insert as normal */
	if ((curbp->b_flags & B_OVERWRITE) && *input != '\r' && *(ptr(curbp, curbp->b_point)) != '\n' && curbp->b_point < pos(curbp,curbp->b_ebuf) ) {
		*(ptr(curbp, curbp->b_point)) = *input;
		if (curbp->b_point < pos(curbp, curbp->b_ebuf))
			++curbp->b_point;
		/* FIXME - overwite mode not handled properly for undo yet */
	} else {
		the_char[0] = *input == '\r' ? '\n' : *input;
		the_char[1] = '\0'; /* null terminate */
		*curbp->b_gap++ = the_char[0];
		curbp->b_point = pos(curbp, curbp->b_egap);
		curbp->b_point--; /* move point back to where it was before, should always be safe */
		/* the point is set so that and undo will DELETE the char */
		add_undo(curbp, UNDO_T_INSAT, curbp->b_point, the_char);
	}

	add_mode(curbp, B_MODIFIED);
}

void backsp()
{
	char_t the_char[7]; /* the deleted char, allow 6 unsigned chars plus a null */
	int n = prev_utf8_char_size();

	curbp->b_point = movegap(curbp, curbp->b_point);
	undoset();

	if (curbp->b_buf < (curbp->b_gap - (n - 1)) ) {
		curbp->b_gap -= n; /* increase start of gap by size of char */
		add_mode(curbp, B_MODIFIED);

		/* record the backspaced chars in the undo structure */
		memcpy(the_char, curbp->b_gap, n);
		the_char[n] = '\0'; /* null terminate, the backspaced char(s) */
		curbp->b_point = pos(curbp, curbp->b_egap);
		//debug("point after bs = %ld\n", curbp->b_point);
		add_undo(curbp, UNDO_T_BACKSPACE, curbp->b_point, the_char);
	}

	curbp->b_point = pos(curbp, curbp->b_egap);
}

void delete()
{
	char_t the_char[7]; /* the deleted char, allow 6 unsigned chars plus a null */
	int n;

	curbp->b_point = movegap(curbp, curbp->b_point);
	undoset();
	n = utf8_size(*(ptr(curbp, curbp->b_point)));

	if (curbp->b_egap < curbp->b_ebuf) {
		/* record the deleted chars in the undo structure */
		memcpy(the_char, curbp->b_egap, n);
		the_char[n] = '\0'; /* null terminate, the deleted char(s) */
		//debug("deleted = '%s'\n", the_char);
		curbp->b_egap += n;
		curbp->b_point = pos(curbp, curbp->b_egap);
		add_mode(curbp, B_MODIFIED);
		add_undo(curbp, UNDO_T_DELETE, curbp->b_point, the_char);
	}
}

void i_gotoline()
{
	int line;

	if (getinput(m_goto, (char*)response_buf, STRBUF_S, F_CLEAR)) {
		line = atoi(response_buf);
		goto_line(line);
	}
}

void goto_line(int line)
{
	point_t p;

	p = line_to_point(line);
	if (p != -1) {
		curbp->b_point = p;
		msg(m_line, line);
	} else {
		msg(m_lnot_found, line);
	}
}

void insertfile()
{
	if (getfilename(str_insert_file, (char*) response_buf, NAME_MAX))
		(void)insert_file(response_buf, TRUE);
}

void i_readfile()
{
	if (FALSE == getfilename(str_read, (char*)response_buf, NAME_MAX))
		return;

	readfile(response_buf);
}

void readfile(char *fname)
{
	buffer_t *bp = find_buffer_by_fname(fname);
	disassociate_b(curwp); /* we are leaving the old buffer for a new one */
	curbp = bp;
	associate_b2w(curbp, curwp);

	/* load the file if not already loaded */
	if (bp != NULL && bp->b_fname[0] == '\0') {
		if (!load_file(fname)) {
			msg(m_newfile, fname);
		}
		safe_strncpy(curbp->b_fname, fname, NAME_MAX);
	}
	
	undoset();
}

void savebuffer()
{
	if (curbp->b_fname[0] != '\0') {
		save_buffer(curbp, curbp->b_fname);
		return;
	} else {
		writefile();
	}
	refresh();
}

char *rename_current_buffer(char *bname)
{
	char bufn[NBUFN];

	strcpy(bufn, bname);
	make_buffer_name_uniq(bufn);
	strcpy(curbp->b_bname, bufn);

	return curbp->b_bname;
}

void writefile()
{
	safe_strncpy(response_buf, curbp->b_fname, NAME_MAX);
	if (getinput(str_write, (char*)response_buf, NAME_MAX, F_NONE)) {
		if (save_buffer(curbp, response_buf) == TRUE) {
			safe_strncpy(curbp->b_fname, response_buf, NAME_MAX);
			// FIXME - what if name already exists, in editor
			// FIXME? - do we want to change the name of the buffer when we save_as ?
			make_buffer_name(curbp->b_bname, curbp->b_fname);
		}
	}
}

void killbuffer()
{
	buffer_t *kill_bp = curbp;
	buffer_t *bp;
	int bcount = count_buffers();

	/* do nothing if only buffer left is the scratch buffer */
	if (bcount == 1 && 0 == strcmp(get_buffer_name(curbp), str_scratch))
              return;

	if (!(curbp->b_flags & B_SPECIAL) && curbp->b_flags & B_MODIFIED) {
		mvaddstr(MSGLINE, 0, str_notsaved);
		clrtoeol();
		if (!yesno(FALSE))
			return;
	}

	/* create a scratch buffer */
	if (bcount == 1) {
		bp = find_buffer(str_scratch, TRUE);
		assert(bp != NULL); /* stops the compiler complaining */
	}

	next_buffer();
	assert(kill_bp != curbp);
	delete_buffer(kill_bp);
}

void i_set_mark()
{
	set_mark();
	msg(str_mark);
}

void set_mark()
{
	curbp->b_mark = (curbp->b_mark == curbp->b_point ? NOMARK : curbp->b_point);
}

void unmark()
{
	assert(curbp != NULL);
	curbp->b_mark = NOMARK;
}

void toggle_overwrite_mode() {
	if (curbp->b_flags & B_OVERWRITE)
		curbp->b_flags &= ~B_OVERWRITE;
	else
		curbp->b_flags |= B_OVERWRITE;
}

void killtoeol()
{
	/* point = start of empty line or last char in file */
	if (*(ptr(curbp, curbp->b_point)) == 0xa || (curbp->b_point + 1 == ((curbp->b_ebuf - curbp->b_buf) - (curbp->b_egap - curbp->b_gap))) ) {
		delete();
	} else {
		curbp->b_mark = curbp->b_point;
		lnend();
		copy_cut(TRUE);
	}
}

int i_check_region()
{
	if (curbp->b_mark == NOMARK) {
		msg(m_nomark);
		return FALSE;
	}

	if (curbp->b_point == curbp->b_mark) {
		msg(m_noregion);
		return FALSE;
	}
	return TRUE;
}

void copy() {
	if (i_check_region() == FALSE) return;
	copy_cut(FALSE);
}

void cut() {
	if (i_check_region() == FALSE) return;
	copy_cut(TRUE);
}

void copy_cut(int cut)
{
	char_t *p;
	/* if no mark or point == marker, nothing doing */
	if (curbp->b_mark == NOMARK || curbp->b_point == curbp->b_mark)
		return;
	if (scrap != NULL) {
		free(scrap);
		scrap = NULL;
	}

	if (curbp->b_point < curbp->b_mark) {
		/* point above mark: move gap under point, region = mark - point */
		(void) movegap(curbp, curbp->b_point);
		/* moving the gap can impact the pointer so sure get the pointer after the move */
		p = ptr(curbp, curbp->b_point);
		nscrap = curbp->b_mark - curbp->b_point;
	} else {
		/* if point below mark: move gap under mark, region = point - mark */
		(void) movegap(curbp, curbp->b_mark);
		/* moving the gap can impact the pointer so sure get the pointer after the move */
		p = ptr(curbp, curbp->b_mark);
		nscrap = curbp->b_point - curbp->b_mark;
	}
	if ((scrap = (char_t*) malloc(nscrap + 1)) == NULL) {
		msg(m_alloc);
	} else {
		undoset();
		(void) memcpy(scrap, p, nscrap * sizeof (char_t));
		*(scrap + nscrap) = '\0';  /* null terminate for insert_string */
		if (cut) {
			//debug("CUT: pt=%ld nscrap=%d\n", curbp->b_point, nscrap);
			add_undo(curbp, UNDO_T_KILL, (curbp->b_point < curbp->b_mark ? curbp->b_point : curbp->b_mark), scrap);
			curbp->b_egap += nscrap; /* if cut expand gap down */
			curbp->b_point = pos(curbp, curbp->b_egap); /* set point to after region */
			add_mode(curbp, B_MODIFIED);
			run_kill_hook(curbp->b_bname);
			msg(m_cut, nscrap);
		} else {
			msg(m_copied, nscrap);
		}
		unmark();
	}
}

unsigned char *get_scrap()
{
	return scrap;
}

/*
 * set the scrap pointer, a setter for external interface code
 * ptr must be a pointer to a malloc'd NULL terminated string
 */
void set_scrap(unsigned char *ptr)
{
	if (scrap != NULL) free(scrap);
	assert(ptr != NULL);
	scrap = ptr;
}

void paste()
{
	insert_string((char *)scrap);
}

void insert_string(char *str)
{
	int len = (str == NULL) ? 0 : strlen(str);

	if (curbp->b_flags & B_OVERWRITE)
		return;
	if (len <= 0) {
		msg(m_empty);
	} else if (len < curbp->b_egap - curbp->b_gap || growgap(curbp, len)) {
		curbp->b_point = movegap(curbp, curbp->b_point);
		undoset();
		//debug("INS STR: pt=%ld len=%d\n", curbp->b_point, strlen((char *)str));
		add_undo(curbp, UNDO_T_YANK, curbp->b_point, (char_t *)str);
		memcpy(curbp->b_gap, str, len * sizeof (char_t));
		curbp->b_gap += len;
		curbp->b_point = pos(curbp, curbp->b_egap);
		add_mode(curbp, B_MODIFIED);
	}
}

/*
 * append a string to the end of a buffer
 */
void append_string(buffer_t *bp, char *str)
{
	int len = (str == NULL) ? 0 : strlen(str);

	assert(bp != NULL);
	if (len == 0) return;

	/* goto end of buffer */
	bp->b_epage = bp->b_point = pos(bp, bp->b_ebuf);

	if (len < bp->b_egap - bp->b_gap || growgap(bp, len)) {
		bp->b_point = movegap(bp, bp->b_point);
		undoset();
		memcpy(bp->b_gap, str, len * sizeof (char_t));
		bp->b_gap += len;
		bp->b_point = pos(bp, bp->b_egap);
		add_mode(curbp, B_MODIFIED);
		bp->b_epage = bp->b_point = pos(bp, bp->b_ebuf); /* goto end of buffer */

		/* if window is displayed mark all windows for update */
		if (bp->b_cnt > 0) {
			b2w_all_windows(bp);
			mark_all_windows();
		}
	}
}

void log_debug_message(char *format, ...)
{
	char buffer[256];
	va_list args;

	va_start(args, format);
	vsprintf(buffer, format, args);
	va_end(args);

	log_message(buffer);
}

void log_message(char *str)
{
	buffer_t *bp = find_buffer("*messages*", TRUE);
	assert(bp != NULL);
	append_string(bp, str);
}

void showpos()
{
	int current, lastln;
	point_t end_p = pos(curbp, curbp->b_ebuf);

	get_line_stats(&current, &lastln);

	if (curbp->b_point == end_p) {
		msg(str_endpos, current, lastln,
			curbp->b_point, ((curbp->b_ebuf - curbp->b_buf) - (curbp->b_egap - curbp->b_gap)));
	} else {
		msg(str_pos, unctrl(*(ptr(curbp, curbp->b_point))), *(ptr(curbp, curbp->b_point)),
			current, lastln,
			curbp->b_point, ((curbp->b_ebuf - curbp->b_buf) - (curbp->b_egap - curbp->b_gap)));
	}
}

char* get_temp_file()
{
	int result = 0;
	static char temp_file[] = TEMPFILE;

	strcpy(temp_file, TEMPFILE);
	result = mkstemp(temp_file);

	if (result == -1)
	{
		printf("Failed to create temp file\n");
		exit(1);
	}

	return temp_file;
}

void match_parens()
{
	assert(curwp != NULL);
	buffer_t *bp = curwp->w_bufp;
	assert(bp != NULL);

	if (buffer_is_empty(bp))
		return;

	char p = *ptr(bp, bp->b_point);

	switch(p) {
	case '{':
		match_paren_forwards(bp, '{', '}');
		break;
	case '[':
		match_paren_forwards(bp, '[', ']');
		break;
	case '(':
		match_paren_forwards(bp, '(', ')');
		break;
	case '}':
		match_paren_backwards(bp, '{', '}');
		break;
	case ']':
		match_paren_backwards(bp, '[', ']');
		break;
	case ')':
		match_paren_backwards(bp, '(', ')');
		break;
	default:
		bp->b_paren = NOPAREN;
		break;
	}
}

void match_paren_forwards(buffer_t *bp, char open_paren, char close_paren)
{
	int lcount = 0;
	int rcount = 0;
	point_t end = pos(bp, bp->b_ebuf);
	point_t position = bp->b_point;
	char c;

	while (position <= end) {
		c = *ptr(bp, position);
		if (c == open_paren)
			lcount++;
		if (c == close_paren)
			rcount++;
		if (lcount == rcount && lcount > 0) {
			bp->b_paren = position;
			return;
		}
		position++;
	}
	bp->b_paren = NOPAREN;
}

void match_paren_backwards(buffer_t *bp, char open_paren, char close_paren)
{
	int lcount = 0;
	int rcount = 0;
	point_t start = 0;
	point_t position = bp->b_point;
	char c;

	while (position >= start) {
		c = *ptr(bp, position);
		if (c == open_paren)
			lcount++;
		if (c == close_paren)
			rcount++;
		if (lcount == rcount && lcount > 0) {
			bp->b_paren = position;
			return;
		}
		position--;
	}
	bp->b_paren = NOPAREN;
}

void i_describe_key()
{
	mvaddstr(MSGLINE, 0, "Describe key ");
	clrtoeol();

	input = get_key(key_map, &key_return);

	if (key_return != NULL)
		msg("%s runs the command '%s'", key_return->key_name, key_return->key_desc);
	else
		msg("self insert %s", input);
}

void i_shell_command()
{
	if (getinput(str_shell_cmd, (char*)response_buf, NAME_MAX, F_CLEAR))
		shell_command(response_buf);
}

void shell_command(char *command)
{
	char sys_command[255];
	buffer_t *bp;
	char *output_file = get_temp_file();

	sprintf(sys_command, "%s > %s 2>&1", command, output_file);
	//debug("sys_command: '%s'\n", sys_command);

	if (0 != system(sys_command))
		return;

	bp = find_buffer(str_output, TRUE);
	disassociate_b(curwp); /* we are leaving the old buffer for a new one */
	curbp = bp;
	associate_b2w(curbp, curwp);

	load_file(output_file);
	msg(""); /* clear the msg line, dont display temp filename */
	safe_strncpy(curbp->b_bname, str_output, NBUFN);
}

int add_mode_global(char *mode_name)
{
	if (0 == strcmp(mode_name, "undo")) {
		global_undo_mode = 1;
		return 1;
	}
	return 0;
}

void version()
{
	msg(m_version);
}

char *get_version_string()
{
	return m_version;
}

/*
static char *wrp=
"(trycatch (let ((b (buffer))) \
   (with-output-to b (princ %s)) \
   (io.tostring! b)) (lambda(x) x ))";
*/

char *whatKey= "";

/* Keyboard Definition is done by user in Lisp */
void keyboardDefinition()
{
	char key_cmd[80];
	sprintf(key_cmd, "(keyboard \"%s\")", whatKey);
	(void)call_lisp(key_cmd);
}

/* call user defined kill-hook procedure */
void run_kill_hook(char *bufname)
{
	char cmd[80];
	sprintf(cmd, "(kill-hook \"%s\")", bufname);
	(void)call_lisp(cmd);
}

void log_debug(char *s)
{
	debug(s);
}


/*
 * execute a lisp command type in atthe command prompt >
 * send any outout to the message line.  This avoids text
 * being sent to the current buffer which means the file
 * contents could get corrupted if you are running commands
 * on the buffers etc.
 * 
 * If the output is too big for the message line then send it to
 * a temp buffer called *list_output* and popup the window
 *
 */
void repl()
{
	char *output;
	buffer_t *bp;

	if (getinput("> ", lisp_query, TEMPBUF, F_CLEAR)) {
		output = call_lisp(lisp_query);

		if (strlen(output) < 60) {
			msg(output);
		} else {
			bp = find_buffer("*lisp_output*", TRUE);
			append_string(bp, output);
			(void)popup_window(bp->b_bname);
		}
	}
}

/*
 * evaluate a block of lisp code encased between a start ( and end )
 *
 */
void eval_block() {
	point_t temp;
	point_t found;

	char p = *ptr(curbp, curbp->b_point);

	/* if not sat on ( or ) then search for an end of a block behind the cursor */
	if (p != '(' && p != ')') {
		found = search_backwards(")");
		if (found == -1) {
			msg("No block behind cursor");
			return;
		} else {
			move_to_search_result(found);
			right();
			match_parens();
		}
	}

	if (curbp->b_paren == -1) {
		msg("No block detected");
		return;
	}

	curbp->b_mark = curbp->b_paren;

	/* if at start of block goto the end of block */
	if (curbp->b_point < curbp->b_paren) {
		temp = curbp->b_mark;
		curbp->b_mark =	curbp->b_point;
		curbp->b_point = temp;
	}

	right(); /* if we have a matching brace we should always be able to move to right */
	copy();
	assert(scrap != NULL);
 	char *output = call_lisp((char *)scrap);

	insert_string("\n");
	insert_string(output);
	insert_string("\n");

	/* later we will avoid using mark/point to grab the block */
	clear_message_line();
}

void resize_terminal()
{
	one_window(curwp);
}

