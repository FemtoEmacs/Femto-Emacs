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
int prev_utf8_char_size()
{
	int n;
	for (n=2;n<5;n++)
		if (0 < curbp->b_point - n && (utf8_size(*(ptr(curbp, curbp->b_point - n))) == n))
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

void insert()
{
	assert(curbp->b_gap <= curbp->b_egap);
	if (curbp->b_gap == curbp->b_egap && !growgap(curbp, CHUNK))
		return;
	curbp->b_point = movegap(curbp, curbp->b_point);

	/* overwrite if mid line, not EOL or EOF, CR will insert as normal */
	if ((curbp->b_flags & B_OVERWRITE) && *input != '\r' && *(ptr(curbp, curbp->b_point)) != '\n' && curbp->b_point < pos(curbp,curbp->b_ebuf) ) {
		*(ptr(curbp, curbp->b_point)) = *input;
		if (curbp->b_point < pos(curbp, curbp->b_ebuf))
			++curbp->b_point;
	} else {
		*curbp->b_gap++ = *input == '\r' ? '\n' : *input;
		curbp->b_point = pos(curbp, curbp->b_egap);
	}
	curbp->b_flags |= B_MODIFIED;
}

void backsp()
{
	int n = prev_utf8_char_size();
	curbp->b_point = movegap(curbp, curbp->b_point);
	undoset();
	if (curbp->b_buf < curbp->b_gap) {
		curbp->b_gap -= n; /* increase start of gap by size of char */
		curbp->b_flags |= B_MODIFIED;
	}
	curbp->b_point = pos(curbp, curbp->b_egap);
}

void delete()
{
	curbp->b_point = movegap(curbp, curbp->b_point);
	undoset();
	if (curbp->b_egap < curbp->b_ebuf) {
		curbp->b_egap += utf8_size(*(ptr(curbp, curbp->b_point)));
		curbp->b_point = pos(curbp, curbp->b_egap);
		curbp->b_flags |= B_MODIFIED;
	}
}

void i_gotoline()
{
	temp[0] = '\0';
	int line;

	result = getinput(m_goto, (char*)temp, STRBUF_S);

	if (temp[0] != '\0' && result) {
		line = atoi(temp);
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
	temp[0] = '\0';
	result = getinput(str_insert_file, (char*) temp, NAME_MAX);
	if (temp[0] != '\0' && result)
		(void) insert_file(temp, TRUE);
}

void readfile()
{
	buffer_t *bp;
	char bname[NBUFN];
	
	temp[0] = '\0';
	result = getfilename(str_read, (char*)temp, NAME_MAX);
	if (result) {
		mk_buffer_name(bname, temp);
		bp = find_buffer(bname, TRUE);
		disassociate_b(curwp); /* we are leaving the old buffer for a new one */
		curbp = bp;
		associate_b2w(curbp, curwp);

		/* load the file if not already loaded */
		if (bp != NULL && bp->b_fname[0] == '\0') {
			if (!load_file(temp)) {
				msg(m_newfile, temp);
			}
			safe_strncpy(curbp->b_fname, temp, NAME_MAX);
		}
		undoset();
	}
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

void writefile()
{
	safe_strncpy(temp, curbp->b_fname, NAME_MAX);
	result = getinput(str_write, (char*)temp, NAME_MAX);
	if (temp[0] != '\0' && result) {
		if (save_buffer(curbp, temp) == TRUE) {
			safe_strncpy(curbp->b_fname, temp, NAME_MAX);
			// FIXME - what if name already exists, in editor
			// FIXME? - do we want to change the name of the buffer when we save_as ?
			mk_buffer_name(curbp->b_bname, curbp->b_fname);
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
	 
	if (curbp->b_flags & B_MODIFIED) {
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

void iblock()
{
	block();
	msg(str_mark);
}

void block()
{
	curbp->b_mark = curbp->b_mark == NOMARK ? curbp->b_point : NOMARK;
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

void copy() {
	copy_cut(FALSE);
}

void cut() {
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
			curbp->b_egap += nscrap; /* if cut expand gap down */
			block();
			curbp->b_point = pos(curbp, curbp->b_egap); /* set point to after region */
			curbp->b_flags |= B_MODIFIED;
			run_kill_hook(curbp->b_bname);
			msg(m_cut, nscrap);
		} else {
			block(); /* can maybe do without */
			msg(m_copied, nscrap);
		}
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
		memcpy(curbp->b_gap, str, len * sizeof (char_t));
		curbp->b_gap += len;
		curbp->b_point = pos(curbp, curbp->b_egap);
		curbp->b_flags |= B_MODIFIED;
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
		bp->b_flags |= B_MODIFIED;
		bp->b_epage = bp->b_point = pos(bp, bp->b_ebuf); /* goto end of buffer */
		
		/* if window is displayed mark all windows for update */
		if (bp->b_cnt > 0) {
			b2w_all_windows(bp);
			mark_all_windows();
		}
	}
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
	buffer_t *bp = curwp->w_bufp;
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
	int result;

	temp[0] = '\0';
	result = getinput(str_shell_cmd, (char*)temp, NAME_MAX);

	if (temp[0] != '\0' && result)
		shell_command(temp);
}

void shell_command(char *command)
{
	char sys_command[255];
	buffer_t *bp;
	char *output_file = get_temp_file();
	
	sprintf(sys_command, "%s > %s 2>&1", command, output_file);	
	result = system(sys_command);

	bp = find_buffer(str_output, TRUE);
	disassociate_b(curwp); /* we are leaving the old buffer for a new one */
	curbp = bp;
	associate_b2w(curbp, curwp);

	load_file(output_file);
	msg(""); /* clear the msg line, dont display temp filename */
	safe_strncpy(curbp->b_bname, str_output, NBUFN);
}

void version()
{
	msg(m_version);
}

char *get_version_string() 
{
	return m_version;
}

static char *wrp=
"(trycatch (let ((b (buffer))) \
   (with-output-to b (princ %s)) \
   (io.tostring! b)) (lambda(x) x ))";

char *whatKey= "";

/* Keyboard Definition is done by user in Lisp */
void keyboardDefinition()
{
	sprintf(temp, "(keyboard \"%s\")", whatKey);
	sprintf(lisp_query, wrp, temp);
	callLisp(lisp_result, lisp_query);
}

/* call user defined kill-hook procedure */
void run_kill_hook(char *bufname)
{
	sprintf(temp, "(kill-hook \"%s\")", bufname);
	sprintf(lisp_query, wrp, temp);
	callLisp(lisp_result, lisp_query);
}

void log_debug(char *s)
{
	debug(s);
}

void repl()
{
	temp[0] = '\0';
	result = getinput("> ", temp, TEMPBUF);
	sprintf(lisp_query, wrp, temp);
	callLisp(lisp_result, lisp_query);

	/*
	 * send any outout to the message line.  This avoids text
	 * being sent to the current buffer which means the file
	 * contents could get corrupted if you are running commands
	 * on the buffers etc.  This assumes that the output will fix
	 * on 1 line.
	 */
	msg(lisp_result);
}
  
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

	/* if at start of block got to end of block */
	if (curbp->b_point < curbp->b_paren) {
		temp = curbp->b_mark;
		curbp->b_mark =	curbp->b_point;
		curbp->b_point = temp;
	}

	right(); /* if we have a matching brace we should always be able to move to right */
	copy();
	assert(scrap != NULL);
	//remove_control_chars(scrap);

	sprintf(lisp_query, wrp, scrap);
	//debug("eval_block: %s\n", lisp_query);

	callLisp(lisp_result, lisp_query);
	insert_string("\n");
	insert_string(lisp_result);
	insert_string("\n"); 
	//debug("result: %s\n", lisp_result);
}

void resize_terminal()
{
	one_window(curwp);
}

