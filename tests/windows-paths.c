/* Windows' filenames in the prompts (16 November 2026): C:\Users\pedro
 * and \\server\share become /c/Users/pedro and //server/share, Cygwin's
 * form, the one the editor's files take on Windows.  Built twice: with
 * CHEZWEB_WINDOWS_PATHS, the conversion (Cygwin does it with its own
 * mounts, and falls back to it); without, nothing changes, since on Linux
 * and the Mac a backslash is a character of a filename. */
#include <assert.h>
#include <stdio.h>
#include <string.h>
extern int file_path_posix(char *, int);
static void is(const char *in, const char *out)
{
 char buf[256];
 snprintf(buf, sizeof buf, "%s", in);
 int changed = file_path_posix(buf, sizeof buf);
 if (strcmp(buf, out)) { fprintf(stderr, "FAIL %s -> %s, not %s\n", in, buf, out); assert(0); }
 assert(changed == !!strcmp(in, out));
}
int main(void)
{
#ifdef CHEZWEB_WINDOWS_PATHS
 is("C:\\Users\\pedro\\doc.md", "/c/Users/pedro/doc.md");
 is("c:/Users/pedro/doc.md", "/c/Users/pedro/doc.md");
 is("D:\\", "/d/");
 is("D:", "/d");
 is("C:\\Users\\", "/c/Users/");
 is("\\\\server\\share\\a b\\x.md", "//server/share/a b/x.md");
 is("notes\\a.md", "notes/a.md");
 is("~\\docs\\x.md", "~/docs/x.md");
 is("/c/Users/pedro/doc.md", "/c/Users/pedro/doc.md");
 is("ação\\coração.md", "ação/coração.md");
 { char small[6] = "C:\\ab"; assert(file_path_posix(small, 5) == 0); }  /* no room: unchanged */
 puts("PASS Windows filenames: drives, network folders, backslashes, ~, UTF-8; Cygwin's own untouched");
#else
 is("C:\\Users\\pedro", "C:\\Users\\pedro");
 is("a\\b", "a\\b");
 puts("PASS outside Windows a backslash stays a character of the filename");
#endif
 return 0;
}
