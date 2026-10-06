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
	{"delete-window", delete_window},
	{"enlarge-window", enlarge_window},
	{"describe-key", i_describe_key},
	{"discard-undo-history", discard_undo_history},
	{"end-of-buffer", end_of_buffer},
	{"end-of-line", lnend},
	{"eval-block", eval_block},
	{"exec-lisp-command", repl},
	{"exit", quit_ask},
	{"find-file", i_readfile},
	{"forward-character", right},
	{"forward-delete-char", delete},
	{"forward-page", forward_page},
	{"forward-word", forward_word},
	{"goto-line", i_gotoline},
	{"insert-file", insertfile},
	{"kill-buffer", killbuffer},
	{"kmacro-end-and-call-macro", kmacro_call},
	{"kmacro-end-macro", kmacro_end},
	{"kmacro-start-macro", kmacro_start},
	{"kill-line", killtoeol},
	{"kill-region", cut},
	{"list-bindings", list_bindings},
	{"list-buffers", list_buffers},
	{"list-undo", list_undos},
	{"list-stats-undo", list_undo_stats},
	{"next-buffer", next_buffer},
	{"next-line", down},
	{"other-window", other_window},
	{"previous-line", up},
	{"query-replace", query_replace},
	{"recenter", recenter},
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
	{"undo", undo_command},
	{"write-file", writefile},
	{"yank", paste},
	{NULL, NULL }
};

/* desc, keys, func */
keymap_t keymap[] = {
	{"backspace", "backspace"             , "\x7f", backsp },
	{"C-a",       "beginning-of-line"     , "\x01", lnbegin },
	{"C-b",       "backward-character"    , "\x02", left },
	{"C-d",       "forward-delete-char"   , "\x04", delete },
	{"C-e",       "end-of-line"           , "\x05", lnend },
	{"C-f",       "forward-character"     , "\x06", right },
	{"C-h",       "backspace"             , "\x08", backsp },
	{"C-k",       "kill-line"             , "\x0B", killtoeol },
	{"C-l",       "refresh"               , "\x0C", redraw },
	{"C-n",       "next-line"             , "\x0E", down },
	{"C-o",       "user-defined-function" , "\x0F", keyboardDefinition},
	{"C-p",       "previous-line"         , "\x10", up },
	{"C-q",       "user-defined-function" , "\x11", keyboardDefinition},
	{"C-r",       "search-backward"       , "\x12", search },
	{"C-space",   "set-mark"              , "\x00", i_set_mark },
	{"C-s",       "search-forward"        , "\x13", search },
	{"C-t",       "user-defined-function" , "\x14", keyboardDefinition },
	{"C-u",       "undo"                  , "\x15", undo_command },
	{"C-v",       "forward-page"          , "\x16", forward_page },
	{"C-w",       "kill-region"           , "\x17", cut},
	{"C-y",       "yank"                  , "\x19", paste},
	{"C-z",       "user-defined-function" , "\x1A", keyboardDefinition},

	{"C-x 0",     "delete-window"         , "\x18\x30", delete_window },
	{"C-x 1",     "delete-other-windows"  , "\x18\x31", delete_other_windows },
	{"C-x 2",     "split-window"          , "\x18\x32", split_window },

	{"C-x C-a",   "user-defined-function" , "\x18\x01", keyboardDefinition },
	{"C-x C-b",   "user-defined-function" , "\x18\x02", keyboardDefinition },
	{"C-x C-c",   "exit"                  , "\x18\x03", quit_ask },
	{"C-x C-b",   "user-defined-function" , "\x18\x02", keyboardDefinition },
	{"C-x C-d",   "user-defined-function" , "\x18\x04", keyboardDefinition },
	{"C-x C-e",   "user-defined-function" , "\x18\x05", keyboardDefinition },
	{"C-x C-f",   "find-file"             , "\x18\x06", i_readfile },
	{"C-x C-g",   "user-defined-function" , "\x18\x07", keyboardDefinition },
	{"C-x C-h",   "user-defined-function" , "\x18\x08", keyboardDefinition },
	{"C-x C-i",   "user-defined-function" , "\x18\x09", keyboardDefinition },
	{"C-x C-j",   "user-defined-function" , "\x18\x0A", keyboardDefinition },
	{"C-x C-k",   "user-defined-function" , "\x18\x0B", keyboardDefinition },
	{"C-x C-l",   "user-defined-function" , "\x18\x0C", keyboardDefinition },
	{"C-x C-m",   "user-defined-function" , "\x18\x0D", keyboardDefinition },
	{"C-x C-n",   "next-buffer"           , "\x18\x0E", next_buffer },
	{"C-x C-o",   "user-defined-function" , "\x18\x0F", keyboardDefinition },
	{"C-x C-p",   "user-defined-function" , "\x18\x10", keyboardDefinition },
	{"C-x C-q",   "user-defined-function" , "\x18\x11", keyboardDefinition },
	{"C-x C-r",   "user-defined-function" , "\x18\x12", keyboardDefinition },
	{"C-x C-s",   "save-buffer"           , "\x18\x13", savebuffer },
	{"C-x C-t",   "user-defined-function" , "\x18\x14", keyboardDefinition },
	{"C-x C-u",   "user-defined-function" , "\x18\x15", keyboardDefinition },
	{"C-x C-v",   "user-defined-function" , "\x18\x16", keyboardDefinition },
	{"C-x C-w",   "write-file"            , "\x18\x17", writefile },
	{"C-x C-y",   "user-defined-function" , "\x18\x18", keyboardDefinition },
	{"C-x C-z",   "user-defined-function" , "\x18\x19", keyboardDefinition },
	{"C-x =",     "cursor-position"       , "\x18\x3D", showpos },
	{"C-x (",     "kmacro-start-macro"    , "\x18\x28", kmacro_start },
	{"C-x )",     "kmacro-end-macro"      , "\x18\x29", kmacro_end },
	{"C-x e",     "kmacro-end-and-call-macro", "\x18\x65", kmacro_call },
	{"C-x ^",     "enlarge-window"        , "\x18\x5E", enlarge_window },
	{"C-x ?",     "describe-key"          , "\x18\x3F", i_describe_key },
	{"C-x !",     "next-grep"             , "\x18\x21", keyboardDefinition },
	{"C-x b",     "list-buffers"          , "\x18\x62", list_buffers },
	{"C-x i",     "insert-file"           , "\x18\x69", insertfile },
	{"C-x k",     "kill-buffer"           , "\x18\x6B", killbuffer },
	{"C-x n",     "next-buffer"           , "\x18\x6E", next_buffer },
	{"C-x o",     "other-window"          , "\x18\x6F", other_window },
	{"C-x @",     "shell-command"         , "\x18\x40", i_shell_command },
	{"mouse",     "mouse"                 , "\x1B\x5B\x4D", editor_mouse_event },
	{"mouse",     "mouse"                 , "\x1B\x5B\x3C", editor_mouse_event },
	{"F1",        "help"                  , "\x1B\x4F\x50", keyboardDefinition },
	{"F1",        "help"                  , "\x1B\x5B\x31\x31\x7E", keyboardDefinition },
	{"F1",        "help"                  , "\x1B\x5B\x5B\x41", keyboardDefinition },
	{"DEL",       "forward-delete-char"   , "\x1B\x5B\x33\x7E", delete },
	{"down",      "next-line"             , "\x1B\x5B\x42", down },
	{"end",       "end-of-line"           , "\x1B\x4F\x46", lnend },
        {"esc a",     "apropos"               , "\x1B\x61", apropos_command },
	{"esc B",     "backward-word"         , "\x1B\x42", backward_word },
	{"esc b",     "backward-word"         , "\x1B\x62", backward_word },
	{"esc <",     "beginning-of-buffer"   , "\x1B\x3C", beginning_of_buffer},
	{"esc c",     "copy-region"           , "\x1B\x63", copy },
	{"esc d",     "kill-line"             , "\x1B\x64", killtoeol },
	{"esc down",  "end-of-buffer"         , "\x1B\x1B\x5B\x42", end_of_buffer },
	{"esc end",   "end-of-buffer"         , "\x1B\x1B\x4F\x46", end_of_buffer },
	{"esc >",     "end-of-buffer"         , "\x1B\x3E", end_of_buffer },
	{"esc esc",   "show-version"          , "\x1B\x1B", version },
	{"esc ]",     "eval-block"            , "\x1B\x5D", eval_block },
	{"esc ;",     "exec-lisp-command"     , "\x1B\x3B", repl },
	{"esc F",     "forward-word"          , "\x1B\x46", forward_word },
	{"esc f",     "forward-word"          , "\x1B\x66", forward_word },
	{"esc G",     "goto-line"             , "\x1B\x47", i_gotoline },
	{"esc g",     "goto-line"             , "\x1B\x67", i_gotoline },
	{"esc home",  "beginning-of-buffer"   , "\x1B\x1B\x4F\x48", beginning_of_buffer},
	{"esc i",     "yank"                  , "\x1B\x69", paste },
	{"esc k",     "kill-region"           , "\x1B\x6B", cut },
	{"esc l",     "list-bindings"         , "\x1B\x6C", list_bindings },
	{"esc m",     "set-mark"              , "\x1B\x6D", i_set_mark },
	{"esc n",     "next-buffer"           , "\x1B\x6E", next_buffer },
	{"esc o",     "delete-other-windows"  , "\x1B\x6F", delete_other_windows },
	{"esc R",     "query-replace"         , "\x1B\x52", query_replace },
	{"esc r",     "query-replace"         , "\x1B\x72", query_replace },
	{"esc @",     "set-mark"              , "\x1B\x40", i_set_mark },
	{"esc up",    "beginning-of-buffer"   , "\x1B\x1B\x5B\x41", beginning_of_buffer},
	{"esc V",     "backward-page"         , "\x1B\x56", backward_page },
	{"esc v",     "backward-page"         , "\x1B\x76", backward_page },
	{"esc W",     "copy-region"           , "\x1B\x57", copy},
	{"esc w",     "copy-region"           , "\x1B\x77", copy},
	{"esc x",     "execute-command"       , "\x1B\x78", execute_command },
	{"home",      "beginning-of-line"     , "\x1B\x4F\x48", lnbegin },
	{"INS",       "toggle-overwrite-mode" , "\x1B\x5B\x32\x7E", toggle_overwrite_mode },
	{"left",      "backward-character"    , "\x1B\x5B\x44", left },
	{"PgDn",      "forward-page"          , "\x1B\x5B\x36\x7E", forward_page },
	{"PgUp",      "backward-page"         , "\x1B\x5B\x35\x7E", backward_page },
        {"resize",    "resize-terminal"       , "\x9A", resize_terminal },
	{"right",     "forward-character"     , "\x1B\x5B\x43", right },
	{"up",        "previous-line"         , "\x1B\x5B\x41", up },
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

/*
 * Every byte of keyboard (and mouse) input passes through here, so that
 * keyboard macros can record it and play it back.
 */
#define MACRO_MAX 4096

static char_t macro_buf[MACRO_MAX];
static int macro_len = 0;
static int macro_recording = 0;
static int macro_play = -1;          /* next byte to play back, or -1 */
static int macro_repeat = 0;         /* "e" right after C-x e repeats it */

int read_key_byte(void)
{
	int c;

	if (macro_play >= 0) {
		if (macro_play < macro_len)
			return macro_buf[macro_play++];
		macro_play = -1;
	}
	c = screen_getch();
	if (macro_repeat) {
		macro_repeat = 0;
		if (c == 'e' && macro_len > 0) {
			macro_play = 0;
			macro_repeat = 1;
			return read_key_byte();
		}
	}
	if (macro_recording && c >= 0) {
		if (macro_len < MACRO_MAX)
			macro_buf[macro_len++] = (char_t) c;
		else {
			macro_recording = 0;
			msg("Keyboard macro too long; recording stopped");
		}
	}
	return c;
}

void kmacro_start(void)
{
	if (macro_recording) {
		msg("Already defining a keyboard macro");
		return;
	}
	macro_len = 0;
	macro_recording = 1;
	msg("Defining keyboard macro...  C-x ) ends it");
}

void kmacro_end(void)
{
	if (!macro_recording) {
		msg("Not defining a keyboard macro");
		return;
	}
	macro_recording = 0;
	/* the C-x ) that ended it was recorded too */
	if (macro_len >= 2 && macro_buf[macro_len - 2] == 0x18 && macro_buf[macro_len - 1] == ')')
		macro_len -= 2;
	msg("Keyboard macro defined; C-x e runs it");
}

void kmacro_call(void)
{
	if (macro_recording) {
		kmacro_end();
		if (macro_len >= 2 && macro_buf[macro_len - 2] == 0x18 && macro_buf[macro_len - 1] == 'e')
			macro_len -= 2;
	}
	if (macro_play >= 0)            /* a macro that calls itself */
		return;
	if (macro_len == 0) {
		msg("No keyboard macro defined");
		return;
	}
	macro_play = 0;
	macro_repeat = 1;
	msg("(Type e to repeat the macro)");
}

/* mouse event decoded by get_key: button, 0-based column and row, press or release */
int mouse_button, mouse_col, mouse_row, mouse_release;

static int read_number(int *terminator)
{
	int n = 0, c;
	while ((c = read_key_byte()) >= '0' && c <= '9')
		n = n * 10 + (c - '0');
	*terminator = c;
	return n;
}

/* ESC [ < b ; x ; y M (press, drag) or m (release): xterm SGR encoding */
static void read_mouse_sgr(void)
{
	int t;
	mouse_button = read_number(&t);
	mouse_col = read_number(&t) - 1;
	mouse_row = read_number(&t) - 1;
	mouse_release = (t == 'm');
}

/* ESC [ M b x y: the old X10 encoding, each byte + 32 */
static void read_mouse_x10(void)
{
	int b = (read_key_byte() & 0xFF) - 32;
	mouse_col = (read_key_byte() & 0xFF) - 33;
	mouse_row = (read_key_byte() & 0xFF) - 33;
	mouse_release = ((b & 3) == 3 && !(b & 64));
	mouse_button = mouse_release ? 0 : b;
}

/*
 * Keys that are not in the table get a name anyway, so that Lisp can
 * bind them: C-g, C-x h, esc d (M-d), esc C-f (C-M-f), C-c 1, ...
 */
static void byte_name(char *out, int b)
{
	b &= 0xFF;
	if (b == 0)
		strcpy(out, "C-space");
	else if (b == 0x1b)
		strcpy(out, "esc");
	else if (b < 27)
		sprintf(out, "C-%c", b + 96);
	else if (b < 32)
		sprintf(out, "C-%c", "\\]^_"[b - 28]);
	else if (b == ' ')
		strcpy(out, "SPC");
	else if (b == 0x7f)
		strcpy(out, "backspace");
	else
		sprintf(out, "%c", b);
}

static char synth_name[64];
static keymap_t synth_key = { synth_name, "user-defined-function", NULL, keyboardDefinition };

/*
 * Name an unmatched sequence, or return 0 when it is ordinary text
 * (printable characters, TAB, RET, UTF-8).
 */
static int name_sequence(char_t *seq, int len)
{
	char a[16], b[16];
	int i, n;

	if (len == 1 && (seq[0] >= 32 || seq[0] == 0x09 || seq[0] == 0x0a || seq[0] == 0x0d))
		return 0;
	if (len == 1) {
		byte_name(synth_name, seq[0]);
		return 1;
	}
	if (len == 2 && (seq[0] == 0x1b || seq[0] == 0x18 || seq[0] == 0x03)) {
		byte_name(b, seq[1]);
		snprintf(synth_name, sizeof(synth_name), "%s %s",
			 seq[0] == 0x1b ? "esc" : seq[0] == 0x18 ? "C-x" : "C-c", b);
		return 1;
	}
	/* an unknown escape sequence (C-left, F5, ...): name its bytes */
	strcpy(synth_name, "esc ");
	n = 4;
	for (i = 1; i < len && n < (int) sizeof(synth_name) - 8; i++) {
		byte_name(a, seq[i]);
		n += snprintf(synth_name + n, sizeof(synth_name) - n, "%s", a);
	}
	return 1;
}

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
		*record++ = (unsigned)read_key_byte();
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
					/* a mouse event: read its parameters now, so
					   that they never reach the buffer as text */
					if (k->func == editor_mouse_event) {
						if (k->key_bytes[2] == '<')
							read_mouse_sgr();
						else
							read_mouse_x10();
					}
					return record; /* empty string */
				}
			}
			/* record bytes match part of a command sequence */
			if (*p == '\0' && *q != '\0') {
				submatch = 1;
			}
		}
	} while (submatch);

	/* the rest of an unknown escape sequence: up to its final byte */
	if (buffer[0] == 0x1b && record - buffer >= 2 && (buffer[1] == '[' || buffer[1] == 'O')) {
		while (!(record[-1] >= 0x40 && record[-1] <= 0x7e && record - buffer > 2)
		       && record - buffer < K_BUFFER_LENGTH - 1) {
			*record++ = (unsigned)read_key_byte();
			*record = '\0';
		}
	}

	/* nothing matched */
	if (name_sequence(buffer, (int) (record - buffer))) {
		record = buffer;
		*record = '\0';
		*key_return = &synth_key;
		return record;
	}
	/* ordinary text: return the recorded bytes one at a time */
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

int getinput(char *prompt, char *buf, int nbuf, int flag)
{
	int cpos = 0;
	int c;
	int start_col = strlen(prompt);

	screen_mvaddstr(MSGLINE, 0, prompt);
	screen_clrtoeol();

	if (flag == F_CLEAR) buf[0] = '\0';

	/* if we have a default value print it and go to end of it */
	if (buf[0] != '\0') {
		screen_addstr(buf);
		cpos = strlen(buf);
	}

	for (;;) {
		screen_refresh();
		c = read_key_byte();
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

			screen_move(MSGLINE, start_col + cpos - 1);
			screen_addch(' ');
			screen_move(MSGLINE, start_col + cpos - 1);
			buf[--cpos] = '\0';
			break;

		default:
			if (cpos < nbuf -1) {
				screen_addch(c);
				buf[cpos++] = c;
				buf[cpos] ='\0';
			}
			break;
		}
	}
}
