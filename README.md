# SBEmacs

A tiny Emacs for the terminal or a window, configured and extended in
Common Lisp.

SBEmacs is [FemtoEmacs](https://github.com/FemtoEmacs/Femto-Emacs) with its
2016 Lisp, femtolisp, replaced by [SBCL](https://www.sbcl.org/).
The editor core (buffers, windows, undo, search, display) is still the small
C program derived from Atto Emacs and Anthony Howe's editor; it draws either
in a terminal (ncurses) or in its own window (SDL2).
Everything that used to be written in femtolisp is now Common Lisp compiled
by SBCL: key bindings, the startup screen, the buffer menu, the kill ring,
dired, grep, and the syntax highlighter.

```
  ┌────────────────────────────────┐        ┌────────────────────────────────┐
  │ SBCL process (sbemacs)         │  FFI   │ libsbemacs-term  or  -gui      │
  │                                │ -----> │                                │
  │ init file, key bindings,       │ fe_*   │ editor core: gap buffers,      │
  │ highlighting, indentation,     │        │ windows, undo, search, keys    │
  │ theme, buffer menu, kill       │ <----- │ ---------- screen.h ---------- │
  │ ring, dired, grep, Esc-;       │ hooks  │ term.c (ncurses) | gui.c (SDL2)│
  └────────────────────────────────┘        └────────────────────────────────┘
```

SBCL is the host process.  It loads one of two C libraries with `sb-alien`
(part of SBCL, no Quicklisp needed), registers three callbacks (evaluate,
events such as keys, and highlight), and calls `fe_main`.  The two libraries
contain the same editor core and export the same functions; they differ only
in the back end behind `src/screen.h`: `libsbemacs-term` draws with ncurses,
`libsbemacs-gui` opens a window with SDL2.  So a terminal-only user never
needs SDL2, and everything written in Lisp works the same in both.

## Requirements

### Windows users

Download `Femto-Emacs-2.0-Windows-x86_64-Setup.exe` from the latest
[release](../../releases), double-click it, and follow the installer.  The
installer creates a normal Start-menu shortcut and can create a desktop
shortcut.  It includes the editor, its SBCL runtime, both the terminal and
graphical libraries, SDL2, SDL2_ttf, and their runtime libraries.  It does not
require MSYS2, a C compiler, `make`, SBCL, or administrator privileges.
The Windows release is built and checked with SBCL 2.6.9.

The installer shortcut starts the SDL2 window.  The terminal interface remains
available by running `sbemacs.exe` without `--gui` in a terminal.

### Building from source

* [SBCL](https://www.sbcl.org/platform-table.html) 2.1 or newer
* a C compiler and `make`
* ncurses with wide-character support (`libncursesw`)
* for the window: [SDL2](https://www.libsdl.org/) and SDL2_ttf (optional;
  without them only the terminal version is built)

| System  | Install the prerequisites |
|---------|---------------------------|
| Debian / Ubuntu | `sudo apt install sbcl build-essential libncurses-dev libsdl2-dev libsdl2-ttf-dev` |
| Fedora  | `sudo dnf install sbcl gcc make ncurses-devel SDL2-devel SDL2_ttf-devel` |
| macOS   | `xcode-select --install` and `brew install sbcl sdl2 sdl2_ttf pkg-config` (the system ncurses is used) |
| Windows | SBCL from sbcl.org, plus [MSYS2](https://www.msys2.org/) with `pacman -S make mingw-w64-x86_64-gcc mingw-w64-x86_64-ncurses mingw-w64-x86_64-pkgconf mingw-w64-x86_64-SDL2 mingw-w64-x86_64-SDL2_ttf` |

## Building

```sh
make            # builds libsbemacs-term, libsbemacs-gui (.so, .dylib, .dll)
                # and the sbemacs executable
make test       # runs the Lisp test suite (no terminal needed)
./sbemacs file.c          # in the terminal
./sbemacs --gui file.c    # in a window
sudo make install        # into /usr/local; PREFIX=... to change
sudo make uninstall
```

These requirements apply to developers who rebuild the native code.  On
Windows run `make` from the *MSYS2 MINGW64* shell, with SBCL on the `PATH`.
Ordinary Windows users should use the installer above and do not need MSYS2.

`sbemacs` is a saved SBCL image.  It finds the libraries next to itself
(or set `SBEMACS_LIB` / `SBEMACS_GUI_LIB` to their full paths), so keep the
files together.  `make install` also creates `sbemacs-gui`, which opens the
window without `--gui`.

Only changes to the C code (`src/`) or to the Lisp engine need `make`.
Everything else in `lisp/` is a *script*: see [Scripts](#scripts-no-rebuild-needed).

Pre-built archives for Linux, macOS and Windows are attached to each
[release](../../releases).

## Using it

```
sbemacs [--gui] [-q] [file] [+]
  --gui, -g  open a window (also when started as sbemacs-gui)
  -q         skip the init file
  +          enable the mouse in the terminal
```

The usual Emacs keys work: `C-x C-f` find file, `C-x C-s` save, `C-x C-c` quit,
`C-s`/`C-r` search, `Esc-r` query replace, `C-space` set mark, `C-w` kill
region, `C-y` yank, `C-u` undo, `C-x 2` split window, `C-x o` other window.
`Esc-l` lists every binding and `Esc-x` runs a command by name.

On macOS, tick *Use Option as Meta key* in Terminal → Settings → Profiles →
Keyboard so that the Option key works as `Esc`.

### The window (`sbemacs --gui`)

The same editor, keys, Lisp and scripts, drawn with SDL2 in a window of its
own: 24-bit colours, a proper font, the mouse and the system clipboard.

* **Mouse:** click to move the cursor (in any window), the wheel scrolls,
  the middle button pastes.
* **Clipboard:** `Esc-w` / `C-w` also copy to the system clipboard;
  `Shift-Insert` pastes from it.  On a Mac, `Cmd-C`, `Cmd-X`, `Cmd-V`,
  `Cmd-Z`, `Cmd-S` and `Cmd-Q` work as usual.
* **Font size:** `Ctrl-+` / `Ctrl--` (`Cmd-+` / `Cmd--` on a Mac).
* **Meta:** Alt (Option on a Mac) works as `Esc`.  Set `*option-is-meta*`
  to `nil` to type accents with Option instead.
* **Look:** `*gui-theme*` is `:dark` or `:light` (in
  [`lisp/theme.lisp`](lisp/theme.lisp)); `set-gui-font` picks any TrueType
  or OpenType file.  By default the first installed of JetBrains Mono, Fira
  Code, Cascadia, Source Code Pro, Menlo, Consolas, DejaVu Sans Mono, ... is
  used ([`lisp/gui.lisp`](lisp/gui.lisp)).

```lisp
;; ~/.sbemacs/init.lisp
(set-gui-font "/Users/me/Library/Fonts/JetBrainsMono-Regular.ttf" 15)
(setf *gui-theme* :light)
(set-color :keyword "#cc6666" :default :bold)   ; "#rrggbb" works everywhere
```

If no window can be opened (no display, e.g. over SSH), `sbemacs --gui`
says so and runs in the terminal.

### The assistant: Claude inside the editor (`C-c r`)

| Key | |
|-----|-|
| `C-c r` | ask Claude about the code at the cursor; press RET at the prompt for hints, or type a question.  The answer opens in a window below (`C-x 1` closes it) |
| `C-c y` | insert the code Claude proposed at the cursor, after you confirm; `C-u` undoes it |
| `C-c x` | the same for Codex (a stub for now: [`lisp/extensions/codex.lisp`](lisp/extensions/codex.lisp)) |

The keys follow Asimov's Three Laws of Robotics; `r` is the "R." of his
robots' names (R. Daneel Olivaw).

1. **No harm:** the assistant never changes your text by itself.  It sees
   only what `C-c r` sends: the file name, its language and the text
   around the cursor (and the region, if any).  The Claude Code CLI runs
   with all tools disabled, so it cannot read or write your files.
2. **Obedience:** `C-c y` types into the buffer only on your order, asks
   first, and can be undone.
3. **Self-preservation:** a missing program, a network error or a timeout
   ends in a message, never in a crash or a lost buffer.

Claude is reached in one of two ways (`*claude-transport*`):

* `:cli`: the [Claude Code](https://claude.com/claude-code) program,
  `claude -p`, with your usual login.  A Claude subscription works; no API
  key is needed.
* `:api`: the Messages API through `curl`, with `ANTHROPIC_API_KEY` or the
  first line of `~/.sbemacs/anthropic-api-key`.  The key is passed to curl
  on its standard input, never on the command line.
* `:auto` (the default): `:cli` when `claude` is installed, `:api` otherwise.

If Claude cannot be reached, the window below says why and how to fix it;
`Esc-;` `(assistant-status)` shows the same check at any time.  The usual
fix is to install Claude Code and log in once in a terminal
(`curl -fsSL https://claude.ai/install.sh | bash`, then `claude`).

`*claude-model*` picks the model (`"sonnet"`, `"opus"`, or a full model
name), `*assistant-timeout*` how long to wait, and `*assistant-instructions*`
what the assistant is told.  The editor waits while the assistant thinks;
the message line says so.  All of it is the script
[`lisp/extensions/assistant.lisp`](lisp/extensions/assistant.lisp): change
it and press `C-x C-r`.

### Lisp interaction

* `C-x C-e` evaluates the expression just before the cursor and shows its
  value on the message line, as in GNU Emacs.
* `Esc-;` reads a Lisp expression on the message line and shows the result.
  Long results open the `*lisp_output*` buffer.
* `Esc-]` evaluates the parenthesised block at the cursor (or the one just
  behind it) and inserts the result below it.

Both evaluate in the `SBEMACS-USER` package, so `(insert "hi")`,
`(defun ...)` and any Common Lisp work.  Errors are reported on the message
line; they never take the editor down.

### Extensions that come with it

| Key       | Command | |
|-----------|---------|-|
| `C-x C-b` | `buffer-menu` | pick a buffer: `1` one window, `2` split, `s` save, `k` kill, `x` exit |
| `C-x C-d` | `dired` | browse directories: `f`/RET open, `u` up, `g` refresh, `x` exit |
| `C-x C-g` | `grep-command` | search files (case-insensitive), results in `*grep*` |
| `C-x !`   | `next-grep` | visit the next grep match |
| `C-c k`   | `kill-ring-menu` | choose an earlier kill, `c` copies it to the clipboard |
| `C-c i`   | `insert-kill-ring` | insert the whole kill ring |
| `C-x C-u` / `C-x C-l` | `upcase-region` / `downcase-region` | |
| `C-c a` `C-c b` `C-c c` | `html-p` `html-h1` `html-pp` | HTML helpers |
| `C-c z`   | `insert-day` | turns a region `(2016 9 3)` into `Saturday` |
| `C-t` / `C-o` | `indent-two` / `deindent-two` | |
| `C-x C-r` | `reload-scripts` | reload edited Lisp scripts (see below) |
| `TAB` | `indent-line` | indent the line for its language (see [Indentation](#indentation)) |
| `RET` | `newline-and-indent` | new line, already indented |
| `C-x C-i` | `indent-region` | indent the lines between mark and cursor |

dired and grep are written in portable Common Lisp, so they behave the same
on every platform.

## Scripts: no rebuild needed

The executable holds only the Lisp engine (`package`, `ffi`, `loader`,
`core`).  The rest of `lisp/` consists of scripts, loaded in this order:

| Script | |
|--------|-|
| `highlight.lisp` | the tokenizer and `define-language` |
| `indent.lisp` | automatic indentation and `define-indentation` |
| `theme.lisp` | the colour theme |
| `languages/*.lisp` | one file per language: colours and indentation |
| `defaults.lisp` | the commands and key bindings that used to be `init.lsp` |
| `extensions/*.lisp` | buffer menu, kill ring, dired, grep |
| `~/.sbemacs/languages/*.lisp`, `~/.sbemacs/extensions/*.lisp` | your own |
| `~/.sbemacs/init.lisp` | your settings, last |

Edit a script and restart, or press **`C-x C-r`** (`reload-scripts`) inside
the editor: every script whose contents changed is loaded again, and the
screen is redrawn with the new colours.  A new file in `languages/` or
`extensions/` is picked up the same way.  Errors are shown on the message
line and leave the previous definitions in place.

How it works: `make` also compiles the scripts into the executable,
remembering their contents, so `sbemacs` runs even without `lisp/`.  At
start-up only scripts that differ from that copy are loaded; each is
compiled once into `~/.cache/sbemacs/`, so start-up stays fast.  The
scripts are looked for in `$SBEMACS_LISP`, then in `lisp/` next to the
executable (the source tree, or `/usr/local/lib/sbemacs/lisp` after
`make install`).

## Configuration: `~/.sbemacs/init.lisp`

The init file is ordinary Common Lisp.  It is optional.  See [`samples/init.lisp`](samples/init.lisp) for a starting point.

```lisp
(defun insert-date ()
  (insert (multiple-value-bind (s m h d mo y) (get-decoded-time)
            (declare (ignore s m h))
            (format nil "~D-~2,'0D-~2,'0D" y mo d))))

(global-set-key "C-c d" 'insert-date)       ; any key Esc-l shows as user-defined-function

(set-color :keyword :blue :default :bold)   ; face, foreground, background, attributes
(set-color :comment 244)                    ; 0-255 on 256-colour terminals

(define-language "Go"
  :extensions '(".go")
  :line-comment "//"
  :block-comment '("/*" . "*/")
  :strings '("\"" "`")
  :keywords '("func" "package" "import" "var" "const" "type" "struct"
              "if" "else" "for" "range" "return" "go" "defer"))

(setf *undo-mode* nil)                      ; save memory: no unlimited undo
```

### Colours

SBEmacs draws on the terminal's own background and default text colour, so
it fits light and dark terminal themes and the terminal's cursor stays
visible.  On 256-colour terminals keywords are bold purple, strings olive
green, numbers orange and comments grey; identifiers and punctuation use the
terminal's text colour.  The theme is the script
[`lisp/theme.lisp`](lisp/theme.lisp).  To change single faces, use
`set-color` in your init file; it overrides the theme.  Faces are
`:keyword :comment :block-comment :string :digits :alpha :symbol :brace
:modeline`, colours `:default :black :red :green :yellow :blue :magenta
:cyan :white` or 0-255, attributes `:bold :underline :reverse :dim :italic`.

### Syntax highlighting

The highlighter lives in [`lisp/highlight.lisp`](lisp/highlight.lisp) and
each language in its own file in [`lisp/languages/`](lisp/languages/).
Before a window is drawn, the C core passes the visible text (and up to 16 KB
above it, so comments opened off-screen are seen) to Lisp, which returns one
colour per byte.  Languages come with C, Common Lisp, Scheme, Python, Ruby,
Haskell, OCaml/ML, TeX, Prolog and Lean.  `define-language` options:

| Option | Meaning |
|--------|---------|
| `:extensions` | `".c"` or a list of them |
| `:line-comment` | `"//"` or a list |
| `:block-comment` | `'("/*" . "*/")` or a list of pairs |
| `:strings` | string delimiters, default `'("\"")` |
| `:escape` | escape character inside strings, default `#\\`, or `nil` |
| `:keywords` | list of strings |
| `:word-chars` | extra identifier characters, e.g. `"-*+!?<>=/"` for Lisps |
| `:case-insensitive` | match keywords ignoring case |
| `:char-prefix` | character-literal prefix to skip, e.g. `"#\\"` |
| `:backslash-commands` | treat `\word` as a keyword (TeX) |

### Indentation

Every language that has colours is also indented: `TAB` indents the
current line, `RET` starts the next line at the right column, and
`C-x C-i` re-indents a region (`indent-buffer` from `Esc-;` does the whole
file).  Closing tokens re-indent their line as you type them: `}` in C,
`else:` / `elif` / `except` / `finally` in Python, `end` in Ruby, `\end` in
TeX.

| Language | Style | |
|----------|-------|-|
| Common Lisp, Emacs Lisp, Scheme, VHDL Lisp | `:lisp` | body forms by 2, distinguished arguments by 4, call arguments aligned under the first |
| C | `:c` | blocks, `case` labels, continuation lines, arguments aligned inside `( )`, comments, preprocessor lines at column 0 |
| Python | `:python` | after `:`, dedent after `return`/`pass`/..., `else`/`elif` line up with their `if`, brackets |
| Prolog | `:prolog` | clause bodies, parentheses |
| Ruby, Haskell, ML, Lean, TeX | `:block` | keywords that open and close blocks |

Where the right level cannot be known (the line after a Python or Haskell
block), pressing `TAB` again steps down one level at a time.

Indentation lives in the language scripts, so it changes without a
rebuild: edit, say, the `define-indentation` form at the end of
[`lisp/languages/c.lisp`](lisp/languages/c.lisp) and press `C-x C-r`.

```lisp
(define-indentation "C"
  :style :c :width 4          ; step
  :tabs :auto                 ; t, nil, or :auto: tabs if the file uses them
  :preprocessor t :case-labels t
  :reindent-on-newline t      ; RET also re-indents the line it leaves
  :electric-keys "{}:#" :electric-prefixes '("{" "}" "#")
  :electric-words '("case" "default"))
```

For Lisp, `:specials` lists the forms with a body and how many
distinguished arguments they take, e.g. `("defun" . 2)`; add your own
macros there.  For a new language, the `:block` style is usually enough:

```lisp
(define-indentation "Go"
  :style :block :width 4 :tabs t
  :comment "//"
  :open-endings '("{" "(")
  :close-chars "})"
  :electric-keys "})" :electric-prefixes '("}" ")"))
```

A completely new style is a Lisp function from an indentation context to
a column, registered with `define-indent-style` (see
[`lisp/indent.lisp`](lisp/indent.lisp)).

### The editor API

These replace the femtolisp builtins and keep their names.  Counts are
optional and default to 1.

| | |
|-|-|
| Text | `point` `line-start` `line-end` `buffer-substring` `buffer-octets` `current-line-text` |
| Movement | `forward-char` `backward-char` `forward-word` `backward-word` `next-line` `previous-line` `forward-page` `backward-page` `beginning-of-line` `end-of-line` `beginning-of-buffer` `end-of-buffer` `goto-line` `goto-char` `point` `mark` `set-mark` `buffer-size` `char-after` |
| Editing | `insert` `backward-delete-char` `delete-char` `kill-region` `copy-region` `yank` `kill-line` `undo` `cut-region` `get-clipboard` `set-clipboard` `current-line-text` |
| Search | `search-forward` `search-backward` (return true when found) |
| Buffers | `get-buffer-name` `get-buffer-count` `buffer-filename` `buffer-modified-p` `select-buffer` `kill-buffer` `save-buffer` `find-file` `list-buffers` `rename-buffer` |
| Windows | `split-window` `other-window` `delete-other-windows` `update-display` `refresh-screen` |
| Interaction | `message` (accepts `format` arguments) `clear-message-line` `prompt` `get-key` `get-key-name` `get-key-binding` |
| Misc | `shell-command` `log-message` `log-debug` `trim` `home` `get-version-string` `quit-editor` |
| Customising | `global-set-key` `global-unset-key` `define-language` `define-indentation` `define-indent-style` `indent-line` `indent-region` `indent-buffer` `set-color` `*kill-hook*` `*startup-hook*` `*kill-ring*` `*undo-mode*` |

`get-key` waits for a key and returns what was typed, or `""` for a bound key
(arrow keys, `C-n`, ...), whose name and command `get-key-name` and
`get-key-binding` then return.  `buffer-menu` in
[`lisp/extensions/buffer-menu.lisp`](lisp/extensions/buffer-menu.lisp) shows
how to write a small interactive mode with it.

## Source layout

```
src/            the C editor core; src/interface.c is the bridge to Lisp,
                src/screen.h the screen layer, term.c and gui.c its back ends
lisp/           engine: package, ffi, loader, core (compiled into sbemacs)
                scripts: highlight, theme, defaults
lisp/languages  one script per language
lisp/extensions buffer menu, kill ring, dired, grep
tests/          make test
samples/        example init file and files to try the highlighter on
build.lisp      compiles the engine and scripts, saves the sbemacs executable
```

## Coming from FemtoEmacs

* `~/init.lsp` and `~/r5rs.scm` are no longer needed; the defaults are built
  in.  Put your own settings in `~/.sbemacs/init.lisp`, in Common Lisp.
* `(newlanguage ".c" "//" "/*" "*/")` followed by `(keyword ...)` calls is
  now one `define-language` form.
* `(define (f) ...)` becomes `(defun f () ...)`, `set!` becomes `setf`,
  `#t`/`#f` become `t`/`nil`, `string-append` becomes `concatenate 'string`
  (or `format nil`).
* `global-set-key` takes a symbol: `(global-set-key "C-c a" 'html-p)`.

## Credits

Femto Emacs by Hugh Barney, derived from Atto Emacs and Anthony Howe's editor
(public domain), extended with femtolisp (by Jeff Bezanson) by the
FemtoEmacs contributors.  SBEmacs replaces femtolisp with SBCL.

SBEmacs is in the public domain.
