/*
 * command.c, Femto Emacs, Hugh Barney, Public Domain, 2016
 * Derived from: Anthony's Editor January 93, (Public Domain 1991, 1993 by Anthony Howe)
 */

#include "header.h"

#ifdef _WIN32
#include <windows.h>
#endif

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
		screen_mvaddstr(MSGLINE, 0, str_modified_buffers);
		screen_clrtoeol();
		if (!yesno(FALSE))
			return;
	}
	quit();
}

/* flag = default answer, FALSE=n, TRUE=y */
int yesno(int flag)
{
	int ch;

	screen_addstr(flag ? str_yes : str_no);
	screen_refresh();
	ch = read_key_byte();
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
	screen_clear();
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

/*
 * The mouse (get_key has decoded the event into mouse_*): pressing the
 * left button moves the cursor there, selecting the window clicked in;
 * dragging selects a region, which stays active after the release.  The
 * wheel is ignored.
 */
static int mouse_dragging = 0;
static int mouse_moved = 0;
static point_t mouse_old_mark = NOMARK;

/* the id of the mode line button under a pressed mouse button, or -1 */
static int menu_down_row = -1, menu_down_index = -1;

void editor_mouse_event()
{
	int b = mouse_button;

	if (b & 64)                     /* wheel */
		return;
	if (menu_down_index >= 0 && (mouse_release || (b & 32))) {
		/*
		 * A button of the mode line menu acts when it is released, as
		 * buttons do: a page that waits for a key (help, say) must not
		 * take the release for one, and moving off before letting go
		 * cancels.  It stays lit a moment, even after a quick click.
		 */
		if (mouse_release) {
			int index = menu_down_index;
			int same = (mouse_row == menu_down_row &&
				    menu_hit(mouse_row, mouse_col) == index);
			menu_down_index = -1;
			update_display();
			screen_pause(120);
			menu_press(-1, -1);
			update_display();
			if (same) {
				char arg[16];
				snprintf(arg, sizeof arg, "%d", index);
				call_lisp_event("menu", arg);
			}
		}
		return;
	}
	if (mouse_release) {
		int selected = (mouse_dragging && mouse_moved && mark_active);
		if (mouse_dragging && !mouse_moved) {
			/* a plain click: leave the mark as it was */
			curbp->b_mark = mouse_old_mark;
			mark_active = 0;
		}
		mouse_dragging = 0;
		/* a drag selected text: Lisp may copy it (copy-on-select) */
		if (selected)
			call_lisp_event("select", "");
		return;
	}
	if (b & 32) {                   /* motion with a button down */
		if (!mouse_dragging || (b & 3) != 0)
			return;
		if (window_position(curwp, mouse_row, mouse_col)) {
			mouse_moved = 1;
			mark_active = (curbp->b_mark != NOMARK && curbp->b_mark != curbp->b_point);
		}
		return;
	}
	if ((b & 3) != 0)               /* only the left button */
		return;
	{
		/*
		 * a button of the mode line: the press selects that window and
		 * lights the button; the release runs it (see above)
		 */
		int index = menu_hit(mouse_row, mouse_col);
		if (index >= 0) {
			(void) goto_screen_position(mouse_row, mouse_col);
			mouse_dragging = 0;
			menu_press(mouse_row, index);
			menu_down_row = mouse_row;
			menu_down_index = index;
			return;
		}
	}
	if (!goto_screen_position(mouse_row, mouse_col))
		return;
	mouse_old_mark = curbp->b_mark;
	curbp->b_mark = curbp->b_point;
	mark_active = 0;
	mouse_dragging = 1;
	mouse_moved = 0;
}

/* put the line with the cursor in the middle of the window */
void recenter()
{
	point_t p = segstart(curbp, lnstart(curbp, curbp->b_point), curbp->b_point);
	int i = curwp->w_rows / 2;

	while (i-- > 0 && p > 0)
		p = upup(curbp, p);
	curbp->b_page = p;
	redraw();
}

void lnbegin()
{
	curbp->b_point = segstart(curbp, lnstart(curbp,curbp->b_point), curbp->b_point);
}

void lnend()
{
	point_t next = dndn(curbp, curbp->b_point);

	curbp->b_point = next;
	/* on the last line of a file without a final newline, dndn() stops at
	   the end of the buffer, which already is the end of the line */
	if (next < document_size(curbp) || (next > 0 && *ptr(curbp, next - 1) == '\n'))
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
		char_t old = *(ptr(curbp, curbp->b_point));
		*(ptr(curbp, curbp->b_point)) = *input;
		record_change(curbp, 'd', curbp->b_point, &old, 1);
		record_change(curbp, 'i', curbp->b_point, (char_t *) input, 1);
		if (curbp->b_point < pos(curbp, curbp->b_ebuf))
			++curbp->b_point;
	} else {
		the_char[0] = *input == '\r' ? '\n' : *input;
		the_char[1] = '\0'; /* null terminate */
		*curbp->b_gap++ = the_char[0];
		record_change(curbp, 'i', curbp->b_point, the_char, 1);
		curbp->b_point = pos(curbp, curbp->b_egap);
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

		/* the backspaced bytes, for undo */
		memcpy(the_char, curbp->b_gap, n);
		the_char[n] = '\0';
		curbp->b_point = pos(curbp, curbp->b_egap);
		record_change(curbp, 'd', curbp->b_point, the_char, n);
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
		record_change(curbp, 'd', curbp->b_point, the_char, n);
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
	screen_refresh();
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
		screen_mvaddstr(MSGLINE, 0, str_notsaved);
		screen_clrtoeol();
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

/*
 * C-space: set the mark where the cursor is and make the region active
 * (it is shaded until the text changes or C-g).  Again at the same place
 * deactivates the region.
 */
void i_set_mark()
{
	if (curbp->b_mark == curbp->b_point && mark_active) {
		mark_active = 0;
		msg("Mark deactivated");
		return;
	}
	curbp->b_mark = curbp->b_point;
	mark_active = 1;
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
	mark_active = 0;
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
		screen_set_clipboard((char *) scrap);  /* the system clipboard, in the GUI */
		if (cut) {
			//debug("CUT: pt=%ld nscrap=%d\n", curbp->b_point, nscrap);
			record_change(curbp, 'd', (curbp->b_point < curbp->b_mark ? curbp->b_point : curbp->b_mark), scrap, nscrap);
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
		record_change(curbp, 'i', curbp->b_point, (char_t *) str, len);
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
		record_change(bp, 'i', bp->b_point, (char_t *) str, len);
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
		msg(str_pos, screen_unctrl(*(ptr(curbp, curbp->b_point))), *(ptr(curbp, curbp->b_point)),
			current, lastln,
			curbp->b_point, ((curbp->b_ebuf - curbp->b_buf) - (curbp->b_egap - curbp->b_gap)));
	}
}

char* get_temp_file()
{
#ifdef _WIN32
	static char temp_file[MAX_PATH + 1];
	char dir[MAX_PATH + 1];

	if (GetTempPathA(sizeof(dir), dir) == 0 ||
	    GetTempFileNameA(dir, "fe", 0, temp_file) == 0) {
		msg("Failed to create temp file");
		safe_strncpy(temp_file, "sbemacs.tmp", sizeof(temp_file));
	}
	return temp_file;
#else
	int result = 0;
	static char temp_file[] = TEMPFILE;

	strcpy(temp_file, TEMPFILE);
	result = mkstemp(temp_file);

	if (result == -1)
	{
		printf("Failed to create temp file\n");
		exit(1);
	}
	close(result);

	return temp_file;
#endif
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
	screen_mvaddstr(MSGLINE, 0, "Describe key ");
	screen_clrtoeol();

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

char *whatKey= "";

/* Keys bound to "user-defined-function" are dispatched to the Lisp keymap */
/*
 * Every key is offered to the Lisp keymap first (see main.c); a key that
 * ends up here has no binding in Lisp and none in C.
 */
void keyboardDefinition()
{
	msg("%s is not bound", whatKey);
}

/* let Lisp know that a region was killed in buffer bufname */
void run_kill_hook(char *bufname)
{
	call_lisp_event("kill", bufname);
}

void log_debug(char *s)
{
	debug("%s", s);
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
		output = malloc(LISP_IN_OUT);
		assert(output != NULL);
		call_lisp(lisp_query, output, LISP_IN_OUT);

		if (strlen(output) < 60) {
			msg("%s", output);
		} else {
			bp = find_buffer("*lisp_output*", TRUE);
			append_string(bp, output);
			append_string(bp, "\n");
			(void)popup_window(bp->b_bname);
		}
		free(output);
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
	char *output = malloc(LISP_IN_OUT);
	assert(output != NULL);
	call_lisp((char *)scrap, output, LISP_IN_OUT);

	insert_string("\n");
	insert_string(output);
	insert_string("\n");
	free(output);

	/* later we will avoid using mark/point to grab the block */
	clear_message_line();
}

void resize_terminal()
{
	one_window(curwp);
}
