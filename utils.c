/* util.c, Femto Emacs, Hugh Barney, Public Domain, 2016 */

#include <assert.h>
#include <string.h>
#include "header.h"

/*
 * Take a file name, and fabricate a buffer name.
 */
void mk_buffer_name(char *bname, char *fname)
{
	char *p = fname;

	/* find the end of the filename */
	while (*p != 0)
		++p;

	/* wind back to the last seperator */
	while (p != fname && p[-1] != '/' && p[-1] != '\\')
		--p;

	safe_strncpy(bname, p, NBUFN);
}


/* trim spaces from front and back of a string, returning a new string */
char *string_trim(char *s)
{

	char *p = s;
	
	if (strlen(s) == 0)
		return s;

	/* find first non space */
	while (*p == ' ')
		++p;

	strcpy(temp, p);

	p = temp;
	
	/* find the end of the string */
	while (*p != '\0')
		++p;

	p--; /* step back to char on the end */
	
	/* wind back as long there are spaces on the end */
	while (*p == ' ') {
		*p = '\0';
		--p;
	}

	return temp;
}

/* replace control chars with spaces in string s */
void remove_control_chars(char_t *s)
{
	char_t *p = s;

	while (*p != '\0') {
		if (*p < 32)
			*p = ' ';
		p++;
	}
}

/* a safe version of strncpy that ensure null terminate in case of overflows */
void safe_strncpy(char *dest, char *src, int nchars)
{
	strncpy(dest, src, nchars);
	*(dest + nchars - 1) = '\0';  /* force null termination */
}
