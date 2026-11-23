# Repeating the four stress-test tasks

These instructions run the four experiments on Chezweb 1.16. A passing
run is the expected, useful result: the editor has met the correctness,
memory and timing checks for that workload. Repeating the tasks provides
confidence in normal editing, including conditions that short examples
rarely exercise. The [four reports](README.md) describe the bugs the tasks
found and the fixes made while developing 1.16.

## Prepare a source checkout

Use a separate checkout for experiments. An installed editor alone is not
enough: the tests compile their own helpers and an instrumented editor.
Some build targets retain the internal name `chezemax` for the native
editor. From a terminal, obtain the released code:

```sh
git clone --branch v1.16 --single-branch \
  https://github.com/FemtoEmacs/Femto-Emacs.git Chezweb-stress-1.16
cd Chezweb-stress-1.16
make
```

The [source archives](https://github.com/FemtoEmacs/Femto-Emacs/releases/tag/v1.16)
work too: extract one, enter its folder and run `make`. All commands below
run from that folder, not from `tests/reports`. An existing 1.16 checkout
also works. See [Building from sources](../../README.md#building-from-sources)
for the normal build dependencies. No browser rebuild, Python, Node.js,
Valgrind or assistant account is needed for these experiments.

**Linux is the reference platform for the complete sanitizer and leak
experiments.** Install the ordinary build dependencies and use a GCC or
Clang toolchain with AddressSanitizer and UndefinedBehaviorSanitizer
runtimes. The tests add the compiler flags themselves. macOS can run the
ordinary memory tests, fuzzing with available ASan/UBSan support, complexity
and boundary tests; use Linux for the LeakSanitizer commands below. Windows
Cygwin runs a subset of the release checks, but is not the reference
platform for the full long-session leak experiment. Its C heap meter is
unavailable in 1.16.

The scripts create disposable files and temporary home directories. The
clipboard stress tests use stand-in clipboard commands. They do not ask
you to edit your papers or paste real personal data. They do create large
files and run real temporary shells. Allow several minutes for initial
compilation, and tens of minutes or longer for the complete set on a slow
machine. Sanitized runs and reducing a failing fuzz sequence take longer.

## Run all four tasks on Linux

This Bash block stops at the first failure and preserves output in
`stress-logs/`. It includes the proposed 5,000-buffer churn workload in
both ordinary and sanitized runs. Do not run the suites concurrently:
several share generated test programs, and contention changes timings.

```bash
bash <<'SH'
set -euo pipefail
unset ASAN_OPTIONS UBSAN_OPTIONS LSAN_OPTIONS
mkdir -p stress-logs
{
  date -u
  uname -a
  if test -e .git; then
    git rev-parse HEAD
  else
    printf 'Chezweb 1.16 source archive\n'
  fi
  cc --version
} > stress-logs/environment.txt

make
make check-fuzz 2>&1 | tee stress-logs/task1-fuzz.log
make chezemax-sanitized
sh tests/endurance.sh -n 5000 -u 100 2>&1 | tee stress-logs/task2-memory.log
sh tests/endurance.sh -a -n 5000 -u 100 2>&1 | tee stress-logs/task2-memory-sanitized.log
make check-complexity 2>&1 | tee stress-logs/task3-complexity.log
make check-shard-boundary 2>&1 | tee stress-logs/task4-shards.log
make check-paste-stress 2>&1 | tee stress-logs/task4-paste.log
SH
```

The block clears inherited sanitizer options inside its own Bash process
so the scripts use their defaults; your calling shell is unchanged. With
an extracted source archive, also record its filename and checksum. The
tests themselves do not require Git history. To run just one task, use
its commands below after `make`.

## Task 1: random-walk fuzzing

```sh
make check-fuzz
```

This runs the C-core fuzzer for five minutes with a new seed, then ten
walks of 400 keys through the sanitized whole editor. It mixes ASCII,
Greek, Chinese, Korean, emoji, combining accents and malformed UTF-8 with
movement, deletion, kill/yank, undo/redo, filling and window operations.
The C fuzzer checks gap-buffer ranges, character boundaries where defined,
folds and the edit journal. The whole-editor fuzzer checks editor
invariants after each key and does byte-for-byte undo/redo comparisons at
checkpoints every 40 keys.

**AddressSanitizer (ASan)** inserts checks into compiled C code to detect
invalid memory accesses, such as reading beyond an allocation or using
memory after it has been freed. **UndefinedBehaviorSanitizer (UBSan)**
checks selected invalid C operations, such as signed integer overflow,
invalid shifts and misaligned pointer access. A sanitizer report makes the
run fail, even when the displayed text appears correct. The instrumented
build uses `-fsanitize=address,undefined`. See the official
[ASan](https://clang.llvm.org/docs/AddressSanitizer.html) and
[UBSan](https://clang.llvm.org/docs/UndefinedBehaviorSanitizer.html) descriptions.

Check the core fuzzer's banner: `under no sanitizers` means it ran the
invariant checks without compiler instrumentation. Do not count that as a
sanitizer run. The instrumented editor target must build successfully for
whole-editor sanitizer testing. Instrumentation covers C files compiled
with those flags; it does not instrument the prebuilt Wasmtime library or
Scheme/Wasm instructions. The explicit undo and editor checks complement
it.

To repeat chosen sequences with fixed counts rather than a time budget:

```sh
sh tests/fuzz-core.sh -s 12345 -n 3000 -k 1000
make chezemax-sanitized
sh tests/fuzz-editor.sh -s 12345 -n 10 -k 400
```

The editor run uses seeds 12345 through 12354. Add `-f md`, `-f org`,
`-f scm` or `-f txt` to choose a file kind. These example seeds are for
your own repeatable runs, not a claim about the seeds of the historical
measurements. Three core runs of 3,000 walks of 1,000 keys each match the
nine-million-key scale reported in [Task 1](task1-fuzzing.md).

Expect `PASS fuzz-core` and `PASS fuzz-editor`. The latter's ten walks
check 4,000 generated editing keys and 100 undo/redo checkpoints. A failing
walk prints its seed and reduces the sequence. Whole-editor failure files
are kept in `fuzz-editor-SEED/`; keep the printed replay command, log and
source revision. `make check-fuzz-core` and `make check-fuzz-found` provide
shorter runs, including stored regressions for known faults.

## Task 2: long-session memory and leak detection

Run the ordinary experiment first, then the instrumented version on Linux:

```sh
sh tests/endurance.sh -n 5000 -u 100
make chezemax-sanitized
ASAN_OPTIONS=detect_leaks=1:abort_on_error=1 \
  sh tests/endurance.sh -a -n 5000 -u 100
```

Without `-t`, each command runs all four scenarios:

- **churn:** open, edit and kill buffers of several kinds, including
  shards and temporary terminal shells. Check memory growth after warm-up,
  open descriptors, remaining buffers and Scheme tables.
- **flood:** send large streams of text and random bytes through a terminal
  buffer, resize it, switch away and back, then kill it. Check bounded
  memory, throughput and cleanup of descriptors and child processes.
- **undo:** repeatedly insert/delete 1–3 MB chunks, with 20 MB every tenth
  cycle, to exercise both eviction of old undo groups and oversized edits.
- **big:** cut/yank a 21 MB text and paste another program's large clipboard
  contents. Check saved bytes and the amount of memory retained.

**RSS** is the process's resident memory. Freed allocations can remain in
allocator caches, so high RSS alone does not establish a leak. The test
also measures live C heap allocations where supported, descriptors,
buffers and Scheme tables, looking for sustained growth after warm-up.
**LeakSanitizer (LSan)** reports heap allocations that are no longer
reachable and have not been freed. The Linux sanitized run enables leak
detection and requests checks during the experiment. It also uses ASan
and UBSan. [Official LSan description](https://clang.llvm.org/docs/LeakSanitizer.html).
Valgrind is not the implementation used by this suite.

Choose a scenario with `-t churn`, `-t flood`, `-t undo` or `-t big`.
`-n` sets buffer-churn cycles and `-u` sets undo cycles. For example:

```sh
sh tests/endurance.sh -t churn -n 5000
sh tests/endurance.sh -a -t churn -n 2000
sh tests/endurance.sh -a -t undo -u 30
```

These examples also let you repeat the reported 5,000-buffer ordinary,
2,000-buffer sanitized and 30-cycle sanitized undo workloads. For a shorter
complete run, `make check-endurance` uses 1,000 buffer cycles and 100 undo
cycles; `make check-endurance-sanitized` uses 1,000 and 30 respectively.
They still run all four scenarios. A successful run prints `PASS churn`,
`PASS flood`, `PASS undo` and `PASS big`. A `SKIP` for an unavailable meter
is not evidence that the corresponding memory bound was measured.

Use `ENDURANCE_KEEP=1` to retain the temporary work folder; its path is
printed. A failure also copies a meter curve to `endurance-meters.txt` in
the checkout. Save that file before rerunning, since a later failure can
replace it. See [Task 2's report](task2-long-sessions.md) for the budgets
and original measurements.

## Task 3: adversarial algorithmic complexity

```sh
make check-complexity
```

The script generates unclosed delimiters in a 10 MB text, failing searches
in 50 MB, 100,000 replacements, a single 5 MB JSON line, and paragraph/list
refilling with tens of thousands of words or items. It drives real keys
through a pseudo-terminal and measures command plus display time with the
backdoor. The script configures and opens that recorder in its temporary
test home; no assistant connection or manual editor setup is needed. It
also checks resulting text and cursor/display consistency.

The default per-key limit is 2,000 ms, with a separate session timeout for
a command that never finishes. This makes severe slowdowns and hangs
observable failures. To repeat one group:

```sh
sh tests/complexity.sh delimiters
sh tests/complexity.sh search
sh tests/complexity.sh replace
sh tests/complexity.sh longline
sh tests/complexity.sh fill
```

Use `COMPLEXITY_KEEP=1` to retain generated files and logs. Record hardware
and load when comparing timings. If you change `COMPLEXITY_LIMIT_MS` for a
particular machine, report the new limit with the result; it changes the
pass criterion. See [Task 3's report](task3-complexity.md).

## Task 4: shard boundaries and malformed or huge pastes

```sh
make check-shard-boundary
make check-paste-stress
```

The shard suite places multi-byte characters, multi-line s-expressions and
long lines near cuts, edits on both sides, saves, and compares the result
byte for byte. It runs small 4 KB shards and the normal 16 MB boundaries,
including a 35 MB line that spans shards. It checks UTF-8 and navigation;
a command that cannot cross a shard must report that boundary correctly.

The paste suite sends malformed UTF-8, UTF-16 surrogate encodings, embedded
NUL bytes, and large payloads through bracketed paste and a stand-in system
clipboard. It checks that accepted bytes survive, keys after a paste still
work, and oversized bracketed pastes are refused whole. In 1.16 the 16 MB
bracketed-paste limit means a 50 MB bracketed paste must be rejected, while
a 50 MB clipboard paste takes a different path and is tested separately.

Expect a `PASS` for every scenario and a zero command exit status. Use
`SHARD_KEEP=1` or `PASTE_KEEP=1` to retain fixtures and logs. The default
`SHARD_LIMIT_MS` and `PASTE_LIMIT_MS` are each 2,000 ms; record any changes.
`make check-boundaries-quick` runs only the shorter subsets, not this full
fourth task. See [Task 4's report](task4-boundaries.md).

## Keep enough information to repeat a result

Save the complete console log, source revision (or source-archive checksum),
OS/CPU, compiler version, commands and options. Preserve printed fuzz seeds
and failing input folders. Record counts, time limits and sanitizer options
if you override defaults. `PASS` means that the checks held for the stated
experiment; a failure supplies a sequence, measurement or mismatch to
investigate. The reports' historical timings are reference measurements,
not promised runtimes on another machine.

The normal `make check` includes short core-fuzz and stored-regression
runs, the big-edit memory check, and quick shard/paste checks. It does not
run the five-minute/whole-editor fuzz suite, the complete endurance suite,
all complexity scenarios or the full boundary/paste workload. Run the four
tasks above to repeat those experiments, even after `make check` passes.
