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
	init_pair(1, COLOR_WHITE, COLOR_BLACK);  /* normal screen */
	init_pair(2, COLOR_BLACK, COLOR_WHITE);   /* modeline */
	init_pair(3, COLOR_BLACK, COLOR_CYAN);  /* brace highlight */
	init_pair(4, COLOR_BLUE, COLOR_BLACK);  /* keyword */
	init_pair(5, COLOR_GREEN, COLOR_BLACK);  /* alpha */
	init_pair(6, COLOR_MAGENTA, COLOR_BLACK);  /* digits */

	bkgd((chtype) (' ' | COLOR_PAIR(1)));

	if (1 < argc) {
		curbp = find_buffer(argv[1], TRUE);
		(void) insert_file(argv[1], FALSE);
		/* Save filename irregardless of load() success. */
		strncpy(curbp->b_fname, argv[1], NAME_MAX);
		curbp->b_fname[NAME_MAX] = '\0'; /* force truncation */
	} else {
		curbp = find_buffer(str_scratch, TRUE);
		strncpy(curbp->b_bname, str_scratch, STRBUF_S);
	}

	wheadp = curwp = new_window();
	one_window(curwp);
	associate_b2w(curbp, curwp);

	if (!growgap(curbp, CHUNK))
		fatal(f_alloc);

	top();
	undoset();
	key_map = keymap;
	initLisp(1, flargv);
	while (!done) {
		update_display();
		input = getkey(key_map, &key_return);

		if (key_return != NULL) {
		      if ( key_return->key_bind[0]=='C' &&
                           key_return->key_bind[1]=='-' && 
                           key_return->key_bind[2]=='c') {
		      whatKey= key_return->key_bind; }
		  (key_return->func)();}
		else
			insert();

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

void fatal(msg_t m)
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

void msg(msg_t m, ...)
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
