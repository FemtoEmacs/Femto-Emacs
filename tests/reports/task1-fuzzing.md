# Task 1. Random-walk fuzzing with sanitizers (UTF-8 and memory corruption)

21 November 2026. Written by Claude for Eduardo. The numbers come from
runs on Linux (x86-64) in Claude's cloud copy of the repository, at the
state pending on Eduardo's Mac (not yet committed).

## The task

Eduardo's text (`paper/test-design/testes.md`):

> Your current tests run scripted key sequences via pty-keys.c. You should
> add a differential/invariant fuzzer compiled with AddressSanitizer and
> UndefinedBehaviorSanitizer (-fsanitize=address,undefined).
>
> - What it does: Generates thousands of random sequences of mixed-width
>   UTF-8 characters (1-byte ASCII, 2-byte Greek, 3-byte Korean/Chinese,
>   4-byte emoji, plus invalid/truncated UTF-8 sequences and combining
>   marks) interleaved with random editing commands (C-f, C-b, M-f, M-b,
>   C-d, BkSp, C-k, C-w, C-y, C-/, C-M-_, M-q).
> - Invariants checked after every single keystroke:
>   1. No mid-codepoint cursor: the byte offset of point and mark must
>      never land on a UTF-8 continuation byte.
>   2. Undo round-trip identity: pressing C-/ N times must restore the
>      exact byte-for-byte buffer content, and pressing C-M-_ N times must
>      return to the edited state.
>   3. Gap-buffer / line-table consistency: moving to M-> and counting
>      lines backward matches moving from M-< forward.

## Bugs found: six, all fixed

```lisp
(bugs
 (bug 1
  (what "M-b and M-f (C versions) compared pointers into the gap buffer")
  (keys "M-b on accented text")
  (what-it-did "M-b stopped inside a character, or at position −1 when the
                gap was at the start; M-f read past the buffer")
  (fix "The word motions compare positions, not pointers, and stop on the
        first byte of a character (command.c)"))
 (bug 2
  (what "C-f, C-k and M-f at the end of the text read the byte at point")
  (keys "C-k, C-f")
  (what-it-did "One byte read past the allocation (ASan:
                heap-buffer-overflow)")
  (fix "The buffer keeps a 0 byte after its end, a sentinel (gap.c)"))
 (bug 3
  (what "C-d on a file that ends inside a character")
  (keys "11 keys ending in C-d")
  (what-it-did "The gap moved past the end of the buffer")
  (fix "C-d never deletes more bytes than are left (command.c)"))
 (bug 4
  (what "The mark did not move with typing, DEL, C-d or C-y")
  (keys "C-SPC, DEL, a typed \\xff")
  (what-it-did "A typed character could hold the mark inside it; C-w then cut
                half a character (invariant 1 broken)")
  (fix "Every change moves the mark, as in Emacs (record_change, undo.c)"))
 (bug 5
  (what "Another window on the same text guessed its position from the change
         of size")
  (keys "C-y, M->, C-x 2, C-w")
  (what-it-did "The other window's point became −10; after C-w of the whole
                text the display read freed memory (ASan:
                heap-use-after-free)")
  (fix "Every change moves every window's point, mark and page (undo.c); the
        guess in display.c is gone"))
 (bug 6
  (what "Typing a character beyond ASCII did not start a new command for undo")
  (keys "C-x 3, a cut lead byte, C-x o, ω, C-/")
  (what-it-did "After C-x o, undoing ω put the cursor back where it had been
                in the other window, inside a character")
  (fix "Such a character now marks a command boundary for undo (main.c, event
        typed in core.scm)")))
```

Each fix was checked both ways: the shrunk sequence fails on the old code
and passes on the new. Bugs 1 to 4 are replayed by every run of the core
fuzzer; bugs 5 and 6 are fixed tests in `tests/fuzz-found.sh`. Both run in
`make check`.

## What was built

```lisp
(built
 (piece "Core fuzzer"
  (file "tests/fuzz-core.c, tests/fuzz-core.sh")
  (what-it-does "Drives the C core alone (no terminal, no Scheme) under ASan
                 and UBSan"))
 (piece "Check mode"
  (file "src/check.c")
  (what-it-does "With CHEZWEB_CHECK=1 the editor checks its own invariants
                 after every key, before and after the display, and stops at
                 the first one broken"))
 (piece "Editor fuzzer"
  (file "tests/fuzz-editor.sh, tests/fuzz-editor.scm")
  (what-it-does "Types random keys into the whole editor, built with the
                 sanitizers, in a terminal"))
 (piece "Fixed tests"
  (file "tests/fuzz-found.sh")
  (what-it-does "Bugs 5 and 6, as ordinary tests"))
 (piece "Sanitized editor"
  (file "make chezemax-sanitized")
  (what-it-does "The editor built with ASan and UBSan, in build/sanitized/")))
```

**What is typed.** Everything the task asks for: ASCII, Greek, Korean,
Chinese, emoji, combining accents, and bytes that are not UTF-8 (a lone
continuation byte, a cut lead byte, an overlong form, F5, FF). Between
them come the commands of the task (C-f, C-b, M-f, M-b, C-d, DEL, C-k,
C-w, C-y, C-/, C-M-_, M-q), and also C-n, C-p, C-a, C-e, M-<, M->,
C-SPC, M-w, TAB, RET, C-x 2, C-x 3, C-x o, C-x 1 and C-g. The core
fuzzer also folds and narrows text and changes the window width.

**The invariants of the task, and how each is checked.**

1. *No mid-codepoint cursor.* Checked after every key, for point and
   mark, in every buffer and every window (the rule proved in
   `Lean/utf8-cursor.lean`). It applies when the text is well-formed
   UTF-8; in malformed text there is no character to be inside.
2. *Undo round trip.* In the core fuzzer, the changes reported to undo,
   applied backward, give back the earlier text byte for byte, and applied
   forward give the text now. In the editor fuzzer, every 40 keys a
   checkpoint undoes every command since the last one (C-/ N times),
   compares the text, then redoes them all (C-M-_ N times) and compares
   again.
3. *Gap-buffer consistency.* Checked: `b_buf ≤ b_gap ≤ b_egap ≤ b_ebuf`,
   the sentinel after the text, and point, mark and page start inside the
   text. **Not done as written:** the editor keeps no line table (lines
   are counted from the text when needed), so counting lines from M-> and
   from M-< was not added.

Also checked: a fold hides whole characters, and after the display the
cursor is not in hidden text.

**When a walk fails**, its seed replays it. It is replayed in a child
process (so that a sanitizer's abort does not stop the tool), shrunk to
the shortest sequence that still fails, and printed. The editor fuzzer
keeps the keys, the file and the last run in `fuzz-editor-SEED/`.

## Results after the fixes

```lisp
(results
 (run "Core fuzzer, three seeds"
  (size "9,000 walks of 1,000 keys (9 million keys)")
  (result "All passed"))
 (run "Editor fuzzer"
  (size "15 walks of 400 keys, on Markdown, Org, Scheme and text files")
  (result "All passed, 10 undo checkpoints each")))
```

The fuzzers were run again after the later tasks changed `display.c`,
`gap.c`, `replace.c`, `key.c` and `command.c`, and passed each time
(10 walks of the editor fuzzer, and `make check-fuzz-core`).

## How to run

```lisp
(how-to-run
 (command "make check-fuzz-core (in make check)"
  (what-runs "300 walks of 300 keys with seed 1, and the shrunk sequences of
              bugs 1 to 4")
  (time "Seconds"))
 (command "make check-fuzz-found (in make check)"
  (what-runs "Bugs 5 and 6 as fixed tests")
  (time "Under a minute"))
 (command "make check-fuzz"
  (what-runs "5 minutes of the core fuzzer with a new seed, then 10 walks of
              the sanitized editor")
  (time "About 10 minutes")))
```
