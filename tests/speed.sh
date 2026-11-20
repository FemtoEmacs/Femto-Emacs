#!/bin/sh
# Speed of the commands (20 November 2026): each command of the table below
# runs at the same place of the same block in a small file (about 32 KB) and
# in a large one (about 8 MB), and the backdoor's `time` gives its
# milliseconds (command and display).  Two checks:
#
#   local   the command's work depends on the text around the cursor (a
#           word, a line, an expression, a paragraph): the large file may
#           cost at most twice the small one plus 20 ms.  The visit that
#           copied the whole file to undo would have failed it.
#   scan    local when the thing is near (the list around the cursor), but
#           with none it scans to an end of the text (C-M-u, C-M-d in prose):
#           either check passes.
#   global  the command must scan the whole text (C-x h then M-w, M-<, M->,
#           a search that fails): at most 0.5 microseconds a byte of the
#           large file.  C-M-f over a whole module, at 4 us a byte, would
#           have failed it.
#
# The report lists every command with both times; the offenders come first
# and make the test fail.  SPEED_ONLY=name restricts it to one fixture
# (scheme, markdown); SPEED_KEEP=1 keeps the files.  It takes a few minutes,
# so it is `make check-speed`, outside `make check`.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-speed.XXXXXX")
[ -n "${SPEED_KEEP:-}" ] || trap 'rm -rf "$work"' EXIT HUP INT TERM
cc=${CC:-cc}
$cc -O2 tests/pty-keys.c -o "$work/pty" -lutil 2>/dev/null ||
 $cc -O2 tests/pty-keys.c -o "$work/pty"
mkdir -p "$work/home/.chezemax"
printf 'time\nrepeats keep\nwatch none\nlines 5000\n' > "$work/home/.chezemax/backdoor-claude.conf"

# ------------------------------------------------------------------
# The fixtures: one block, repeated; the cursor goes to line LINE of the
# middle block before each command
# ------------------------------------------------------------------
cat > "$work/block.scm" <<'EOF'
;;; A section of definitions, with a comment that is long enough to be
;;; filled, and a second sentence.  And a third one, for M-e and M-a.

(define (fib n)
  "The Nth Fibonacci number, the slow way."
  (if (< n 2)
      n
      (+ (fib (- n 1)) (fib (- n 2)))))

(define (walk tree visit)
  ;; every node, depth first
  (cond ((null? tree) 'done)
        ((pair? tree) (walk (car tree) visit) (walk (cdr tree) visit))
        (else (visit tree))))

(define table '((alpha . 1) (beta . 2) (gamma . "a \"quoted\" (string)")))

EOF
cat > "$work/block.md" <<'EOF'
## A heading

This paragraph has several sentences.  It is long enough to be filled
again with M-q, and its words are moved over, killed and transposed by
the word commands.  The last sentence ends here.

- an item of a list
- another item, with *emphasis* and `code`

A second paragraph, shorter.  It follows a blank line.

EOF
# fixture name, extension, the line of the block the cursor goes to
fixtures="scheme scm 6
markdown md 4"

# repeat BLOCK N times into FILE
build() {
  : > "$3"
  cp "$1" "$work/rep"
  left=$2
  # doubling, then the remainder, so 8 MB is quick to build
  while [ $left -gt 0 ]; do
    if [ $((left % 2)) -eq 1 ]; then cat "$work/rep" >> "$3"; fi
    left=$((left / 2))
    if [ $left -gt 0 ]; then cat "$work/rep" "$work/rep" > "$work/rep2"; mv "$work/rep2" "$work/rep"; fi
  done
}

# ------------------------------------------------------------------
# The commands: kind, name, the keys (pty-keys notation).  A local one runs
# at the block's line; a global one from the start of the text.
# ------------------------------------------------------------------
cat > "$work/commands" <<'EOF'
local	C-f forward-char	^F
local	C-b backward-char	^B
local	C-n next-line	^N
local	C-p previous-line	^P
local	C-a beginning-of-line	^A
local	C-e end-of-line	^E
local	M-f forward-word	\ef
local	M-b backward-word	\eb
local	M-e forward-sentence	\ee
local	M-a backward-sentence	\ea
local	M-} forward-paragraph	\e}
local	M-{ backward-paragraph	\e{
local	M-m back-to-indentation	\em
local	C-M-f forward-sexp	\e^F
local	C-M-b backward-sexp	\e^B
scan	C-M-u backward-up-list	\e^U
scan	C-M-d down-list	\e^D
local	C-M-a beginning-of-defun	\e^A
local	C-M-e end-of-defun	\e^E
local	C-v scroll-down	^V
local	M-v scroll-up	\ev
local	C-l recenter	^L
local	x self-insert	x
local	DEL backspace	^?
local	C-d delete-char	^D
local	M-d kill-word	\ed
local	M-DEL backward-kill-word	\e^?
local	C-k kill-line	^K
local	C-y yank	^Y
local	C-M-k kill-sexp	\e^K
local	M-k kill-sentence	\ek
local	C-t transpose-chars	^T
local	M-t transpose-words	\et
local	C-x C-t transpose-lines	^X^T
local	M-u upcase-word	\eu
local	M-l downcase-word	\el
local	M-c capitalize-word	\ec
local	C-o open-line	^O
local	M-\ delete-horizontal-space	\e\\
local	M-SPC just-one-space	\exjust-one-space\r
local	M-^ delete-indentation	\e^
local	C-x C-o delete-blank-lines	^X^O
local	M-q fill-paragraph	\eq
local	M-; comment-dwim	\e;
local	TAB indent-for-tab	\t
local	RET newline	\r
local	M-h mark-paragraph	\eh
local	M-w copy-region	\ew
local	M-@ mark-word	\e@
local	C-M-SPC mark-sexp	\e^@
local	C-x C-x exchange-point-and-mark	^X^X
local	C-SPC set-mark	^@
local	C-g keyboard-quit	^G
local	C-/ undo	^_
global	M-> end-of-buffer	\e>
global	M-< beginning-of-buffer	\e<
global	C-x h mark-whole-buffer	^Xh
global	M-w copy-whole-buffer	\ew
global	C-s search-fails	^Szzqqxx^G
EOF

# ------------------------------------------------------------------
# One editor session per fixture and size: before each command, M-g to the
# block's line (local) or M-< (global); the record has one line a key
# ------------------------------------------------------------------
keys_for() {   # LINE -> the script of pty-keys
  printf 'await-screen [SAVE]\nkeys \\exbackdoor-claude\\r\nwait 300\n'
  while IFS='	' read -r kind name keys; do
    if [ "$name" = "M-< beginning-of-buffer" ]; then printf 'keys \\e>\n'; elif [ "$kind" != global ]; then printf 'keys \\eg%s\\r\n' "$1"; else printf 'keys \\e<\n'; fi
    printf 'wait 30\nkeys %s\nwait 30\n' "$keys"
  done < "$work/commands"
  printf 'wait 500\nkeys \\exbackdoor-claude\\r\nwait 500\nkeys ^X^C\nwait 300\nkeys y\n'
}

# the record's key lines (the M-x that opened the backdoor is not one), as
# "ms" a line, in the order of the commands: every second line (the first
# of each pair is M-g or M-<)
times_of() {
  awk -v expected="$(wc -l < "$work/commands")" '
    /^#[0-9]/ {
      count++
      if (count % 2 == 0) {
        value = $0
        if (value !~ /[|] [0-9]+[.][0-9]+ ms:/) { bad=1; next }
        sub(/^.*[|] /, "", value); sub(/ ms:.*$/, "", value)
        print value
      }
    }
    END { if (bad || count != 2 * expected) {
      print "FAIL missing, malformed or unexpected timing records" > "/dev/stderr"; exit 1
    } }' "$1"
}

report="$work/report"
: > "$report"
bad=0
printf '%s\n' "$fixtures" | while read -r fx ext line; do
  [ -z "${SPEED_ONLY:-}" ] || [ "$SPEED_ONLY" = "$fx" ] || continue
  blines=$(wc -l < "$work/block.$ext")
  bbytes=$(wc -c < "$work/block.$ext")
  for size in small large; do
    if [ $size = small ]; then n=$((32768 / bbytes + 1)); else n=$((8388608 / bbytes + 1)); fi
    build "$work/block.$ext" $n "$work/$fx-$size.$ext"
    middle=$(( (n / 2) * blines + line ))
    keys_for $middle > "$work/$fx-$size.keys"
    rm -f "$work/home/.chezemax/backdoor.txt"
    (cd "$work" && HOME="$work/home" CHEZEMAX_NO_INIT=1 LC_ALL=C.UTF-8 \
       "$work/pty" "$work/$fx-$size.keys" 600 "$work/screen" "$root/chezemax" "$fx-$size.$ext") ||
      { echo "FAIL the editor did not finish the $fx $size run"; exit 1; }
    cp "$work/home/.chezemax/backdoor.txt" "$work/$fx-$size.record"
    times_of "$work/$fx-$size.record" > "$work/$fx-$size.times"
  done
  big=$(wc -c < "$work/$fx-large.$ext")
  paste "$work/commands" "$work/$fx-small.times" "$work/$fx-large.times" |
  awk -F'\t' -v fx="$fx" -v big="$big" -f "$root/tests/speed-report.awk" >> "$report" || { cat "$report"; exit 1; }
done
sort "$report" | sed -n -e '/^SLOW/p' -e '/^MISSING/p'
sort "$report" | sed -n '/^ok/p'
if grep -Eq '^SLOW|^MISSING' "$report"; then
  echo "FAIL $(grep -Ec '^SLOW|^MISSING' "$report") of $(wc -l < "$report") commands are slow on the large file (or not recorded)"
  exit 1
fi
echo "PASS $(wc -l < "$report") commands: local ones within 2x + 20 ms of the small file, global ones within 0.5 us a byte"
