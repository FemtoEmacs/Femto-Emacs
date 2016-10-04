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

void apropos_command()
{
	buffer_t	*bp;
	command_t       *fn;

	temp[0] = '\0';
	result = getinput("apropos: ", (char*)temp, NAME_MAX);

	if (temp[0] == '\0' || !result) return;

	bp = find_buffer("*help*", TRUE);
	assert(bp != NULL);
	zero_buffer(bp);

	for (fn = commands; fn->name != NULL; fn++) {
		if (strstr(fn->name, temp) == NULL)
			continue;
		append_string(bp, fn->name);
		append_string(bp, "\n");
	}

	delete_other_windows();
	split_window();
	select_buffer("*help*");
}
