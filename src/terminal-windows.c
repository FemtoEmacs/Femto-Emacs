/* ConPTY handles the Windows process and UTF-8 VT stream. The editor
 * uses overlapped pipe ends so a blocked shell cannot block redisplay. */
#ifdef __CYGWIN__
#define WIN32_LEAN_AND_MEAN
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0601
#endif
#include <windows.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>
#include <unistd.h>
#include <sys/cygwin.h>
#include "terminal-windows.h"

#ifndef PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE
#define PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE 0x00020016
#endif
#define CHUNK 16384
#define INPUT_LIMIT (16U * 1024U * 1024U)

typedef HRESULT (WINAPI *create_console)(COORD, HANDLE, HANDLE, DWORD, HANDLE *);
typedef HRESULT (WINAPI *resize_console)(HANDLE, COORD);
typedef void (WINAPI *close_console)(HANDLE);
typedef HRESULT (WINAPI *release_console)(HANDLE);

typedef struct {
    HANDLE pipe;
    OVERLAPPED io;
    int pending;
    char bytes[CHUNK];
} channel;

struct windows_terminal {
    HANDLE console, process;
    close_console close;
    resize_console resize;
    int released;
    ULONGLONG exited_at;
    channel input, output;
    char *queue;
    size_t start, queued, capacity;
};

static void close_handle(HANDLE handle)
{
    if (handle && handle != INVALID_HANDLE_VALUE) CloseHandle(handle);
}

static int open_channel(channel *ch, HANDLE *peer, int reading)
{
    static unsigned serial;
    wchar_t name[100];
    swprintf(name, sizeof name / sizeof *name, L"\\\\.\\pipe\\chezweb-%lu-%u",
             (unsigned long)GetCurrentProcessId(), ++serial);
    ch->io.hEvent = CreateEventW(NULL, TRUE, FALSE, NULL);
    if (!ch->io.hEvent) return 0;
    ch->pipe = CreateNamedPipeW(name, (reading ? PIPE_ACCESS_INBOUND : PIPE_ACCESS_OUTBOUND)
                               | FILE_FLAG_OVERLAPPED | FILE_FLAG_FIRST_PIPE_INSTANCE,
                               PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT
                               | PIPE_REJECT_REMOTE_CLIENTS, 1, 65536, 65536, 0, NULL);
    if (ch->pipe == INVALID_HANDLE_VALUE) return 0;
    *peer = CreateFileW(name, reading ? GENERIC_WRITE : GENERIC_READ, 0,
                        NULL, OPEN_EXISTING, 0, NULL);
    if (*peer == INVALID_HANDLE_VALUE) return 0;
    if (ConnectNamedPipe(ch->pipe, &ch->io)) return 1;
    if (GetLastError() == ERROR_PIPE_CONNECTED) return 1;
    if (GetLastError() != ERROR_IO_PENDING) return 0;
    ch->pending = 1;
    return 0;
}

static void close_channel(channel *ch)
{
    if (ch->pending) {
        DWORD bytes;
        CancelIoEx(ch->pipe, &ch->io);
        GetOverlappedResult(ch->pipe, &ch->io, &bytes, TRUE);
    }
    close_handle(ch->pipe);
    close_handle(ch->io.hEvent);
}

void windows_terminal_close(windows_terminal *t)
{
    if (!t) return;
    close_channel(&t->input);
    /* On older Windows, closing the output reader first prevents
     * ClosePseudoConsole from waiting for space in its output pipe. */
    close_channel(&t->output);
    if (t->console) t->close(t->console);
    close_handle(t->process);
    free(t->queue);
    free(t);
}

static COORD dimensions(int rows, int cols)
{
    COORD result = { (SHORT)(cols > SHRT_MAX ? SHRT_MAX : cols),
                     (SHORT)(rows > SHRT_MAX ? SHRT_MAX : rows) };
    return result;
}

const char *windows_terminal_open(windows_terminal **result, int rows, int cols)
{
    HMODULE kernel = GetModuleHandleW(L"kernel32.dll");
    /* Cygwin patches the executable's imported CreateProcessW in a tty.
     * That hook prepares the outer tty for native programs. This child
     * has its own ConPTY, so call the kernel export directly. */
    __typeof__(&CreateProcessW) start_process =
        (__typeof__(&CreateProcessW))GetProcAddress(kernel, "CreateProcessW");
    create_console create = (create_console)GetProcAddress(kernel, "CreatePseudoConsole");
    resize_console resize = (resize_console)GetProcAddress(kernel, "ResizePseudoConsole");
    close_console close = (close_console)GetProcAddress(kernel, "ClosePseudoConsole");
    release_console release = (release_console)GetProcAddress(kernel, "ReleasePseudoConsole");
    STARTUPINFOEXW start = {0};
    PROCESS_INFORMATION child = {0};
    HANDLE input = NULL, output = NULL;
    wchar_t shell[32768], command[32768];
    wchar_t *directory = NULL;
    char *cwd = NULL;
    SIZE_T bytes = 0;
    int attributes_ready = 0;
    const char *failure = "Cannot create the Windows pseudo-terminal";
    windows_terminal *t;

    *result = NULL;
    if (!create || !resize || !close) return "M-x term requires Windows ConPTY (Windows 10 1809 or later)";
    if (!start_process) return "Cannot resolve the native Windows process launcher";
    t = calloc(1, sizeof *t);
    if (!t) return "No memory for a terminal";
    t->close = close;
    t->resize = resize;
    if (!open_channel(&t->input, &input, 0) || !open_channel(&t->output, &output, 1))
        goto cleanup;
    if (FAILED(create(dimensions(rows, cols), input, output, 0, &t->console)))
        goto cleanup;

    failure = "Cannot attach a Windows shell to the pseudo-terminal";
    start.StartupInfo.cb = sizeof start;
    InitializeProcThreadAttributeList(NULL, 1, 0, &bytes);
    start.lpAttributeList = malloc(bytes);
    if (!start.lpAttributeList ||
        !InitializeProcThreadAttributeList(start.lpAttributeList, 1, 0, &bytes))
        goto cleanup;
    attributes_ready = 1;
    if (!UpdateProcThreadAttribute(start.lpAttributeList, 0,
                                   PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE,
                                   t->console, sizeof t->console, NULL, NULL))
        goto cleanup;

    cygwin_internal(CW_SYNC_WINENV);
    DWORD length = GetEnvironmentVariableW(L"ComSpec", shell, 32768);
    if (!length || length >= 32768) {
        length = GetSystemDirectoryW(shell, 32768);
        if (!length || length >= 32768 - 9) goto cleanup;
        wcscat(shell, L"\\cmd.exe");
    }
    if (swprintf(command, 32768, L"\"%ls\"", shell) < 0) goto cleanup;
    cwd = getcwd(NULL, 0);
    if (cwd) {
        ssize_t size = cygwin_conv_path(CCP_POSIX_TO_WIN_W, cwd, NULL, 0);
        if (size > 0) directory = malloc((size_t)size);
        if (directory && cygwin_conv_path(CCP_POSIX_TO_WIN_W, cwd, directory, (size_t)size)) {
            free(directory);
            directory = NULL;
        }
    }
    if (!directory || !start_process(shell, command, NULL, NULL, FALSE,
                                      EXTENDED_STARTUPINFO_PRESENT, NULL, directory,
                                      &start.StartupInfo, &child))
        goto cleanup;
    CloseHandle(child.hThread);
    t->process = child.hProcess;
    if (release) t->released = SUCCEEDED(release(t->console));
    *result = t;
    failure = NULL;

cleanup:
    if (attributes_ready) DeleteProcThreadAttributeList(start.lpAttributeList);
    free(start.lpAttributeList);
    free(directory);
    free(cwd);
    close_handle(input);
    close_handle(output);
    if (failure) windows_terminal_close(t);
    return failure;
}

static void input_consumed(windows_terminal *t, DWORD bytes)
{
    t->queued -= bytes;
    t->start = t->queued ? t->start + bytes : 0;
}

static int flush_input(windows_terminal *t)
{
    channel *ch = &t->input;
    DWORD count;
    if (ch->pending) {
        if (!GetOverlappedResult(ch->pipe, &ch->io, &count, FALSE))
            return GetLastError() == ERROR_IO_INCOMPLETE;
        ch->pending = 0;
        input_consumed(t, count);
    }
    while (t->queued) {
        DWORD size = (DWORD)(t->queued < CHUNK ? t->queued : CHUNK);
        memcpy(ch->bytes, t->queue + t->start, size);
        ResetEvent(ch->io.hEvent);
        if (!WriteFile(ch->pipe, ch->bytes, size, &count, &ch->io)) {
            if (GetLastError() != ERROR_IO_PENDING) return 0;
            ch->pending = 1;
            return 1;
        }
        if (!count) return 0;
        input_consumed(t, count);
    }
    return 1;
}

int windows_terminal_send(windows_terminal *t, const char *data, size_t length)
{
    if (!flush_input(t) || length > INPUT_LIMIT - t->queued) return 0;
    if (t->start + t->queued + length > t->capacity && t->start) {
        memmove(t->queue, t->queue + t->start, t->queued);
        t->start = 0;
    }
    if (t->queued + length > t->capacity) {
        size_t capacity = t->capacity ? t->capacity : CHUNK;
        while (capacity < t->queued + length) capacity *= 2;
        char *queue = realloc(t->queue, capacity);
        if (!queue) return 0;
        t->queue = queue;
        t->capacity = capacity;
    }
    if (length) memcpy(t->queue + t->start + t->queued, data, length);
    t->queued += length;
    return flush_input(t);
}

int windows_terminal_read(windows_terminal *t, char *data, size_t capacity)
{
    channel *ch = &t->output;
    DWORD count;
    flush_input(t);
    if (ch->pending) {
        if (!GetOverlappedResult(ch->pipe, &ch->io, &count, FALSE)) {
            if (GetLastError() != ERROR_IO_INCOMPLETE) {
                ch->pending = 0;
                return -1;
            }
            if (!t->released && WaitForSingleObject(t->process, 0) == WAIT_OBJECT_0) {
                ULONGLONG now = GetTickCount64();
                if (!t->exited_at) t->exited_at = now;
                if (now - t->exited_at >= 150) return -1;
            }
            return 0;
        }
        ch->pending = 0;
    } else {
        DWORD size = (DWORD)(capacity < CHUNK ? capacity : CHUNK);
        ResetEvent(ch->io.hEvent);
        if (!ReadFile(ch->pipe, ch->bytes, size, &count, &ch->io)) {
            if (GetLastError() != ERROR_IO_PENDING) return -1;
            ch->pending = 1;
            return 0;
        }
    }
    if (!count) return -1;
    memcpy(data, ch->bytes, count);
    return (int)count;
}

void windows_terminal_resize(windows_terminal *t, int rows, int cols)
{
    t->resize(t->console, dimensions(rows, cols));
}

int windows_terminal_status(windows_terminal *t, int *status)
{
    DWORD code;
    if (WaitForSingleObject(t->process, 0) != WAIT_OBJECT_0 ||
        !GetExitCodeProcess(t->process, &code)) return 0;
    *status = (int)code;
    return 1;
}
#endif
