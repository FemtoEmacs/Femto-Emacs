# Reports of the four stress tests

21 and 22 November 2026. Written by Claude for Eduardo. One report a task.
Each opens with the task as Eduardo gave it (`paper/test-design/testes.md`),
then lists the bugs that running it found.

```lisp
(tasks
 (task "1. Random-walk fuzzing with sanitizers (UTF-8 and memory corruption)"
  (report "task1-fuzzing.md")
  (bugs-found 6)
  (fixed 6)
  (tests "make check-fuzz-core, make check-fuzz-found (in make check); make
          check-fuzz"))
 (task "2. Long-session RSS and heap leak detection (valgrind / LSan), and
        the 330 MB memory cost"
  (report "task2-long-sessions.md")
  (bugs-found "5 (no leak)")
  (fixed 5)
  (tests "make check-big-edit (in make check); make check-endurance; Lean:
          make -C Lean visit-audit"))
 (task "3. Adversarial algorithmic complexity benchmarks (O(N²) hangs)"
  (report "task3-complexity.md")
  (bugs-found 5)
  (fixed 5)
  (tests "make check-complexity"))
 (task "4. Boundary-crossing shard and clipboard stress"
  (report "task4-boundaries.md")
  (bugs-found 4)
  (fixed 4)
  (tests "quick part in make check; make check-shard-boundary, make
          check-paste-stress")))
```

**20 bugs found, 20 fixed.** Most were found by a test failing, and the
test passes now. A few were found by reading the code while writing a
test (task 2, bug 2; task 4, bugs 3 and 4), and one was slow without
failing (task 3, bug 5, C-s within its limit); each report says which.

Task 2 also has a proof in Lean, `oversized_without_bytes`
(`Lean/undo-visit.lean`, section 5). It shows that the C core loses no
undo when it stops sending a change larger than the undo limit to Scheme:
the history after `'o'` is exactly the one that recording the change and
trimming would have left.

Still open:

- the rerun of task 4's quick test on the Mac, after its UTF-8 check was
  changed from `iconv` to the test's own C program;
- `make -C Lean visit-audit`, to have Lean check the proof (the cloud could
  not download Lean's toolchain).

The earlier reports, `stress-tests.md` (tasks 1 and 2), `complexity.md`
and `boundaries.md`, are in `bkp/`.
