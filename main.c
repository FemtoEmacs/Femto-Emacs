/*
 * main.c, Femto Emacs, Hugh Barney, Public Domain, 2016
 * Derived from: Anthony's Editor January 93, (Public Domain 1991, 1993 by Anthony Howe)
 */

#include "header.h"

int main(int argc, char **argv)
{
	int i;
	char *flargv[10];
	flargv[0]= (char *)malloc(300);
	flargv[1]= (char *)malloc(300);		
	
	/* Find basename. */
	prog_name = *argv;
	i = strlen(prog_name);
	while (0 <= i && prog_name[i] != '\\' && prog_name[i] != '/')
		--i;
	prog_name += i+1;

	setlocale(LC_ALL, ""); /* required for 3,4 byte UTF8 chars */

	if (initscr() == NULL)
		fatal(f_initscr);

	raw();
	noecho();
	idlok(stdscr, TRUE);

        start_color();
	init_pair(ID_COLOR_SYMBOL, COLOR_WHITE, COLOR_BLACK);     /* non alpha, non digit */
	init_pair(ID_COLOR_MODELINE, COLOR_BLACK, COLOR_WHITE);   /* modeline */
	init_pair(ID_COLOR_BRACE, COLOR_BLACK, COLOR_CYAN);       /* brace highlight */
	init_pair(ID_COLOR_KEYWORD, COLOR_MAGENTA, COLOR_BLACK);  /* keyword */
	init_pair(ID_COLOR_ALPHA, COLOR_CYAN, COLOR_BLACK);       /* alpha */
	init_pair(ID_COLOR_DIGITS, COLOR_YELLOW, COLOR_BLACK);    /* digits */
	init_pair(ID_COLOR_COMMENTS, COLOR_GREEN, COLOR_BLACK);   /* comments */

	bkgd((chtype) (' ' | COLOR_PAIR(ID_COLOR_ALPHA)));

	if (1 < argc) {
		char bname[NBUFN];
		/* Save filename irregardless of load() success. */
		safe_strncpy(temp, argv[1], NAME_MAX);
		mk_buffer_name(bname, temp);
		curbp = find_buffer(bname, TRUE);
		(void)insert_file(temp, FALSE);
		strcpy(curbp->b_fname, temp);
	} else {
		curbp = find_buffer(str_scratch, TRUE);
	}

	wheadp = curwp = new_window();
	one_window(curwp);
	associate_b2w(curbp, curwp);

	top();
	undoset();
	key_map = keymap;
	initLisp(1, flargv);
	
	while (!done) {
		update_display();
		input = get_key(key_map, &key_return);

		if (key_return != NULL) {
			whatKey= key_return->key_name;			
			(key_return->func)();
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

		/* debug_stats("main loop:"); */
		match_parens();
	}
	
	if (scrap != NULL)
		free(scrap);

	move(LINES-1, 0);
	refresh();
	noraw();
	endwin();

	return (EXIT_OK);
}

void fatal(char *m)
{
	if (curscr != NULL) {
		move(LINES-1, 0);
		refresh();
		endwin();
		putchar('\n');
	}
	fprintf(stderr, m, prog_name);
	if (m == f_ok)
		exit(EXIT_OK);
	if (m == f_error)
		exit(EXIT_ERROR);
	if (m == f_usage)
		exit(EXIT_USAGE);
	exit(EXIT_FAIL);
}

void msg(char *m, ...)
{
	va_list args;
	va_start(args, m);
	(void) vsprintf(msgline, m, args);
	va_end(args);
	msgflag = TRUE;
}

void debug(char *format, ...)
{
	char buffer[256];
	va_list args;
	va_start (args, format);

	static FILE *debug_fp = NULL;

	if (debug_fp == NULL) {
		debug_fp = fopen("debug.out","w");
	}

	vsprintf (buffer, format, args);
	va_end(args);

	fprintf(debug_fp,"%s", buffer);
	fflush(debug_fp);
}

void debug_stats(char *s) {
	debug("%s bsz=%d p=%d m=%d gap=%d egap=%d\n", s, curbp->b_ebuf - curbp->b_buf, curbp->b_point, curbp->b_mark, curbp->b_gap - curbp->b_buf, curbp->b_egap - curbp->b_buf);
}
