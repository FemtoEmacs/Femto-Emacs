#Femto Emacs Change Log

## 2026-10-22 — The mouse wheel scrolls

* command.c: the wheel scrolls the window under the pointer, 3 rows a notch
  (WHEEL_ROWS, header.h), in both directions (scroll_window).  The cursor
  stays put while it is visible; otherwise it moves to the nearest visible
  row, as in Emacs.  Scrolling stops at the top and with the last line at
  the top of the window.  Before, the terminal's wheel reports were read
  and ignored.
* display.c: select_screen_window chooses the window under the pointer
  without moving its cursor.
* gui.c: the window build turns SDL's wheel events into the same reports
  (one a notch, at the pointer), in the system's direction (natural
  scrolling on a Mac included).
* Tried in the terminal build with the reports a terminal sends: down,
  up, a visible cursor kept, the cursor pushed off the bottom, the top and
  the end of the file.  231/231 checks pass; gui.c compiles against SDL.

## 2026-10-21 — The view without tags moves with nvim's keys

* The view (C-c TAB, C-c l) opens in read mode, as after C-x C-q: h j k l,
  Enter, w b e, gg G, C-d C-u, / ? n N move, yy and v...y copy; the mode
  line says READ.  i, a, A, I and C-x C-q return to the file at the same
  place, to edit it there (read-only.scm: leave-normal-mode asks
  tag-view.scm), so the view is never made editable; M-x vim-mode is
  refused in it.

## 2026-10-21 — Hidden tags keep the colours

* With the tags hidden (C-c TAB, C-c l), the text keeps the colours it has
  in the file: titles, bold, italics, links, citations and math.  The file
  is coloured once, as HTML or LaTeX, when the tags are hidden, and each
  piece of the view takes the colours of the text it came from (an entity
  takes the colour around it, a "- " the symbol colour).
* The colouring call now says where the visible text starts in the buffer
  and which buffer it is (display.c, interface.c, hooks.c:
  highlight-buffer-text FILE TEXT COLORS BUFFER START), so a buffer can
  carry colours made in advance (highlight.scm, *buffer-faces*).
* Line breaks between tags no longer pile up as blank lines in the view.

## 2026-10-21 — HTML and LaTeX colours; hiding their tags

* languages/html.scm (new): HTML colours, for .html .htm .xhtml .xml .svg.
  Tags and <!DOCTYPE> keyword, attribute names digits, values string,
  comments comment, entities digits; the text of <h1>..<h6> and <title>
  heading, <b> <strong> strong, <i> <em> emphasis, <a> link, <code> <pre>
  <script> <style> string.
* languages/tex.scm: LaTeX gets a highlighter of its own (the old one
  coloured only commands and comments): section titles heading, math ($ $$
  \[ \( and equation, align ...) string, environment names digits, \emph
  emphasis, \textbf strong, \cite \ref \label \url ... link.  Also for
  .latex .ltx .cls .dtx .ins.  Markdown blocks ```html and ```latex use them.
* extensions/tag-view.scm (new): C-c TAB hides the HTML tags, C-c l the
  LaTeX commands, in a read-only, word-wrapped view (*tags-hidden*) in the
  same window; the same key returns to the file.  The cursor keeps its
  place in the text both ways.  The file is never changed.  M-x html-mode
  and M-x latex-mode colour a file of any name as HTML or LaTeX
  (highlight.scm, *language-overrides*).
* display.c: the word-wrap hook gets the buffer's name when it has no file,
  so the view can wrap; markdown.scm still refuses every other *name*.
* tests: the TeX check now expects the coloured title; nine new checks;
  231/231 pass.  Tried in the terminal build: the colours, both toggles, the
  cursor back at the same byte, html-mode on a .txt file, wrapping, and
  typing refused in the view.

## 2026-10-21 — vim mode pastes what other programs copied

* read-only.scm: p and P pasted the newest kill made in Schememax, never
  what another program (Grammarly, a browser) had copied since, so an older
  text came out.  They now take the system clipboard first, as C-y does.
  In vim mode C-y also pastes, at the cursor; before, the read-only buffer
  underneath refused it silently, and so it refused Cmd-V in the window
  (which sends C-y).  In read mode, C-y says that it would edit.

## 2026-10-20 — A key that ends a search does its usual job

* search.c: an arrow pressed during C-s (or C-r) ended the search on its
  Esc, and the rest of the arrow, "[A", was typed into the text
  ("Ishizuka[A's").  Now the search ends and the whole key is given back
  (key.c, unread_key_bytes), so the arrow moves the cursor, as in Emacs.
  The same holds for Home, End, PgUp, PgDn, a mouse click and control keys
  (C-a, C-n, C-e ...).  Esc alone still just ends the search; RET ends it,
  C-g cancels it.

## 2026-10-19 — An editable minibuffer; assistant buttons; all buffers sent

* src/lineedit.c (new): the answer to every prompt is edited anywhere in
  it: left/right and C-b/C-f, C-left/C-right and M-b/M-f by words,
  Home/End and C-a/C-e, Backspace, Delete and C-d, C-k, C-u; typed text
  goes in at the cursor, UTF-8 by characters, and a long answer scrolls.
  Mouse reports and unknown keys are read whole and ignored (before, an
  arrow typed "[D" into the answer).  getinput (key.c), getfilename
  (complete.c, TAB completion kept) and M-x (funcmap.c, TAB and the list
  of commands kept) all use it.
* display.c, segstart: with word wrap, the end of a file without a final
  newline counted as the start of a new empty row, so up at the end of the
  file moved to the row the cursor was already on and seemed stuck.  The
  cursor at the end now belongs to the last row, where it is drawn.  A
  file that ends with a newline is unchanged.
* The assistants' windows have their own buttons and no [?]:
  [SEND][TANGLE][CLOSE] in *discussion* and *codex-chat* (TANGLE = C-c t,
  CLOSE = M-x close-discussion-window), [SEND][TANGLE][CLOSE] in
  *claude-request* and *codex-request*, [TANGLE][CLOSE] under an answer
  (TANGLE = C-c y).
* Claude and Codex are sent, after the file with the cursor, every other
  buffer open in the editor, by name and file, within the same 400 KB; the
  editor's own windows (help, menus, assistants) are not sent.
* Read-only and vim mode: y and v...y copy to the system clipboard too
  (pbcopy on macOS); G goes to the end of the text (42G to line 42).
* tests/run-tests.scm: two new checks; 222/222 pass in a headless build,
  and the minibuffer, up at the end of a wrapped file, G, v...y, the
  buttons and the buffers sent were tried in the terminal build.

## 2026-10-19 — Claude and Codex can propose a new buffer

* Asked to put five questions in a new buffer with the paper below them,
  Claude answered that it could not open buffers, and that it saw the paper
  only up to Table 2.  Both are fixed, for Claude (C-c r) and Codex (C-c g).
* The assistants are sent the whole file up to 400 KB (was 60 KB around the
  cursor), so a textified paper is seen to its end.
* Both are told (*new-buffer-instructions*) that they may propose a buffer:
  a fenced block opening with ```new-buffer NAME, in which a line <<FILE>>
  stands for the whole file.  C-c y, or C-c t on the block in a
  discussion, asks, then creates the buffer (NAME, or NAME<2> if taken; at
  most 16 characters) with the file pasted in place of <<FILE>>.  Second
  Law: nothing is made without your y.  A proposed buffer is never inserted
  as code.
* tests/run-tests.scm: six new checks; README and the help page updated.

## 2026-10-19 — C-c p shows data tables in a window

* sketch.scm: with the cursor in a `(data-table ...)`, C-c p sends irene-dixe
  a table: caption, header, rows (depth, group) and notes.  The cells are
  printed text, taken from the table's tokens, so 33.0 stays 33.0:
  (:count N :percent P) -> "N (P)", (:value X :ci (L H)) -> "X (L–H)",
  (:< 0.001) -> "<0.001", :na -> "NA", nil -> empty; counts of five digits
  or more get thousands commas (18,053).  Without a display, aligned text in
  *plot*.
* irene-dixe.c: a table mode.  Ruled header, bold group rows, indented
  subcategories, banded lines, notes below; the window is sized to the table
  (up to 1400 x 900), arrows, wheel, PgUp/PgDn, Home and End scroll it, and
  s (or --render) saves the whole table, not just the visible part.
* tests/run-tests.scm: three new checks; README and the help page updated.

## 2026-10-19 — TTFY tables are S-expressions, the same from ChatGPT and Claude

* ttfy/plots-guidelines.md (version 1.1), section 2: every table is one
  S-expression in a `lisp` block; no Markdown pipe tables, aligned columns or
  `text` record blocks.  Printed tables use a closed schema,
  `(data-table :schema schememax/data-table/1 ...)`: fixed fields in a fixed
  order, columns c1, c2 ..., one cell per column, and a short list of cell
  forms ((:count N :percent P), (:value X :ci (L H)), (:< 0.001), :na, nil).
* src/assistant.c: the C-c f prompt, the same for both providers, says so.
* ttfy.scm: the answer is checked.  A pipe table that slipped through is
  sent back, alone, to the same provider to be rewritten as a data-table;
  a lisp block that does not read is reported at the top of the answer.
  Then every lisp block is laid out by Schememax's own fixed rules (atoms
  keep their printed text), so ChatGPT and Claude give the same layout.
* tests/run-tests.scm: seven new TTFY checks.

## 2026-10-19 — Keywords are constants, as in Common Lisp

* femtoscheme already read :time, :title, :estimator as Common Lisp does:
  self-evaluating, eq? to their quoted forms, so plot tables such as
  Figure 1A in NAIA-tst/hardy-2025-wo.md need no quoting.
* What differed: (define :time 3) and (set! :time 3) were silently ignored,
  and (let ((:x 1)) :x) or (lambda (:y) :y) bound a keyword as a variable.
  Common Lisp signals an error for all of these; now femtoscheme does too
  ("compile error: cannot assign to keyword :time", "keyword :x cannot be
  a variable").  Fix in femtoscheme/compiler.scm; femtoscheme.boot rebuilt
  with bootstrap.sh; all femtoscheme tests pass.
* Still different from Common Lisp, by design: keywords are case-sensitive
  (:Time is not :time), (symbol->string :time) is ":time", and a trailing
  colon (time:) also makes a keyword, used for keyword arguments.

## 2026-10-18 — Read-only and vim mode, with nvim's normal-mode keys

* M-x read-only (also M-x read-mode, M-x read-only-mode, C-x C-q): the
  buffer is read-only and the keys are nvim's motions and copies (h j k l,
  w b e, 0 ^ $, gg G, Enter, C-d C-u, / ? n N, yy, y{motion}, v ... y).
  Keys that would edit say so.
* M-x vim-mode: the same, plus dd, d{motion}, x, p, P, u, C-r, v ... d, o,
  O, a, A, I.  Counts repeat (3dd, 5j).  Each edit is one undo step.
* vim-mode also has . (repeat the last change; a count replaces its count),
  J (join lines), r{char} (replace) and :w, :wq, :x, :q, :NUMBER.  Esc is
  still Meta, as in Emacs: C-g cancels.
* % jumps to the matching paren, bracket or brace, in both modes (d% and
  y% too); off the line's brackets, it takes the first one after the
  cursor, as vim does.
* The help page (C-h) is read-only: every motion key works on it (j k,
  gg G, C-d C-u, / n, % ...), nothing edits it, and i or [CLOSE] returns
  to the page that asked for help, where the cursor was.  The mode line
  says "i closes help".  C-c r and C-c g close it and ask about that page.
* i returns to Emacs from both.  The mode line shows %% and READ, NORMAL
  or VISUAL; the help page lists the keys.
* core.scm: *modal-key-handler* sees every key first (a mode that owns the
  keyboard, such as these).

## 2026-10-18 — Read-only mode; C-c p draws sampled curves

* M-x read-only (also M-x read-only-mode, C-x C-q) toggles read-only mode
  for the buffer.  The C core refuses every change in such a buffer, typed
  or made by a script (insert, delete, kill, yank, replace, undo,
  insert-file); moving, searching, copying, C-c p and saving still work.
  The mode line shows %% after the file name.
* C-c p now draws tables recorded as sampled landmarks (:landmark rows),
  as in hardy-2025-wo.md: dots joined by dotted lines, because the shape
  between them is unknown.  Before, those curves came out flat at 1.
* A trace shared by several cohorts ((:cohort (p1 p2 p3)), where curves
  overlap) is drawn in dark grey and named after all of them; a cohort
  with several curve records is listed once.  Statistics given as rows
  (:kind :median / :p-value) are shown in words.
* A paren whose match is off the screen (a long plot table, a long
  definition) now says where the match is, as Emacs does:
  "Matches line 383:   :omissions nil)".
* C-c p and M-x plot-save act only with the cursor in a plot table (on
  its opening paren, inside it, or just after its closing paren).  Before,
  they drew the next table below the cursor from anywhere in the file.

## 2026-10-18 — C-c p: plots back from their tables

* C-c p (M-x plot-at-point, also M-x irene-dixe) draws the Kaplan-Meier
  table (estimator-plot ...) at the cursor in a window of its own, by the
  new program irene-dixe (src/irene-dixe.c, SDL2 and SDL2_ttf): legend
  colours, censor marks, shaded unresolved intervals, numbers at risk and
  the printed statistics.  s saves a PNG beside the file; q closes.  With
  no display, a character sketch opens in *plot*.
* Tables are read, never evaluated; # outside strings is refused (#. would
  evaluate while reading).
* M-x plot-save writes the picture without a window and confirms that
  the file exists.  s in the window now draws the picture again in
  software before saving; reading the window back could fail silently on
  macOS.  The window shows where the picture went.
* Pictures are PNG, written by irene-dixe itself (no SDL_image or zlib):
  about 120 KB for a plot that took 2.5 MB as BMP.
* Fixed: a file opened by a relative name (`schememax paper.md`) had its
  pictures saved in the home folder; they now go beside the file.
* New primitives: spawn-program (start without waiting), os-name, getpid.
* Fixed: number->string truncated reals (0.8 gave "0"), in femtoscheme.
* Fixed: windows split or joined by a script (TTFY, the assistants, C-c p)
  could keep stale text at the ends of shortened rows until C-l.

## 2026-10-18 — Emacs-style word wrap

* Fixed: in a wrapped file (Markdown, TeX, text) that does not end in a
  newline, the cursor at the end of the file sat at the start of the row
  below the text, or at the bottom of the window, while typing went
  above it.  It now stays after the last character.

* Markdown, TeX and plain-text files wrap long lines at word boundaries,
  like Emacs's visual-line-mode.  The blanks at a break stay at the end
  of the upper row, so the next row starts with a word.
* C-c w, MORE > "Word wrap on/off", M-x toggle-word-wrap or
  M-x visual-line-mode switch wrapping on or off for the current file, in
  any language.  The help page (C-h) lists C-c w.
* The help page (C-h, or [?] > Keybindings) has a new section, "M-x
  commands", for commands without a key of their own: toggle-word-wrap,
  visual-line-mode, indent-buffer, python-mode, dark-theme ...
* The help page's mode line has [CLOSE] instead of [?]: help from help
  only reopened the same page.  C-c r and C-c g still reach Claude and
  ChatGPT from the help page.

## 2026-10-18 — SBEmacs's scripts ported to Scheme

* Every script of SBEmacs's lisp/ folder now has a Scheme counterpart in
  scheme/ (core, api, highlight, indent, theme, undo, gui, languages/,
  defaults, extensions/, modes/): Emacs editing keys, undo and redo,
  indentation for 12 languages, Markdown, the mode line menu, help, the
  shell window, dired, grep, kill ring, buffer menu, the Claude and Codex
  assistants with discussions, the Python and Nim modes.
* Key bindings in Emacs notation now work (M-w, M-:, C-/ ... were never
  reached before).
* src/highlight.c: the highlighters (generic tokenizer, Markdown, Python,
  Nim), fed by the Scheme language tables.
* src/primitives.c: buffer text in bulk, exact byte insertion, files,
  running programs with a timeout.
* src/hooks.c: highlight, mode line, change and wrap hooks call Scheme.
* tests/run-tests.scm: SBEmacs's test suite, ported (make check).
* TTFY moved from C-c t to C-c f; C-c t is SBEmacs's discussion key again.
* ~/.schememax/init.scm and ~/.schememax/{languages,extensions}/ are loaded
  after the scripts.

## 2026-10-18 — source reorganization

* All C sources now live in `src/` (the former `bridge/` files moved there).
* Removed the obsolete FemtoEmacs clone at the top level (old C sources,
  `femtolisp/`, `samples/`, old makefiles, `femto.boot`, `init.lsp`,
  `r5rs.scm`, `sbemacs` binaries and `SBEmacs.app`).
* femtoscheme: `string_from_cstr(n)` take `const char *`.
* Editor Scheme scripts moved to `scheme/` (counterpart of the original
  `lisp/`); `init.scm` loads the others through `*scheme-dir*`.


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

2026-10-17: C-owned embedded femtoscheme architecture in sbcl-rasp/sbemacs.
Based on original master, replacing the embedded femtolisp runtime with the
local Browsered femtoscheme runtime. Added Makefile, init.scm, C bridge and
headless --eval/--version commands. Native build, runtime suites, and terminal
editing/save/evaluation smoke checks passed on macOS. No SBCL dependency.

The editor folder is now ordinary vendored source under sbcl-rasp; its nested
Git history has been removed. The original SBEmacs repository retains that history.

2026-10-17: Imported modern sbcl-branch C screen/editor core, keeping C-owned
startup and embedding femtoscheme. Built terminal, GUI and macOS app bundle.
Added typed Scheme API, mode-line menus, light/dark palettes with contrasting
cursors, provider CLI bridges, basic undo/navigation/editing extensions and
basic highlighting. Local provider/highlighter tests passed. Full original
feature parity remains incomplete; FEATURE-PARITY.md records the gaps.

2026-10-17: Shared GUI/ncurses Help selector matching the original editor:
1 Keybindings, 2 ChatGPT, 3 Claude; arrows/Enter, direct number selection,
mouse Run/Close, and source/point restoration. Added help.scm and menu checks.

2026-10-17: Fixed Help Run for ChatGPT/Claude: bypass the invisible secondary
menu and open the request pane directly, preserving drafts. Refresh provider
shortcut menus before reading input. Added dispatch regression tests and tested
actual ncurses mouse selection/Run for both providers without an extra key.

2026-10-17: Replaced blank provider request panes with visible instructions,
Send/Close buttons and empty-request feedback. Exclude form instructions from
provider prompts. Added request-form tests and verified terminal mouse Send
through a local fake provider to the displayed response.

2026-10-17: AI response/setup panes now have a dedicated Close action instead
of the document Quit button. Close removes the pane and restores the source
buffer. Added modeline and Close-dispatch regression checks for both providers.

2026-10-17: Renamed build outputs to schememax, schememax-gui and Schememax.app.
Updated GUI launcher, bundle metadata, checks and documented launch commands.

2026-10-17: Added TTFY button, provider menu, completing PDF picker and page
ranges. Native macOS PDF rendering supplies Codex image attachments or Claude
Read inputs; Markdown opens in an editable, savable result buffer. Added
plot-to-table guidelines, diagnostic panes and offline seven-page Benedetto
integration tests. Restored missing complete-file event/native binding for
Tab completion in C-x C-f and the PDF picker, with ~/ expansion on acceptance.

2026-10-17: Require Kaplan-Meier curve-building S-expression tables in TTFY.
Documented axis calibration, every recoverable jump, separate censor/risk
annotations, uncertainty, gaps, start/end points and step reconstruction.

2026-10-17: Fixed Search: typing now searches incrementally, Enter accepts,
C-s/C-r repeat in their respective directions, and C-g restores the origin.
Fixed backward matches at buffer start, off-by-one positioning and unsafe
end-of-buffer reads. Failed searches retain the previous cursor position.
Added C regression tests covering input handling and gap-buffer boundaries.
