/* Add or remove Chezweb's command directory in the current user's PATH. */
#include <windows.h>
#include <shellapi.h>
#include <stdio.h>
#include <stdlib.h>
#include <wchar.h>

static LSTATUS update_path(const wchar_t *directory, int install)
{
    size_t dir_len = wcslen(directory);
    if (!dir_len || wcschr(directory, L';') || wcschr(directory, L'%'))
        return ERROR_INVALID_NAME;

    HKEY key;
    LSTATUS result = RegCreateKeyExW(HKEY_CURRENT_USER, L"Environment", 0, NULL,
        0, KEY_QUERY_VALUE | KEY_SET_VALUE, NULL, &key, NULL);
    if (result != ERROR_SUCCESS) return result;

    DWORD type = REG_EXPAND_SZ, bytes = 0;
    wchar_t *old_path = NULL, *new_path = NULL;
    result = RegQueryValueExW(key, L"Path", NULL, &type, NULL, &bytes);
    if (result == ERROR_FILE_NOT_FOUND) {
        result = ERROR_SUCCESS;
        if (!install) goto done;
        type = REG_EXPAND_SZ;
        bytes = 0;
    } else if (result != ERROR_SUCCESS) {
        goto done;
    } else if (type != REG_SZ && type != REG_EXPAND_SZ) {
        result = ERROR_INVALID_DATATYPE;
        goto done;
    }

    old_path = calloc(bytes / sizeof(wchar_t) + 2, sizeof(wchar_t));
    new_path = calloc(bytes / sizeof(wchar_t) + dir_len + 3, sizeof(wchar_t));
    if (!old_path || !new_path) {
        result = ERROR_OUTOFMEMORY;
        goto done;
    }
    if (bytes) {
        result = RegQueryValueExW(key, L"Path", NULL, NULL, (BYTE *)old_path, &bytes);
        if (result != ERROR_SUCCESS) goto done;
    }

    size_t used = 0;
    int found = 0, kept = 0;
    const wchar_t *entry = old_path;
    for (;;) {
        size_t len = wcscspn(entry, L";");
        size_t compare_len = len;
        while (compare_len && (entry[compare_len - 1] == L'\\' ||
                               entry[compare_len - 1] == L'/'))
            compare_len--;
        int matches = compare_len == dir_len &&
            CompareStringOrdinal(entry, (int)compare_len, directory, (int)dir_len, TRUE) == CSTR_EQUAL;
        if (matches) found = 1;
        if (!matches || install) {
            if (kept++) new_path[used++] = L';';
            wmemcpy(new_path + used, entry, len);
            used += len;
        }
        if (!entry[len]) break;
        entry += len + 1;
    }

    if (install && !found) {
        if (used) new_path[used++] = L';';
        wmemcpy(new_path + used, directory, dir_len);
        used += dir_len;
    }
    if (install != found) {
        result = RegSetValueExW(key, L"Path", 0, type, (const BYTE *)new_path,
                               (DWORD)((used + 1) * sizeof(wchar_t)));
        if (result == ERROR_SUCCESS)
            SendMessageTimeoutW(HWND_BROADCAST, WM_SETTINGCHANGE, 0,
                (LPARAM)L"Environment", SMTO_ABORTIFHUNG, 1000, NULL);
    }

done:
    free(new_path);
    free(old_path);
    RegCloseKey(key);
    return result;
}

int main(void)
{
    int argc;
    wchar_t **argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    if (!argv) return 1;
    LSTATUS result = ERROR_INVALID_PARAMETER;
    if (argc == 3 && (!wcscmp(argv[1], L"add") || !wcscmp(argv[1], L"remove")))
        result = update_path(argv[2], !wcscmp(argv[1], L"add"));
    LocalFree(argv);
    if (result == ERROR_SUCCESS) return 0;
    fprintf(stderr, "Cannot update the Chezweb command on PATH (Windows error %ld).\n",
            (long)result);
    return 1;
}
