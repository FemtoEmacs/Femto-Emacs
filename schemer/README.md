# Native Schemer backend

Schemer is the user's Chez-inspired compiler, vendored on 2026-10-30 and
brought up to date on 2026-10-31 with ~/claude-sandbox/schemer: records
(R6RS, R7RS and Chez forms), libraries (`library`, `define-library`,
import sets), `syntax-case`, and `%mem-u8` for code that reads the
browser editor's memory. It compiles Scheme to WasmGC. The native backend
embeds Wasmtime 50.0.1 through its C API; no Node.js, JavaScript engine or
browser is used.

Schememax and Browsered carry the same Schemer: prelude.scm, expand.scm,
compiler.scm, link.scm, wasm.scm and the helper files are identical, and
so is compiler.wasm, byte for byte (the seed this host builds is the seed
Browsered's builds). Update both together, and compare their md5 sums.

## Self-hosted compiler

`compiler.wasm` contains the compiler, expander, linker and runtime prelude,
compiled by Schemer itself. The standalone C driver `../schemer-compile`
links Wasmtime only. It reads a private request and runs this module; source
being compiled is never executed. Compiler file access is limited to that
request. Arguments go directly to the process without shell interpolation.
The parent caches emitted modules and retains procedure stores until shutdown.

`compiler-support.scm` provides Scheme tables and integer operations needed
by the compiler. `compiler-main.scm` reads a request and emits hexadecimal
module bytes. `wasm.scm` encodes UTF-8, floating-point values and module bytes
using Scheme operations, without old interpreter buffers or native ports.
It emits finalized exception handling (`try_table` and `throw_ref`).

Run `make rebuild-compiler` to rebuild the seed using the current seed.
`make check-selfhost` rebuilds two generations, compares their bytes, checks
that the driver has no old interpreter linkage, and verifies that compilation
does not execute source or accept undefined procedures in strict mode.
The retired interpreter launcher is preserved locally under `bkp/`.

## Editor runtime still in migration

`native-host.c` supplies Unicode strings, file ports, math, decimal printing,
tables and editor callbacks. Text ports preserve embedded NULs. Native
callbacks run synchronously on the editor thread; Asyncify/JSPI is unnecessary.
`browsered.scm` adapts shared globals and editor byte-string lengths.

The editor core still starts FemtoScheme and uses its values, garbage
collector, macros, native ports and higher-order callbacks. Compatible editing
commands and ordinary expressions execute as compiled Scheme. This compiler
migration does not remove the editor interpreter. See `../RUNTIME-MIGRATION.md`.
`SCHEMEMAX_SCHEME=legacy` disables automatic compiled dispatch for diagnosis.
Runtime failures never retry an editing operation in the interpreter.

`make check-compiled` runs ten compiler fixtures and native integration tests.
`make check-ui` checks prompts, search and mocked assistant protocols.
