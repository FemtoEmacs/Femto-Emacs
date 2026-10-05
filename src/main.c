/*
 * main.c, Femto Emacs, Hugh Barney, Public Domain, 2016
 * Derived from: Anthony's Editor January 93, (Public Domain 1991, 1993 by Anthony Howe)
 */

#include "header.h"

/*
 * Entry point, called from SBCL (see lisp/sbemacs.lisp) after the Lisp
 * side has installed its hooks with fe_set_hooks() and loaded the user's
 * init file.
 */
int fe_main(int argc, char **argv)
{
	int i;
	/* Find basename. */
	prog_name = *argv;
	i = strlen(prog_name);
	while (0 <= i && prog_name[i] != '\\' && prog_name[i] != '/')
		--i;
	prog_name += i+1;

	setlocale(LC_ALL, "") ; /* required for 3,4 byte UTF8 chars */

	if (initscr() == NULL)
		fatal(f_initscr);

	raw();
	noecho();
	idlok(stdscr, TRUE);

	init_colors();

	if ( (argc == 3) && (strcmp(argv[2], "+") == 0) )
            { mousemask( ALL_MOUSE_EVENTS |
                                  REPORT_MOUSE_POSITION, NULL);
            }
        if ( (argc == 2) && (strcmp(argv[1], "+") == 0))
           { mousemask( ALL_MOUSE_EVENTS |
                                  REPORT_MOUSE_POSITION, NULL);
             argc = 1;
           }
	bkgd((chtype) (' ' | COLOR_PAIR(ID_COLOR_ALPHA)));

	if (argc > 1) {
		char bname[NBUFN];
		char fname[NAME_MAX + 1];
		/* Save filename irregardless of load() success. */
		safe_strncpy(fname, argv[1], NAME_MAX);
		make_buffer_name(bname, fname);
		curbp = find_buffer(bname, TRUE);
		(void)insert_file(fname, FALSE);
		strcpy(curbp->b_fname, fname);
	} else {
		curbp = find_buffer(str_scratch, TRUE);
	}

	wheadp = curwp = new_window();
	one_window(curwp);
	associate_b2w(curbp, curwp);

	beginning_of_buffer();
	undoset();
	call_lisp_event("startup", "");
	key_map = keymap;


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
	(void) vsnprintf(msgline, TEMPBUF, m, args);
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

	vsnprintf (buffer, sizeof(buffer), format, args);
	va_end(args);

	fprintf(debug_fp,"%s", buffer);
	fflush(debug_fp);
}

void debug_stats(char *s) {
	debug("%s bsz=%d p=%d m=%d gap=%d egap=%d\n", s, curbp->b_ebuf - curbp->b_buf, curbp->b_point, curbp->b_mark, curbp->b_gap - curbp->b_buf, curbp->b_egap - curbp->b_buf);
}
