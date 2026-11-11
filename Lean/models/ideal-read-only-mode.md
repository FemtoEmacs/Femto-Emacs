# Ideal read-only mode

Proposal recorded: **6 November 2026**.

## Why build this model?

We need an editor that works in a browser.

Repeated Enter presses in READ mode made Chezweb slow, then fail. Early runs
failed after roughly 400 lines. Later failures required another traversal.
One successful trip through a file was not enough.

The repair history records repeated Scheme scans and buffer copies, followed by
a compiler fix for closure cycles retaining buffers under Wasmtime's GC.
Moving correctly once did not establish safe repetition.

Enter must move the cursor, preserve the text, and remain safe to repeat.
Navigation must not accumulate retained memory or increasing work with every
press. Build a model. Prove its laws. Compare Chezweb with its predictions.

## What we will build

Write an executable terminal model in Lean. Start with one buffer, one selected
window, and ordinary Enter in READ mode. Start with no numeric prefix or pending
command. Test the model before connecting it to Chezweb.

Use ordinary text with unequal line lengths. Include empty lines, tabs, Unicode,
wrapped lines, and files with or without a final newline.

## Components

Use S-expressions for structured data: nested lists with named fields.
Ron Rivest and Donald Eastlake describe this representation and its goals of
readability, generality and easy extension in [RFC 9804, section 1](https://www.rfc-editor.org/rfc/rfc9804.html#section-1).

```lisp
(components
  (buffer
    (meaning "Fixed text bytes, size, identity, read-only flag and modified flag."))
  (gap
    (meaning "Unused storage between two text segments. Logical text joins the segments. The gap is not the cursor."))
  (character
    (meaning "A Unicode scalar encoded in one or more UTF-8 bytes."))
  (logical-line
    (meaning "Text between newline boundaries. Its length may vary."))
  (visual-row
    (meaning "The part of a logical line shown on one screen row."))
  (layout-policy
    (meaning "Width, wrapping, tab stops and character display widths."))
  (buffer-cursor
    (meaning "A byte offset at a character boundary or at EOF."))
  (window
    (meaning "A view of the buffer: height, width, viewport and saved cursor fields."))
  (screen-cursor
    (meaning "The row and column calculated from the buffer cursor and viewport."))
  (auxiliary-state
    (meaning "Selection, other editor activity, rendering and resource state.")))
```

A line has no separate mutable cursor. Calculate its cursor column from the
buffer position. Keep byte offsets, character counts and display columns distinct.

Buffer and window cursor fields are separate in Chezweb. Prove their agreement
after synchronization. Calculate screen coordinates from that agreed position.

Make display width explicit. Chezweb's word-wrap policy currently counts a
non-ASCII character as one cell and uses eight-column tab stops. Compare this
policy with what each real terminal displays.

## Keep interference visible

Represent these components as abstract state sets first:

```lisp
(auxiliary-states
  (selection (contains anchor flags selection-mode))
  (environment (contains hooks other-editor-activity))
  (display (contains rendering terminal-activity))
  (resource (contains retained-storage work-counters)))
```

Give auxiliary operations explicit transitions. Let them affect the core state.
Then identify which effects preserve Enter's prediction.

Prove noninterference: an auxiliary operation that preserves text, cursor,
geometry and layout preserves Enter's destination. Its own state may change.

Test whether Chezweb's actual auxiliary operations satisfy those conditions.
Refine a component when a test exposes an important effect.

## One perfect Enter

Define `enter : State → State`.

1. Find the visual row containing the cursor.
2. Find the following visual row.
3. Move to the corresponding column. Clamp to an available cursor position.
4. Move to EOF when no further row remains. Stay there on later presses.
5. Adjust the viewport to show the cursor.
6. Synchronize the selected window and calculate the displayed cursor.

Compute row boundaries in Lean. Handle empty text and final newlines explicitly.
A completed step includes movement and the resulting frame.

## Connection to Chezweb

Enter in READ mode uses the same movement as the down arrow.

```lisp
(connection-to-chezweb
  (receive-the-key
    (functions screen_getch read_key_byte get_key))
  (dispatch-it
    (functions editor_dispatch_key call_lisp_event)
    (description "event handler"))
  (handle-read-mode
    (functions read_mode_event fe_read_key reset))
  (move-down
    (functions down dndn lncolumn))
  (find-rows
    (functions lnstart segstart segnext wrap_row_end))
  (read-across-the-gap
    (functions document_size ptr pos))
  (interpret-characters
    (functions utf8_size screen_cols screen_unctrl))
  (supply-word-wrapping
    (functions wrap_row compiled_wrap markdown-wrap-row markdown-wrap-end markdown-hang-blanks)
    (description "wrap-setting lookup"))
  (reframe-and-synchronize
    (functions update_display display upup b2w w2b))
  (finish-the-frame
    (description "Screen drawing, clearing and refresh operations")))
```

Parenthesis matching, highlighting, selection painting, the mode line and messages
also run around movement. Include their effects in auxiliary transitions and
resource measurements.

## Laws to prove

```lisp
(laws-to-prove
  (gap-representation
    (trust "Logical text remains the same wherever the storage gap lies."))
  (row-partition
    (trust "Layout covers the text in order, without gaps or duplicated ranges."))
  (read-preservation
    (trust "Enter preserves text, size, modified flag, history and clipboard."))
  (exact-destination
    (trust "Enter reaches the prescribed row and clamped column."))
  (unicode-alignment
    (trust "Every resulting byte offset is a character boundary or EOF."))
  (cursor-agreement
    (trust "The selected window and buffer agree after synchronization."))
  (visibility
    (trust "The completed frame places the cursor inside the text area."))
  (progress
    (trust "Before EOF, Enter advances. At EOF, navigation settles and stays."))
  (finite-traversal
    (trust "Repeated Enter reaches EOF within a derived finite bound."))
  (noninterference
    (trust "Auxiliary effects preserving navigation inputs preserve its destination."))
  (repetition-bound
    (trust "Retained memory stays within a file/layout-dependent bound; per-step work does not grow with the number of earlier presses.")))
```

Prove preservation for any finite sequence after proving one step. For the
resource law, account for temporary allocations as well as retained storage.

## Increase trust one law at a time

The present progress check detects a stuck cursor. Exact destination adds more:
it detects skipped visual rows, wrong columns and wrong clamping.

For each law, record three things:

1. Which failures does it rule out in the model?
2. Which Chezweb observations agree with its predictions?
3. Which next law would detect another failure class?

Report coverage by behavior and test cases. Measure agreement. Find and retain
counterexamples. Use them to improve the model or fix Chezweb.

## First experiments

Run Enter repeatedly inside the Lean model. Vary text, widths, heights, cursor
positions and gap positions. Check each predicted destination and final state.

Then run the same cases in Chezweb. Observe the cursor, viewport, text and resource
use after each completed step. Compare them with Lean. Include repeated full-file
traversals and mode switches: these exposed failures that one traversal missed.

Keep reports bounded. Check a batch, retain its verified count, then reuse its
storage. Keep a small failure example when predictions and observations differ.

## Dated evidence

```lisp
(dated-evidence
  (record
    (date "5 November 2026, 09:05 -03:00")
    (finding "Commit f9ff721 moved READ navigation into C, removing repeated Scheme line scans and buffer copies.")
    (source "https://github.com/FemtoEmacs/Femto-Emacs/commit/f9ff7214cc950c2f7de7b80a7c712da30c8cc927"))
  (record
    (date "5 November 2026, 11:11 -03:00")
    (finding "Commit 4c38408 removed closure cycles that retained bytevectors under Wasmtime's deferred reference counting. It added allocation and repeated-traversal tests.")
    (source "https://github.com/FemtoEmacs/Femto-Emacs/commit/4c38408ec3521bc517feb171b99dca9711d4ece1"))
  (record
    (date "6 November 2026")
    (finding "The preserved native log records 100,000 allocations, READ/Vim navigation through 1,829 lines, and four wrapped-file traversals in one process."))
  (record
    (date "6 November 2026")
    (finding "The preserved Chrome log records READ/Vim navigation through 1,829 lines and four traversals in one page.")))
```

The user's earlier screenshots show Emacs navigation reaching line 1,829,
then READ failures at lines 446 and 502. A later screenshot shows a failure at
line 1,113. The accompanying reports describe failures after repeated navigation.
Their exact capture dates were not recorded. The screenshots are in the project
discussion; their original clipboard files are no longer in the local directory.

Keep the records with the model:

- [Repair history and source hashes](evidence/2026-11-06-navigation-record.txt).
- [Native regression log](evidence/2026-11-06-native-check.log).
- [Chrome regression log](evidence/2026-11-06-browser-check.log).

These passing runs document the repaired behavior. The screenshots document the
reported failure. Preserve both when evaluating the model.

## Reference

Ron Rivest and Donald Eastlake 3rd. *Simple Public Key Infrastructure (SPKI)
S-Expressions*. RFC 9804, June 2025.
[Specification](https://www.rfc-editor.org/rfc/rfc9804.html).
Section 1.3 traces this specification to Rivest's proposal of 4 May 1997.
