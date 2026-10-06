---
name: sbemacs-scripts
description: Write or change SBEmacs Lisp scripts (key bindings, commands, syntax colouring with define-language, indentation with define-indentation, colours, extensions) for SBEmacs, the FemtoEmacs editor running on SBCL. Use when the user wants SBEmacs to do something new, or asks how its Lisp API works.
---

# Writing SBEmacs scripts

SBEmacs is a small editor core in C driven by SBCL.  Everything a user
customises is Common Lisp, in *scripts* that the editor reloads with
`C-x C-r`: no `make` is needed.  Work in scripts; touch `src/*.c` or the
four engine files (`lisp/package.lisp`, `ffi.lisp`, `loader.lisp`,
`core.lisp`) only when the user explicitly asks for a change to the core,
and then remind them to run `make && sudo make install`.

## Where scripts live

| Folder | Package | Use it for |
|---|---|---|
| `~/.sbemacs/init.lisp` | `SBEMACS-USER` | the user's settings and small commands |
| `~/.sbemacs/extensions/*.lisp` | `SBEMACS-USER` | the user's larger extensions |
| `~/.sbemacs/languages/*.lisp` | `SBEMACS-USER` | the user's languages |
| `lisp/` in the sources | `SBEMACS` | only when changing SBEmacs itself |

`SBEMACS-USER` uses `COMMON-LISP` and `SBEMACS`, so only exported symbols
are available there; do not reach into `sbemacs::` internals from a user
script.  Load order: `highlight`, `indent`, `theme`, `undo`, `gui`,
`languages/*`, `defaults`, `extensions/*`, then the user's languages,
extensions and `init.lisp`.

## Rules

1. **First Law: never change the user's text behind their back.**  A
   command changes the buffer only when the user runs it, and asks first
   (`prompt` for y/n) before anything large or destructive.
2. **Errors end in a message, never a crash.**  Check inputs; report with
   `(message "...")`.  Commands run inside a handler, but do not rely on it.
3. **Declare, do not muffle.**  Use `(declaim (ftype (function (...) ...) name))`,
   `(declare (type ...))` and `(declaim (optimize (safety 3)))`.  Never
   muffle warnings; fix them.
4. **`defparameter`, not `defvar`, for values that must change when the
   script is reloaded.**  `defvar` keeps the old value, so an edit to it
   seems to have no effect after `C-x C-r`.
5. **Keys in Emacs notation:** `"C-c d"`, `"M-o"`, `"C-M-f"`, `"C-x h"`,
   `"F1"`.  Every key reaches the Lisp keymap before the C core, so any key
   can be bound.  Leave `C-c <letter>` keys to the user unless asked.
6. **Define commands with `defcommand`** (same syntax as `defun`) so that
   `M-x` finds them.
7. **Positions are byte offsets** into UTF-8 text; `buffer-substring`
   returns a string, `buffer-octets` the bytes.
8. **Undo is automatic.**  Every change is recorded; all the changes made
   by one key are undone together by `C-/`.  Do not record anything
   yourself.
9. Test pure functions with `make test` (`tests/run-tests.lisp`, forms
   `(check "name" form expected)`).

## The API (package SBEMACS)

- Moving: `point` `goto-char` `forward-char` `backward-char` `next-line`
  `previous-line` `beginning-of-line` `end-of-line` `beginning-of-buffer`
  `end-of-buffer` `goto-line` `line-start` `line-end` `line-number`
- Reading: `buffer-size` `buffer-substring` `buffer-octets` `char-after`
  `current-line-text` `search-forward` `search-backward`
- Changing: `insert` `delete-char` `backward-delete-char` `kill-region`
  `copy-region` `yank` `kill-line` `undo` `redo`
- Mark and region: `mark` `set-mark` (activates the shaded region)
  `push-mark` (does not) `region-active-p` `deactivate-mark`
- Buffers and windows: `get-buffer-name` `buffer-filename` `buffer-modified-p`
  `select-buffer` `find-file` `save-buffer` `kill-buffer` `split-window`
  `other-window` `delete-window` `delete-other-windows` `window-count`
- Talking to the user: `message` `clear-message-line` `prompt`
  `update-display` `get-key` (returns the typed text, or "" for a bound
  key, then `get-key-name` gives its name) `set-buffer-hint` (text at the
  end of a buffer's mode line)
- Keys and commands: `global-set-key` `global-unset-key` `key-binding`
  `defcommand` `execute-builtin` (runs a command of the C core by name)
- Looks: `set-color` (faces `:keyword` `:comment` `:block-comment`
  `:string` `:digits` `:alpha` `:symbol` `:brace` `:modeline` `:region`;
  colours `:red`..., 0-255 or `"#rrggbb"`)
- Languages: `define-language` (`:extensions` `:line-comment`
  `:block-comment` `:strings` `:keywords` `:escape` `:char-prefix`
  `:case-insensitive` `:word-chars` `:backslash-commands`),
  `define-indentation` (`:style` `:c` `:lisp` `:python` `:prolog` `:block`,
  `:width`, `:tabs`), `define-indent-style`
- Shell: `shell-command`

## Recipes

A command on a key:

```lisp
(defcommand insert-date ()
  "Insert today's date at the cursor."
  (multiple-value-bind (s m h d mo y) (get-decoded-time)
    (declare (ignore s m h))
    (insert (format nil "~D-~2,'0D-~2,'0D" y mo d))))

(global-set-key "C-c d" 'insert-date)
```

A language (one file in `~/.sbemacs/languages/`):

```lisp
(define-language "Go"
  :extensions '(".go")
  :line-comment "//"
  :block-comment '("/*" . "*/")
  :strings '("\"" "`")
  :keywords '("func" "package" "import" "return" "if" "else" "for"))

(define-indentation "Go" :style :c :width 4)
```

Reading keys in a small modal loop (as the help page does):

```lisp
(loop
  (message "y: yes, any other key: no")
  (update-display)
  (let ((k (get-key)))
    (return (string= k "y"))))
```

## After writing a script

Tell the user where the file is and that `C-x C-r` (or restarting the
editor) loads it; name the key or the `M-x` command that uses it.
