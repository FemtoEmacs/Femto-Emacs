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

/*
 * match possible function names
 */
string_list_t *match_functions(const char *fname)
{
	command_t       *fn;
	string_list_t   *head, *sl;
	int		 len;

	len = strlen(fname);
	head = NULL;
	
	for (fn = commands; fn->name != NULL; fn++) {
		if (memcmp(fname, fn->name, len) == 0) {
			if ((sl = malloc(sizeof(*sl))) == NULL) {
				free_string_list(head);
				return (NULL);
			}
			
			sl->string = strdup(fn->name);
			sl->next = head;
			head = sl;
		}
	}
	
	return (head);
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

void apropos_command()
{
	buffer_t *bp;
	command_t *fn;
	keymap_t *ky;
	char bindlist[40];
	char apropos[80];
	
	temp[0] = '\0';
	result = getinput("apropos: ", (char*)temp, NAME_MAX);

	if (temp[0] == '\0' || !result) return;

	bp = find_buffer("*help*", TRUE);
	assert(bp != NULL);
	zero_buffer(bp);

	for (fn = commands; fn->name != NULL; fn++) {
		if (strstr(fn->name, temp) == NULL)
			continue;

		bindlist[0] = '\0';

		for (ky = keymap; ky->key_desc != NULL; ky++) {
			if (strcmp(fn->name, ky->key_desc) == 0) {
				if (bindlist[0] != '\0')
					strcat(bindlist, ", ");

				strcat(bindlist, ky->key_name);

				/* place some limits on the number of keys we will show  */
				if (strlen(bindlist) > 30)
					break;
			}
		}

		sprintf(apropos, "%-30s %s\n", fn->name, bindlist);		
		append_string(bp, apropos);
	}

	(void)popup_window("*help*", FALSE);
}

void list_bindings()
{
	buffer_t *bp;
	keymap_t *ky;
	char binding[80];
	
	bp = find_buffer("*help*", TRUE);
	assert(bp != NULL);
	zero_buffer(bp);

	for (ky = keymap; ky->key_desc != NULL; ky++) {
		sprintf(binding, "%-16s %s\n", ky->key_name, ky->key_desc);		
		append_string(bp, binding);
	}

	(void)popup_window("*help*", FALSE);
}
