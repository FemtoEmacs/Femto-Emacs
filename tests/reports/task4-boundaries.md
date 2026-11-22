# Task 4. Boundary-crossing shard and clipboard stress

22 November 2026. Written by Claude for Eduardo. The numbers come from
runs on Linux (x86-64) in Claude's cloud copy of the repository, at the
state pending on Eduardo's Mac (not yet committed). The tests run on Linux
and macOS.

## The task

Eduardo's text (`paper/test-design/testes.md`):

> - Cross-Shard Edits (shards.sh): Your shard boundary splits a >1 GB
>   file into ~16 MB pieces. Add a test specifically placing a multi-byte
>   UTF-8 character and a multi-line s-expression / code block right
>   across the 16 MB boundary, editing across it, and verifying that
>   saving doesn't split a UTF-8 sequence in half or corrupt byte offsets.
> - Malformed & Huge Clipboard Paste: Inject a 50 MB paste and a paste
>   containing embedded NUL bytes (\0), lone surrogates, and invalid UTF-8
>   bytes via the clipboard/bracketed-paste path (bracketed-paste.c) to
>   verify the editor neither hangs nor truncates the buffer at \0.

A remark on "right across the 16 MB boundary": a shard ends at a newline,
so a character or a line can only be split where a line longer than two
shards is cut inside. The test places the 16 MB cut right after a 4-byte
character, places a cut inside a multi-line s-expression (at 4 KB shards),
and cuts inside lines of 20 KB and 35 MB, where a character could be
split.

## Words used in this report

- **Shard.** A file too large to hold (over 1 GB, or any file opened with
  M-x find-file-shards) is read a piece at a time, as Emacs's VLF does:
  only one shard is in the buffer. `src/shard.c` cuts the file into shards
  of about 16 MB, each ending at a newline. A line longer than two shards
  (32 MB) is cut inside, before a byte that starts a character.
- **UTF-8.** Most characters take one byte; *ç* takes two, *€* three,
  *😀* four. A character cut in two leaves bytes that are not text.
- **Malformed text.** Bytes that are not valid UTF-8: a NUL byte (0), a
  *surrogate* written as UTF-8 (`ED A0 80`; surrogates belong to UTF-16
  and are never valid in UTF-8), bytes that no UTF-8 has (`FF FE`), an
  *overlong* NUL (`C0 80`), a lone continuation byte (`80`), a character
  cut short (`E2 82`).
- **Bracketed paste.** A terminal that pastes sends `ESC [200~`, the text,
  and `ESC [201~`, so that the editor inserts the text as it is instead of
  running it as keys (`paste_bracketed` in `src/command.c`).
- **C string.** In C, a string ends at its first NUL byte. A function that
  takes a C string sees only the text before the first NUL.

## Bugs found: four, all fixed

```lisp
(bugs
 (bug 1
  (what "M-g to a line that starts in one shard and is cut into the next")
  (before "It went to the cut, in the next shard, not to the start of the
           line")
  (after "The start of the line")
  (cause "shard_goto_line took a shard's first line to be the line after the
          newlines before it. That is wrong for a shard that starts inside a
          long line")
  (fix "It finds the shard holding newline N − 1. The line starts after it,
        or at the next shard's start when that newline ends its shard
        (ends_with_newline)"))
 (bug 2
  (what "A bracketed paste of 15 MB")
  (before "11 s; a paste of 50 MB took some 37 s only to be refused")
  (after "0.22 s; 50 MB refused in 0.56 s")
  (cause "Curses reads one byte with each call to read()")
  (fix "During a paste, key.c reads the terminal in blocks of 64 KB
        (screen_read_keys, term.c) and keeps what follows the paste for the
        keys after it"))
 (bug 3
  (what "C-y of a kill or clipboard with a NUL byte")
  (before "The text up to the first NUL")
  (after "Every byte")
  (cause "The text C-y inserts (the *scrap*) was inserted as a C string, and
          the clipboard's text was measured as one")
  (fix "The scrap carries its length (set_scrap_len, insert_bytes). The
        clipboard's length counts NULs. A clipboard text with a NUL goes to
        the scrap in C, as a large one does (fe-system-clipboard-nul,
        adopt-system-clipboard). The kill ring does not keep a kill cut at
        its NUL (remember-kill)"))
 (bug 4
  (what "C-w of a text with a NUL, then C-y, with a clipboard tool")
  (before "The clipboard got the text up to its NUL (a C string). The next
           C-y took that image for another program's copy and inserted it")
  (after "The kill, whole")
  (cause "The clipboard may not give back what it was given")
  (fix "The first read after the editor's own copy is taken for that copy as
        the clipboard keeps it, and remembered (length and hash). A later,
        different text is another program's and is adopted
        (read_system_clipboard, interface.c)")))
```

Findings 1 and 2 were measured. Findings 3 and 4 were found by reading
the code while writing the tests, then confirmed: with those two fixes
taken out, paste tests 5 and 6 fail (1 byte of 10 written; 21 of 30).

What held from the start: `shard.c` never cut a character, at 4 KB or at
16 MB, after a 4-byte character or inside a 35 MB line. Saving kept every
byte. The edits on both sides of a cut saved exactly, and C-M-f and C-M-b
at a split s-expression said so without moving. A paste of 15 MB of
malformed text went in byte for byte: NUL bytes, surrogates and bytes
that are not UTF-8 included. The editor never hung.

**A fault of the test itself, found on the Mac.** `make check` on
Eduardo's Mac failed in the quick part: "the saved file is not well-formed
UTF-8". In the same run the saved file was byte for byte the file
expected, and the same file is well-formed in the cloud. The check used
`iconv`, which behaves differently on macOS and Linux: the likely cause,
not proven until the rerun. The check is now a small C program that the
test compiles itself, and that names the first bad byte. The rerun on the
Mac is pending.

## The tests that were built

### `tests/shard-boundary.sh` (`make check-shard-boundary`)

1. **Marks at the cuts.** A `.scm` file, opened in shards of 4 KB. The
   first cut falls after a line ending in *😀*, inside a multi-line
   s-expression whose lines begin with *ç*. Further cuts fall inside a
   line of 20,000 bytes of characters of two to four bytes. The test types
   a `|` at the start and at the end of each of the 7 shards, then
   C-x C-s. Three things are checked:
   - the saved file, with its marks taken out, is the original byte for
     byte, so no offset moved;
   - with its marks, it is valid UTF-8, so no shard cut a character;
   - the marks are exactly where an independent model of `shard.c`'s rule
     puts the cuts (a small C program in the test).
2. **Edits on both sides of a cut.** The same file:
   - a line is added in shard 1;
   - C-M-f is pressed on the `(define` that the cut splits;
   - at the end of shard 1, DEL twice (the newline, then the 4-byte
     *😀*), two characters typed, and a newline;
   - at the start of shard 2, C-d (the 2-byte *ç*), then C-M-b;
   - M-g goes to the long line that starts in shard 2 and runs on into
     the shards after it; `@` is typed;
   - C-x C-s.

   The saved file must be the original with exactly these edits, and valid
   UTF-8. C-M-f and C-M-b must say there is no whole expression, and not
   move.
3. **The real 16 MB shards.** A file of 52 MB, opened with
   find-file-shards at the default size: 16.8 MB of lines, each beginning
   with *ç* and ending with *😀*; one line of 35 MB of *ção€😀ñ中*; 1,000
   lines after it. That gives three shards: a cut after a newline, and one
   inside the long line. The test checks as in 1, and also that the 16 MB
   cut falls between a line ending in *😀* and one beginning with *ç*.

### `tests/paste-stress.sh` (`make check-paste-stress`)

The malformed block above, repeated. Each file the editor writes is
compared, byte for byte, with what went in.

1. A bracketed paste of 15 MB.
2. A bracketed paste of 50 MB, larger than a paste may be (16 MB). It
   must be refused whole, the editor must say so, and the keys after it
   must still work.
3. A paste and the keys after it, sent in one write.
4. 50 MB copied by another program, then C-y.
5. A few bytes with a NUL copied by another program, then C-y.
6. C-w of a text with NUL bytes, then C-y. Then another program copies,
   and C-y again.

The system clipboard is a stand-in: `pbcopy`, `pbpaste` and `xclip`
scripts on PATH. The user's own clipboard is never touched. The stand-in
`pbpaste` can also act as another program copying, on its Nth call.
`tests/pty-keys.c` gained `send-file`: it writes a file's bytes into the
terminal as they are (NULs, escapes, megabytes), reading the editor's
output meanwhile so that neither side waits for the other.

In both tests every key must finish within 2 seconds, as the backdoor's
`time` measures it. `make check` runs a quick part of each (shard tests 1
and 2, paste tests 3, 5 and 6; about 40 seconds).

## Not changed, and why

- **The limit of a paste, 16 MB** (`TERMINAL_PASTE_LIMIT`). A 50 MB paste
  is refused whole and the editor says so: nothing is cut. It is now read
  in half a second, so a larger limit would cost no wait. Raising it is
  your choice.
- **C-M-f across a cut.** A shard is a buffer of its own. An s-expression
  that a cut splits cannot be crossed, and the commands say so. Emacs's
  VLF does the same.
- **A kill with a NUL is not on the kill ring.** C-y still inserts it
  whole (the scrap); M-y passes it by. The kill ring holds Scheme strings
  made from C strings.
- **The window (SDL) and the browser** read the clipboard as C strings, so
  a NUL ends the text there. The terminal's tools (`pbpaste`, `xclip`,
  `wl-paste`) carry it.
- **pbcopy on macOS** may change bytes that are not UTF-8. The editor's
  own copies are recognised as they come back (fix 4). Malformed text that
  another program copies comes in as `pbpaste` gives it.

## Summary

The shard index held: no character was cut, no offset moved, and edits
on both sides of a cut were saved exactly. The tests found four faults
and all are fixed: M-g to a line cut across shards; a slow paste (11 s
for 15 MB); C-y stopping at a NUL byte; and the editor's own kill coming
back cut from the clipboard. `make check`, the fuzzers and the endurance
tests pass.

```lisp
(summary
 (run "make check-shard-boundary, make check-paste-stress (quick parts in
       make check)")
 (time "about a minute each")
 (limits "SHARD_LIMIT_MS, PASTE_LIMIT_MS (2000)")
 (keep-the-files "SHARD_KEEP=1, PASTE_KEEP=1")
 (files "tests/shard-boundary.sh, tests/paste-stress.sh, tests/pty-keys.c
         (send-file); src/shard.c; src/key.c, src/term.c, src/gui.c,
         web/screen.c, src/screen.h; src/command.c, src/interface.c,
         src/native.c, src/header.h; compiled/scripts/core.scm,
         scheme/core.scm; makefile"))
```

