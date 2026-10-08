# Editing modes

The loader implementation and its `M-x load-mode` / `reload-mode` commands
live in `lisp/modes/load-mode.lisp`. A small startup entry point in
`lisp/extensions/zz-modes.lisp` loads that file after the menu library.
It contains no mode-loading implementation.

Mode lookup is anchored to the absolute directory containing the loader,
`lisp/modes/`, regardless of the shell's working directory. While loading a
mode, Common Lisp's default directory is temporarily that mode file's
directory, so relative `load` and file paths resolve beside it. The caller's
default directory is restored afterwards. User modes in `~/.sbemacs/modes/`
retain precedence. `load-mode.lisp` is a file, not a subdirectory.

`python-mode.lisp` is now the standard Python mode, activated automatically
at startup. The original script is archived in `lisp/modes/legacy/python.lisp`,
outside the automatic `languages/*.lisp` scan. The startup scanner also
ignores a stale `languages/python.lisp` when the replacement mode exists,
and `make install` removes that obsolete installed file. This prevents an
upgrade from reverting callbacks while retaining the new menu. The new mode implements the Python-style
specification in `lisp/languages/python.synpy` by hand, in Common Lisp.
No Python interpreter or synpy compiler is used by the editor.

## Try it

From the repository:

```sh
cd /Users/eduardo/csand/sbemacs
make
./sbemacs example.py
```

Python files automatically get the new coloring, indentation and menu.
To load another mode or reactivate Python explicitly, press **M-x**, type
**load-mode**, and press Enter. At
**Load mode:** type **py**, press **TAB** to complete **python-mode**,
and press Enter. You can also type **python** directly. `python-mode` is also
accepted there. For ambiguous names, TAB extends the common prefix and
repeated TAB cycles through matching modes. The cursor remains on the
prompt line immediately after the typed name, including after completion. C-g cancels, Backspace erases,
and C-u clears the name. Completion includes bundled modes and mode files
in both the loader directory and `~/.sbemacs/modes/`. The shortcut is **M-x python-mode Enter**.

The mode installs coloring and indentation callbacks for `.py`, `.pyw`,
`.pyi` and `.synpy`, using the existing C/Lisp callback interfaces.
Registrations apply to all files with those extensions in the current
session. This first mechanism does not provide independent per-buffer
major modes or mode-local keymaps. Restarting uses the new Python mode
automatically. Activation does not modify buffer text.

* TAB: indent; repeated TAB cycles through possible levels.
* RET: indent the new line, using the existing editor machinery.
* IND / C-x C-i: indent the region.
* # / M-;: use the existing comment command with Python's `#`.
* DEF> / M-x python-next-definition: visit the next definition.
* <DEF / M-x python-previous-definition: visit the preceding definition.

The common menu starts with `[?][QUIT][MORE]`, keeping Help, Quit and
More ahead of the Python tools. MORE opens a separate actions window,
including commands omitted from a narrow status line. Use arrows and
Enter, or click an option and click RUN; q or C-g dismisses it. Actions
run in the original document after the menu window closes. Python uses `[IND][#][DEF>][<DEF]` for indentation,
comments and definition navigation. AI help and buffers use `[AI][BUFS]`.
The Python buttons preserve the existing common menu actions. On narrow
windows some buttons on the right may not fit; all commands remain available
by keyboard. Menus for non-Python files and special buffer menus are preserved.

After editing `modes/python-mode.lisp`, run **M-x reload-mode Enter** or
**M-x python-mode Enter**. Ordinary **C-x C-r** reloads the normal scripts;
if a language script resets the Python registration, activate the optional
mode again. A forced reload of all scripts reapplies active installers.

For the installed editor, run `make` followed by `sudo make install`, then
restart it; Python mode activates automatically. No C changes are required. Building bundles
the optional Python definitions into the executable; activation also works
without the source directory. Source files, when present, take precedence
so the mode can be edited without rebuilding.

## Add another mode

Put `<name>-mode.lisp` in `lisp/modes/`, or `~/.sbemacs/modes/` for your own
mode. The user directory takes precedence. Inside the mode file, define
functions and register an installer, without activating it at file load:

```lisp
(in-package #:sbemacs)

(defun install-example-mode ()
  (define-language "Example" :extensions '(".example")
    :line-comment "#" :keywords '("begin" "end"))
  (define-indentation "Example" :style :block :width 4))

(register-editing-mode "example" #'install-example-mode)
```

Then use **M-x load-mode Enter example Enter**. This file is an SBEmacs
implementation module in the SBEMACS package. Its registration helpers
are internal APIs, not exported functions for ordinary SBEMACS-USER scripts.
The supplied Python mode is bundled during the build; other modes currently
require their source files to be installed.

`install-mode-menu` takes an owner name and a function of `(buffer-name
previous-buttons)` returning the new buttons. Reinstalling the same owner
replaces its contribution. This preserves unrelated providers and avoids
stacking copies on reload. Mode names cannot contain path separators.
Compile/load failures are shown on the message line; as with ordinary Lisp
script loading, a failing file can leave definitions evaluated before the
failure. Mode loading is not a transactional Lisp evaluator.

## Validation and limits

```sh
make test
python3 lisp/py2sexpr/test_lisp_python_mode.py
```

The second suite executes real SBCL callbacks against the Python oracle,
including complete UTF-8 color arrays, f-strings, incomplete triple strings,
Unicode, bracket indentation, clause alignment, mode registration, menus,
byte-offset definition navigation, and bundled-mode fallback. It also
invokes the actual foreign-callable highlighting entry point.

This is an editor lexer, not a complete Python parser. The limits in
`../py2sexpr/PYTHON_MODE.md` also apply to the Lisp implementation: heuristic
soft keywords, builtin shadowing, some modern f-string quoting, bounded
highlighting context, and full-prefix indentation cost on large files.

The status line keeps only frequent actions. MORE opens the complete menu;
QUIT stays at the far right with a non-clickable gap. [?] offers Keybindings,
ChatGPT (the Codex integration), and Claude in document and assistant views.
Select sets the mark: move the cursor or drag the mouse to select text.
A nonempty active region replaces Select with COPY and DELETE; Python also
shows INDENT. These actions use the existing undo and indentation commands.
