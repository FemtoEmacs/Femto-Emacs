# TTFY verification - 2026-10-17

Fixture: benedetto.pdf, seven PDF pages, printed pages 263-269.

## Automated checks

`make check` and `make check-ui` cover the embedded runtime, existing editor
menus, the new TTFY menu and provider dispatch, guidelines loading, completing
PDF filenames and directory suffixes, and Close-only diagnostic panes.
Offline provider tests render all seven pages, verify seven Codex image
arguments and its read-only sandbox, verify Claude's Read-only tool selection,
exercise page ranges 3-4, and reject missing files/out-of-range pages. Provider
nonzero exits preserve diagnostic paths. Ordinary consultation protocol tests
continue to pass.

## Interactive checks

Terminal: C-x C-f + Tab completed ttfy/benedetto.p to benedetto.pdf;
clicking TTFY opened the provider menu; the PDF picker also completed with
Tab; C-g at the page-range prompt cancelled without changing the document.
A local provider drove an actual conversion through the menu into a modified
Markdown buffer, which was saved with C-x C-s and checked on disk.

Native GUI: Textify menu and provider choices were inspected; the PDF picker
completed the absolute Benedetto filename with Tab. The full live Codex
Markdown was opened and displayed in the editor. GUI and terminal builds and
the app bundle were rebuilt with ttfy.scm and the guidelines included.

## Live conversions

- `benedetto.codex.md`: actual Codex conversion of all seven pages, about
  52 KB, with seven page markers, manuscript sections, references, printed
  tables, a Kaplan-Meier curve table, and image captions. Provider diagnostics
  and the correctly scaled page PNGs: `/tmp/schememax-ttfy-K5l1mB/`.
- `benedetto-page4.claude.md`: actual Claude conversion of PDF page 4 only,
  about 11 KB, labeled PARTIAL, including the Kaplan-Meier table. This is a
  raw AI response; it also contains an unsolicited connector note at the end,
  illustrating why the Markdown remains editable.

The rendered page 4 was visually compared with an independent Poppler render.
This caught and corrected Quartz's refusal to upscale in its page transform:
the bitmap CTM is now explicitly scaled to preserve full-page 144-dpi detail.
The initial stopped run and its diagnostics are retained separately; it is
not the delivered full conversion.

Both live responses identify the figure type and label curve coordinates as
estimates. The plotted numbers at risk were spot-checked against the page:
IACC 35,25,15,8,2,1,1 and SEER 72,45,23,14,8,4,3 at years 0,5,...,30.
The Codex plot section's lines fit the specified 88-character limit and its
record continuation lines use two spaces. Printed-versus-plotted numerical
inconsistencies are retained and identified by the responses.

These are working conversion examples, not a certified full transcription
or reconstructed patient data. Every numeric field in the entire article
has not been independently verified. Plot estimates differ between providers;
review them and retain the PDF as the reference.

## Current limits

Native PDF rendering is macOS-only; other builds report that limitation.
Choose at most 32 pages per request; larger papers require explicit ranges.
A request blocks the editor with a status message for up to 20 minutes.
Results are AI-generated and require human review before downstream use.
