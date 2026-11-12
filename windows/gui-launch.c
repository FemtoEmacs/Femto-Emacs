/* Launch the graphical editor directly from the Windows shortcut. */
#define _GNU_SOURCE
#include <windows.h>
#include <sys/cygwin.h>
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
    size_t root_length = (size_t)(bin - module);
    if (root_length + sizeof(L"\\app\\chezweb-gui.exe") / sizeof(*module) >
        sizeof(module) / sizeof(*module))
        return launch_error(L"The Chezweb installation path is too long.");

    /* Create the folder using the physical Windows path. The installer may
       omit empty directories, and Cygwin can remap a POSIX /tmp. */
    wcscpy(bin, L"\\tmp");
    if (!CreateDirectoryW(module, NULL)) {
        DWORD error = GetLastError();
        DWORD attributes = GetFileAttributesW(module);
        if (error != ERROR_ALREADY_EXISTS || attributes == INVALID_FILE_ATTRIBUTES ||
            !(attributes & FILE_ATTRIBUTE_DIRECTORY)) {
            wchar_t detail[32768];
            swprintf(detail, sizeof(detail) / sizeof(*detail),
                     L"Cannot create the Chezweb temporary folder (Windows error %lu).\n%ls",
                     (unsigned long)error, module);
            return launch_error(detail);
        }
    }
    char *tmp = cygwin_create_path(CCP_WIN_W_TO_POSIX, module);

    wcscpy(bin, L"\\app\\chezweb-gui.exe");
    char *editor = cygwin_create_path(CCP_WIN_W_TO_POSIX, module);
    wcscpy(bin, L"\\app");
    char *app = cygwin_create_path(CCP_WIN_W_TO_POSIX, module);
    wcscpy(bin, L"\\bin");
    char *tools = cygwin_create_path(CCP_WIN_W_TO_POSIX, module);
    const char *profile = getenv("USERPROFILE");
    char *home = profile ? cygwin_create_path(CCP_WIN_A_TO_POSIX, profile) : NULL;
    const char *old_path = getenv("PATH");
    char *path;
    if (!tmp || !editor || !app || !tools || !home ||
        asprintf(&path, "%s:%s%s%s", tools, app,
                 old_path && *old_path ? ":" : "", old_path ? old_path : "") < 0)
        return launch_error(L"Cannot prepare the Chezweb startup paths.");

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
