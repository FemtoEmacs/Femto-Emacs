/* Start the bundled Bash without allocating a console for GUI startup. */
#include <windows.h>
#include <wchar.h>

enum { max_command_chars = 32767 };

static int launch_error(const wchar_t *message)
{
    MessageBoxW(NULL, message, L"Chezweb GUI", MB_OK | MB_ICONERROR);
    return 1;
}

/* Skip argv[0] and keep the user's Windows argument quoting intact. */
static const wchar_t *argument_tail(const wchar_t *command)
{
    int quoted = 0;

    while (*command == L' ' || *command == L'\t')
        ++command;
    while (*command) {
        if (*command == L'"')
            quoted = !quoted;
        else if (!quoted && (*command == L' ' || *command == L'\t'))
            break;
        ++command;
    }
    return command;
}

int main(void)
{
    static wchar_t bash[max_command_chars];
    static wchar_t command[max_command_chars];
    static const wchar_t prefix[] =
        L"bash.exe --noprofile --norc /app/start.sh --gui";
    static const wchar_t filename[] = L"bash.exe";
    const wchar_t *tail = argument_tail(GetCommandLineW());
    STARTUPINFOW startup = {0};
    PROCESS_INFORMATION process = {0};
    DWORD length = GetModuleFileNameW(NULL, bash, max_command_chars);

    if (!length || length >= max_command_chars)
        return launch_error(L"Cannot locate the Chezweb launcher.");
    wchar_t *separator = wcsrchr(bash, L'\\');
    if (!separator || (size_t)(separator + 1 - bash) + wcslen(filename) >= max_command_chars)
        return launch_error(L"Cannot locate the bundled Bash.");
    wcscpy(separator + 1, filename);

    if (wcslen(prefix) + wcslen(tail) >= max_command_chars)
        return launch_error(L"The Chezweb command line is too long.");
    wcscpy(command, prefix);
    wcscat(command, tail);

    startup.cb = sizeof(startup);
    if (!CreateProcessW(bash, command, NULL, NULL, FALSE, CREATE_NO_WINDOW,
                        NULL, NULL, &startup, &process))
        return launch_error(L"Cannot start the bundled Bash.");

    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    return 0;
}
