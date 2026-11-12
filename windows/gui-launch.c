/* Launch the graphical editor directly from the Windows shortcut. */
#define _GNU_SOURCE
#include <windows.h>
#include <sys/cygwin.h>
#include <sys/stat.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <wchar.h>

static int launch_error(const wchar_t *message)
{
    MessageBoxW(NULL, message, L"Chezweb GUI", MB_OK | MB_ICONERROR);
    return 1;
}

int main(int argc, char **argv)
{
    wchar_t module[32768];
    DWORD length = GetModuleFileNameW(NULL, module, sizeof(module) / sizeof(*module));
    if (!length || length >= sizeof(module) / sizeof(*module))
        return launch_error(L"Cannot locate the Chezweb launcher.");

    char *root = cygwin_create_path(CCP_WIN_W_TO_POSIX, module);
    if (!root)
        return launch_error(L"Cannot resolve the Chezweb installation folder.");
    char *filename = strrchr(root, '/');
    if (!filename)
        return launch_error(L"Cannot locate the Chezweb installation folder.");
    *filename = '\0';
    char *bin = strrchr(root, '/');
    if (!bin || strcmp(bin, "/bin"))
        return launch_error(L"The Chezweb launcher must be in the bin folder.");
    *bin = '\0';

    const char *profile = getenv("USERPROFILE");
    char *home = profile ? cygwin_create_path(CCP_WIN_A_TO_POSIX, profile) : NULL;
    const char *old_path = getenv("PATH");
    char *editor, *tmp, *path;
    if (!home ||
        asprintf(&editor, "%s/app/chezweb-gui.exe", root) < 0 ||
        asprintf(&tmp, "%s/tmp", root) < 0 ||
        asprintf(&path, "%s/bin:%s/app%s%s", root, root,
                 old_path && *old_path ? ":" : "", old_path ? old_path : "") < 0)
        return launch_error(L"Cannot prepare the Chezweb startup paths.");

    if (mkdir(tmp, 0700) < 0 && errno != EEXIST)
        return launch_error(L"Cannot create the Chezweb temporary folder.");
    if (setenv("PATH", path, 1) || setenv("HOME", home, 1) ||
        setenv("TMPDIR", tmp, 1) || setenv("TERM", "xterm-256color", 1) ||
        setenv("LANG", "C.UTF-8", 1) || (argc == 1 && chdir(home) < 0))
        return launch_error(L"Cannot prepare the Chezweb startup environment.");

    argv[0] = editor;
    execv(editor, argv);
    return launch_error(L"Cannot start the graphical Chezweb editor.");
}
