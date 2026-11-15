# What the manual tests should leave behind

This file is for whoever checks a manual test: a maintainer, or the AI
(Claude, Codex) on the tester's machine. The tester sends, or leaves in
`~/chezweb-tests` (`~/chezweb-testes` for the Portuguese scripts):

- `backdoor-natbrowser.txt` and `backdoor-vsplit.txt`: copies of
  `~/.chezemax/backdoor.txt`, one for each script;
- the test files: `natbrowser-test.md`, `natbrowser-copy.md`,
  `#natbrowser-test.md#`, `vsplit-test.md` and `vsplit-test.c`.

Compare them with what follows, step by step. Report each step as
passed or failed, quoting the lines that decide it. A step with no
evidence either way (keys typed in Chrome are not recorded) is reported
as "not shown in the record", never as passed.

## Reading the record

AGENTS.md ("The backdoor") explains the format; in short:

- The header gives the date, the options read from
  `~/.chezemax/backdoor-claude.conf`, the front end and the screen size.
  If the options say `(no backdoor.conf: the defaults)` or `lines 120`,
  the configuration was not copied, and the record may have lost its
  beginning.
- One line per key: `#N KEY pt= page= cur=ROW,COL size= BUFFER`. Buffer
  names are cut at 16 characters: `natbrowser-test.md` shows as
  `natbrowser-test.`, and `#natbrowser-test.md#` as `#natbrowser-test`.
  Keys typed inside a prompt (a file name after C-x C-f) are not
  recorded; their numbers are skipped.
- Indented lines under a key say what changed and who changed it.
- The tester's notes appear as `note: PASSO 3 ok` (or `STEP 3 ok`).
  A note that is not "ok" describes a failure in the tester's words:
  report it.
- Lines starting with `chezweb:` are saves between the browser and the
  native window (src/browser-save.h, src/browser-launch.c). They appear
  under the key the native window was handling, or alone.

## natbrowser-interaction.org: one rule for saving

The rule: C-x C-s in either window saves the file and puts its text in
the other window; unsaved edits there go to `#natbrowser-test.md#`.

| Step | Passes when the record has | Fails when |
|---|---|---|
| 0 | `#1 C-c d ... natbrowser-test.` | no C-c d; options not read |
| 1 | `chezweb: browser C-x C-s, N bytes: 200 Saved .../natbrowser-test.md` | no 200; any 409 or 500 |
| 2 | a key `C-x C-s ... natbrowser-test.`, then `chezweb: native C-x C-s of natbrowser-test., N bytes, sent to the browser (version V)` | the native save is not "sent to the browser" |
| 3 | `chezweb: browser C-x C-s ...: 200 Saved ...; previous native edits saved in #natbrowser-test.md#.`; then `C-x C-f ... #natbrowser-test`; then a `C-x k` line whose buffer is `natbrowser-test.` | the save message lacks the recovery file; C-x k shows `*backdoor*` or any other buffer |
| 4 | `chezweb: native C-x C-s of ...sent to the browser`, then `chezweb: browser recovery request, N bytes: 200 Previous browser edits saved in the recovery file.`; C-x k back to `natbrowser-test.` | no recovery request (the browser's B4 would be lost) |
| 5 | `C-x C-q`, then `chezweb: browser C-x C-s ...: 409 Not saved: the native buffer of ... is read-only`; `C-x C-q` again, then `200 Saved` | a 200 between the two C-x C-q |
| 6 | a `C-x k` line whose buffer is `*scratch*`; then `C-x C-f ... natbrowser-test.`; a browser `200 Saved`; a native save `sent to the browser` | C-x k shows `*backdoor*`; the browser save after C-x C-f does not reach the reopened buffer |
| 7 | `C-x C-w ... natbrowser-copy.`; a browser `200 Saved .../natbrowser-test.md` (the original file, not the copy); `C-x C-f ... natbrowser-test.`; a native save `sent to the browser` | the browser saves the copy |
| 8 | a `C-x C-f` (the prompt), then one browser `200 Saved`: at once after the prompt closed (C-g within about ten seconds), or after the tester saved again (a save that timed out leaves no line) | a `200 Saved` while the prompt was open |
| 9 | `chezweb: browser save into a granted folder, N bytes: Saved from the browser; this buffer has the text, and the native edits are in #natbrowser-test.md#.`; a final `C-x C-b` whose list (on screen) has no `*web-1*` | a conflict buffer `*web-N*` appears anywhere |
| 10 | the last line `backdoor closed` | |

The test files, at the end:

- `natbrowser-test.md`, second line: `B1 N2 B3 N4 B5 B6 N6 B7 N7 B8 B9`, in
  that order (each step types at the end of that line). N3, B4 and N9
  are absent; B5 and B8 appear once.
- `natbrowser-copy.md` (made in step 7): the same line up to N6, with no
  B7.
- `#natbrowser-test.md#`: the text that the last displacement replaced:
  the line up to B8, then N9.

If the testers typed at another place (an earlier version of the
script said the start of the file), the tokens are in another order:
check which are present and absent, not the order.

## vsplit.md: the side-by-side split (C-x 3)

Here the record carries most of the evidence; the tester's notes carry
the rest (a vanished cursor is noted as `note: PASSO n cursor sumiu` or
`note: STEP n cursor lost`).

| Step | Passes when the record has | Fails when |
|---|---|---|
| 2-3 | the C-n before C-x 3 and the `C-x 3 ... (left pane, from column 0)` line show the same `page=` and the same `cur=` row (3); no `page A -> B` line under C-x 3 | the page changes at C-x 3, or `cur=` jumps to the bottom row |
| 4-14 | key lines end in `(right pane, from column C)`, C about half the screen's columns (the header gives them); after `C-f` over Korean, `pt=` grows by 3 and the `cur=` column by 2 | a `cur=` column at or past the pane's width; notes of a lost cursor |
| 15-18 | `mouse press 1 at R,C` lines name the pane clicked; in the right pane, the `cur=` column is C minus the pane's first column | a click that lands in the other pane |
| 19-21 | the same buffer (`vsplit-test.c`) in both panes; XYZ typed once (`size=` grows by 3) | |
| 22-27 | lines `terminal *terminal*: drawn, its cursor at row r, column c` and `shown: the cursor at screen row ..., in *terminal*`; C-c o and C-x o switch panes | notes of a lost cursor (in particular at the y/n question, step 25) |
| 28 | a `C-x 2` line; the refusal itself is on the screen, not in the record | a note says the window split |
| 29 | `resize` lines; under them `reframe` or `display` notes are normal | notes of a lost cursor |
| 30-33 | `C-x 0`, then lines without the pane suffix (one window); then the suffix again after C-x 3 | |
| 34-35 | `backdoor closed` | |

`vsplit-test.md` and `vsplit-test.c` change freely in this test; they
prove nothing.
