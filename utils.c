/* util.c, Femto Emacs, Hugh Barney, Public Domain, 2016 */

#include <assert.h>
#include <errno.h>
#include <string.h>
#include <ctype.h>
#include "header.h"


#define IS_SPACE(chr) (chr == ' ' || chr == '\n' || chr == '\r'  || chr == '\t')


extern int errno;


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


/*
 * trim spaces from front and back of a string
 * though Femtolisp has a string.trim procedure, I cant get it to work
 * this function is only called by the femtolisp interface to the editor.
 *
 */

char *string_trim(char *str)
{
	if (!str) {
		errno = EINVAL;
		return NULL;
	}

	/* if empty string return the string, it would be fatal to traverse backwards*/
	if (strlen(str) == 0) return str;

	char *ptr = str;

	/* first first none space */
	while (IS_SPACE (*ptr))
		++ptr;

	str = ptr;

	/* find first char before the end NULL terminator */
	ptr = strchr (str, '\0') - 1;

	/* traverse back to first none space */
	while (IS_SPACE (*ptr))
		--ptr;

	*++ptr = '\0';

	return str;
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
