/* complete.c, SBEmacs (after Femto Emacs, Hugh Barney, Public Domain, 2016) */

#include "header.h"

/*
 * File name completion in the prompts of C-x C-f, C-x i, C-x C-w ...
 *
 * The names are found by Lisp (FILE-NAME-COMPLETIONS, defaults.lisp), with
 * SBCL's own DIRECTORY: no shell is involved, so it works the same on
 * Linux, macOS and Windows (whose cmd.exe would not expand "name*").  C
 * raises the "complete-file" event with what was typed; Lisp answers with
 * fe_set_completions, the names one per line.
 *
 * TAB first fills in what all the names have in common; then each TAB
 * shows the next name.  After a single name (a directory, say), the next
 * TAB looks again, inside it.
 */

static const char *completion_event = "complete-file";
static char *completions = NULL;     /* names separated by '\n', or NULL */

void fe_set_completions(char *names)
{
	size_t n = strlen(names);

	free(completions);
	completions = malloc(n + 1);
	if (completions != NULL)
		memcpy(completions, names, n + 1);
}

static int completion_count(void)
{
	int n = 0;
	char *p;

	if (completions == NULL || completions[0] == '\0') return 0;
	for (n = 1, p = completions; *p; p++)
		if (*p == '\n' && p[1] != '\0') n++;
	return n;
}

/* the Ith name; its length in *LEN */
static const char *completion_nth(int i, size_t *len)
{
	const char *p = completions;

	while (i-- > 0 && p != NULL) {
		p = strchr(p, '\n');
		if (p != NULL) p++;
	}
	if (p == NULL) p = "";
	*len = strcspn(p, "\n");
	return p;
}

/* copy LEN bytes of S into BUF (of NBUF bytes); the new length */
static int set_text(char *buf, int nbuf, const char *s, size_t len)
{
	if ((int) len > nbuf - 1) len = (size_t) (nbuf - 1);
	memcpy(buf, s, len);
	buf[len] = '\0';
	return (int) len;
}

/* the length of the prefix that all the names share */
static size_t common_prefix(int count)
{
	size_t len, best;
	const char *first = completion_nth(0, &best);
	int i;

	for (i = 1; i < count; i++) {
		const char *s = completion_nth(i, &len);
		size_t k = 0;
		while (k < best && k < len && s[k] == first[k]) k++;
		best = k;
	}
	return best;
}

/*
 * TAB in a file-name prompt (lineedit.c calls it): the answer in BUF, LEN
 * bytes; AGAIN when the key before was TAB too.  The new length.
 */
static int complete_name(char *buf, int nbuf, int len, int again)
{
	static int cycle = -1;          /* the next name for TAB, or -1: look for names */
	static int count = 0;
	size_t name_len;
	const char *name;

	if (!again) cycle = -1;
	if (cycle < 0) {
		size_t shared, first_len;
		const char *first;

		buf[len] = '\0';
		free(completions);
		completions = NULL;
		(void) call_lisp_event((char *)completion_event, buf);
		count = completion_count();
		if (count == 0)
			return len;             /* nothing matches */
		first = completion_nth(0, &first_len);
		shared = (count == 1) ? first_len : common_prefix(count);
		if (count == 1 || (int) shared > len) {
			/*
			 * the part all the names share; the next TAB looks
			 * again: at the names, or inside the directory that
			 * was the only one
			 */
			cycle = -1;
			return set_text(buf, nbuf, first, shared);
		}
		cycle = 0;
	}
	name = completion_nth(cycle, &name_len);
	cycle = (cycle + 1) % count;
	return set_text(buf, nbuf, name, name_len);
}

extern int file_prompt_start(char *, int);
extern void file_prompt_accept(const char *);

static int complete_filename(char *prompt, char *buf, int nbuf, int flag)
{

	for (;;) {
		if (!line_edit(prompt, buf, nbuf, flag, complete_name))
			return FALSE;
		flag = F_NONE;              /* again: keep what was typed */
		if (buf[0] == '~' && buf[1] == '/' && getenv("HOME")) {
			size_t home_len = strlen(getenv("HOME"));
			if (home_len + strlen(buf + 1) >= (size_t) nbuf) {
				msg("Expanded filename is too long; shorten the path");
				continue;
			}
			memmove(buf + home_len, buf + 1, strlen(buf + 1) + 1);
			memcpy(buf, getenv("HOME"), home_len);
		}
		file_prompt_accept(buf);
		return TRUE;
	}
}

int getfilename(char *prompt, char *buf, int nbuf)
{
    return complete_filename(prompt, buf, nbuf, file_prompt_start(buf, nbuf) ? F_NONE : F_CLEAR);
}

/* Save As keeps an existing filename editable, with the same completion and
 * path expansion as Open. Unnamed buffers use the usual starting folder. */
int getfilename_default(char *prompt, char *buf, int nbuf)
{
    char full[PATH_MAX], cwd[PATH_MAX];
    const char *home=getenv("HOME"), *path;
    int n;
    if (!buf[0]) return getfilename(prompt,buf,nbuf);
    if (buf[0]=='/' || (buf[0]=='~' && buf[1]=='/'))
        n=snprintf(full,sizeof full,"%s",buf);
    else {
        if (!getcwd(cwd,sizeof cwd)) { msg("Cannot determine the current folder"); return FALSE; }
        n=snprintf(full,sizeof full,"%s/%s",cwd,buf);
    }
    if (n<0 || (size_t)n>=sizeof full) { msg("Filename is too long"); return FALSE; }
    path=full;
    int tilde=home && *home && strcmp(home,"/") &&
        !strncmp(full,home,strlen(home)) && full[strlen(home)]=='/';
    if (tilde) path=full+strlen(home);
    if (strlen(path)+(tilde?1:0)>=(size_t)nbuf) { msg("Filename is too long"); return FALSE; }
    if (tilde) { buf[0]='~'; memcpy(buf+1,path,strlen(path)+1); }
    else memcpy(buf,path,strlen(path)+1);
    return complete_filename(prompt,buf,nbuf,F_NONE);
}

/* Shell text is completed without filename expansion or execution. */
int getcommand(char *buf, int nbuf)
{
    completion_event = "complete-command";
    int accepted = line_edit("Command: ", buf, nbuf, F_CLEAR, complete_name);
    completion_event = "complete-file";
    return accepted;
}
