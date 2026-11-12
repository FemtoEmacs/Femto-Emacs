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

    /* Cygwin may map the physical bin directory to /usr/bin.
       Find its parent in Windows coordinates before converting the root. */
    wchar_t *filename = wcsrchr(module, L'\\');
    if (!filename)
        return launch_error(L"Cannot locate the Chezweb installation folder.");
    *filename = L'\0';
    wchar_t *bin = wcsrchr(module, L'\\');
    if (!bin || lstrcmpiW(bin, L"\\bin"))
        return launch_error(L"The Chezweb launcher must be in the bin folder.");
    bin[1] = L'\0';

    char *root = cygwin_create_path(CCP_WIN_W_TO_POSIX, module);
    if (!root)
        return launch_error(L"Cannot resolve the Chezweb installation folder.");
    size_t root_length = strlen(root);
    if (root_length && root[root_length - 1] == '/')
        root[root_length - 1] = '\0';

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
    char error[512];
    snprintf(error, sizeof(error), "Cannot start the graphical Chezweb editor.\n%s", strerror(errno));
    MessageBoxA(NULL, error, "Chezweb GUI", MB_OK | MB_ICONERROR);
    return 1;
}
