# Task 2. Long-session RSS and heap leak detection (valgrind / LSan)

21 and 22 November 2026. Written by Claude for Eduardo. The numbers come
from runs on Linux (x86-64) in Claude's cloud copy of the repository, at
the state pending on Eduardo's Mac (not yet committed), except where a
Mac run is named.

## The task

Eduardo's text (`paper/test-design/testes.md`):

> run-gc-allocation.sh checks Scheme GC allocation, but C-side leaks across
> buffer lifecycles, libvterm, and SDL2/ncurses redraws often slip past
> short tests.
>
> - Buffer Churn Test: Open and kill (C-x k) 5,000 buffers—including
>   Markdown, Org, Lisp, sharded files, and M-x term shells—in a single
>   session, then assert that Resident Set Size (RSS) plateaus rather than
>   growing linearly.
> - Undo-Ring Eviction Leak Test: Repeatedly insert and delete 20 MB
>   chunks in a single buffer (exceeding the 8 MB *undo-limit*) to verify
>   that evicted undo records actually free their C heap allocations and
>   Scheme references.
> - Terminal Flood Test (M-x term): Run yes or cat /dev/urandom | base64
>   inside M-x term for 10 seconds, switch buffers, resize the terminal
>   (SIGWINCH), and kill the *terminal* buffer to catch libvterm
>   scrollback leaks or resize crashes.

Then: "I want you to look into the large memory cost (330 MB)" that the
undo test showed.

## Bugs found: five, all fixed

```lisp
(bugs
 (bug 1
  (what "put_text (terminal.c) called memcpy from a NULL pointer when it
         emptied the buffer")
  (found-by "The sanitized churn stopped at the first M-x term (UBSan)")
  (what-it-did "Undefined behaviour at every terminal that cleared its text")
  (fix "The copy is skipped when there is nothing to copy"))
 (bug 2
  (what "The shell's output changed the buffer without telling the rest of
         the editor")
  (found-by "Reading put_text after bug 1")
  (what-it-did "Another window on a terminal, its page and its folds did not
                follow the shell's text")
  (fix "It goes through record_change_unreported, like every other edit"))
 (bug 3
  (what "Undo copied a change it could never keep")
  (found-by "The undo test: a 20 MB chunk raised RSS by 330 MB, for good")
  (what-it-did "A change larger than *undo-limit* (8 MB) was still sent to
                undo.scm as a bytevector (four bytes a byte in the compiled
                program), only to be dropped by trim-history")
  (fix "The scripts tell the C core the limit; a larger change is reported as
        'o', without its bytes, and forget-oversized leaves the history that
        recording it would have left (undo.c, undo.scm). Proved in Lean,
        below"))
 (bug 4
  (what "The kill ring copied a kill it would never keep")
  (found-by "The new big-edit test: C-w of 21 MB raised RSS by 231 MB, for
             good")
  (what-it-did "Every C-w went to Scheme as a string (four bytes a
                character), and push-kill then dropped anything over 1 MB")
  (fix "remember-kill asks the size first (fe-scrap-length) and takes nothing
        the kill ring would not keep; C-y still inserts the cut from C's own
        copy"))
 (bug 5
  (what "C-y read the editor's own cut back from the system clipboard")
  (found-by "make check on Eduardo's Mac (the cloud has no clipboard tool): C
             heap +53.5 MB, RSS +324 MB")
  (what-it-did "C-w gave 21 MB to pbcopy; C-y read them back with pbpaste
                into C and into Scheme, took them for another program's copy,
                and copied them again")
  (fix "The terminal compares the clipboard with the text C-y inserts while
        it reads, and copies nothing when they are the same; another
        program's text too large for the kill ring goes to C-y in C, without
        Scheme (term.c, interface.c, core.scm)")))
```

**No leak was found.** To be sure that the churn could see one, a leak was
injected (one `free` removed from `delete_buffer`): the test reported
+2.2 KB a cycle and failed.

## The proof in Lean: `oversized_without_bytes`

Fix 3 changes what the C core tells undo: for a change larger than the
limit, it sends `'o'` and no bytes. That saves the copies, but is any
undo lost? `Lean/undo-visit.lean`, section 5, answers that no undo is
lost.

The model. A history is a list of groups, each counted by its size in
bytes, the newest first. `trim limit n h` is what `trim-history` does,
at most `n` times: while the sizes add up to more than the limit, drop the
oldest group. Recording a group of `g` bytes means trimming `g :: rest`.
What `forget-oversized` does to the sizes is `forgetOversized`: it
returns the empty history.

```lean
/-- What undo.scm does on 'o', for the sizes alone: nothing is left. -/
def forgetOversized (_rest : List Nat) : List Nat := []

theorem oversized_without_bytes (limit g : Nat) (hg : g > limit) (n : Nat)
    (rest : List Nat) (hn : rest.length < n) :
    forgetOversized rest = trim limit n (g :: rest) := by
  rw [trim_oversized limit g hg n rest hn]; rfl
```

In words: whatever the history was, for any change of `g` bytes with
`g > limit`, the history after `'o'` is exactly the history that
recording the change and trimming would have given. Both are empty. So not
sending the bytes loses nothing that undo could have kept.

The proof rests on `trim_oversized`, proved in section 4 of the same file
by induction on `n`. A group larger than the limit sends every older group
away, oldest first, and then itself: nothing is left. `trim_oversized`
explained why C-x i of a file larger than the limit is refused before
anything is copied. `oversized_without_bytes` extends that argument from
C-x i to every change: cuts, yanks and pastes.

What the proof does and does not cover. It is a model of the sizes: it
says what is left in the history, not that `undo.scm` implements `trim`
faithfully. The code was checked against the model by tests
(`tests/history-limits.sh`, `tests/endurance.sh -t undo` and `-t big`).
`undo.scm` also refuses to record the rest of that command, as recording
did, since the oldest group dropped was the command's own. **To check the
proof:** `make -C Lean visit-audit`. It compiles the file and prints the
axioms each theorem rests on. It was not run here: the cloud cannot
download Lean's toolchain.

## What was built

```lisp
(built
 (piece "Meters"
  (file "src/meters.c")
  (what-it-does "The live C heap (exact under ASan), RSS, open descriptors,
                 buffers, windows, bytes from the shells; fe-meter,
                 fe-meter-note; a line of meters every CHEZWEB_METERS_MS;
                 fe-leak-check asks LSan in the middle of a run"))
 (piece "Scenarios"
  (file "tests/endurance.sh, tests/endurance.scm")
  (what-it-does "churn, flood, undo, big"))
 (piece "Terminal resize"
  (file "tests/pty-keys.c, resize ROWS COLS")
  (what-it-does "A real SIGWINCH")))
```

**Why RSS alone is not enough.** The C allocator keeps freed pages, and the
compiled program's heap grows and never shrinks, so RSS can rise to a
high-water mark with no leak at all. Under ASan, RSS also holds the
quarantine of freed memory. The tests therefore read several meters and
judge a slope: what keeps growing with the work, after a warm-up.

**valgrind was not used.** It does not run on Apple Silicon, and on Linux
it is very slow with Wasmtime's compiled code. The sanitizers (LSan with
ASan) and the meters cover the same ground.

```lisp
(scenarios
 (scenario "churn"
  (task-test "Buffer churn")
  (what-it-does "5,000 files opened, shown, used and closed with C-x k in one
                 session: Markdown, Org with a fold, Scheme narrowed, text in
                 read mode, a big file in shards, a second window, and an M-x
                 term shell every 25")
  (pass-rule "C heap grows by at most 64 bytes a cycle, RSS by at most 4 KB;
              descriptors and buffers come back; no Scheme table grows; LSan
              finds nothing"))
 (scenario "flood"
  (task-test "Terminal flood")
  (what-it-does "Three rounds: yes (3 million lines); base64 of 20 MB of
                 random bytes while the terminal is resized three times; C-c
                 b to another buffer and back; 4 MB of raw random bytes; the
                 terminal killed")
  (pass-rule "Heap bounded during the flood; the third round leaves no more
              than the second; no descriptor or process left"))
 (scenario "undo"
  (task-test "Undo eviction")
  (what-it-does "100 cycles of 1 to 3 MB inserted and deleted, so undo drops
                 its oldest history again and again; 20 MB every tenth cycle;
                 undos and redos")
  (pass-rule "History stays under *undo-limit*; C heap and RSS flat over the
              second half"))
 (scenario "big"
  (task-test "(after bug 4)")
  (what-it-does "C-w, C-y and C-/ of 21 MB; C-y of 21 MB another program
                 copied; C-y of a few words; the clipboard a stand-in")
  (pass-rule "The text comes back byte for byte; memory rises by the copies C
              keeps, no more")))
```

**A difference from the task.** The undo test inserts 1 to 3 MB a cycle,
with 20 MB every tenth cycle, not 20 MB every time. Small chunks make undo
drop old groups one by one, which is where a leak of evicted records would
show. A 20 MB chunk is larger than the limit, so the whole history is
dropped at once.

## Results

```lisp
(results
 (scenario "churn"
  (ordinary-build "5,000 cycles in 38 s; C heap −0.2 bytes a cycle; RSS flat
                   at 54 MB; descriptors 6 → 6; buffers 1 → 1")
  (sanitized-build "2,000 cycles: C heap +0.8 bytes a cycle; LSan found
                    nothing"))
 (scenario "flood"
  (ordinary-build "115 MB from the shells; C heap 6.1 MB before, 11.2 at the
                   peak, 7.9 / 8.1 / 8.1 MB after the three kills; no process
                   left")
  (sanitized-build "Same shape; nothing for the sanitizers"))
 (scenario "undo"
  (ordinary-build "History at most 8.0 MB; flat over the second half; the
                   first 20 MB chunk raised RSS by 332 MB before fix 3, 152
                   MB after it, 100 MB with packed bytevectors (below)")
  (sanitized-build "Passed (30 cycles)"))
 (scenario "big"
  (ordinary-build "C-w of 21 MB: +231 MB before fix 4, +22 MB after; on the
                   Mac, +324 MB before fix 5")
  (sanitized-build "—")))
```

## Not changed here, and why

- **Four bytes a byte in the compiled program.** Schemer stored a
  bytevector as an array of references to small integers, and a string as
  an array of 32-bit code points. On Eduardo's decision, bytevectors are
  now packed, one byte a byte (a prototype, waiting for its own commit;
  `schemer/README.md`). Strings stay as they are, so that `string-ref`
  stays fast.
- **The first M-: of a session** adds about 48 MB, probably the compiler
  starting up. It is paid once.

## How to run

```lisp
(how-to-run
 (command "make check-big-edit (in make check)"
  (what-runs "big")
  (time "Seconds"))
 (command "make check-endurance"
  (what-runs "churn (1,000 cycles), flood, undo, big")
  (time "A few minutes; the first run compiles the scenarios into the editor
         (3 minutes)"))
 (command "make check-endurance-sanitized"
  (what-runs "The same under the sanitizers (Linux, for LSan)")
  (time "About 15 minutes"))
 (command "sh tests/endurance.sh -t churn -n 5000"
  (what-runs "One scenario, any size")
  (time "—"))
 (command "make -C Lean visit-audit"
  (what-runs "The Lean proofs of undo-visit.lean, with their axioms")
  (time "Seconds")))
```

A failing run keeps its curve of meters in `endurance-meters.txt`, which
git ignores.
