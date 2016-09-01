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
	/* FIXME might be a problem on windows seperators with this */
	while (p != fname && p[-1] != '/')
		--p;
	
	strncpy(bname, p, STRBUF_S);

	/* truncate if base filename is too long */
	*(bname + STRBUF_S) = '\0';
	debug("bname='%s'\n", bname);
}
