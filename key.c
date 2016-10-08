/*
 * key.c, Femto Emacs, Hugh Barney, Public Domain, 2016
 * Derived from: Anthony's Editor January 93, (Public Domain 1991, 1993 by Anthony Howe)
 */

#include "header.h"

/* name, function */
command_t commands[] = {
        {"apropos", apropos_command},
	{"backspace", backsp},
	{"backward-character", left},
	{"backward-page", backward_page},
	{"backward-word", backward_word},
	{"beginning-of-buffer", beginning_of_buffer},
	{"beginning-of-line", lnbegin},
	{"clear-message-line", clear_message_line},
	{"copy-region", copy},
	{"cursor-position", showpos},
	{"delete-left", backsp},
	{"delete-other-windows", delete_other_windows},
	{"describe-key", i_describe_key},
	{"end-of-buffer", end_of_buffer},
	{"end-of-line", lnend},
	{"eval-block", eval_block},
	{"exec-lisp-command", repl},
	{"exit", quit_ask},
	{"find-file", readfile},
	{"forward-character", right},
	{"forward-delete-char", delete},
	{"forward-page", forward_page},
	{"forward-word", forward_word},
	{"goto-line", i_gotoline},
	{"insert-file", insertfile},
	{"kill-buffer", killbuffer},
	{"kill-line", killtoeol},
	{"kill-region", cut},
	{"list-bindings", list_bindings},
	{"list-buffers", list_buffers},
	{"next-buffer", next_buffer},
	{"next-line", down},
	{"other-window", other_window},
	{"previous-line", up},
	{"query-replace", query_replace},
	{"refresh", redraw},
	{"resize-terminal", resize_terminal},
	{"save-buffer", savebuffer},
	{"search-backward", search},
	{"search-forward", search},
	{"set-mark", i_set_mark},
	{"shell-command", i_shell_command},
	{"show-version", version},
	{"split-window", split_window},
	{"toggle-overwrite-mode", toggle_overwrite_mode},
	{"undo", undo},
	{"write-file", writefile},
	{"yank", paste},
	{NULL, NULL }
};


/* desc, keys, func */
keymap_t keymap[] = {
        {"resize",    "resize-terminal"       , "\x9A", resize_terminal },
	{"up",        "previous-line"         , "\x1B\x5B\x41", up },
	{"down",      "next-line"             , "\x1B\x5B\x42", down },
	{"left",      "backward-character"    , "\x1B\x5B\x44", left },
	{"right",     "forward-character"     , "\x1B\x5B\x43", right },
	{"C-a",       "beginning-of-line"     , "\x01", lnbegin },
	{"C-e",       "end-of-line"           , "\x05", lnend },
	{"home",      "beginning-of-line"     , "\x1B\x4F\x48", lnbegin }, /* home key */
	{"end",       "end-of-line"           , "\x1B\x4F\x46", lnend }, /* end key */
	{"C-b",       "backward-character"    , "\x02", left },
	{"C-f",       "forward-character"     , "\x06", right },
	{"C-n",       "next-line"             , "\x0E", down },
	{"C-p",       "previous-line"         , "\x10", up },
	{"C-d",       "forward-delete-char"   , "\x04", delete },
	{"INS",       "toggle-overwrite-mode" , "\x1B\x5B\x32\x7E", toggle_overwrite_mode }, /* Ins key */
	{"DEL",       "forward-delete-char"   , "\x1B\x5B\x33\x7E", delete }, /* Del key */
	{"backspace", "backspace"             , "\x7f", backsp },
	{"C-h",       "backspace"             , "\x08", backsp },
	{"C-l",       "refresh"               , "\x0C", redraw },
	{"C-u",       "undo"                  , "\x15", undo },
	{"esc v",     "backward-page"         , "\x1B\x76", backward_page },
	{"esc V",     "backward-page"         , "\x1B\x56", backward_page },
	{"C-v",       "forward-page"          , "\x16", forward_page },
	{"PgUp",      "backward-page"         , "\x1B\x5B\x35\x7E", backward_page },
	{"PgDn",      "forward-page"          , "\x1B\x5B\x36\x7E", forward_page },
	{"esc <",     "beginning-of-buffer"   , "\x1B\x3C", beginning_of_buffer},
	{"esc >",     "end-of-buffer"         , "\x1B\x3E", end_of_buffer },
	{"esc home",  "beginning-of-buffer"   , "\x1B\x1B\x4F\x48", beginning_of_buffer},
	{"esc end",   "end-of-buffer"         , "\x1B\x1B\x4F\x46", end_of_buffer },
	{"esc up",    "beginning-of-buffer"   , "\x1B\x1B\x5B\x41", beginning_of_buffer},
	{"esc down",  "end-of-buffer"         , "\x1B\x1B\x5B\x42", end_of_buffer },
        {"esc a",     "apropos"               , "\x1B\x61", apropos_command },
	{"esc b",     "backward-word"         , "\x1B\x62", backward_word },
	{"esc f",     "forward-word"          , "\x1B\x66", forward_word },
	{"esc g",     "goto-line"             , "\x1B\x67", i_gotoline },
	{"esc r",     "query-replace"         , "\x1B\x72", query_replace },
	{"esc B",     "backward-word"         , "\x1B\x42", backward_word },
	{"esc F",     "forward-word"          , "\x1B\x46", forward_word },
	{"esc G",     "goto-line"             , "\x1B\x47", i_gotoline },
	{"esc R",     "query-replace"         , "\x1B\x52", query_replace },
	{"esc c",     "copy-region"           , "\x1B\x63", copy },
	{"esc d",     "kill-line"             , "\x1B\x64", killtoeol },
	{"esc i",     "yank"                  , "\x1B\x69", paste },
	{"esc k",     "kill-region"           , "\x1B\x6B", cut },
	{"esc l",     "list-bindings"         , "\x1B\x6C", list_bindings },
	{"esc m",     "set-mark"              , "\x1B\x6D", i_set_mark },
	{"esc n",     "next-buffer"           , "\x1B\x6E", next_buffer },
	{"esc o",     "delete-other-windows"  , "\x1B\x6F", delete_other_windows },
	{"esc x",     "execute-command"       , "\x1B\x78", execute_command },
	{"C-space",   "set-mark"              , "\x00", i_set_mark },
	{"esc @",     "set-mark"              , "\x1B\x40", i_set_mark },
	{"C-w",       "kill-region"           , "\x17", cut},
	{"C-y",       "yank"                  , "\x19", paste},
	{"esc w",     "copy-region"           , "\x1B\x77", copy},
	{"esc W",     "copy-region"           , "\x1B\x57", copy},
	{"C-k",       "kill-line"             , "\x0B", killtoeol },
	{"C-s",       "search-forward"        , "\x13", search },
	{"C-r",       "search-backward"       , "\x12", search },
	{"C-o",       "exec-lisp-command"     , "\x0F", repl },
	{"C-x 1",     "delete-other-windows"  , "\x18\x31", delete_other_windows },
	{"C-x 2",     "split-window"          , "\x18\x32", split_window },
	{"C-x o",     "other-window"          , "\x18\x6F", other_window },
	{"C-x @",     "shell-command"         , "\x18\x40", i_shell_command },
	{"C-x =",     "cursor-position"       , "\x18\x3D", showpos },
	{"C-x ?",     "describe-key"          , "\x18\x3F", i_describe_key },
	{"C-x i",     "insert-file"           , "\x18\x69", insertfile },
	{"C-x k",     "kill-buffer"           , "\x18\x6B", killbuffer },
	{"C-x C-n",   "next-buffer"           , "\x18\x0E", next_buffer },
	{"C-x n",     "next-buffer"           , "\x18\x6E", next_buffer },
	{"C-x C-b",   "list-buffers"          , "\x18\x02", list_buffers },
	{"C-x C-f",   "find-file"             , "\x18\x06", readfile },
	{"C-x C-s",   "save-buffer"           , "\x18\x13", savebuffer },
	{"C-x C-u",   "user-defined-function" , "\x18\x15", keyboardDefinition },
	{"C-x C-l",   "user-defined-function" , "\x18\x0C", keyboardDefinition },
	{"C-x C-w",   "write-file"            , "\x18\x17", writefile },
	{"C-x C-c",   "exit"                  , "\x18\x03", quit_ask },
	{"esc ]",     "eval-block"            , "\x1B\x5D", eval_block },
	{"esc esc",   "show-version"          , "\x1B\x1B", version },
        {"C-c a",     "user-defined-function" , "\x03\x61", keyboardDefinition },
        {"C-c b",     "user-defined-function" , "\x03\x62", keyboardDefinition },
        {"C-c c",     "user-defined-function" , "\x03\x63", keyboardDefinition },
        {"C-c d",     "user-defined-function" , "\x03\x64", keyboardDefinition },
        {"C-c e",     "user-defined-function" , "\x03\x65", keyboardDefinition },
        {"C-c f",     "user-defined-function" , "\x03\x66", keyboardDefinition },
        {"C-c g",     "user-defined-function" , "\x03\x67", keyboardDefinition },
        {"C-c h",     "user-defined-function" , "\x03\x68", keyboardDefinition },
        {"C-c i",     "user-defined-function" , "\x03\x69", keyboardDefinition },
        {"C-c j",     "user-defined-function" , "\x03\x6A", keyboardDefinition },
        {"C-c k",     "user-defined-function" , "\x03\x6B", keyboardDefinition },
        {"C-c l",     "user-defined-function" , "\x03\x6C", keyboardDefinition },
        {"C-c m",     "user-defined-function" , "\x03\x6D", keyboardDefinition },
        {"C-c n",     "user-defined-function" , "\x03\x6E", keyboardDefinition },
        {"C-c o",     "user-defined-function" , "\x03\x6F", keyboardDefinition },
        {"C-c p",     "user-defined-function" , "\x03\x70", keyboardDefinition },
        {"C-c q",     "user-defined-function" , "\x03\x71", keyboardDefinition },
        {"C-c r",     "user-defined-function" , "\x03\x72", keyboardDefinition },
        {"C-c s",     "user-defined-function" , "\x03\x73", keyboardDefinition },
        {"C-c t",     "user-defined-function" , "\x03\x74", keyboardDefinition },
        {"C-c u",     "user-defined-function" , "\x03\x75", keyboardDefinition },
        {"C-c v",     "user-defined-function" , "\x03\x76", keyboardDefinition },
        {"C-c w",     "user-defined-function" , "\x03\x77", keyboardDefinition },
        {"C-c x",     "user-defined-function" , "\x03\x78", keyboardDefinition },
        {"C-c y",     "user-defined-function" , "\x03\x79", keyboardDefinition },
        {"C-c z",     "user-defined-function" , "\x03\x7A", keyboardDefinition },
	{NULL, NULL, NULL, NULL }
};

char_t *get_key(keymap_t *keys, keymap_t **key_return)
{
	keymap_t *k;
	int submatch;
	static char_t buffer[K_BUFFER_LENGTH];
	static char_t *record = buffer;

	*key_return = NULL;

	/* if recorded bytes remain, return next recorded byte. */
	if (*record != '\0') {
		*key_return = NULL;
		return record++;
	}
	/* reset record buffer. */
	record = buffer;

	do {
		assert(K_BUFFER_LENGTH > record - buffer);
		/* read and record one byte. */
		*record++ = (unsigned)getch();
		*record = '\0';

		/* if recorded bytes match any multi-byte sequence... */
		for (k = keys, submatch = 0; k->key_bytes != NULL; ++k) {
			char_t *p, *q;

			for (p = buffer, q = (char_t *)k->key_bytes; *p == *q; ++p, ++q) {
			        /* an exact match */
				if (*q == '\0' && *p == '\0') {
	    				record = buffer;
					*record = '\0';
					*key_return = k;
					return record; /* empty string */
				}
			}
			/* record bytes match part of a command sequence */
			if (*p == '\0' && *q != '\0') {
				submatch = 1;
			}
		}
	} while (submatch);
	/* nothing matched, return recorded bytes. */
	record = buffer;
	return (record++);
}

/* wrapper to simplify call and dependancies in the interface code */
char *fe_get_input_key()
{
	return (char *)get_key(key_map, &key_return);
}

/* the name of the bound function of this key */
char *get_key_binding()
{
	assert(key_return != NULL);
	return key_return->key_desc;
}

/* the name of the last key */
char *get_key_name()
{
	assert(key_return != NULL);
	return key_return->key_name;
}

int getinput(char *prompt, char *buf, int nbuf)
{
	int cpos = 0;
	int c;
	int start_col = strlen(prompt);

	mvaddstr(MSGLINE, 0, prompt);
	clrtoeol();

	/* if we have a default value print it and go to end of it */
	if (buf[0] != '\0') {
		addstr(buf);
		cpos = strlen(buf);
	}

	for (;;) {
		refresh();
		c = getch();
		/* ignore control keys other than backspace, cr, lf */
		if (c < 32 && c != 0x07 && c != 0x08 && c != 0x0a && c != 0x0d)
			continue;

		switch(c) {
		case 0x0a: /* cr, lf */
		case 0x0d:
			buf[cpos] = '\0';
			return (cpos > 0 ? TRUE : FALSE);

		case 0x07: /* ctrl-g */
			return FALSE;

		case 0x7f: /* del, erase */
		case 0x08: /* backspace */
			if (cpos == 0)
				continue;

			move(MSGLINE, start_col + cpos - 1);
			addch(' ');
			move(MSGLINE, start_col + cpos - 1);
			buf[--cpos] = '\0';
			break;

		default:
			if (cpos < nbuf -1) {
				addch(c);
				buf[cpos++] = c;
				buf[cpos] ='\0';
			}
			break;
		}
	}
}
