# Run an existing text through a Lean test protocol

1. Open `Lean/rdonly-tester.lean` in native Chezweb.
2. Edit its commented `TestSettings` section.
3. Invoke **M-x chez-tester** and choose the text file at the filename prompt.

The current Lean buffer supplies the protocol, including unsaved edits. The
selected file supplies the text. There is no launcher script or save/build step.
Lean 4.30.0 must be available as `lean` on PATH. `M-x run-tester` is an alias.
Ordinary editor builds do not require Lean.

The filename prompt supports completion, spaces, Unicode and `~/`. Its initial
default is the existing `docs/chezemax.md` in this checkout (`docs/chezweb.md`
is absent). Any existing UTF-8 text file within the configured size limit can
be selected. Text is read from disk; unsaved changes in another editor buffer
are not included automatically.

## Settings in the Lean buffer

```lean
def mode : Mode := .alternating  -- also .readOnly or .vim
def passes : Nat := 4
def maxEnterPressesPerPass : Nat := 10000
def maxInputBytes : Nat := 1024 * 1024
def delayMilliseconds : Nat := 10
def keepReference : Bool := false
```

These are Lean expressions, not text parsed by C. Lean checks the source and
proofs, evaluates the settings, reads the selected text and gives C its plan.
For example, `passes := 1 + 1` runs two traversals. Alternating begins in
copy-only Vim and then uses READ. Each pass starts at the beginning, presses
Enter until EOF, then presses Enter eight more times to test EOF stability.
The safety limit fails the run if stable EOF is not reached in time.

The document appears in a disposable `*ct0000*` buffer (or the next unused
name). A private snapshot retains the chosen file's extension, enabling the
normal language and default wrapping/highlighting callbacks. Existing per-file
wrap overrides keyed to the original pathname are not copied. The original
file is never associated with the test buffer and is never saved or changed.
The Lean source buffer, cursor and selection are restored afterward. The
clipboard is untouched. Escape/C-g or changing geometry cancels the test.

Native macOS terminal and SDL GUI adapters are implemented. Browser and Windows
adapters are not implemented by this harness.

## What is checked

For every reset/Enter observation, Lean checks:

- The expected mode and read-only protection, with no observed runtime error.
- Exact preservation of the snapshot bytes, reported by the C observer.
- Position within the chosen text; logical line number computed independently
  from the file's newline offsets.
- Reset at byte zero; subsequent Enter makes forward progress until EOF,
  cannot skip a logical line, and stays at EOF once there.
- All requested traversals finish with eight stable EOF presses, with no missing
  or duplicate observation indices and no unacknowledged batch at completion.

Wrapped visual rows can share a logical line number. This profile does not
formally predict each exact visual-row byte offset; it can miss incorrect
forward movement within the same logical line. It checks progress, logical line
accounting, protection and completion, rather than claiming a verified wrapping
implementation. Copy/paste/undo profiles remain future work.

## Bounded output

Only three managed report files are used, with these maximum payload sizes:

| File | Limit | Meaning |
|---|---:|---|
| `Lean/results/pending.trace` | 8 KiB | Current unacknowledged window |
| `Lean/results/failure.trace` | 8 KiB | Diagnostic window on failure |
| `Lean/results/summary.txt` | 4 KiB | Outcome, filename, counters and scope |

Total report payload is at most **20 KiB**, independent of test duration and
repeated runs. Directory metadata/build products are outside this accounting.
The C writer guards every write. Lean acknowledges batches of at most 62
observations; only a matching acknowledgment permits recycling the pending
window. Success normally leaves both traces empty. A short summary is an
operational receipt, not an independently replayable proof of erased history.
A failing window preserves recent context, not a complete run or a restart
certificate. Starting a new run always starts checking at sequence zero.

A zero-byte exclusive lock prevents overlapping writers; a stale lock needs
review after a crash. Symlinks, hard-linked reports and unsafe directories are
refused. The selected text and visited protocol file are also protected from
truncation if either has a managed report filename. Checker communication has fixed deadlines; a silent checker cannot
make the log grow. A hard editor/process hang requires external termination
and cannot produce a completed PASS.

Temporary inputs are separate from reports: the current Lean source snapshot
is capped at 256 KiB; the document snapshot uses `maxInputBytes` (default 1 MiB,
configurable up to 64 MiB). Both are deleted after completion or handled failure.
A process crash can leave these bounded inputs in `/tmp/chez-tester-source.*`.
No trace grows alongside the input snapshot.

### Tiny replayable run

For a small text and one pass, set `keepReference := true`. The complete run
must fit **60 observations**; exceeding that limit fails without claiming PASS.
The existing pending-file slot retains the full protocol, so the report budget
stays 20 KiB. Replay it against the original text:

```sh
lean --run Lean/rdonly-tester.lean --check-file /path/to/text.txt < Lean/results/pending.trace
```

Replay uses the trace's bounded settings and checks against the supplied bytes.
It does not require changing the settings at the top of the Lean source.
The byte observer and honest association with the original run remain trusted.
`examples/native-file.trace` and `examples/native-file.txt` provide a tiny
captured example for reviewers to replay with `--check-file`.

## Proofs and trust boundary

The file contains pure models, executable predicates and kernel-checked proofs.
For the chosen-file profile, `text_step_sound`, `text_line_sound`, `text_progress`,
`text_feed_pending_bound`, `text_pass_requires_eof` and
`text_complete_not_prefix` establish the stated per-step, EOF/pass, counter and
completion properties of the pure checker. Shared reservation/encoding proofs
bound the reporting model to 20 KiB and require acknowledgment before reuse.
The historical fixed-width protocol and its composition/completion proofs
remain for tiny independent regression examples; it is not the public workflow.

There are no proof placeholders or new application axioms. The audit reports
Lean's standard `propext`, `Quot.sound`, and where used `Classical.choice`.
C, byte collection, file/index preparation, the pure-to-IO adapter/parser,
compiler/runtime, OS and storage remain trusted. This is not a formal C-to-Lean
refinement proof or a proof of the whole editor. A lying observer or modified
protocol can manufacture an accepted report. Reviewers should audit the actual
Lean source used for their run.

## Development checks

```sh
make check-lean          # proofs, axiom audit, corrupted/truncated protocol
make check-lean-native   # real keyboard decoder/dispatcher, chosen files, quotas
```

Native checks use disposable text/source files and mocked failed/stalled
checkers. They test chosen READ/Vim/alternating files, wrapping, UTF-8, CRLF,
empty and unterminated files, unsaved Lean expressions/errors, filename defaults,
actual documentation traversal, input/step bounds, replay and corrupt traces.
The optional `make lean-checker` builds a standalone checker used by these
regressions; it is not needed by `M-x chez-tester`.

Ordinary `make`, `make check`, `make check-ui`, and `make check-selfhost` remain
independent of Lean. No live assistant providers or user document saves are
used by these tests.

## Seeded move/copy/move/paste/undo experiment

Open `mv-cp-mv-paste-undo.lean`, set the seed/repetitions/delay, and run
`M-x chez-tester`. Choose a Markdown file or a directory such as
`~/mysand/chezmoi/docs`. Directory scans are sorted and nonrecursive, with at
most 64 files. Inputs must be nonempty UTF-8 texts; an empty selected file
fails before editing because there is no region to copy. Snapshots have the
per-file and total budgets shown in Lean (defaults 1 MiB and 8 MiB).

The experiment runs in ordinary editable Emacs mode, on private Markdown copies.
Each cycle chooses a logical line and character column, then a forward region
of 1..200 Unicode scalar values (at most 800 UTF-8 bytes), and a new destination.
Line jumps use the editor's `M-g` key path and columns use its counted native
forward-character primitive, equivalent to repeated C-f. C-SPC, M-w, C-y,
Control-slash/C-_, and M-< use the actual key decoder and dispatcher. Rendering
runs at each visible stage. The copy and pasted image are compared byte for
byte, followed by an exact original-image comparison after undo, the unmodified
flag, and cursor zero after M-<. Every random movement also checks the editor's
logical line number against the original bytes.

The model proves bounded character/byte positions, region length, paste/undo
identity, and preservation for **any finite schedule**, including varying
random destinations/selections. It does not prove the C editor's implementation
or universal freedom from GC faults. The C observer, native motion primitives,
Scheme history observations, Lean IO adapter and runtimes remain trusted.
Actual repeated runs check the implementation against that model. Lean runs
via `lean --run`; this protocol is interpreted, not transpiled to C.

Editor-wide default retention policies are enforced in both Scheme runtimes:

| History | Limit |
|---|---|
| Kill ring | 60 entries, 4 MiB total, 1 MiB per entry |
| Undo + redo, per buffer | 8 MiB payload, 200 groups, 10,000 change records |

An oversized kill remains on the clipboard for C-y but is not retained in the
kill ring. Text is never silently truncated to fit. Oversized undo groups are
forgotten completely; subsequent acts of that same command are not retained
as a misleading partial undo. Eviction invalidates an unreachable saved
boundary. Redo disposal subtracts its bytes, so the accounting measures live
payload rather than cumulative allocation.

The experiment isolates the user's ring/clipboard once at run start and restores
them at the end; system clipboard export/import is disabled during the run.
**It never clears the ring or undo history between cycles.** The ring must
remain bounded, done must return to zero, redo must contain the one just-undone
paste, and counted/live undo bytes must agree with the selected payload.
Deleting each test buffer must return the history map to its prior size. The
restored user's ring and current history are also checked against the policy
ceilings before PASS. Existing user history is preserved subject to the new
retention caps; originals and the open Lean buffer are never saved.

The same three report slots and 20 KiB bound are used. An edit cycle has a
bounded E command and R observation. Only a matching ACK permits erasure.
Reports include seed (in the H 3 diagnostic header), file/cycle counts,
ring/undo payload peaks and cleanup status. A failed or interrupted prefix
cannot claim success; a small summary is not a standalone replay certificate.

`make check-history` tests both runtimes' eviction/accounting policies inside
the owning Scheme module. `make check-lean-edit` checks proofs, corrupt
observations and real key-driven edit cycles in both runtimes.
