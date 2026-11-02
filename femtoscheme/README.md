# femtoscheme

A small, fast Scheme: a subset of R7RS-small built on Jeff Bezanson's
[femtolisp](https://github.com/JeffBezanson/femtolisp). It keeps femtolisp's
bytecode compiler and VM, compacting GC, proper tail calls and tiny size, and
changes the surface language to Scheme. It runs natively and in the browser,
compiled to WebAssembly, where Browsered uses it as its scripting language.

## What changed from femtolisp

Syntax:

- `[` `]` are parentheses, as in R6RS and common R7RS practice;
  vectors are written `#(1 2 3)` and print that way.
- `#true` `#false`, `#u8(1 2 3)` bytevectors, `#e`/`#i` exactness prefixes.
- R7RS character names (`#\space`, `#\null`, `#\escape`, ...), and printable
  Unicode characters print as themselves (`#\λ`), independent of the C locale.
- R7RS string escapes `\x3bb;`. Strings that are not valid UTF-8 print bytes as
  three-digit octal escapes (`\204`), so printed data always reads back.
- `read` no longer reports end of file when the input ends right after an atom.

Library (`r7rs.scm`, part of the boot image):

- `define-syntax`, `let-syntax`, `letrec-syntax` and `syntax-rules` with
  literals, `_`, nested ellipses, tail patterns after an ellipsis, vectors,
  custom ellipsis and `(... ...)`; internal `define-syntax` in bodies.
- `call/cc`, `dynamic-wind`, `values`, `call-with-values`, `let-values`,
  `let*-values`, `define-values`, `case-lambda`, `parameterize`,
  `make-parameter`, `delay`, `delay-force`, `make-promise`, `force`,
  `case` with `=>`, `letrec*`.
- `guard`, `raise`, `raise-continuable`, `with-exception-handler`, `error`,
  `error-object?`, `error-object-message`, `error-object-irritants`.
- Numbers: `exact`, `inexact`, `floor`, `ceiling`, `round` (to even),
  `truncate`, `floor/`, `truncate/`, `quotient`, `remainder`, `modulo`, `gcd`,
  `lcm`, `expt`, `exact-integer-sqrt`, `square`, two-argument `atan` and `log`.
- Characters, strings (indexed by character, not byte), symbols, lists,
  vectors, bytevectors and string ports with their R7RS names, plus a few
  SRFI-1 and SRFI-13 conveniences (`fold`, `filter-map`, `string-contains`,
  `string-split`, `string-join`, `sort`, ...).

femtolisp's own names (`aref`, `string.sub`, `io.write`, `trycatch`,
`define-macro`, optional arguments as `(lambda ((x 0)) ...)`) still work.

## Differences from R7RS-small

- `syntax-rules` is not fully hygienic. Identifiers that a template binds
  (`lambda`, `let`, `let*`, `letrec`, `letrec*`, named `let`, `do`) are renamed
  at each expansion, which prevents the usual capture bugs (`swap!` with a
  variable named `tmp`, for instance). Free identifiers in a template refer to
  what is visible where the macro is used.
- `call/cc` captures escaping continuations: early exits, loops and error
  handling work; re-entering a continuation after its extent has ended reports
  an error.
- There are no exact rationals: `(/ 1 2)` is `0.5`. Integers are exact.
- Strings are immutable UTF-8: `string-set!`, `string-fill!` and
  `string-copy!` signal an error.
- There is no `define-library` or `import`.

## Build and test

```sh
make                  # builds ./femtoscheme and runs both test suites
./femtoscheme         # REPL
./femtoscheme file.scm
sh bootstrap.sh       # rebuild femtoscheme.boot after changing system.scm,
                      # compiler.scm or r7rs.scm
wasm/build.sh         # WebAssembly build (needs Emscripten: brew install emscripten)
```

`tests/unittest.scm` is femtolisp's suite; `tests/r7rs-test.scm` checks the
Scheme layer. In WebAssembly, `wasm/fsweb.c` exports `fs_start` and
`fs_eval`, and Scheme reaches the page through one primitive, `%host`.

## Files

| File | Contents |
|---|---|
| `flisp.c`, `read.c`, `print.c`, ... | the interpreter, in C |
| `system.scm` | core library and macro expander |
| `compiler.scm` | bytecode compiler |
| `r7rs.scm` | the R7RS layer |
| `femtoscheme.boot` | compiled image of the three files above |
| `llt/` | femtolisp's portable C support library |
| `wasm/` | WebAssembly entry points and build script |

femtolisp is Copyright (c) 2008 Jeff Bezanson, under the BSD license in
`LICENSE`; the same license covers the changes made for femtoscheme.
