# Porting Chezemax to Schemer

The goal: Chezemax runs every script on Schemer, compiled to WebAssembly,
and femtoscheme is deleted. The same compiled program then runs in the
browser. This file lists what femtoscheme does for the editor today
(measured on 1 November 2026, when Chezemax was copied from Schememax), and
the order of the work.

## What there is

| Part | Size | Runs on |
|---|---|---|
| C core (`src/`) | keys, buffers, windows, screen, files, processes | native |
| Scripts (`scheme/`) | 40 files, 9,617 lines | femtoscheme (interpreted) |
| femtoscheme (`femtoscheme/`) | interpreter, garbage collector, boot image | native |
| Schemer (`schemer/`) | self-hosted compiler to WasmGC, run by Wasmtime | Wasmtime |

When Chezemax was copied, Schemer compiled only M-:, C-x C-e, `--eval` and
the commands it could (on first use, about 14 s each, `zz-compiled.scm`);
everything else was interpreted, and compiled code reached the editor's
state by sending text back to femtoscheme (`compiled.c`, `editor_request`).
Since the end of step 4 every script is compiled, by `make`, and the
compiled program runs the editor; femtoscheme runs the scripts only with
`CHEZEMAX_SCHEME=femtoscheme`.

## 1. C calls Scheme: six hooks, and startup

Everything the C core asks of the scripts goes through `src/hooks.c` and
`src/flcall.c`. A Scheme error never unwinds into C: each hook catches it
and the C core carries on.

| When | Procedure called | Arguments | Returns |
|---|---|---|---|
| start-up | `load` of `scheme/init.scm` (it loads every script, then the user's `~/.chezemax`) | | |
| every key, command, click, typed character | `editor-event` | kind, argument (strings) | handled? |
| painting a window | `highlight-buffer-text` | file, text, colours (bytes, filled in), buffer, offset | |
| each mode line | `mode-line-pieces` | name, file, buffer, line, flags, columns | the line |
| every change to a text (undo) | `record-change` | buffer id, kind, offset, text | |
| each visual row of prose | `markdown-wrap-row` | file, text, columns | bytes in the row |
| M-:, C-x C-e, `--eval` | `scheme_eval` | an expression (text) | its value printed |

Six procedures and a text evaluator: this is the whole surface the compiled
program must export.

## 2. Scheme calls C: 182 functions

`src/native.c` gives the scripts 182 C functions; 151 are named in the
scripts (the other 31 are the C core's command names, reached through
`execute-builtin`). Most are `fe-...`: the buffer and its text (insert,
delete, point, mark, region, search), windows, keys and commands, prompts
and messages, colours and the window's fonts, the clipboard; the rest are
files and processes (`directory-files`, `file-contents`, `run-program`,
`spawn-program`, `assistant-request`, `ttfy-request` ...).

They keep their names and become imports of the compiled module. Numbers
pass directly; text passes through the module's linear memory, as the hot
paths in Browsered already do (`%mem-u8`: the highlighter reads the
editor's bytes and writes the colours in place).

## 3. The dialect: what the scripts use that Schemer lacks

| femtoscheme feature | Uses | In Schemer |
|---|---|---|
| strings are UTF-8 bytes: `aref` on strings, `byte-substring`, byte `length`, `string.sub`, `string.find` | 243, 102, ~300, 35, 20 | strings are characters. The editor's text is bytes (offsets are bytes in the C core), so the scripts need byte strings: a byte-string type with the same operations, as `browsered.scm` and the hot paths already adapt |
| `define-macro`: `defcommand` (127 uses), `defvar` (60) | 2 macros | rewrite as `syntax-rules` (Schemer has it, and `syntax-case`) |
| tables: `table`, `put!`, `get`, `has?`, `del!`, `table.keys`, `table.foldl` | ~50 | hashtables, under the same names |
| text buffers: `buffer`, `io.write`, `io.tostring!`, `io.close` | ~30 | string ports |
| globals by name: `top-level-value`, `set-top-level-value!`, `bound?`, `function:name`, `builtin?` | 11, 4, 26, 2, 2 | M-x, key bindings and hooks name procedures by symbol: a registry of named procedures and variables in the compiled program |
| `trycatch` | 3 | `guard` |
| evaluating at run time: `eval`, `eval-string`, `load` | 1, 2, 2 | M-:, C-x C-e, the user's `~/.chezemax` files and C-x C-r need the compiler at run time (`compiler.wasm` in the same Wasmtime) and new modules linked to the editor's globals |
| library procedures | | missing: `sort`, `every`, `filter-map`, `delete-duplicates`, `string-join`, `string-split`, `string-prefix?`, `string-suffix?`, `string-trim`, `list-index`, `random`, `void`, `os.getenv`, `os.setenv`, `path.cwd`, `path.exists?` |

## 4. Compiling takes time

Schemer compiles about 105 lines a second (its own 4,120 lines in 39 s).
The scripts' 9,617 lines would take about a minute and a half: so they are
compiled once, by `make`, into one module. Only the user's own files are
compiled when Chezemax starts (and again on C-x C-r), and kept in a cache
until they change. Making the compiler faster is worth doing later; the
14 s first use of a command today comes from compiling it at that moment.

## Progress

**Strings (decided 1 November 2026): Chez strings, and bytevectors where
bytes matter.** A string is characters, as in Chez; where the C core's
bytes matter (buffer text for highlighters, offsets), scripts use Chez's
bytevectors (`bytevector-u8-ref`, `utf8->string`). The bridge turns strings
into UTF-8 and back at the border.

**Step 3, first part (1 November 2026): the bridge.**

- `compiled/bridge.scm` and `src/bridge.c`: compiled Scheme calls C with
  Chez's own form, `(foreign-procedure "fe-insert" (string) void)`, and C
  calls Scheme's hooks. Arguments and results go through a mailbox in a
  memory both share (integers, strings, bytevectors, lists, booleans);
  errors come back as messages on both sides, and calls may nest.
- The 90 typed C functions of `src/native.c` are reachable from compiled
  Scheme. Both sides of the table are generated by awk from `native.c`
  (`tools/gen-bridge.awk`, `tools/gen-bridge-scheme.awk`), so they cannot
  drift apart.
- `make` builds `chezemax.wasm` from `compiled/` (`tools/build-program.sh`,
  about 40 s). The C core loads it at start-up (`src/compiled-program.c`)
  and gives it every event first; what it does not handle goes on to the
  femtoscheme scripts (`hooks.c`). So scripts can move over one at a time.
  `CHEZEMAX_PROGRAM=file.wasm` loads another program; empty, none.
- Cost: a C call from compiled Scheme about 4 us, a hook from C about 6 us
  (100,000 of each in `tests/bridge-test.c`). Measured on the way: in
  Schemer, variadic calls and `apply` cost about 1 us, `string->utf8` 10 us
  and `utf8->string` 20 us for three letters, `guard` 12 us. The bridge
  avoids them; the prelude should be fixed too (see below).
- `make check-bridge` (part of `make check`): both directions, Unicode,
  3 MB arguments, errors, nesting, speed; then, in the real editor, a key
  bound in compiled Scheme inserting text through the C core. `--eval` now
  has a `*scratch*` buffer, so buffer functions work there.

**Step 3, second part (1 November 2026): hooks, hashtables, strings.**

- Four more hooks, each tried in compiled Scheme first, and left to the
  femtoscheme scripts when it answers `#f` (`compiled/editor.scm`,
  `src/compiled-program.c`, `src/hooks.c`):
  `(compiled-highlighter! predicate procedure)` for colours (the text as a
  bytevector in, a bytevector of faces out),
  `(compiled-mode-line! procedure)` for mode lines (built with
  `mode-line-pieces`), `(compiled-change! procedure)` for undo, and
  `(compiled-wrapper! predicate procedure)` for wrapped rows. C calls only
  the hooks the program has registered, and fetches a hook's text
  (`hook-text`) only when the hook asks for it.
- The evaluation hook waits for the compiler at run time (step 4).
- Hashtables, the symbol table and `string-hash` are now inside Wasm, in
  Schemer's prelude: no table goes through the host any more. Times in
  microseconds, before and after:

  | operation | before | after |
  |---|---|---|
  | `hashtable-ref`, string keys | 86 | 4-6 |
  | `hashtable-ref`, symbol keys | 170 | 2-3 |
  | `hashtable-set!`, existing key | 82 | 2 |
  | `hashtable-contains?` | 170 | 0.7 |
  | `string->utf8`, 100 characters | 62 | 9 |
  | `utf8->string`, 100 bytes | 103 | 6 |
  | `string->symbol` | 17 | 4 |

  Schemer builds itself in 35 s instead of 44 s. `utf8->string` stays safe
  on malformed UTF-8. Chezemax's prelude now differs from the canonical
  Schemer's (and Schememax's and Browsered's); the changes should go to them
  later.
- `make check-bridge` checks each hook both ways (handled here, left to the
  scripts), and that a program registering none is never called.

**Step 3, third part (1 November 2026): the rest of the runtime.** Step 3
is done: what the scripts need from Schemer, and from C, is there and
tested; moving the scripts over is step 4.

- `guard` is now `(%guard thunk handler)` in the prelude: one `%catch`, no
  `call/cc`, `call-with-values` or `apply`. A guard costs about 1.7 us
  without an error (was 24) and 2.7 us with one (was 17). `apply` and
  `call-with-values` lost their extra lists too (apply: 2.0 -> 0.7 us).
- Variadic calls: what is left is the rest list itself. In Wasmtime each
  allocation (a pair, a closure) costs about 0.2 us, so `(f 1 2 3)` with a
  rest list costs about 0.6 us. Only fewer allocations make it cheaper; the
  hot paths avoid rest lists.
- Library procedures in Schemer's prelude (Chez's, SRFI 1's and 13's):
  `sort` (both argument orders), `list-sort`, `vector-sort(!)`, `every`,
  `any`, `find`, `find-tail`, `filter-map`, `fold`, `reduce`, `remove`,
  `delete`, `delete-duplicates`, `partition`, `list-index`, `last`,
  `memp`, `assp`, `remq`, `void`, `random`, the bitwise operations
  (inline on fixnums: new primitives `%fxand`, `%fxior`, `%fxxor`,
  `%fxsra`), `string-prefix?`, `string-suffix?`, `string-search-forward`,
  `string-contains`, `string-index`, the `string-trim`s, `string-join`,
  `string-split`, `bytevector->u8-list` and more.
- Globals by name, as in Chez: `top-level-value`, `set-top-level-value!`,
  `top-level-bound?`, `define-top-level-value`, and `procedure-name`. A
  program that uses them starts by registering its globals (Schemer's
  `link.scm`, `with-registry`); procedures are registered without a setter,
  so they are still called directly.
- `compiled/syntax.scm`: `defcommand` and `defvar` as `syntax-rules`.
  Compiled, `defvar` is `define`: the program is built once.
- `compiled/femtoscheme.scm`: femtoscheme's names on Chez's -- `table`,
  `put!`, `get`, `has?`, `del!`, `table.foldl`, `table.keys`...; `buffer`,
  `io.write`, `io.tostring!`, `io.close`, `file`; `trycatch`;
  `with-bindings` (with `*output-stream*` as the output port); `bound?`,
  `function:name`, `builtin?`. It goes with femtoscheme (step 5).
- `compiled/system.scm` and `src/bridge-more.c`: the 35 C functions of the
  scripts beyond `native.c`'s table -- buffer text in bulk, the command
  and hint tables, files, `run-program`, `spawn-program`, `os.getenv`,
  `path.cwd`..., the highlighters, the assistants. Each is a wrapper
  around the same C as femtoscheme's builtin: that C was taken out of the
  femtoscheme wrappers into plain functions (`src/system.c`, and the
  cores of `highlight.c` and `assistant.c`), so step 5 only deletes the
  wrappers. `make check-bridge` checks them from compiled Scheme, and the
  colours against femtoscheme's builtin.
- `make check-library` (part of `make check`): 50 checks of the prelude's
  new procedures, `guard` and globals by name; 17 of femtoscheme's names
  and the scripts' forms.
- The editor's program (`chezemax.wasm`) does not include the three new
  files yet: they would make start-up 0.45 s slower before any script
  uses them. They join it with the first scripts in step 4, when
  `chezemax.wasm` will also need its machine code saved by `make`, as
  Schememax saves the compiler's (each 100 KB of program takes about
  0.4 s to translate at start-up).

What compiling all the scripts together still reports, for step 4 to
change in the scripts themselves:

- femtoscheme's byte strings: `aref` on strings (243 uses),
  `byte-substring` (102), `length` of a string (part of 307),
  `string.sub` (35), `string.find` (20), `aset!`, `array`;
- femtoscheme's optional parameters, `(define (f a (b default)) ...)`, in
  55 definitions: they become `case-lambda` or rest arguments;
- `eval`, `eval-string`, `load` (M-:, C-x C-e, the user's files): they
  need the compiler at run time, as does the evaluation hook;
- `init.scm`'s loading of the scripts and `zz-compiled.scm` (the legacy
  route to Schemer), which the compiled program replaces.

## Step 4: the scripts, compiled

**How they move (decided 1 November 2026): all together at the end.** A
script ported to Chez Scheme goes to `compiled/scripts/`, in the order
`compiled/scripts/ORDER` gives; femtoscheme keeps running the editor with
`scheme/` until every script is ported, then the editor switches to the
compiled program and `scheme/` goes. Running half of the scripts in each
runtime would need calls, procedures, tables and variables to cross
between the two, a layer that step 5 would delete. Meanwhile a script
exists twice: a change to `scheme/x.scm` must be made in
`compiled/scripts/x.scm` too.

- `make check-scripts` (part of `make check`) compiles the ported scripts
  and evaluates every case of `tests/scripts-cases.scm` twice, in
  femtoscheme with `scheme/` and compiled with `compiled/scripts/`: both
  must give the same values (`tests/run-scripts.sh`).
- `compiled/scripts/pending.scm`: what the ported scripts call in scripts
  not ported yet, failing with "not compiled yet" until they are. When it
  is empty, the switch can be made.
- How a script is ported: Chez strings of characters, with the `byte-`
  procedures of `core.scm` counting UTF-8 bytes where offsets of the
  buffer matter (`buffer-bytes` gives the buffer's text as a bytevector);
  Chez's hashtables for femtoscheme's tables; `case-lambda` for
  femtoscheme's optional parameters, `(define (f a (b 1)) ...)`.

**Step 4, first part (1 November 2026).**

- The editor's program has its machine code made once: `make` writes
  `chezemax.cwasm` beside `chezemax.wasm` (`schemer-compile
  --machine-code`), and the C core loads it instead of translating the
  WebAssembly at every start: 0.30 s instead of 0.86 s to start with the
  program (0.26 s without one). The file holds the fingerprint of the
  WebAssembly it was made from: if they do not match, or this Wasmtime
  cannot load it, the program is translated as before
  (`schemer/native-host.c`, `sc_code_save`, `sc_module_open_code`).
- `core.scm` and `api.scm` ported; 38 cases give the same values as
  femtoscheme's: helpers, bytes of UTF-8, key names, the keymap,
  commands, events, hooks, the kill ring, the buffer, the mark, colours.
  Not yet: `eval-string` (the compiler at run time).
- Found on the way: `builtin-command-names` (api.scm) never ended in
  femtoscheme, since `fe-command-name` gives "" after the last name, not
  #f; fixed in both.

**Step 4, second part (1 November 2026).**

- Ported: `highlight.scm`, `indent.scm`, `undo.scm`, `gui.scm`
  (`compiled/scripts/`). The buffer's text the highlighter, the
  indentation styles and undo scan is a bytevector; the words taken from
  it are strings.
- Compiled as they are, from `scheme/` (they need no change, so they are
  not copied): `theme.scm` and nine language files -- C, Common Lisp,
  Haskell, Lean, ML, Prolog, Ruby, Scheme, VHDL Lisp.
- `make check-scripts`: 107 cases give the same values in both runtimes,
  among them every highlighting and indentation check of
  `tests/run-tests.scm` for these languages, and undo's grouping, joining,
  saving, forgetting and limit.
- Schemer's `write` now writes tabs, returns and other control
  characters as Chez does (`\t`, `\r`, `\x1;`), as femtoscheme does too.
- Still in `scheme/` for the next parts: `defaults.scm`, the languages
  with highlighters of their own (HTML, Markdown, TeX), the modes and the
  extensions.

**Step 4, third part (1 November 2026).**

- Ported: `defaults.scm` (C-x C-e's `sexp-before`, file name completion,
  the dates, the key bindings), and the three languages with highlighters
  of their own: HTML, Markdown (colours, indentation by the language of a
  ``` block, RET continuing lists, TAB levels, word wrap) and TeX. Their
  "text without tags" views wait for `tag-view.scm`, in `pending.scm`.
- `make check-scripts`: 140 cases give the same values in both runtimes,
  among them every check of `tests/run-tests.scm` for HTML, TeX, Markdown,
  word wrapping, the dates and file name completion.
- Each runtime now writes its report to a file: through `--eval`, whose
  answer is cut at 8 KB, a long report would have been compared only in
  part.
- `match-at` compares an ASCII pattern with the text without making its
  bytes first: it runs at every byte of an HTML or TeX highlighter.
- The modes (`python`, `nim`, `load-mode`) go with the extensions: they
  are loaded after the menu library, which they extend.

**Step 4, fourth part (1 November 2026).**

- Ported: six extensions -- `buffer-menu.scm`, `dired.scm`, `grep.scm`,
  `help.scm`, `kill-ring.scm` and `tag-view.scm` (the views without HTML
  tags or LaTeX commands, now complete with `html.scm` and `tex.scm`; the
  view is made of bytes, so its offsets are the buffer's).
- `make check-scripts`: 159 cases give the same values in both runtimes,
  among them the checks of `tests/run-tests.scm` for the tagless views,
  help, the buffer menu and the kill ring, and new ones for dired's
  paths and listing and for grep.
- Found on the way, in both: `\ref{x} 50` lost its space and showed
  `x}` in the view without LaTeX commands (C-c l): the key ran to the
  blanks after the argument. Fixed in `scheme/languages/tex.scm` and its
  port.
- Order matters for the rest: the files are compiled in the order
  `init.scm` loads them, and `shell.scm`, `codex.scm` and the modes call,
  as they load, procedures of `menu.scm` and `assistant.scm`; those come
  first.

**Step 4, fifth part (1 November 2026).**

- Ported: `emacs-keys.scm` (motion by words, sentences, paragraphs and
  expressions, the kills, transposing, case, spaces, comments with M-;,
  filling with M-q, the buffer picker), `menu.scm` (the mode line and its
  buttons) and `read-only.scm` (read-only buffers and vim-mode).
- `make check-scripts`: 200 cases give the same values in both runtimes.
- Schemer's `char-upcase` and `char-downcase` knew only ASCII: M-u turned
  "ação" into "AçãO".  They now map the whole Basic Multilingual Plane as
  the C library does (glibc's tables, kept as runs in the prelude), so the
  compiled scripts change case as femtoscheme does.  The compiler was
  rebuilt to its fixed point.
- Found on the way, in femtoscheme: in a read-only buffer a typed
  non-ASCII character (é) counted as two bytes, was not refused and went
  into the buffer; `r é` asked for a character.  `scheme/extensions/
  read-only.scm` now counts characters.
- In `--eval` the C core gives no events to the scripts, so the kill
  ring does not grow there: the cases check the kills by the clipboard.
  A compiled `car` of an empty list stops the program (a WasmGC trap,
  which `guard` cannot catch) where femtoscheme raises an error: cases must
  not rely on that error.

**Step 4, sixth part (1 November 2026).**

- Ported: the last five extensions -- `assistant.scm` (Claude: the
  context sent, the answer window, C-c y, the discussions, the Messages
  API's JSON), `codex.scm`, `shell.scm` (M-!, C-c m and its TAB
  completion), `sketch.scm` (C-c p: Kaplan-Meier tables, data tables, the
  character sketches) and `ttfy.scm` (C-c f: pipe tables rewritten,
  tables laid out by fixed rules).  `pending.scm` is now empty.
- `make check-scripts`: 229 cases give the same values in both runtimes,
  among them the checks of `tests/run-tests.scm` for JSON, proposed code
  and buffers, the shell, the plots and TTFY.  No case reaches Claude or
  Codex: the cases run `/bin/sh`, `cat` and the parsers.
- The positions the answer and the plot tables share with the buffer
  (fenced blocks in a discussion, the table under the cursor) are bytes,
  as the buffer's; the rest works on characters.  TTFY's table layout
  still counts columns in bytes, as femtoscheme's does.
- The bridge reads a string cut inside a character (a buffer's text
  taken up to a byte limit, as the assistant's context is) as U+FFFD
  instead of reading past its end.
- femtoscheme writes shared values with labels (`#0=`); its side of the
  comparison now writes a fresh copy, so the cases need no workaround.
- Left for step 4: the modes (`load-mode`, `python`, `nim`), `eval` for
  M-: and C-x C-e, and the switch.

**Step 4, last part: the switch (1 November 2026).**

- Ported: the modes -- `load-mode.scm`, `python-mode.scm` and
  `nim-mode.scm` (lexers, indentation, definitions, menus), and `modes.scm`
  (`zz-modes.scm`), which activates Python and Nim.  The bundled modes are
  compiled; a mode of your own in `~/.chezemax/modes/` is loaded by `eval`.
- `make` now compiles every script into `chezemax.wasm`
  (`compiled/scripts/ORDER`, then `compiled/start.scm`), in about three and
  a half minutes, and saves its machine code (`chezemax.cwasm`).  The C core
  loads it at start-up and gives it every hook: keys, commands, clicks,
  colours, mode lines, undo, word wrap and evaluation (a sixth hook,
  `BRIDGE_HOOK_EVAL`).  femtoscheme still starts, but loads no script:
  `scheme/init.scm` is not read.  `CHEZEMAX_SCHEME=femtoscheme` runs the
  scripts there as before (and `legacy` as before, without Schemer's
  M-:); so does a missing or broken `chezemax.wasm`.
- `eval`, `eval-string` and `load` (`compiled/eval.scm`): M-:, C-x C-e,
  C-M-x, M-], `--eval` and the user's own files are not compiled.  Their
  text is read, analysed once into closures and run, inside the program:
  an answer comes at once, with no compiler started, and what it defines
  is a global of the registry like any other, so keys, M-x and the hooks
  find it by name.  The forms are R7RS's (with `syntax-rules`, without
  hygiene), femtoscheme's optional parameters and `define-macro`, and the
  scripts' `defcommand`, `defvar` and `trycatch`.  The library's procedures
  are found by name in `compiled/eval-primitives.scm`, made by `make` from
  the prelude (awk).  This replaces the plan of compiling the user's code
  into modules of its own at run time: such a module cannot share the
  program's procedures and values.
- `compiled/start.scm` does what `scheme/init.scm` did: the user's files
  (`~/.chezemax/languages`, `extensions`, `init.scm`), the undo mode, the
  window's settings; C-x C-r reloads the user's files.
- A trap in the program (a `car` of a number, an index out of range) stops
  the call it happened in, not the editor: the C core says the depth of
  hooks running (`bridge.c`), and at depth 0 the program puts back its
  handlers and output port (`bridge.scm`).  The traps are said briefly
  ("an index out of range").  `eval` checks the syntax of its forms and
  the arguments of `car`, `cdr`, `vector-ref`, `string-ref` and their
  kin, so that a mistake typed in M-: is an error, not a trap.
- `make check-scripts`: 238 cases give the same values in both runtimes,
  among them `eval-string` on 50 expressions and the modes' lexers and
  indentation.  New, `tests/run-editor.sh` (`make check`): `--eval` in the
  compiled program, then Chezemax in a terminal of its own
  (`tests/pty-keys.c`), on a disposable file and a disposable home folder:
  keys typed, a command defined in `~/.chezemax/init.scm`, M-:, C-x C-s and
  C-x C-c.  The tests that load femtoscheme's own files (`run-tests.scm`,
  `compiled.scm`) set `CHEZEMAX_SCHEME=femtoscheme`; the assistants'
  protocol tests (`make check-ui`) now run compiled.
- **After the switch (1 November 2026): `(fib 35)` in M-:.**  It seemed to
  crash the editor: the first `eval` looked every global up in two tables
  at every reference, and the library's `+`, `-` and `<` take any number of
  arguments (a list made at every call), so a call cost some 45 µs and
  `(fib 35)`, 30 million calls, would have taken about twenty minutes, with
  no way to stop it.  Now a reference keeps what it found (a cell, read in
  place, until `eval` defines something), two-argument arithmetic and
  comparisons of the library are done directly, frames are made without
  the library's optional arguments, and a call costs about 1.2 µs:
  `(fib 30)` 1.6 s, `(fib 35)` about 18 s.  `make check-scripts`: 239 cases.  femtoscheme's bytecode does
  `(fib 30)` in 0.07 s: compiled Scheme in Wasmtime pays for every closure
  call and every allocation, and only compiling the user's code would close
  that gap.  `time` is back (`(time expr)`, "Elapsed time: ... seconds"),
  with R7RS's `current-jiffy` (milliseconds) from the C core.  Also found:
  Schemer's `case-lambda` costs about 4 µs a call (it makes a list of the
  arguments and a closure each time); the ported scripts use it, and the
  compiler should dispatch on the count instead.
- **Compiling the scripts: `chezemax --compile-scripts` (1 November 2026).**
  Schemer compiles a whole program at once (it has no linker), so a change
  to one script means compiling them all again.  `make` does it into the
  installation folder; `chezemax --compile-scripts`, or M-x compile-scripts
  in the background, does it into `~/.chezemax/chezemax.wasm` and its
  machine code, from the installed sources (`src/compile-scripts.c`).  The
  files and their order are `compiled/PROGRAM`, which make reads too
  (`tools/program-files.awk`).  Your own code, unrelated to the editor,
  goes in `~/.chezemax/users/` (every `.scm`, subfolders included):
  `--compile-scripts` compiles it with the scripts, after them.  The
  editor uses your program from its next start, unless it is older than
  Chezemax's own (after `make`) or fails to start; then Chezemax's own is
  used, and the message line says why.  A compilation that fails leaves the
  program you had; M-x compile-scripts then opens the log.
- The compiler's own machine code is saved too (`schemer/compiler.cwasm`,
  by make): `schemer-compile` used to translate `compiler.wasm` at every
  run, some 17 s of the 18 a small compilation took; now a small one takes
  0.75 s, and the whole program about three minutes (Schemer itself, some
  65 lines a second).  The compiler's error messages no longer end in a
  WebAssembly backtrace.
- `make check` runs `tests/run-compile-scripts.sh`: code in
  `~/.chezemax/users` compiled and used at the next start, a failed
  compilation reported without changing anything, an old program not used.
- **No interpreter: M-:, C-x C-e, `--eval` and your files compiled
  (2 November 2026).**  The evaluator written for the switch
  (`compiled/eval.scm`, `eval-primitives.scm`) is gone.  Everything you
  evaluate is compiled by Schemer into a program of its own and run at full
  speed (`compiled/eval-compiled.scm`, `src/compiled-eval.c`): `(fib 35)`
  in 0.165 s, where femtoscheme takes about 0.8 s and that evaluator took
  far longer (5.3 s for `(fib 34)`).  Each definition is written once in
  the program, so its calls stay direct: written twice, a name loses them
  and `fib` ran three times slower.
  - The compiler runs in the editor's process, from its saved machine
    code, and is kept between evaluations: its program's value is now a
    procedure that compiles the next request (`compiler-main.scm`), and the
    library is expanded once (`link.scm`, `expanded-library`); a warm
    compilation gives the same bytes as a cold one (all ten fixtures
    compared).  An evaluation now takes about half a second to a second:
    some 0.35 s compiling the program's share of the library, 0.1-0.2 s
    for Wasmtime to translate it, the rest running.  The first in a run
    adds about 0.4 s.
  - The program calls the editor's procedures by name, with data, as text
    (`(insert "Hello")`, answered "ok VALUE"), through a seventh hook,
    `BRIDGE_HOOK_REQUEST`; it reads the editor's variables the same way.
    The answer is decoded by a small decoder in the prelude
    (`%decode-datum`), not by `read`: the reader and `string->number`
    added more than a second of compiling to every program that called
    the editor.
  - Defining or setting one of the editor's names is refused: "insert is
    the editor's: change it in a script"; so is `defcommand` (a procedure
    cannot be given to the editor).  Your files (`~/.chezemax/init.scm`,
    `languages/`, `extensions/`) may set the editor's variables and bind
    keys; they are compiled once and kept in `~/.chezemax/cache` (the
    first start after a change takes a few seconds longer), and loaded
    after the program has started (the event "init", `flcall.c`).  A mode
    of your own (`~/.chezemax/modes`) cannot register its installer, a
    procedure: modes are scripts now.
  - Your definitions make a session for the rest of the editor's run:
    each later evaluation is compiled with them, and a variable that holds
    data keeps its value (M-x scheme-reset forgets them).
  - Found: Schemer's `write` writes `#\tab` as `#\` and a tab; the program
    text avoids it.  To fix in the prelude.
- Left: step 5, deleting femtoscheme.  What still needs it: the
  `CHEZEMAX_SCHEME=femtoscheme` path and its tests (`run-tests.scm`,
  `compiled.scm`, `run-scripts.sh`'s first half), the `--eval` test
  builtins of `compiled-program.c`, and `flcall.c`'s start-up.

## 5. The order of the work

3. **The runtime.** Schemer's prelude gains byte strings, tables, string
   ports, the missing procedures and the registry of named procedures;
   `defcommand` and `defvar` become `syntax-rules`. The native host
   (`schemer/native-host.c`) gives the compiled module the 151 C functions
   as imports and exports the six hooks; the C core calls them instead of
   femtoscheme when Chezemax runs on Schemer. `make` compiles `scheme/`.
4. **The scripts, one file at a time**, each checked by `tests/run-tests.scm`
   (257 tests) running compiled, until all of them run there. Until then
   both runtimes stay, chosen when Chezemax starts.
5. **Delete femtoscheme** (`femtoscheme/`, `flcall.c`, the compatibility
   paths of `zz-compiled.scm`); then the browser version, on the same
   compiled program.

Done when Chezemax starts and edits without loading `femtoscheme.boot` or
linking femtoscheme, and its keyboard, prompt, buffer, file-save, shell
and (mocked) assistant tests pass that way.

**An acceptance check, left on purpose (1 November 2026).** In Schememax the
first C-x s (`save-some-buffers`, a Scheme command) waited about 5 s on the
user's Mac, compiled on first use; C-x C-s, a C command, never did. That was
fixed in Schememax by saving the compiler's machine code and compiling in
the editor's own process. In Chezemax it is left as it was: when the editor's
commands are compiled ahead of time by `make`, the first C-x s in a fresh
session must be instant, with no compilation. Your own code (C-x C-e, M-:,
`~/.chezemax`) is still compiled as you work, so Chezemax will need
Schememax's two remedies too (schemer/native-host.c `sc_code_load`,
src/compiled.c), and then the prelude compiled once instead of per request.
