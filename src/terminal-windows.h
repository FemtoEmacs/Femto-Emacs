#ifndef CHEZWEB_TERMINAL_WINDOWS_H
#define CHEZWEB_TERMINAL_WINDOWS_H
#include <stddef.h>
typedef struct windows_terminal windows_terminal;
const char *windows_terminal_open(windows_terminal **result, int rows, int cols);
int windows_terminal_send(windows_terminal *terminal, const char *data, size_t length);
/* Positive: bytes read. Zero: pending. Negative: session ended. */
int windows_terminal_read(windows_terminal *terminal, char *data, size_t capacity);
void windows_terminal_resize(windows_terminal *terminal, int rows, int cols);
int windows_terminal_status(windows_terminal *terminal, int *status);
void windows_terminal_close(windows_terminal *terminal);
#endif
