# Task 3. Adversarial algorithmic complexity benchmarks (O(N²) hangs)

22 November 2026. Written by Claude for Eduardo. The numbers come from
runs on Linux (x86-64) in Claude's cloud copy of the repository, at the
state pending on Eduardo's Mac (not yet committed). The test runs on Linux
and macOS.

## The task

Eduardo's text (`paper/test-design/testes.md`):

> You already hit an O(N²) or linear-scan bottleneck with C-M-f in a large
> file (sexp-speed.sh). Add automated timeout assertions (timeout 2s) for
> other classic editor traps on a 10 MB single-line file and a
> 100,000-line file:
>
> - Unclosed delimiters: C-M-f and C-M-b at the start of 10 MB of nested
>   ((((... with no matching ) (ensuring the scanner doesn't re-lex from
>   the top of the file on every character).
> - Pathological regex / incremental search: Typing a failing pattern in
>   C-s or M-% across a 50 MB file, or replacing 100,000 occurrences at
>   once (! in M-%), which frequently turns O(N) into O(N²) due to
>   repeated gap-buffer shifts or undo-record allocations.
> - Single-line long-line rendering: Opening a minified JSON/JS file with
>   one 5 MB line and moving the cursor (C-f, C-e, C-a) or clicking with
>   the mouse—which often triggers O(line_length) UTF-8 column-width
>   recalculations on every frame.
> - Paragraph refill (M-q) on huge blocks: Running M-q on a 50,000-word
>   unbroken paragraph or deeply nested Markdown/Org list.

Every point of the task is in the test. Two remarks:

- C-s and M-% search for literal text; the editor has no
  regular-expression search, so the trap of a pathological regular
  expression does not arise.
- C-a and C-e go to the ends of the row shown on the screen, as Emacs's
  visual-line-mode does, not to the ends of the 5 MB line; M-> was used to
  reach its end.

## Words used in this report

- **Linear, O(N).** A cost that grows with the size N of the text: twice
  the text, twice the time. Reading a 10 MB file once is linear.
- **Quadratic, O(N²).** A cost that grows with the square of the size:
  twice the text, four times the time. It usually comes from doing a
  linear thing once for every byte, line, word or occurrence. On a small
  file it does not show; on a large one a key takes minutes.
- **Gap buffer.** How the C core holds a text: one block of memory with a
  hole (the gap) where typing happens. Moving the gap, or making it
  bigger, copies the text after it.
- **Bridge call.** A call from the compiled Scheme to the C core, or back.
  Each one costs far more than an ordinary call (the arguments are copied
  through a shared memory), so a loop that crosses the bridge for every
  byte or line is slow even when it is linear.
- **The backdoor's `time`.** With `time` in its configuration, the
  backdoor writes, for every key, the milliseconds of its command and of
  the display that follows. The test reads its limits from there.

## Bugs found: five, all fixed

Four of them turned linear work into quadratic work or worse; the fifth
(C-s) was linear but slow.

```lisp
(bugs
 (bug 1
  (trap "The end of a 10 MB line (open-line): every key")
  (before "2.6 to 5.1 s a key, all of it in the display")
  (after "20 to 320 ms")
  (cause "For every key the highlighter read the text from the start of the
          line before the page: all 10 MB, copied and sent to Scheme. And the
          display found the row of the screen holding a position by scanning
          its line from the start (segstart, lnstart), several times a key")
  (fix "The highlighter starts at most 64 KB back (lnstart_within; in a
        longer line, 16 KB before the page). The display remembers, for the
        long line it last scanned, where it starts and the start of a row
        every 32 KB along it (long_line in display.c); a scan then begins at
        the nearest row start it knows"))
 (bug 2
  (trap "M-% with ! on 100,000 occurrences (replace-*)")
  (before "83 s on 100,000 lines of 5.4 MB, and C-/ then undid nothing")
  (after "0.14 to 0.33 s, and C-/ gives the whole text back")
  (cause "(a) For every change, undo summed the bytes and the changes of its
          whole history, twice (history-actual-bytes, history-change-count).
          (b) Every occurrence was a change of its own: 200,000 reports to
          Scheme, past the 10,000 changes the history keeps, so the command
          was dropped from undo. (c) The gap grew by 512 bytes at a time")
  (fix "(a) undo.scm counts bytes and changes as they come (count-history),
        in both runtimes. (b) ! replaces the rest in one pass (replace_rest
        in replace.c): the new text of the stretch is built apart and put in
        at once, one deletion and one insertion for undo. (c) growgap grows
        by an eighth of the buffer, at least, and moves the text with memmove"))
 (bug 3
  (trap "The first display after M-% in a line of 1.4 MB, in a text file")
  (before "188 s")
  (after "0.17 s")
  (cause "Text files wrap at words, and the words are a script's (wrap_hook),
          asked one row at a time across the bridge: 17,500 rows, some 25
          times a display")
  (fix "A line of 64 KB or more is wrapped at the window's edge, not at words
        (in_long_line), as Emacs's *so-long* mode gives up more for less. The
        rows of words of shorter lines are remembered too"))
 (bug 4
  (trap "M-q on 50,000 words (fill-paragraph)")
  (before "1.7 s on one line; the second M-q, on the 5,000 lines the first
           made, did not end in 3.5 minutes")
  (after "1.3 to 1.9 s for each")
  (cause "The words of each line were appended to the list of all the words
          before (append acc ...): quadratic. Then every line's start, end
          and text was a bridge call or more; the words were split by
          replacing tabs and newlines and splitting at every character; a
          filled line was made again with each word it took")
  (fix "The words are put on the list newest first and reversed once
        (prepend-reversed; both runtimes). M-q reads the text through one
        reader (buffer-reader, blocks of 64 KB) and the paragraph at once;
        split-words and the lines of the paragraph are cut in one pass over
        the bytes; fill-words makes each line once"))
 (bug 5
  (trap "C-s of a pattern found at the end of 50 MB (search)")
  (before "1.1 to 1.6 s")
  (after "0.6 s (the slowest key of the scenario)")
  (cause "search_forward read every byte through ptr()")
  (fix "It reads the text a run at a time (before the gap, after it) with
        memchr for the first byte of the pattern, and compares only there")))
```

Already within the limit at the first run: C-M-f and C-M-b over 10 MB of
unclosed `(` (1.1 to 1.6 s for the scan that fails, about 20 ms for C-M-b,
which fails at once), the 100,000-line file of `(`, C-s and M-% of a
pattern that fails over 50 MB (about 130 ms a scan), and M-q on the nested
Markdown and Org lists (under 0.5 s). The long line of JSON was measured
only after fix 1: 22 keys, none over 0.1 s; run with the display's memory
of the line turned off (below), M-> at its end takes 2.5 s.

Saving a file no longer counts as a change of its text (`record_change`,
kind `'s'`): C-x C-w made the display forget what it knew of the long line
and scan it again (4.6 s in a word-wrapped line, before fix 3).

### Is the remembered display the same?

The long-line memory is checked twice. `open-line` and `longline` run a
second time with `CHEZWEB_LONG_LINES=scan`, which makes `display.c`
remember nothing and scan from the start, as before; point, page and
cursor after every key must be the same in both runs. And the fuzzers ran
again over the changed `display.c`, `gap.c` and `replace.c`
(`make check-fuzz-core` in `make check`, and ten walks of
`make check-fuzz-editor` under the sanitizers).

## The test that was built

`tests/complexity.sh` (`make check-complexity`; a minute or two, so it is
not part of `make check`). It builds the files, runs the editor in a
terminal of its own (`tests/pty-keys.c`), types the keys, and then checks
two things:

1. **Every key within 2 seconds**, command and display together, as the
   backdoor measured them. `COMPLEXITY_LIMIT_MS` changes the limit. A key
   that never finishes ends the scenario at its timeout, and the test says
   so.
2. **The result is right.** The files written after each step are
   compared with what they must be.

Keys that read a prompt (M-%, C-s, C-x C-w) are *pasted*, all at once
(the new `paste` step of `tests/pty-keys.c`). Typed one at a time, each
waits 30 ms, and those waits counted in the command's time: a file name
of 70 characters made C-x C-w take 2 seconds of nothing.

```lisp
(scenarios
 (scenario "open-line"
  (file "10 MB of ( on one line, never closed (.scm)")
  (keys "C-M-f and C-M-b at the start and at the end; typing and DEL at both
         ends; C-a, C-e"))
 (scenario "open-lines"
  (file "100,000 lines of 100 ( each (10 MB)")
  (keys "the same, with C-n, C-p, M-<, M->"))
 (scenario "search"
  (file "50 MB of text (880,000 lines)")
  (keys "C-s and C-r of a pattern that fails (4 characters, each a search of
         the whole text); C-s of the last line; M-% of a pattern that is not
         there"))
 (scenario "replace-lines-*"
  (file "100,000 lines, one foo each")
  (keys "M-% foo → barbaz with !, then C-/; the same with foo → x"))
 (scenario "replace-line-*"
  (file "one line of 100,000 foo (1.1 MB)")
  (keys "the same"))
 (scenario "longline"
  (file "one line of 5 MB of minified JSON, with accents and CJK")
  (keys "C-e, C-a, C-f, C-b, M-<, M->, C-n, C-p, three mouse clicks, typing"))
 (scenario "fill-paragraph"
  (file "one paragraph of 50,000 words on one line")
  (keys "M-q, then M-q again on the filled paragraph (5,000 lines)"))
 (scenario "fill-md, fill-org"
  (file "nested lists of 12,000 items, eight levels deep (.md, .org)")
  (keys "M-q on items at the top, the middle and the end")))
```

Checked after the keys: C-s found the last line; M-% with `!` gave exactly
what `sed s/foo/.../g` gives, and said "100000 substitutions"; C-/ gave the
original text back, byte for byte; M-q kept every word, in order, and left
no line longer than 70 columns; M-> reached the end of the long line.

## Not changed, and why

- **C-M-f over 10 MB of unclosed `(`: 1.1 to 1.6 s.** Linear, and under
  the limit, but with less room than the rest. It is the Scheme scanner of
  `emacs-keys.scm`, reading 64 KB blocks; making it faster is making
  Schemer faster, not a change of algorithm.
- **M-q on 50,000 words: 1.3 to 1.9 s.** Linear now, but the closest to the
  limit on this machine: each word is a few Scheme strings and list cells,
  and allocating them is what is left. On a loaded machine it may cross 2
  s; `COMPLEXITY_LIMIT_MS=3000` gives room without hiding a quadratic
  cost, which shows as minutes.
- **The display after an edit in a 10 MB line: about 0.3 s.** Any change
  to the text makes the display forget the long line, and the next display
  scans it once. Keeping the row starts before the change would need the
  position of every change since the last display.
- **Words in long lines.** A line of 64 KB or more is wrapped at the edge
  of the window, even in a text file; the colours of such a line may be
  wrong where they depend on more than 16 KB before the page. Both are
  what Emacs's *so-long* mode does, in a milder form.
- **Marks inside the stretch replaced by `!`** go to its start, since undo
  now sees one deletion and one insertion. Point is where it was: at the
  start of the last replacement.
- **The bridge.** A call across it costs tens of microseconds; most of the
  slow loops above crossed it for every line or byte. The fixes cross it
  less; the bridge itself is unchanged.
- **The Scheme scripts of femtoscheme** got the two fixes of their own
  quadratic loops (undo's accounting, M-q's words), not the speed-ups that
  only matter to the compiled program.

## Summary

The test found five bugs. Four turned linear work into quadratic work or
worse: the display of a long line (seconds a key), M-% with `!` (83 s, and
not undoable), word wrapping of a long line (188 s), and M-q on a long
paragraph (minutes). The fifth, C-s over 50 MB, was linear but slow. All
five are fixed, and every key of every scenario now finishes within 2
seconds on this machine; the slowest are C-M-f over 10 MB and M-q on
50,000 words, both linear. `make check`, the fuzzers and
the endurance tests pass.

```lisp
(summary
 (run "make check-complexity, or sh tests/complexity.sh delimiters (search,
       replace, longline, fill)")
 (time "about a minute and a half")
 (limit "COMPLEXITY_LIMIT_MS (2000)")
 (keep-the-files "COMPLEXITY_KEEP=1")
 (files "tests/complexity.sh; tests/pty-keys.c (paste); src/display.c,
         src/gap.c, src/replace.c, src/search.c, src/undo.c;
         compiled/scripts/undo.scm, compiled/scripts/emacs-keys.scm;
         scheme/undo.scm, scheme/extensions/emacs-keys.scm; makefile"))
```

