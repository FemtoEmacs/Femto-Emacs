/* Link this against the compiled Nim library, without Lisp or SBEmacs. */
#include <assert.h>
#include <string.h>
#include "../native/nim-mode/nim_mode.h"
int main(void) {
    const uint8_t source[] = "proc main() =\necho \"你好\"";
    uint8_t faces[sizeof(source) + 2];
    memset(faces, 255, sizeof faces);
    assert(sbemacs_nim_abi() == 1);
    assert(sbemacs_nim_highlight(source, sizeof(source)-1, faces+1) == 0);
    assert(faces[0] == 255 && faces[sizeof(source)] == 255);
    assert(faces[1] == 4 && faces[6] == 11);
    assert(sbemacs_nim_indent(source, sizeof(source)-1, 14, 2) == 2);
    assert(sbemacs_nim_highlight(NULL, 1, faces) < 0);
    assert(sbemacs_nim_highlight(NULL, 0, NULL) == 0);
    assert(sbemacs_nim_indent(source, sizeof(source)-1, sizeof(source), 2) == -2);
    assert(sbemacs_nim_indent(source, sizeof(source)-1, 14, 0) == -2);
    return 0;
}
