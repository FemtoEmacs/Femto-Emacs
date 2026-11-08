# November -- 2026

## November 07, 2026. Complaint 1

I copied about fifty lines from the Internet and inserted them into a buffer with C-y. I edited the copy. Then I inserted more lines from the clipboard with C-y. The second insertion was very slow (one line per second).  The second copy has a list of four items. Two false entries were added to the list (not registered in the figures below).

![Before typing](nov2026-figs/nov-07-2026-fig01.png)
![After typing](nov2026-figs/nov-07-2026-fig02.png)

Screenshot 1 shows the cursor at the beginning of an edit. After I type a few characters, the window scrolls and the cursor jumps to the last line. I repeated the experiment many times. I didn't close the window because you may have trouble reproducing the bug. In that case, you can try reproducing it in my open file.

### Investigation and repair

We separated two symptoms: a cursor jump while typing and a slow paste that
changed list numbering. Turning word wrap off did not stop the jump. The saved
file reproduced it in another terminal, without another clipboard operation.
It also reproduced in the GUI. The decisive input was `ã`; ordinary letters
were not the trigger.

Two UTF-8 defects were found. Unwrapped navigation could put point between the
two bytes of `ã`. Also, keyboard input inserted its bytes in separate editor
turns. Redisplay could therefore see an unfinished character and reframe the
window, moving the visible cursor toward the bottom. This was an input and
cursor-boundary problem; we found no evidence of a garbage-collector failure.

`src/display.c` now keeps unwrapped movement and mouse placement on character
boundaries. `src/key.c` collects a complete UTF-8 character before returning
it. `src/command.c` inserts or overwrites that character before redisplay.
Malformed input gives unrelated lookahead back to the key reader. A continuation
byte cannot become the editor's synthetic resize key.

Evidence: Eduardo confirmed that typing `ã` in a freshly launched GUI no longer
moved the window. `tests/unwrapped-navigation.c` checks 240 navigation cases.
`tests/utf8-input.c` checks complete-character insertion, overwrite and lookahead.
`tests/utf8-typing.sh` types `ã` through a real pseudo-terminal and checks both
saved bytes and the centred viewport. The fixes were committed as `c305b53` on
7 November 2026.

After the cursor repair, Eduardo could no longer reproduce the original C-y
slowdown. His working explanation is that it was a consequence of the cursor
error. We close that complaint on this basis and do not pursue it further.
Complaint 3 concerns the separate terminal ⌘-V path.

## November 07, 2026. Complaint 2
Cursor is jumping. Screenshot 1 -- Cursor at the end of the buffer. Screenshot 2 -- I press Enter two or more times to introduce a few blank lines; the cursor shouldn't move down, but it advances a few columns. Screenshot 3 -- I click the up arrow or click the line above the displaced cursor; it goes to column 1, where it should have been all along.

![Cursor before Return](nov2026-figs/nov-07-2026-fig03.png)
![Cursor after Return](nov2026-figs/nov-07-2026-fig04.png)
![Cursor after moving up](nov2026-figs/nov-07-2026-fig05.png)

### Investigation and repair

The apparent horizontal drift was real indentation in the buffer. Markdown's
Return handler inherited indentation from the preceding list paragraph and
inserted spaces on blank prose lines. Repeated Return therefore left the cursor
a few columns to the right.

Both Markdown implementations now leave a blank prose line unindented:
`compiled/scripts/markdown.scm` and `scheme/languages/markdown.scm`. Return still continues a nonempty list item, ends an empty item, and preserves the existing fenced-code rule. This repair is also in commit `c305b53`.

`tests/markdown-blank-newline.sh` checks those five cases through real terminal
keys with each Scheme runtime: ten passing cases. It compares saved text,
including spaces, rather than relying on cursor appearance alone.

## November 07, 2026. Complaint 3
If I copy text from the internet and paste it with Command ⌘-v, it is very slow, and the inserted text may contain one or two errors. It would be nice if Command-C and Command-V worked normally. 

### Cause and repair

In a text terminal, ⌘-V belongs to the terminal application. Without paste
framing, Chezweb receives a stream indistinguishable from typing. It processes
and redraws each character, and each pasted Return can run Markdown's automatic
list continuation. That explains a concrete route to slow paste and unwanted
numbered items. C-y uses a different clipboard/yank path.

Chezweb now enables bracketed paste when entering the terminal and disables it
on exit. `src/key.c` recognises the opening marker. `paste_bracketed` in
`src/command.c` collects the payload through the closing marker, normalises CR
and CRLF line endings to LF, and inserts it as one undoable edit. Pasted control
bytes remain text; they do not run commands. Markdown's Return handler is not
called. Read-only buffers reject the insertion after consuming the whole frame,
so rejected text cannot leak into subsequent commands.

The temporary collection is limited to 16 MiB. If collection exceeds that limit
or allocation fails, the rest of the frame is consumed and nothing is inserted.
An incomplete frame also inserts nothing. Overwrite mode retains the existing
yank policy of refusing insertion. The kill ring is not replaced by this path.

Protocol reference: [XTerm control sequences, bracketed paste mode 2004](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html).
The terminal must support and honour this protocol. Its own configured paste
throttling can still limit transfer speed; Chezweb avoids running editor commands
for each pasted character.

⌘-C remains the terminal's native copy command. In Chezweb's GUI, ⌘-C and ⌘-V
already have explicit copy/paste handlers. There is no need to disable Command.
In a terminal, use its native selection for ⌘-C, or Chezweb's marked-region copy
command M-w.

Regression test: `tests/bracketed-paste.sh` exercises a multiline Portuguese
Markdown paste, one-step undo and read-only rejection with both Scheme runtimes.
It compares saved bytes with the expected text; all six cases passed.
`tests/bracketed-paste.c` also passed decoder checks for CR/CRLF, literal
control bytes (including NUL), a partial closing-marker prefix, an empty frame,
an incomplete frame, size-limit rejection, read-only and overwrite rejection.
The size test uses a 32-byte limit to exercise rejection without large allocation.
This repair is local and has not
yet been committed or pushed.

### Build and publication issues found the same day

The first Windows regression build failed when linking the new small C test
harnesses under Cygwin. The production installer had built; the harnesses needed
Cygwin-specific whole-program optimisation and restricted symbol exports.
Commit `71c5109` fixes the common makefile; Windows commit `f51a771` passed native
build, regression checks, clean installation and terminal/GUI startup:
[successful Windows run](https://github.com/FemtoEmacs/Femto-Emacs/actions/runs/42402883083).

A macOS Apple Silicon runner timed out during the long navigation test. The
test now waits for a checked line-number acknowledgement every 200 keys rather
than accumulating unchecked terminal input. Commit `d585b0e` also increases the
per-traversal timeout and bounds failure output. The complete navigation test,
including repeated traversals, passed locally.

Windows originally ran only in its separate workflow. Commit `05ac65e` adds an
explicit Windows installer job to the main `build.yml`, calling the Windows
branch's reusable workflow. This keeps the native Windows port intact.

The successful build had uploaded Actions artifacts but had not published a
new Release. We published the [7 November Windows preview](https://github.com/FemtoEmacs/Femto-Emacs/releases/tag/chezweb-windows-0.1-2026-11-07)
from the verified `f51a771` revision, with installer, matching component sources,
package list and checksums. The installer SHA-256 was checked against the build's
manifest. The later integrated CI run is separate evidence; publication does
not imply that every subsequent run has finished.


### Validation of the local clipboard repair

`make` and the maintainer browser rebuild completed. `make check` passed,
including the four cumulative wrapped-file traversals with Vim/READ switches.
The separate paste-decoder target passed. `make check-selfhost` passed with a
byte-identical compiler rebuild. UI checks passed; the PDF fixture test was
skipped because `ttfy/benedetto.pdf` is absent. These are automated tests through a pseudo-terminal; the new ⌘-V path still deserves Eduardo's check in a fresh Terminal or iTerm session with his usual clipboard text.

## November 08, 2026. Claude's eval of Nov 07 bugs found a chink.
The logbook describes three complaints, two repairs committed as `c305b53` and one uncommitted. To judge them I need the code and its history, not just the narrative:The fix is good: the diagnosis is right and the repair is at the source. There's one gap I'd close and one conclusion I'd revise.

**The cursor jump (Complaint 1): diagnosis confirmed.** Your second screenshot ("corrosã", the cursor thrown to the last line) matches what the code does before the fix:

1. The main loop (`src/main.c`) redraws the screen before every key, and `get_key` handed over the two bytes of `ã` as two separate keys. So the editor redrew between them, with only the first byte in the buffer.
2. The painter (`update_display`, `src/display.c`) advances character by character. Reading that lone first byte, it assumed a two-byte character, jumped over the cursor's position, and never found the cursor on the page.
3. When the cursor isn't found, the editor reframes the window so the cursor sits on the bottom line. That's the jump you saw.

Codex's repair, `get_key` delivering a complete character and `insert()` inserting it whole, removes exactly this cause. The second defect it found is also real: the up/down arithmetic counted bytes as columns, so it too could leave the cursor inside `ã`. I read the diff of `c305b53` and found no error in it.

**The gap: the painter is still fragile.** Codex fixed the two known ways of putting the cursor inside a character. But the painter still reacts to any such position by reframing the window. A script that computes positions with `string-length`, which counts characters while the buffer counts bytes, would bring the jump back. A three-line guard would make it impossible for good: when the cursor falls inside a character, draw it on that character. Separately, every character still counts as one column, so combining accents and wide characters (CJK, emoji) can shift the cursor. That matters for polytonic Greek if your keyboard produces combining accents.

-- Claude, insert the three-line guard that would make the jump impossible for good. Introduce a polytonic Greek keyboard, since it would be very usefull.

**The C-y slowdown: I'd revise that conclusion.** Complaint 1 was closed because "it no longer reproduces". But C-y (`yank-command`) inserts the whole text in one step. It can't be slow line by line, and it can't run Markdown's Return handler, which is what adds false list items. Both symptoms are exactly what Complaint 3 explains: the terminal's ⌘-V arrives as if typed. So the first paste was most likely ⌘-V, and the real fix is the bracketed paste. If you remember using C-y there, it deserves a reproduction.
-- Human comment: I agree.

**The blank Markdown lines (Complaint 2): correct.** The indentation really was in the file, the change is the same in both Markdown implementations, and the test compares the saved bytes, spaces included.

**⌘-V (Complaint 3): right approach, still uncommitted.** Bracketed paste (mode 2004) is the standard solution and is well implemented: it consumes the whole frame even on failure, normalizes CR/CRLF, makes one undoable edit, and covers the 16 MiB limit. Small loose ends:
- The mode is turned off only on a normal exit. A crash or kill leaves it on in your shell.
- Programs run with M-! inherit it while they run.
- It's still local: commit it once you've tested ⌘-V in a fresh Terminal.

I only read the code and the screenshots and didn't build chezmoi here. Shall I write the display guard, with a test that puts the cursor inside `ã` and checks the window doesn't move?


## November 08, 2026. Complaint 1.
I use the mouse wheel to scroll past the text, so the screen goes blank. Then, I click on the blank screen. The window scrolls automatically until the first non-blank line, which appears at the end of the screen. At this point, the scroll wheel stops responding to up commands, but responds to down commands. After down-wheeling the mouse, up-wheeling starts responding as well.

* ~/mysand/chezmoi/bug_events/nov2026-figs/nov-08-2026-Complain1-fig01.png
* ~/mysand/chezmoi/bug_events/nov2026-figs/nov-08-2026-Complain1-fig02.png

This is not Emacs behavior. In Emacs, in a terminal, the blank window doesn't scroll when I click on it.


## November 08, 2026. The guard and the backdoor (Claude)

### The guard

The display (`update_display`, `src/display.c`) finds the cursor by
walking the page a character at a time. When point lay inside a
multi-byte character, the walk stepped over it, the cursor was "not
found", and the window reframed with the cursor on its last row: the jump
of 7 November. Codex's repair removed the two known causes (keys delivered
byte by byte, and up/down arithmetic in bytes); the display stayed fragile
to any other one. Now, when point falls inside a character, the display
moves point to the start of that character and draws the cursor there.
The window does not move, and typing there cannot split the character.

### The backdoor

M-x backdoor-claude or M-x backdoor-codex opens it; the same command closes
it. While open, the mode line shows B/D and the editor records one line per
key (`#N KEY pt= page= cur=ROW,COL size= BUFFER`) and one-line notes:
`guard: point P was inside the character at C` and `reframe: point P not on
the page` from the display, `note: TEXT` from scripts (`fe-backdoor-note`).
The lines appear in the buffer *backdoor* (refreshed only while a window
shows it) and in `~/.chezemax/backdoor.txt` (written at most once a second
and on closing), which an assistant reads. Only the last 120 lines are kept
(15 KB at most). Closed, the backdoor frees its memory and its buffer; what
remains is one test of an int per key. Code: `src/backdoor.c`; how to use it
for a diagnosis: `AGENTS.md`, "The backdoor".

### Evidence

`tests/backdoor-guard.sh` (in `make check`) opens the backdoor in a PTY,
centres a line containing "coração" (line 50 of 60), and has a script put
point inside `ç`. With the guard: a `guard:` note, page 333 before and
after, cursor row 11. With the guard disabled, the same keys give a
`reframe:` note and the window moves from page 333 to 243, the line from
row 11 to row 21, the bottom: the jump, reproduced. The test also checks
B/D, the file left on closing, and the 120-line cap after 300 keys.
`make`, `make check`, `make check-ui` and `make check-selfhost` pass on
Linux. The browser bundle must be rebuilt (`make browser-rebuild`).

### Found with the backdoor: incremental search splits characters

The backdoor's first run showed the guard firing during C-s: typing `aç`
in the search prompt put point between the two bytes of `ç` before the
second byte arrived. The search prompt reads keys a byte at a time, the
defect Codex fixed in `get_key`. The guard now hides it from the display;
the search itself should read whole characters. Not yet repaired.

### Still open

- Every character counts as one column: combining accents (zero width)
  and wide characters (CJK, emoji: two cells) can misplace the cursor.
  Relevant to polytonic Greek typed with combining accents.
- A polytonic Greek keyboard (requested above).
- November 08, Complaint 1 (clicking a blank window scrolls it).

## November 08, 2026. Character widths (Claude)

The first item still open above. Every character counted as one column:
a combining accent (polytonic Greek typed as letter + accent, U+0300-036F)
moved everything after it one column to the right of where the terminal drew
it, and a wide character (CJK, emoji) one column to the left.

`src/width.c` now gives each character its columns: 0 for combining accents
and invisible format characters, 2 for East Asian wide and fullwidth
characters and emoji, 1 for the rest (precomposed Greek, U+1F00-1FFF,
included). One table serves everything:

- the C core (`src/display.c`): the painter, up and down movement (a goal
  column inside a wide character lands after it, as Emacs's
  `move-to-column`), the column of a mouse click, and C-e on long lines.
  A wide character that would cross the right edge starts the next row, as
  terminals draw it. After reaching a column, the cursor goes past the
  accents of the character before, never between a letter and its accent;
- Markdown/TeX/text word wrap (`markdown-wrap-end`, both runtimes), through
  a new script function `(fe-char-width code-point)`, called only for
  non-ASCII characters;
- the SDL window (`src/gui.c`) and the browser (`web/screen.c`,
  `web/page.js`): a cell keeps its character and up to two accents, drawn
  together; a wide character takes a second cell; backgrounds are painted
  before glyphs so a wide glyph is not covered.

The terminal draws accents and wide characters itself (ncurses).

Evidence: `tests/char-width.sh` (in `make check`) reads the cursor columns
from the backdoor in a PTY: decomposed accents, CJK, and a CJK character at
column 79 of 80. `tests/scripts-cases.scm` compares the wrap with accents
and CJK, and the widths, in both runtimes. `tests/chezweb-width.cjs` (in
`make check-browser`) checks the browser's screen text and cursor columns
for decomposed `ἐν ἀρχῇ`, `ação` and `中文x`. A screenshot of the SDL window
(Xvfb) showed the Greek accents on their letters. CJK appeared as empty boxes
there: the window uses one monospaced font and SDL_ttf has no fallback, a
font matter, not a width one.

Found and fixed on the way: the backdoor did not write its file when
`~/.chezemax` did not exist yet (the browser, a new account); it now makes
the folder.

`tests/unwrapped-navigation.c` (7 November) assumed that the emoji U+1F642
takes one column; it takes two, as terminals draw it. Three of its
expectations changed accordingly (column 4 lands after the emoji; the full
row 🙂B on a 3-column screen ends before the newline; a click on column 1
lands on the emoji). Both its checks pass.

## November 08, 2026. The polytonic Greek keyboard (Claude)

M-x polytonic turns on a keyboard for polytonic Greek in Beta Code (the
TLG's convention); the same command turns it off. The mode line shows Ἑλ.

- Letters: a α, b β, g γ, d δ, e ε, z ζ, h η, q θ, i ι, k κ, l λ, m μ,
  n ν, c ξ, o ο, p π, r ρ, s σ, t τ, u υ, f φ, x χ, y ψ, w ω, v ϝ, j ς.
- Marks, typed after the letter: `)` smooth, `(` rough breathing, `/`
  acute, `\` grave, `=` circumflex, `|` iota subscript, `+` diaeresis:
  `a)/` ἄ, `w(=|` ᾧ, `i+/` ΐ, `r(` ῥ. A new accent replaces the old one.
- Capitals: `*` and the marks before the letter, as in Beta Code (`*)/a`
  Ἄ), or Shift.
- σ becomes ς when the word ends (blank, punctuation, RET).
- `:` ano teleia (·), `'` apostrophe of elision (’), `#` keraia (ʹ).
- Marks apply to vowels (all) and rho (breathings); after another letter
  or a blank, or typed twice, a mark is the character itself, so `(λόγος)`
  is typed `(lo/gos)`.
- The result is precomposed (NFC), from a table generated from Unicode's
  own decompositions (211 characters). A combination with no precomposed
  character (ε with circumflex) gets a combining accent, which the display
  now draws on its letter.

Code: `compiled/scripts/polytonic.scm` (a self-insert hook; no C). It runs
in the terminal, the SDL window and the browser. Tests: `tests/polytonic.sh`
(in `make check`) types two lines of Beta Code (John 1:1 and the first line
of the Odyssey, with ῥήτωρ, ΐ, parentheses, a doubled mark and ε͂) and
compares the saved bytes; `tests/chezweb-polytonic.cjs` (in `make
check-browser`) types John 1:1 in Chrome.

## November 08, 2026. Complaint 1 (the ghost window): investigation and repair (Claude)

Reproduced with the backdoor in a PTY: 20 wheel notches down a 50-line file
leave its last line at the top of the window (page 383); a click on the
blank rows below puts point at the end of the text (391), and the window
jumped to page 223 with the cursor on its last row. Wheel notches up then
dragged the cursor along.

The cause: `update_display` (`src/display.c`) reframes when
`b_epage <= b_point`, `b_epage` being where the last paint stopped. When the
text ends inside the window, the paint stops at the end of the text, which
is where the click put point: `<=` read "point is below the window" for a
cursor that was on it. Every later redisplay reframed again for the same
reason, which is why the wheel seemed not to scroll up.

The repair: before reframing, `end_on_page` checks whether point is the end
of the text and that end is on the page (on the last line's row, or on the
row after it when the text ends with a newline). Then the window stays, as
in Emacs. After the repair: the click leaves page 383, the cursor at the
end on row 1; the wheel scrolls up three lines a notch (383, 359, 335,
311), the cursor at the end of the text, visible.

Evidence: `tests/ghost-window.sh` (in `make check`) replays the wheel and
the click, with and without a final newline, and reads page and point from
the backdoor. It fails without the repair ("the click moved the window
(page 383, then 223)") and passes with it.

## November 08, 2026. Chinese input in tonal pinyin (Claude)

M-x chinese-input turns on Chinese typed in tonal pinyin; the same command
turns it off. The mode line shows 中 (anyone typing Chinese has a font for
it; 🀄 depends on emoji support, PY says less).

No burden for anyone else: the code is a small script
(`compiled/scripts/chinese.scm`); its two tables, in the folder `Chinese/`,
are read only when the input is turned on (0.19 s, 150 KB) and dropped
when it is turned off. `tests/chinese-input.sh` checks that the tables do
not exist before M-x chinese-input, nor after it is turned off.

Typing: the letters of a syllable (ü is v) show its candidates, every tone,
most frequent first; a digit 1-5 then picks the tone (5 neutral) and only
its characters remain; then 1-9 takes a candidate (SPC the first, also
before a tone); - and = page; DEL takes back the tone, then letters; RET
inserts the letters as typed; C-g drops them. After a character, its 联想
followers show (中→ 1国 2心 3央 4学 ...): 1-9 takes one, whose own
followers then show. , . ? ! : ; type ，。？！：；. Keys the input does not
use go on to the other key handlers (vim mode keeps working).

The tables (`tools/chinese-tables.sh`, sh/awk/sort, maintainers only):

- `Chinese/pinyin.txt`: the 8105 characters of the 通用规范汉字表 (2013)
  with their readings, from Unihan's kTGHZ2013 field (via
  mozillazg/pinyin-data), ordered by the frequencies of jieba's
  dictionary; 1699 lines (syllables with and without tone).
- `Chinese/lianxiang.txt`: for 5024 characters, at most nine followers,
  from the most frequent two-character words of jieba's dictionary.
  中's first page is 国 心 央 学 间 部 共 原 华: jieba ranks 文 and 午
  below these.
- `Chinese/README.md`: the sources and their licences (Unicode V3, MIT,
  MIT).

In the browser, M-x chinese-input says to use the system's pinyin input
method, which the page's text field takes: the page does not carry the
tables. `make app` copies `Chinese/` into Chezweb.app; the Windows
installer (its own branch) will need the folder too.

Evidence: `tests/chinese-input.sh` (in `make check`) types, in a PTY,
zhong 1 1, 1 (the follower 国), ni3 1, hao3 SPC, a comma, wo SPC, abc RET,
zhonx DEL g 1 2, ma C-g, then turns the input off and types ok; the saved
file is 中国你好，我abc钟ok.
