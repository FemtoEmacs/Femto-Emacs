#ifndef SBEMACS_NIM_MODE_H
#define SBEMACS_NIM_MODE_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
/* ABI 1: caller owns all buffers. Functions retain no pointers.
 * highlight: 0 success, negative error; output must have length bytes.
 * indent: column >= 0, -1 means preserve (inside unfinished string/comment),
 * -2 means invalid arguments or failure. line is a UTF-8 byte offset.
 * Call on the editor thread; this build has threads disabled.
 * Loading the shared library initializes its Nim runtime automatically. */
int sbemacs_nim_abi(void);
int sbemacs_nim_highlight(const uint8_t *text, size_t length, uint8_t *colors);
int sbemacs_nim_indent(const uint8_t *text, size_t length, size_t line, int width);
#ifdef __cplusplus
}
#endif
#endif
