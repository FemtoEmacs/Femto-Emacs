/* Exercise the Windows path fallback without consulting Cygwin's mounts. */
#include <assert.h>
#include <stdio.h>
#include <string.h>

extern int windows_path_to_posix(char *, size_t);

static void check(const char *source, const char *expected)
{
    char path[256];
    snprintf(path, sizeof path, "%s", source);
    assert(windows_path_to_posix(path, sizeof path));
    assert(strcmp(path, expected) == 0);
}

int main(void)
{
    check("C:\\Users\\user\\doc.md", "/c/Users/user/doc.md");
    check("D:\\", "/d/");
    check("\\\\server\\share\\a b.md", "//server/share/a b.md");
    check("notes\\a.md", "notes/a.md");
    check("~\\docs\\ação.md", "~/docs/ação.md");
    check("/c/Users/user/doc.md", "/c/Users/user/doc.md");
    puts("PASS Windows path fallback: drives, shares, relative paths and UTF-8");
}
