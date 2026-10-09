# Writing an SBEmacs mode in Nim

`nim_mode.nim` implements Nim coloring and indentation in Nim. Compile it
into a shared library; SBEmacs's existing C renderer calls its Lisp
highlighting callback, which pins the byte arrays and calls the Nim library
through SBCL FFI. Indentation uses the same library. No C core change is needed.
Menus, selection, build/run commands, and definition navigation remain in
`lisp/modes/nim-mode.lisp`.

## Build and use

With Nim installed and on PATH, `make` builds the library automatically.
Alternatively run:

```sh
make nim-mode
make test-nim-native
make
sudo make install
```

Restart SBEmacs, open a `.nim`, `.nims`, or `.nimble` file, and use
`M-x nim-native-status` to see the library path. The installed library lives
beside the editor executable, in `PREFIX/lib/sbemacs`. `make dist` includes
it when built. Without the library, the existing Lisp mode still works.
Nim is required to build the library, but not to use it.

Edit `native/nim-mode/nim_mode.nim` to change the lexer or indentation rules,
run `make nim-mode`, and restart SBEmacs (a loaded library cannot reliably
be replaced in a running process). Set `SBEMACS_NIM_MODE_LIB` before starting
SBEmacs to use a library at another path. In Lisp, setting
`sbemacs::*nim-native-enabled*` to `nil` selects the Lisp fallback.

## C ABI

`nim_mode.h` documents ABI version 1. Three exported `cdecl` functions provide
version checking, highlighting, and indentation. Inputs are UTF-8 bytes,
lengths and positions use C `size_t`, and coloring returns one byte per input
byte using SBEmacs face IDs. The caller supplies and owns the output array.
No Lisp/Nim strings or allocated objects cross this interface. Call on the
editor thread; the library uses ARC and has threads disabled.

The lexer handles nested ordinary/documentation comments, raw and triple
strings, backtick names, numeric suffixes, Unicode identifiers, and definition
names. The indentation engine handles blocks, declaration sections, branch
alignment, bracket continuations, and incomplete strings/comments. It is a
tolerant editing lexer, not the Nim compiler's semantic parser.

The same source builds `.dylib` on macOS, `.so` on Linux, and `.dll` on Windows
with the matching Nim/C toolchain and editor architecture. Windows/Linux
execution has not yet been validated. This change does not alter the GitHub
installer workflow; it needs a Nim installation to include the native library.

Tests compare native coloring with the existing Lisp implementation and use
existing indentation examples as an oracle. `tests/nim-native-abi.c` checks
calls from C, output boundaries and invalid arguments independently of Lisp.
