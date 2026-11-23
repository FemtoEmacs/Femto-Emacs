# Reports of the four stress tests

## Repeat the experiments on Chezweb 1.16

Start with [Repeating the four stress-test tasks](RUNNING.md). It provides
copyable commands for all four tasks, a complete Linux run, 5,000-buffer
churn, sanitizer prerequisites, fixed seeds, expected output and retained
logs. A successful run on 1.16 is the expected evidence that the repaired
editor meets those workloads. You do not need a buggy version to repeat
the experiments.

| Task | Instructions | Discovery report |
| --- | --- | --- |
| 1. Random-walk fuzzing | [Run task 1](RUNNING.md#task-1-random-walk-fuzzing) | [Six bugs and their fixes](task1-fuzzing.md) |
| 2. Long-session memory and leaks | [Run task 2](RUNNING.md#task-2-long-session-memory-and-leak-detection) | [Memory findings and measurements](task2-long-sessions.md) |
| 3. Algorithmic complexity | [Run task 3](RUNNING.md#task-3-adversarial-algorithmic-complexity) | [Slowdowns and fixes](task3-complexity.md) |
| 4. Shards and clipboard | [Run task 4](RUNNING.md#task-4-shard-boundaries-and-malformed-or-huge-pastes) | [Boundary and paste findings](task4-boundaries.md) |

The reports below preserve the development record. The running guide
explains current commands and distinguishes full experiments from the
shorter tests included in `make check`.

## Original reports

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

Status recorded when these reports were written:

- the rerun of task 4's quick test on the Mac, after its UTF-8 check was
  changed from `iconv` to the test's own C program;
- `make -C Lean visit-audit`, to have Lean check the proof (the cloud could
  not download Lean's toolchain).

**1.16 follow-up:** the Mac quick shard/paste tests subsequently passed in
the [five-platform release validation](https://github.com/FemtoEmacs/Femto-Emacs/actions/runs/45080586617).
The original reports retain their dated observations.

The earlier reports, `stress-tests.md` (tasks 1 and 2), `complexity.md`
and `boundaries.md`, are in `bkp/`.
