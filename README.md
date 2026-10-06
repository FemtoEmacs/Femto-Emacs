# SBEmacs

A tiny Emacs for the terminal, configured and extended in Common Lisp.

SBEmacs is [FemtoEmacs](https://github.com/FemtoEmacs/Femto-Emacs) with its
2016 Lisp, femtolisp, replaced by [SBCL](https://www.sbcl.org/).
The editor core (buffers, windows, undo, search, the ncurses display) is still
the small C program derived from Atto Emacs and Anthony Howe's editor.
Everything that used to be written in femtolisp is now Common Lisp compiled
by SBCL: key bindings, the startup screen, the buffer menu, the kill ring,
dired, grep, and the syntax highlighter.

```
  ┌──────────────────────────────┐        ┌──────────────────────────────┐
  │ SBCL process (sbemacs)       │  FFI   │ libsbemacs (C core)          │
  │                              │ ─────► │                              │
  │ init file, key bindings,     │ fe_*   │ gap buffers, windows, undo,  │
  │ syntax highlighting,         │        │ search, ncurses display,     │
  │ buffer menu, kill ring,      │ ◄───── │ keyboard                     │
  │ dired, grep, Esc-; Esc-]     │ hooks  │                              │
  └──────────────────────────────┘        └──────────────────────────────┘
```

SBCL is the host process.  It loads the C core as a shared library with
`sb-alien` (part of SBCL, no Quicklisp needed), registers three callbacks
(evaluate, events such as user keys, and highlight), and calls `fe_main`.

## Requirements

* [SBCL](https://www.sbcl.org/platform-table.html) 2.1 or newer
* a C compiler and `make`
* ncurses with wide-character support (`libncursesw`)

| System  | Install the prerequisites |
|---------|---------------------------|
| Debian / Ubuntu | `sudo apt install sbcl build-essential libncurses-dev` |
| Fedora  | `sudo dnf install sbcl gcc make ncurses-devel` |
| macOS   | `xcode-select --install` and `brew install sbcl` (the system ncurses is used) |
| Windows | SBCL from sbcl.org, plus [MSYS2](https://www.msys2.org/) with `pacman -S make mingw-w64-x86_64-gcc mingw-w64-x86_64-ncurses mingw-w64-x86_64-pkgconf` |

## Building

```sh
make            # builds libsbemacs.so (.dylib, .dll) and the sbemacs executable
make test       # runs the Lisp test suite (no terminal needed)
./sbemacs file.c
sudo make install        # into /usr/local; PREFIX=... to change
sudo make uninstall
```

On Windows run `make` from the *MSYS2 MINGW64* shell, with SBCL on the `PATH`.

`sbemacs` is a saved SBCL image that holds all the compiled Lisp.  It finds
`libsbemacs` next to itself (or set `SBEMACS_LIB` to its full path), so keep
the two files together.

Pre-built archives for Linux, macOS and Windows are attached to each
[release](../../releases).

## Using it

```
sbemacs [-q] [file] [+]      -q: skip the init file   +: enable the mouse
```

The usual Emacs keys work: `C-x C-f` find file, `C-x C-s` save, `C-x C-c` quit,
`C-s`/`C-r` search, `Esc-r` query replace, `C-space` set mark, `C-w` kill
region, `C-y` yank, `C-u` undo, `C-x 2` split window, `C-x o` other window.
`Esc-l` lists every binding and `Esc-x` runs a command by name.

On macOS, tick *Use Option as Meta key* in Terminal → Settings → Profiles →
Keyboard so that the Option key works as `Esc`.

### Lisp interaction

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

dired and grep are written in portable Common Lisp, so they behave the same
on every platform.

## Configuration: `~/.sbemacs/init.lisp`

The init file is ordinary Common Lisp.  It is optional; the defaults are
compiled in.  See [`samples/init.lisp`](samples/init.lisp) for a starting point.

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
terminal's text colour.  Change any face with `set-color`: faces are
`:keyword :comment :block-comment :string :digits :alpha :symbol :brace
:modeline`, colours `:default :black :red :green :yellow :blue :magenta
:cyan :white` or 0-255, attributes `:bold :underline :reverse :dim :italic`.

### Syntax highlighting

The highlighter lives in [`lisp/highlight.lisp`](lisp/highlight.lisp).
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

### The editor API

These replace the femtolisp builtins and keep their names.  Counts are
optional and default to 1.

| | |
|-|-|
| Movement | `forward-char` `backward-char` `forward-word` `backward-word` `next-line` `previous-line` `forward-page` `backward-page` `beginning-of-line` `end-of-line` `beginning-of-buffer` `end-of-buffer` `goto-line` `goto-char` `point` `mark` `set-mark` `buffer-size` `char-after` |
| Editing | `insert` `backward-delete-char` `delete-char` `kill-region` `copy-region` `yank` `kill-line` `undo` `cut-region` `get-clipboard` `set-clipboard` `current-line-text` |
| Search | `search-forward` `search-backward` (return true when found) |
| Buffers | `get-buffer-name` `get-buffer-count` `buffer-filename` `buffer-modified-p` `select-buffer` `kill-buffer` `save-buffer` `find-file` `list-buffers` `rename-buffer` |
| Windows | `split-window` `other-window` `delete-other-windows` `update-display` `refresh-screen` |
| Interaction | `message` (accepts `format` arguments) `clear-message-line` `prompt` `get-key` `get-key-name` `get-key-binding` |
| Misc | `shell-command` `log-message` `log-debug` `trim` `home` `get-version-string` `quit-editor` |
| Customising | `global-set-key` `global-unset-key` `define-language` `set-color` `*kill-hook*` `*startup-hook*` `*kill-ring*` `*undo-mode*` |

`get-key` waits for a key and returns what was typed, or `""` for a bound key
(arrow keys, `C-n`, ...), whose name and command `get-key-name` and
`get-key-binding` then return.  `buffer-menu` in
[`lisp/extensions/buffer-menu.lisp`](lisp/extensions/buffer-menu.lisp) shows
how to write a small interactive mode with it.

## Source layout

```
src/            the C editor core; src/interface.c is the bridge to Lisp
lisp/           package, FFI, highlighter, languages, callbacks, defaults
lisp/extensions buffer menu, kill ring, dired, grep
tests/          make test
samples/        example init file and files to try the highlighter on
build.lisp      compiles lisp/ and saves the sbemacs executable
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
