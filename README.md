# Chezweb: native and Chrome editor

Chezweb is the current implementation of **Femto-Emacs**, based on Chezemax.
The original editor remains on the [legacy branch](https://github.com/FemtoEmacs/Femto-Emacs/tree/legacy).
The existing repository, history, stars and fork network are retained.

Edit in a terminal, an optional GUI, or Chrome. Press **C-c d** in the native
editor to open the current buffer in Chrome; the native window stays open
for Codex and Claude. All views use the same editor core and Scheme commands.

```sh
git clone https://github.com/FemtoEmacs/Femto-Emacs.git
cd Femto-Emacs
make
./chezweb
```

The same `make` builds on Intel Macs, Apple Silicon Macs and 64-bit Linux.
On macOS, install Apple's command-line tools with `xcode-select --install`.
On Debian/Ubuntu, install `build-essential libncurses-dev pkg-config curl xz-utils`.
For the optional `./chezweb-gui` interface, install `sdl2 sdl2_ttf` with Homebrew, or
`libsdl2-dev libsdl2-ttf-dev` on Debian/Ubuntu, for the GUI.
`make show-config` shows the selected compiler architecture and libraries.
Wasmtime is downloaded with a pinned checksum for that architecture.

The browser editor is included: `make` installs the bundled WebAssembly files
and builds the local server automatically. No separate browser compiler,
Node.js, Python, or API keys are needed. The same browser bundle runs on macOS
and Linux; its checksums are verified against the editor sources.

Double-click `Chezweb.command` or `Chezweb-GUI.command` on macOS. `make app`
packages `Chezweb.app`, including the browser assets and local server.
Press **C-c d** in either native window to open Chrome. The original native
window stays available for Codex (`C-c g`) and Claude (`C-c r`). Browser AI
commands and Help-menu entries direct you there; the browser has no AI API,
CLI login, shell endpoint, or credentials. On macOS Chrome is opened by name;
on Linux the launcher uses `google-chrome`. Set `CHEZWEB_BROWSER` to a browser
executable path if needed; its only argument is the local session URL.

Grammarly starts **off** every time. The **Grammarly: off** button toggles a real text field over the selected
buffer's canvas rows. Enable it when you want the installed Grammarly
extension to check your text; click again to remove the field. Emacs keys
continue to work. Corrections return to the buffer as undoable changes and
are saved only when you explicitly save. Switching buffers ends the check.

Browser notices have a reserved status row above the canvas; ordinary notices
expire automatically and never cover the buffer. In Chrome, **M-!** opens the
command buffer (Enter adds a line; **C-c s** runs it), and **C-c m** opens a
minibuffer command prompt. Both support Tab completion and share the current
directory. Commands are limited to `ls` (`-a`, `-l`, `-d`), `cd`, `pwd`, and
`help`, using browser storage and folders explicitly granted to Chrome.
Quotes, `;`, and `&&` are supported. External commands, pipes, redirection,
and expansion are rejected. `cd` also updates the starting folder of
`C-x C-f`. The native terminal and SDL windows retain their full system shell.
As in `C-x C-f`, the first TAB at `~/` (`cd ` TAB, `ls ~/` TAB) asks for a
folder when none has been granted yet; TAB on a folder name the browser does
not have yet (`ls ~/papers/` TAB) asks for that folder.
Use **Choose folder** to grant any additional directory and make it current.
You can also type `cd --pick` in the shell minibuffer (`C-c m`), or use
`ls --pick` to list a chosen directory without changing the current one.
Earlier folder grants remain available. Selected folders appear as
`~/<folder-name>/`; different folders with the same name receive suffixes
such as `-2`. Chrome supplies folder handles rather than native parent paths.
An unknown explicit directory path, including an absolute path, asks you to
select that directory before listing or entering it.

No browser command is forwarded to the local server or an AI provider.

**Left to the terminal and SDL windows:** the assistants (C-c r, C-c g,
and C-c y, C-c t on their answers), TTFY (C-c f, [TTFY]), the plots (C-c p)
and M-x compile-scripts. In the browser the assistants' keys and these
commands say so; TTFY and the plots are gone from the mode line, the keys
and the help page, whose header says what the browser does.

**Your settings** are the same in both windows. The browser editor loads
your `~/.chezemax/init.scm` and the `.scm` files of `~/.chezemax/languages`
and `~/.chezemax/extensions`, as the native editor does: the native window's
server reads them, read-only, when the page starts. **C-x C-r** in the
browser fetches them again, so after editing them (in either window) and
saving, C-x C-r loads the new version. As natively, what your files define
is for the editor (keys, settings, commands), not for M-:.

**Your compiled scripts** (`./chezweb --compile-scripts`, which compiles
the editor's scripts with your code in `~/.chezemax/users`) run in the
browser too, chosen as in the terminal: yours when they are not older than
Chezweb's own and they start; otherwise Chezweb's own, and the editor says
why. The server reads `~/.chezemax/chezemax.wasm`, read-only. Compiling
itself stays a terminal or SDL job: restart the browser editor (C-c d again
after closing its tab) to use what you compiled.

The browser initially receives a **snapshot** of the selected buffer,
including unsaved text and its filename. Native and browser cursors are
independent. `C-x C-s` in Chrome sends that snapshot's edited text back to the
native buffer. Return to the native window and press a key to import it;
then `C-x C-s` there saves the original document to disk. Native concurrent
changes are preserved: browser text goes to a new conflict buffer. Repeating
`C-c d` reopens the existing browser session. It does not silently replace an
active browser session with a different buffer. Reloading restores the last
explicit browser save; unsaved browser typing is not persisted.

**C-x C-f** now uses ordinary editable filename prompts and Tab completion
for Chrome-granted folders. On the first Tab at `~/`, or when completing an
unknown `~/folder/...`, choose that folder in Chrome's directory picker. It
then appears as `~/folder/`; Tab completes its filenames and subfolders.
Only immediate directory entries are listed, with contents read when opened.
Within this browser session, later prompts remember the last accepted folder.
Cancelling a prompt or browsing a directory never writes to the computer.
Save and Save As work inside the folders you explicitly granted.

The browser's **Open local file** button also uses Chrome's file picker;
subsequent saves of that picked file write through its granted handle. Files
created only in the browser filesystem are temporary and do not become files
on the computer automatically. Closing the native process stops its server
and removes its private handoff files. Quitting the browser editor with
`C-x C-c` closes its tab after any pending explicit save finishes. The native
window stays open. If Chrome blocks tab closure, the page tells you to close
the tab manually.
There is no continuous background synchronization or automatic disk saving.

`make` builds native executables using C, make, ncurses, and Wasmtime, and
installs the bundled browser editor. The bundled browser files need no extra
compiler or language runtime on the user's machine. The local server binds only to loopback, serves a fixed
asset allowlist, requires a random session token, and checks Host/Origin and
write content types. It can exchange only the session's temporary buffer, and read (never
write) the settings files and the compiled scripts named above.

Developer checks:

```sh
make check check-ui check-selfhost
make check-browser       # development-only Node + playwright; installed Chrome
```

The JSPI build lives in `build/chezweb.js` and `build/chezweb.wasm`, with
`Chezweb.html` at the root. The Scheme program is `chezemax.wasm` (retained
internal filename). The native Wasmtime backend remains separate from
`web/host.c` and `web/runtime.js`, which implement the same module/bridge API
in Chrome. `web/screen.c` adapts Browsered's screen grid; its menus and prompt
logic remain the compiled Scheme implementations. Backups are under `bkp/`.

---

## Inherited Chezemax implementation notes

# Chezemax: an Emacs-inspired editor scripted in Schemer

Chezemax is Schememax's successor (a copy of it, made on 1 November 2026). Its C core owns `main()`, startup, the
event loop and both screen backends (terminal and window); key bindings,
editing commands, indentation, highlighting, undo, menus, help, the shell
window and the assistants are Scheme scripts (`scheme/`).

**The goal: no femtoscheme.** Today Chezemax is still Schememax inside: the scripts
run on femtoscheme, with Schemer (the Chez-inspired compiler to WasmGC,
`schemer/`) compiling some commands and expressions. Chezemax will run every
script on Schemer, compiled ahead of time, with the C core calling it through
Wasmtime; femtoscheme will then be deleted, and the same compiled program
will run in the browser. PORT-TO-SCHEMER.md is the plan and the inventory of
what femtoscheme does for the editor today.

The keys, menus and behaviour follow Schememax and SBEmacs before it.
FEATURE-PARITY.md lists what was ported from SBEmacs.

## Build and launch

```
make
./chezemax paper.md           # terminal
./chezemax --gui paper.md     # window (SDL2), when built
make app                       # macOS application bundle
open Chezemax.app
make check                     # femtoscheme suites and the editor's tests
make check-ui                  # search, assistant protocols, PDF rendering
```

The terminal uses the system curses library; the window uses SDL2 and
SDL2_ttf. The Scheme runtime is bundled source: no Scheme installation or
package manager is needed. `make` builds the window version when its
libraries are found through pkg-config.

Keep the executable beside the `scheme/`, `schemer/`, `runtime/`, `femtoscheme/` and `ttfy/`
folders; `make app` copies them into Chezemax.app.

## Compiled Scheme runtime

Chezemax now executes compatible Scheme through Schemer and the embedded
Wasmtime C API. No Node.js, JavaScript engine or browser is used. `C-x C-e`,
`C-M-x`, `M-:` and `--eval` use the compiler for compatible code. Procedure
definitions persist, so defining `fib` and then evaluating `(time (fib 40))`
runs compiled recursion. Compatible editing commands compile on first use.
`M-x schemer-status` reports compilation and editor-callback counts.

The compiler and old editor dialect are not fully compatible. Legacy macros,
ports, shared mutable objects and higher-order native callbacks retain
compatibility handlers. The compiler itself is self-hosted WasmGC and does
not use the interpreter. The editor core still uses the interpreter; it has
not been removed. `CHEZEMAX_SCHEME=legacy ./chezemax` temporarily
selects the interpreter for comparison or troubleshooting.

The first `make` downloads a checksum-verified Wasmtime 50.0.1 C SDK using
curl and tar (unzip under Windows/MSYS2). `make fetch-wasmtime` downloads it
separately. To build offline, unpack that SDK into `runtime/wasmtime`, or set
`WASMTIME_ROOT`. End users of a packaged editor need no compiler or download.
The Apple Silicon runtime library is about 22.4 MiB; the development SDK also
includes headers and a larger static library. Keep `runtime/wasmtime/lib`
beside the executable; `make app` includes the library, compiled compiler seed and standalone driver.

Wasmtime supplies native SDKs for Linux, macOS and Windows. This integration
was tested on Apple Silicon macOS. The existing editor's terminal, GUI and
process code still needs its platform-specific build support: selecting a
portable Scheme runtime alone does not port that C code to Windows.

`make check` now includes ten compiler fixture suites and native bridge
checks. `make check-ui` verifies search and mock assistant protocols without
contacting live services. `make check-selfhost` verifies byte-identical compiler self-rebuilding without
interpreter linkage. Native backend details are in
[schemer/README.md](schemer/README.md).

## Layout

| Path | Contents |
|---|---|
| `src/` | The C sources: editor core, screen backends (`term.c`, `gui.c`), the femtoscheme bridge (`hooks.c`, `native.c`, `primitives.c`) and the tokenizers (`highlight.c`) |
| `femtoscheme/` | The bundled Scheme, built by its own Makefile |
| `scheme/` | The scripts, in load order: `core`, `api`, `highlight`, `indent`, `theme`, `undo`, `gui`, `languages/`, `defaults`, `extensions/` |
| `scheme/modes/` | The Python and Nim modes and their loader (M-x load-mode) |
| `tests/` | `run-tests.scm` (`make check`) and the C and protocol tests (`make check-ui`) |
| `reference/sbcl-lisp/` | SBEmacs's Lisp scripts, the specification of the port |
| `docs/` | Historical FemtoEmacs documentation |

## Customizing

The editor's scripts are compiled into one program, `chezemax.wasm`, by
`make`. After editing a script (in `compiled/scripts/`), compile them again
with

```
./chezemax --compile-scripts        # or M-x compile-scripts, in the background
```

and restart Chezemax: the compiled program goes to `~/.chezemax/chezemax.wasm`
(nothing in the installation folder is written), and the editor uses it
from its next start. Schemer compiles the whole program at once, so this
takes about three minutes. Code of your own that has nothing to do with the
editor -- a statistics package, say -- goes in `~/.chezemax/users/` (any
`.scm` file, subfolders included): `--compile-scripts` compiles it with the
scripts, and its procedures are there at every start. If a compilation
fails, the program you had stays, and the log says why; if `make` builds a
newer Chezemax, its own program is used until you compile yours again.

Your settings go in `~/.chezemax/init.scm`, loaded at every start, and in
`~/.chezemax/languages/*.scm` and `~/.chezemax/extensions/*.scm`; C-x C-r
loads them again. For example:

```scheme
(global-set-key "C-c d" 'insert-day)       ; Emacs key notation
(set-color 'comment 244)                   ; a face, 0-255 or "#rrggbb"
(set! *fill-column* 78)
(set! *gui-theme* 'light)                  ; or M-x light-theme
(set-gui-font "/Library/Fonts/JetBrainsMono-Regular.ttf" 15)
(define-language "Zig" 'extensions '(".zig") 'line-comment "//"
  'keywords '("fn" "const" "var" "pub" "return"))
```

`CHEZEMAX_NO_INIT=1` skips these files. One that fails to load is reported
on the message line at start-up; the others still load.

## Filename prompts

`C-x C-f` starts with an editable folder path, initially the working folder,
with the home directory abbreviated as `~`. Append a filename or edit/erase
the prefix; TAB still completes names. Accepted file prompts remember their
folder for the session. Cancelling preserves that folder, and changing the
process working directory resets the starting folder to the new directory.
This applies to both the terminal and native GUI.

## Keys

C-h (or F1) shows every key on one page. The highlights:

- **Emacs editing:** words, sentences, paragraphs and expressions (M-f, M-e,
  M-}, C-M-f ...), kills that join in the kill ring (C-k C-k, M-d) with
  C-y/M-y, transposing, case changes, M-q filling, M-; comments.
- **Undo and redo:** C-/ (also C-_, C-x u, C-u) undoes a command at a time;
  C-M-_ or M-_ redoes. Undoing back to the saved text clears the `*`.
- **Indentation:** TAB, RET and electric keys indent C, Lisp, Scheme,
  Python, Nim, Ruby, Haskell, Lean, ML, Prolog, TeX and Markdown; repeated
  TAB cycles through the levels where that makes sense. C-x TAB indents the
  region. In Markdown, RET continues a list and an empty item ends it.
- **Files and buffers:** C-x b (filtered buffer picker), C-x C-b (buffer
  menu), C-x d / C-x C-d (directory browser), C-x C-g and C-x ! (grep),
  C-x s, C-x C-v, TAB completion with `*` and `?` in file prompts.
- **Scheme:** C-x C-e, C-M-x and M-: evaluate; C-x C-r reloads the scripts.
- **HTML and LaTeX:** both are coloured: tags, attributes and values,
  comments, entities, and the text of headings, bold, italics and links;
  LaTeX commands, section titles, math, environment names, emphasis and
  references. C-c TAB hides the HTML tags and C-c l the LaTeX commands:
  the text appears in the same window, read-only and word-wrapped, with
  the cursor where it was; the same key brings back the file, the cursor
  at the same place in the text. M-x html-mode and M-x latex-mode colour
  a file with another extension as HTML or LaTeX.
- **Shell:** M-! (or C-x @) opens a window for a command (Enter: more
  lines); C-c s runs it and shows the output below the command. C-c q (or
  [CLOSE]) closes it and goes back to the file that called it; if there
  were two windows, both stay as they were.
- **Prompts (the minibuffer):** the answer to every prompt (C-x C-w,
  C-x C-f, M-x, M-:, query-replace ...) can be edited anywhere: left and
  right (C-b, C-f), C-left and C-right (M-b, M-f) by words, Home and End
  (C-a, C-e), Backspace and Delete (C-d), C-k to the end, C-u the whole
  answer; typed text goes in at the cursor. TAB completes file and command
  names; C-g cancels.

## Menus

The mouse wheel scrolls the window under the pointer, 3 rows a notch; the
cursor stays where it is while it is visible, and otherwise moves to the
nearest visible row. A click moves the cursor, a drag selects.

Every mode line is a menu the mouse can click:
`file.py, L. 12 [?][SAVE][UNDO][Select][MORE][TTFY]   [QUIT]`. With text
selected, Select becomes COPY and DELETE. A narrow window drops buttons
from the right but keeps [?], [MORE], [TTFY] and [QUIT]. [MORE] lists every action for the
window, including those a narrow window cannot show. The file name is a
button too: it shows the file's lines, words, size and save time. [?] offers
Keybindings, ChatGPT and Claude.

M-x light-theme and M-x dark-theme switch the window's Tomorrow palettes
(blue and yellow cursors). The terminal keeps its own background.

## Assistants

C-c r asks Claude and C-c g asks Codex (ChatGPT). Each offers **h** hints
about the code at the cursor, **q** a question written in a window of its
own (the same key sends it), or **d** a discussion that stays open. C-c y
inserts the code of an answer, after asking; in a discussion, C-c t inserts
the snippet under the cursor. C-c q (or [CLOSE]) closes the assistant's
window and leaves the other windows as they were. Their windows have buttons instead of [?]:
[SEND][TANGLE][CLOSE] in a question or a discussion, [TANGLE][CLOSE] under
an answer; [TANGLE] is C-y's insert (C-c t in a discussion). Besides the
file with the cursor, the assistants are sent every other buffer open in
the editor, by name, so "the answers buffer" means something to them; the
editor's own windows (help, menus, the assistants') are not sent. The
assistants only read: Claude runs with
every tool disabled, Codex in its read-only sandbox, and nothing enters
your file without confirmation (C-/ takes it back).

Neither assistant can open a buffer, but either can propose one: "make
five questions on this paper, put them in a new buffer and paste the paper
below them" gets an answer with a block that opens with
` ```new-buffer NAME `, in which a line `<<FILE>>` stands for the whole
file. C-c y (or C-c t on the block, in a discussion) asks, then makes the
buffer, with your file pasted where `<<FILE>>` was; the assistant never
retypes the paper. C-x C-w saves the new buffer to a file. The assistants
are sent the whole file when it is under 400 KB, so a paper is seen to
its end.

Claude is reached through Claude Code (`claude -p`, your usual login) or,
without it, the Messages API with ANTHROPIC_API_KEY or
`~/.chezemax/anthropic-api-key`. Codex is found on the PATH, in
`~/.local/bin` or in the ChatGPT app. `CHEZEMAX_CLAUDE` and
`CHEZEMAX_CODEX` choose other executables.

## Textify a PDF for an AI that accepts only text

Click [TTFY] on the mode line (or press C-c f), then **1 Textify with ChatGPT** or
**2 Textify with Claude**. The PDF prompt has the same TAB completion as
C-x C-f. Choose `all` pages, a page such as `4`, or a range such as `3-5`;
C-g cancels.

The chosen CLI receives the selected pages and `ttfy/plots-guidelines.md`.
On macOS, the C bridge renders 144-dpi page PNGs through Quartz/ImageIO; no
Python, OCR library or Poppler installation is needed. Codex receives image
attachments in its read-only sandbox; Claude gets only the Read tool, for
these page images. The Markdown appears in a new `*ttfy-N.md*` buffer; C-x
C-w saves it. Failures are shown in a window below; logs and rendered pages
stay in private `/tmp/chezemax-ttfy-*` folders. Ranges are limited to 32
pages per conversion. Native rendering is implemented on macOS only.

`make check-ui` exercises rendering, both provider protocols, page selection
and failures with offline test providers. It expects the seven-page fixture
`ttfy/benedetto.pdf`.

### Plots back from their tables: C-c p

A textified paper carries each Kaplan-Meier figure as an `(estimator-plot ...)`
table. Put the cursor on a table, or anywhere inside it, and press C-c p
(M-x plot-at-point): `irene-dixe`, a small SDL program built by `make`,
opens a window with the curves redrawn from the table, in the legend's
colours, with censor marks, the unresolved intervals shaded, the numbers at
risk under the axis and the printed statistics beside it. In that window s
saves the picture as a PNG beside the Markdown file (`paper-plot-1.png`),
q closes it. M-x plot-save writes the same picture without opening a
window, and the editor checks that the file is there before saying
"Saved". Without a display, or without irene-dixe, a character sketch
opens in `*plot*`.

A printed table, `(data-table ...)`, opens the same way: C-c p shows it in
irene-dixe's window as a table, with its caption, a ruled header, indented
subcategories, bold group rows, banded lines and the notes under it. The
cells are shown as printed: `(:count 2839 :percent 76.4)` is "2839 (76.4)",
`(:value 133 :ci (122 154))` is "133 (122–154)", `(:< 0.001)` is "<0.001".
Arrows, the wheel and PgUp/PgDn scroll a large table; s saves the whole
table as a PNG. Without a display it opens in `*plot*` as aligned text.

The table is read as data and never evaluated; a table with `#` outside
strings is refused, because the reader's `#.` would run code. Levels that
do not join (a drop starting away from the current level) are listed under
the legend for review, not repaired. `irene-dixe --render TABLE OUT.png`
draws without a window. Sketches of diagnostic images will use C-c p too.

Curves recorded as sampled landmarks (`:landmark` rows) are drawn as dots
joined by dotted lines: the table does not say what the curve does between
them.

## Read-only and vim mode

M-x read-only (or C-x C-q) makes the buffer read-only and turns the keys
into nvim's normal-mode motions: h j k l (and the arrows), w b e, 0 ^ $,
gg G (G: the end of the text; 42G: line 42), Enter, C-d C-u, / ? n N,
% (the matching paren); yy and y{motion} copy, v selects (then y copies).
What is copied also goes to the system clipboard, so Cmd-V (Ctrl-V)
pastes it in other programs. Nothing can change the buffer, neither a key
nor a script.

M-x vim-mode adds the keys that edit: dd and d{motion} (dw, d$, dgg), x,
p and P, u and C-r, v ... d, o and O; . repeats the last change, J joins
lines, r{char} replaces a character, and :w saves (:wq or :x save and
quit, :q quits, :42 goes to line 42). A count repeats (3dd, 5j, 3.).

In both modes i returns to Emacs; the mode line shows `%%` and READ,
NORMAL or VISUAL. C-g cancels a count, an operator or a selection. The
help page (C-h) lists the keys; it is read-only itself, so the same
motion keys move on it, and i (or [CLOSE]) closes it.

## Search

C-s searches forward and C-r backward as you type; repeat them for the
next or previous match. Enter accepts; C-g cancels and returns. M-%
replaces, asking each time. Search is literal and case-sensitive.

`C-x C-w` (Save As) prefills the full current filename as an editable
path, abbreviating home as `~`, and TAB completes directories and filenames.
For unnamed buffers it starts at the normal remembered folder. Cancelling
preserves the current filename and does not save a file.

Shell commands in the `M-!` / `C-x @` window now support Tab completion
at the cursor, preserving any command text after it. Tab expands a common
prefix and repeated Tab cycles through ambiguous matches; paths with spaces
and Unicode are supported. `C-c m` opens a one-line minibuffer command with
Tab completion, Enter to run and `C-g` to cancel. Completion never executes
the command. Native Chezemax and the local Browsered launcher continue to
run the full system shell.

## Rebuilding the browser bundle (maintainers only)

Users run ordinary `make`; it never invokes a browser compiler. When changing
the editor sources, maintainers with Emscripten/JSPI installed run
`make browser-rebuild`. This builds the portable browser program, updates
`web/prebuilt/chezweb.js` and `web/prebuilt/chezweb.wasm`, and records the
asset/source checksums in `web/prebuilt/SHA256SUMS`. Commit those files with
the source change. `make check-browser-assets` catches missing, stale or
corrupted bundles. Emscripten 6.0.13 is the tested maintainer toolchain.
