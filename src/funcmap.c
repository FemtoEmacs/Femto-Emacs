/* funcmap.c, Femto Emacs, Hugh Barney, Public Domain, 2016 */

#include "header.h"

void free_string_list(string_list_t *list)
{
	string_list_t *next;

	while (list) {
		next = list->next;
		free(list->string);
		free(list);
		list = next;
	}
}

int count_string_list(string_list_t *list)
{
	int count = 0;
	string_list_t *sl;

	if (list == NULL) return 0;

	for (sl = list; sl != NULL; sl = sl-> next)
		count++;
	return count;
}


/*
 * Commands defined in Lisp, offered by Esc-x next to the C ones (Lisp
 * registers them with fe_add_command_name; Esc-x runs them through the
 * "command" event).
 */
static char **lisp_commands = NULL;
static int n_lisp_commands = 0;
static int lisp_commands_cap = 0;

void fe_add_command_name(char *name)
{
	int i;
	for (i = 0; i < n_lisp_commands; i++)
		if (strcmp(lisp_commands[i], name) == 0)
			return;
	if (n_lisp_commands == lisp_commands_cap) {
		lisp_commands_cap = lisp_commands_cap ? 2 * lisp_commands_cap : 64;
		lisp_commands = realloc(lisp_commands, lisp_commands_cap * sizeof(char *));
		assert(lisp_commands != NULL);
	}
	lisp_commands[n_lisp_commands++] = strdup(name);
}

static string_list_t *add_match(string_list_t *head, const char *name)
{
	string_list_t *sl;
	for (sl = head; sl != NULL; sl = sl->next)  /* a Lisp command may shadow a C one */
		if (strcmp(sl->string, name) == 0)
			return head;
	if ((sl = malloc(sizeof(*sl))) == NULL)
		return head;
	sl->string = strdup(name);
	sl->next = head;
	return sl;
}

/*
 * match possible function names
 */
string_list_t *match_functions(const char *fname)
{
	command_t       *fn;
	string_list_t   *head, *sl;
	int		 len;
	int              count = 0;

	len = strlen(fname);
	head = NULL;

	(void) sl;
	(void) count;
	for (fn = commands; fn->name != NULL; fn++)
		if (strncmp(fname, fn->name, len) == 0)
			head = add_match(head, fn->name);
	for (count = 0; count < n_lisp_commands; count++)
		if (strncmp(fname, lisp_commands[count], len) == 0)
			head = add_match(head, lisp_commands[count]);
	return head;
}

/*
 * should run this after changing the static key-binding list to check if any
 * mis-matches of command names against the key binding names have been introduced.
 *
 */
void check_maps()
{
	command_t *fn;
	keymap_t *ky;
	int found;

	for (ky = keymap; ky->key_desc != NULL; ky++) {

		found = 0;

		for (fn = commands; fn->name != NULL; fn++)
			if (strcmp(fn->name, ky->key_desc) == 0)
				found = 1;

		if (found == 0)
			debug("No match for (%s) (%s)\n", ky->key_name, ky->key_desc);
	}
}

typedef void (*void_func)(void);

/* translate from function name to function pointer */
void_func name_to_function(const char *fname)
{
	command_t *fn;

	for (fn = commands; fn->name != NULL; fn++)
		if (strcmp(fn->name, fname) == 0)
			return fn->func;
	return NULL;
}


int match_string_position(string_list_t *list, int pos)
{
	string_list_t *sl;
	char ch;

	if (list == NULL)
		return FALSE;

	ch = list->string[pos];

	for (sl = list; sl != NULL; sl = sl->next) {
		if (sl->string[pos] != ch)
			return FALSE;
	}
	return TRUE;
}

int shortest_string_len(string_list_t *list)
{
	string_list_t *sl;
	int shortest = 100;
	int i = 0;

	if (list == NULL) return 0;

	for (sl = list; sl != NULL; sl = sl->next) {
		i = strlen(sl->string);
		if (i <= shortest)
			shortest = i;
	}
	return shortest;
}

char *shortest_common_string(string_list_t *list)
{
	static char str[60];
	static char empty_string[] = "";
	int pos;
	int len = shortest_string_len(list);

	if (len == 0) return empty_string;

	for (pos = 0; pos < len; pos++)
		if (match_string_position(list, pos) == FALSE)
			break;

	pos++;

	/* return pos chars from first string */
	safe_strncpy(str, list->string, pos);
	return str;
}

/* show commands that match a sub-string */
void apropos_command()
{
	buffer_t *bp;
	command_t *fn;
	keymap_t *ky;
	char bindlist[40];
	char apropos[STRBUF_M];

	if (0 == getinput(str_apropos, response_buf, STRBUF_M, F_CLEAR))
		return;

	bp = find_buffer(str_help_buf, TRUE);
	assert(bp != NULL);
	zero_buffer(bp);

	for (fn = commands; fn->name != NULL; fn++) {
		if (strstr(fn->name, response_buf) == NULL)
			continue;

		bindlist[0] = '\0';

		for (ky = keymap; ky->key_desc != NULL; ky++) {
			if (strcmp(fn->name, ky->key_desc) == 0) {
				if (bindlist[0] != '\0')
					strcat(bindlist, ", ");

				strcat(bindlist, ky->key_name);

				/* place some limits on the number of keys bindings we will show per command */
				if (strlen(bindlist) > 30)
					break;
			}
		}

		sprintf(apropos, "%-30s %s\n", fn->name, bindlist);
		append_string(bp, apropos);
	}

	(void)popup_window(str_help_buf);
}

/* show all the key bindings in a buffer */
void list_bindings()
{
	buffer_t *bp;
	keymap_t *ky;
	char binding[80];

	bp = find_buffer(str_help_buf, TRUE);
	assert(bp != NULL);
	zero_buffer(bp);

	for (ky = keymap; ky->key_desc != NULL; ky++) {
		sprintf(binding, "%-16s %s\n", ky->key_name, ky->key_desc);
		append_string(bp, binding);
	}

	(void)popup_window(bp->b_bname);
}

/* Esc-x execute command prompt */
void execute_command()
{
	buffer_t *bp = NULL;
	window_t *wp = NULL;
	string_list_t *cmd_list, *sl;
	void_func funct = NULL;

	int process_input = 1;
	int tab_count = 0;
	int column = 0;
	int cpos = 0;
	int ch;
	char command_name[STRBUF_M + 1];
	char prompt[] = "Execute command: ";
	char *shortest_match;

	command_name[0] = '\0';
	bp = find_buffer(str_completions, TRUE);
	assert(bp != NULL);

	display_prompt_and_response(prompt, command_name);
	cpos = strlen(command_name);

	while (process_input) {
		ch = read_key_byte();
		/* ignore control keys other than C-g, TAB, backspace, del, CR, ESC */
		if (ch < 32 && ch != 7 && ch != 9 && ch != 8 && ch != 13 && ch != 10 && ch != 27)
			continue;

		switch(ch) {
		case 27: /* esc */
			tab_count = 0;
			screen_flushinp(); /* discard any escape sequence without writing in buffer */
			break;

		case 7: /* ctrl-g */
			command_name[0] = '\0';
			process_input = 0;
			break;

		case 13: /* CR, LF, only allow if there is 1 matched command waiting */
		case 10:
			cmd_list = match_functions(command_name);
			/* one candidate, or one that is exactly what was typed */
			for (sl = cmd_list; sl != NULL; sl = sl->next)
				if (strcmp(sl->string, command_name) == 0)
					break;
			if (sl == NULL && 1 != count_string_list(cmd_list)) {
				free_string_list(cmd_list);
				continue;
			}
			if (sl == NULL)
				strcpy(command_name, cmd_list->string);

			free_string_list(cmd_list);
			process_input = 0;
			break;

		case 9: /* TAB */
			tab_count++;
			cmd_list = match_functions(command_name);
			shortest_match = shortest_common_string(cmd_list);
			if (strlen(shortest_match) == 0) {
				free_string_list(cmd_list);
				break;
			}

			strcpy(command_name, shortest_match);
			cpos = strlen(command_name);

			if (tab_count > 1 || wp != NULL) {
				zero_buffer(bp);
				wp = popup_window(bp->b_bname); /* does nothing if already exists */
				column = 0;

				/* show matched commands, start wrapping from 30 chars from end of screen */
				for (sl = cmd_list; sl != NULL; sl = sl->next) {
					append_string(bp, sl->string);
					append_string(bp, "  ");
					column += (2 + strlen(sl->string));

					if (column >= screen_cols() - 30) {
						append_string(bp, "\n");
						column = 0;
					}
				}
				display(wp, TRUE);
			}
			free_string_list(cmd_list);
			display_prompt_and_response(prompt, command_name);
			screen_refresh();
			break;

		case 0x7f: /* del, erase */
		case 0x08: /* backspace */
			tab_count = 0;
			if (cpos == 0)
				continue;
			command_name[--cpos] = '\0';
			display_prompt_and_response(prompt, command_name);
			break;

		default:
			tab_count = 0;
			if (cpos < STRBUF_M - 1) {
				command_name[cpos++] = ch;
				command_name[cpos] = '\0';
				display_prompt_and_response(prompt, command_name);
			}
			break;
		}
	}

	/* restore to previous window states */
	if (wp != NULL && wp->w_hijack != NULL)
		restore_hijacked_window(wp);
	else if (wp != NULL && count_windows() == 2)
		delete_other_windows();

	/* attempt to execute matched command */
	if (strlen(command_name) > 0) {
		/* a Lisp command of that name wins, as in the keymap */
		if (!call_lisp_event("command", command_name)) {
			funct = name_to_function(command_name);
			if (funct != NULL)
				(funct)();
		}
	}

	mark_all_windows(); /* a lot has gone on, mark every window for update */
}
