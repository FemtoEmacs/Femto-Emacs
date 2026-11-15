#!/bin/sh
# The side-by-side split, C-x 3 (14 November 2026).  The split keeps the
# page of the window, so the cursor's line stays on its row in both panes
# (it went to the bottom row); the backdoor says which pane a key was typed
# in; a pane's mode line keeps the file name and drops buttons first; and a
# y/n question asked from M-x term in a pane shows the cursor on the
# message line.  Disposable home, file and PTY.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-vsplit.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
cc=${CC:-cc}
$cc -O2 tests/pty-keys.c -o "$work/pty" -lutil 2>/dev/null ||
 $cc -O2 tests/pty-keys.c -o "$work/pty"
mkdir -p "$work/home/.chezemax"
printf 'watch page point\n' > "$work/home/.chezemax/backdoor-claude.conf"
awk 'BEGIN { for (i = 1; i <= 200; i++) printf "row %03d\n", i }' > "$work/rows.txt"
log="$work/home/.chezemax/backdoor.txt"
fail() { echo "FAIL $1"; tail -c 2500 "$log" 2>/dev/null; exit 1; }
run() { (cd "$work"; SHELL=/bin/sh TERM=xterm HOME="$work/home" CHEZEMAX_NO_INIT=1 LC_ALL=C.UTF-8 \
         "$work/pty" "$1" 60 "$work/screen" "$root/chezemax" rows.txt) }

# 1. the page, the cursor's row, the pane, the mode line
{ echo 'await-screen [SAVE]'; echo 'keys ^V'; echo 'wait 300'
  echo 'keys ^N^N^N'; echo 'wait 300'
  echo 'keys \exbackdoor-claude\r'; echo 'wait 300'
  echo 'keys ^X3'; echo 'wait 400'; echo 'keys ^Xo'; echo 'wait 300'
  echo 'keys \exbackdoor-claude\r'; echo 'wait 300'; echo 'keys ^X^C'; } > "$work/keys"
run "$work/keys"
[ -s "$log" ] || fail 'no backdoor record'
# C-v put row 1 + (one window less two rows) on the top row; C-n three
# times put the cursor on the fourth row, and C-x 3 must leave it there
split=$(grep '^#[0-9]* C-x 3 ' "$log" | sed 's/.* page=\([0-9]*\) cur=\([0-9]*\),.*/\1 \2/')
set -- $split
[ "${1:-0}" -gt 0 ] && [ "${2:-}" = 3 ] || fail "C-x 3 moved the window (page ${1:-?}, cursor on row ${2:-?})"
! grep -A3 '^#[0-9]* C-x 3 ' "$log" | grep -q '^  page ' || fail 'C-x 3 changed the page'
grep -q '^#[0-9]* C-x o .* rows.txt (right pane, from column 40)$' "$log" || fail 'the backdoor does not name the pane'
echo 'PASS C-x 3 keeps the page and the row of the cursor; the backdoor names the pane'

# 2. a y/n question from a terminal in the right pane shows the cursor
{ echo 'await-screen [SAVE]'; echo 'keys ^X3'; echo 'wait 400'; echo 'keys ^Xo'; echo 'wait 300'
  echo 'keys \exterm\r'; echo 'wait 1500'; echo 'keys ^C^X^C'
  echo 'await-screen quit anyway (y/n)'; echo 'wait 500'; echo 'keys y'; } > "$work/keys"
run "$work/keys"
# the last show or hide of the cursor before the editor leaves the screen
# (?2004l, the first thing it sends on its way out) must be a show
last=$(tr '\n\r' '  ' < "$work/screen" | sed 's/?2004l.*//' | grep -o '?25[hl]' | tail -n 1)
grep -q 'quit anyway (y/n)' "$work/screen" || fail 'no y/n question'
[ "$last" = '?25h' ] || fail 'the y/n question from M-x term hid the cursor'
echo 'PASS a y/n question asked from M-x term in a pane shows the cursor'
# (the backdoor's B/D, in 1, leaves a 39-column pane too little room)
esc=$(printf '\033')
sed "s/$esc[[(][0-9;?]*[A-Za-z]//g" "$work/screen" | grep -q 'rows.txt, L. [0-9]* \[?\]\[MORE\]\[TTFY\]' || fail "a pane's mode line lost the file name"
echo "PASS a pane's mode line keeps the file name"
