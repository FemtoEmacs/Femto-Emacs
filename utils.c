/* util.c, Femto Emacs, Hugh Barney, Public Domain, 2016 */

#include <assert.h>
#include <errno.h>
#include <string.h>
#include "header.h"


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

	safe_strncpy(bname, p, STRBUF_S);
}


/* trim spaces from front and back of a string, returning a new string */
char *string_trim(char *str)
{
    if (!str) {
        errno = EINVAL;
	return NULL;
    }
    char *ptr = str;

    while (*ptr == ' ' || *ptr == '\n' || *ptr == '\t')
        ++ptr;

    str = ptr;
    ptr = strchr (str, '\0') - 1;

    while (*ptr == ' ' || *ptr == '\n' || *ptr == '\t') {
        --ptr;
    }
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
	*(dest + nchars) = '\0';  /* force null termination */
}
