# SBEmacs / Femto Emacs Change Log

## SBEmacs 2.0
* Help: C-h or F1 shows every key, one line each, on a page of its own;
  the arrows scroll it, C-c r / C-c g ask Claude / ChatGPT, any other key
  returns to the file and closes the assistants' windows
  (lisp/extensions/help.lisp).  The mode line reads
  "SBEmacs: Ctrl-h or F1 for help == file, line N == Ctrl-c r calls
  Claude; Ctrl-c g calls ChatGPT" (set-mode-line-hints changes the hints).
* The GNU Emacs keys FemtoEmacs lacked, in lisp/extensions/emacs-keys.lisp:
  sentence, paragraph, s-expression and defun motion; kill-word,
  backward-kill-word, kill-sexp, kill-sentence, zap-to-char, joined kills,
  yank-pop; transpose chars/words/lines; up/down/capitalize-word;
  open-line, delete-indentation, delete-horizontal-space, just-one-space,
  delete-blank-lines, fill-paragraph, comment-dwim; mark-whole-buffer,
  exchange-point-and-mark, mark-paragraph/word/sexp; keyboard-quit;
  switch-to-buffer, find-alternate-file, save-some-buffers, quoted-insert,
  eval-expression (M-:), eval-defun, describe-key.  In C: keyboard macros
  (C-x ( C-x ) C-x e, e repeats), delete-window (C-x 0), enlarge-window
  (C-x ^), recenter (C-l).  M-x also runs Lisp commands.
* Every key goes to the Lisp keymap first, and keys missing from the C
  table get names (C-g, C-x h, esc d, esc C-f ...), so any key can be bound
  from a script; global-set-key takes Emacs notation (M-d, C-M-f, M-DEL).
* The region is shaded while active (C-SPC, a mouse drag, C-x h ...) and
  deactivated by editing, M-w or C-g; new face :region.
* The mouse in the terminal too (xterm SGR reporting), on by default
  (--no-mouse turns it off): click to move or to select a window, drag to
  select.  The window (--gui) drags the same way; the wheel no longer
  scrolls.
* An assistant: C-c r asks Claude about the code at the cursor (through
  the Claude Code CLI, or the Messages API with curl) and shows the
  answer in a window; C-c y inserts the proposed code after confirmation.
  C-c x is the same for Codex, a stub for now.  Keys and safeguards after
  Asimov's Three Laws.  Pure Lisp scripts: lisp/extensions/assistant.lisp
  and codex.lisp.
* A window of its own: `sbemacs --gui` (or `sbemacs-gui`) draws with SDL2
  and SDL2_ttf, with 24-bit colours, a TrueType font, mouse clicks and
  wheel, the system clipboard, font zoom, and dark and light themes.  Falls
  back to the terminal when no window can be opened.
* The C core no longer calls ncurses: it draws through src/screen.h, with
  two back ends, src/term.c (ncurses) and src/gui.c (SDL2).  They are built
  into two libraries with the same API, libsbemacs-term and libsbemacs-gui;
  the executable loads one at start-up.
* `set-color` accepts "#rrggbb" (approximated in a terminal).
* femtolisp replaced by SBCL.  SBCL is now the host process and loads the C
  editor core (src/) as a shared library through sb-alien; the core calls
  back into Lisp for evaluation, user keys, kill hooks and highlighting.
* Syntax highlighting rewritten in Common Lisp (lisp/highlight.lisp), with
  `define-language`; the highlighter now looks up to 16 KB above the window
  so comments opened off-screen are coloured correctly.  Added Prolog and
  Lean; Python triple-quoted strings are strings.
* init.lsp ported to Common Lisp and compiled in (lisp/defaults.lisp); the
  user's file is now ~/.sbemacs/init.lisp and is optional.  Errors in it are
  shown on the message line instead of aborting.
* Buffer menu, kill ring, dired and grep ported to Common Lisp
  (lisp/extensions/).  Kills are recorded in `*kill-ring*` by default.
  dired and grep no longer shell out, so they work on Windows.
* Lisp scripts load dynamically: the executable holds only the engine;
  highlight.lisp, theme.lisp, languages/*.lisp (one file per language),
  defaults.lisp and extensions/*.lisp are reloaded at start-up when edited
  (compiled once into ~/.cache/sbemacs/), and C-x C-r reloads them in a
  running editor.  ~/.sbemacs/languages/ and ~/.sbemacs/extensions/ are
  loaded too.  The colour theme moved from C to lisp/theme.lisp.
* Automatic indentation for every highlighted language (lisp/indent.lisp
  and a `define-indentation` form in each language script): TAB indents
  the line (and cycles levels in Python, Haskell, ML, Lean), RET indents
  the new line, C-x C-i indents the region, closing tokens re-indent
  their line.  Styles :lisp, :c, :python, :prolog and :block.
* C-e on the last line of a file without a final newline now goes to the
  real end of the line.
* C-x C-e evaluates the Lisp expression before the cursor (eval-last-sexp).
* Errors in Esc-; and Esc-] are reported, never fatal.
* New colour scheme on the terminal's own background (FemtoEmacs forced a
  black one, which hid the cursor on light terminal themes); 256-colour
  palette when available; `set-color` takes 0-255 and :bold etc.
* New build: `make`, `make test`, `make install`, `make dist`; GitHub
  Actions builds Linux, macOS and Windows archives.
* Removed femtolisp/, femto.boot, xfemto.boot, r5rs.scm, the old makefiles
  and uninstall.sh.


## Femto 1.13 27 Dec 2016
* Fixed bug where could not open multiple files of same name but with different filepaths
* added (rename-buffer) and (find-file) commands
* added grep-command extension C-x C-g to search files, C-x ! to visit next find. (see init.lsp)

## Femto 1.12 18 Dec 2016
* Fixed annoyance. Changed searchtext so that is reset to blank when search is started.

## Femto 1.11 18 Dec 2016
* Modified init.lsp so that keys are bound using 'global-set-key' and there is an interpretter loop
* added additional entries for C-x C-char user-defined-function

## Femto 1.10 6 Nov 2016
* fixed UTF8 char handling in undo for INSERT, BACKSPACE, DEL, INSERT_AT
* fixed DEL, INSERT_AT now working properly at all.
* python support for syntax highlighting
* added C-x C-d start of Dired functionality

## Femto 1.9 27 Oct 2016
* added discard-undo-history command and lisp interface

## Femto 1.8.1 27 Oct 2016
* removed _(x) macro from header.h
* changed C-o to Esc-; for repl(), frees up Control-O for other editor commands.
* cleaned up call_lisp code in flcall.c
* cleaned up main code that calls init_lisp(), pass size of heap in KB into init_lisp().
* removed double wrapping of lisp commands with the (let ((b buffer)) expression
* changed repl() so that output more than 60 chars is sent to a *lisp_output* buffer that pops up
* changed killbuffer so it does not ask to kill a special buffer (even if modified)
* renamed temp to response_buf and ensured we only use it for getting response at the command line

## Femto 1.8 26 Oct 2016
* Added unlimited undo (supports Insert, Backspace, Yank, Kill-Region, Delete), see docs/undo.txt for details
* Added special buffer mode for buffers that have names starting with * (Thanks to chigoncalves)

## Femto 1.7 9 Oct 2016
* Potential fix for segmentation fault when calling (environment) within FemtoEmacs

## Femto 1.6 8 Oct 2016
* Added apropos Esc-a
* Execute-command Esc-x (with command completion)
* Added list-bindings command
* Sorted key binding list
* Fixed bug with copying first time in a buffer

## Femto 1.5.X dd/mm/yy
* Interim history to be added from got logs

## Femto 1.5 20 June 2016
* Added automatic matching of parenthesis {}() and []
* Fixed bug where a new file created when file not found did not have a buffer created

## Femto 1.4 13 June 2016
* Initialised buffer name to empty string
* Added basic colour scheme

## Femto v1.3 12 June 2016
* Fixed defect with paste command introduced in v1.1
* Added messages on copy and cut to show how many bytes

## Femto v1.2 3 June 2016
* Added UTF8 support

## Femto v1.1 31 May 2016
* Added list-buffers C-x C-b
* fixed problem of opening up multiple output windows
* refactored paste.  Paste now calls insert-string with contents of scrap

## Femto v1.0 29 May 2016
* Added filename completion (use TAB to complete)
* Added shell-command (C-x @), output is read into a buffer
