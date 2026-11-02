# Feature parity with SBEmacs (the `sbcl` branch)

Every script of SBEmacs's `lisp/` folder has a Scheme counterpart in
`scheme/`, with the same commands, keys and behaviour. The C core is the
`sbcl` branch's. The specification of the port is the original Lisp, kept in
`reference/sbcl-lisp/`, and the original test suite, ported to
`tests/run-tests.scm` (189 checks, `make check`).

| SBEmacs (lisp/) | Schememax (scheme/) |
|---|---|
| core.lisp, ffi.lisp | core.scm, api.scm: key names in Emacs notation, the keymap, M-x commands, events from C, kill ring and system clipboard, start-up banner, user init file |
| loader.lisp | init.scm: the load order, ~/.schememax/{languages,extensions,init.scm}, C-x C-r |
| highlight.lisp, languages/*.lisp | highlight.scm, languages/*.scm (12 languages); the tokenizers run in C, src/highlight.c |
| languages/markdown.lisp | languages/markdown.scm: Markdown colours, code blocks in their language, list indentation, RET continuing lists, word wrapping of Markdown, TeX and text files (blanks hang at the break, as in Emacs; M-x toggle-word-wrap) |
| indent.lisp | indent.scm: styles lisp, c, python, prolog, block, markdown; TAB cycling, RET, electric keys, indent-region |
| undo.lisp | undo.scm: command grouping, typed runs, redo, saved state, size limit |
| theme.lisp, gui.lisp | theme.scm, gui.scm: terminal and window palettes, fonts, Option as Meta |
| defaults.lisp | defaults.scm: init.lsp's commands, C-x C-e, copy on select, file name completion with wildcards |
| extensions/emacs-keys.lisp | extensions/emacs-keys.scm: words, sentences, paragraphs, expressions, defuns, kills that join, M-y, transposing, case, filling, comments, mark commands, C-x b picker, C-x C-v, C-x s, C-q, C-x ? |
| extensions/menu.lisp | extensions/menu.scm: the mode line menu, narrow windows, COPY/DELETE, [MORE], the file name button, per-buffer buttons and hints |
| extensions/help.lisp | extensions/help.scm: the keys page (C-h, F1) |
| extensions/shell.lisp | extensions/shell.scm: M-!, C-c s, the transcript |
| extensions/dired.lisp, grep.lisp, kill-ring.lisp, buffer-menu.lisp | the same names, .scm |
| extensions/assistant.lisp, codex.lisp | assistant.scm, codex.scm: hints, questions, discussions, C-c y, C-c t, set-up pages, Claude API fallback |
| modes/load-mode.lisp, python-mode.lisp, nim-mode.lisp | modes/*.scm; the Python and Nim painters run in C, src/highlight.c |

## Differences

- Scripts are Scheme (femtoscheme), not Common Lisp; options are written
  `'extensions '(".c")` instead of `:extensions '(".c")`.
- The highlighters that run at every redisplay (the generic tokenizer,
  Markdown's, Python's and Nim's) are in C, src/highlight.c: in
  femtoscheme's bytecode they cost 10-50 ms per key, in C under 1 ms.  The
  language tables still come from the Scheme scripts, and a block of code in
  Markdown is coloured by the language its fence names.
- The optional native Nim library of SBEmacs is not used.
- Schememax keeps its own C-c f (textify a PDF, TTFY in [MORE]).
- M-x is the C core's command prompt, which completes over the Scheme
  commands too.

## Verified

In the cloud build (Linux terminal): `make check` (189 checks) and
`make check-ui` (search, both assistants' protocols with offline mock
programs), and in a terminal driven key by key: indentation, undo and redo,
kills and yanks, filling, comments, Python and Markdown editing, the help
page, [?], [MORE], the file name button, M-!, C-x b, C-x C-d, C-x C-b, C-c k,
C-x C-g and C-x !, M-x load-mode.  The window version and PDF rendering need
the Mac build.
