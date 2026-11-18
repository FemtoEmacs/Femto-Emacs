#!/bin/sh
# Only complete characters are typed (18 November 2026,
# Lean/utf8-cursor.lean): a byte that is not a complete UTF-8 character
# (a continuation byte alone, a lead byte whose continuation bytes do not
# follow, C0, F5, FF) is typed as U+FFFD, in insert and in overwrite
# mode, and C-b and C-f step over it whole; complete characters are typed
# as they are; fe-fold refuses ends inside a character.  M-x
# toggle-utf8-fix turns this off (the bytes go in as they are, as before)
# and on again.  Disposable home, file and PTY; the backdoor gives point.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-stray-bytes.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
cc=${CC:-cc}
$cc -O2 tests/pty-keys.c -o "$work/pty" -lutil 2>/dev/null ||
 $cc -O2 tests/pty-keys.c -o "$work/pty"
mkdir -p "$work/home/.chezemax"
printf 'watch point\nrepeats keep\n' > "$work/home/.chezemax/backdoor-claude.conf"
printf 'xy\n' > "$work/text.txt"
log="$work/home/.chezemax/backdoor.txt"
fail() { echo "FAIL $1"; cat "$log" 2>/dev/null; od -An -c "$work/text.txt"; exit 1; }
# the keys, with raw bytes (pty-keys types every byte as it is)
{
  printf 'await-screen [SAVE]\n'
  printf 'keys \\exbackdoor-claude\\r\nwait 300\n'
  printf 'keys \\e[2~\nwait 200\nkeys \200\nwait 200\nkeys \\e[2~\nwait 200\n'   # overwrite x
  printf 'keys ^E\\r\nwait 100\n'
  printf 'keys a\200\nwait 200\nkeys ^B\nwait 200\nkeys ^F\nwait 200\n'
  printf 'keys \\r\342a\nwait 300\n'
  printf 'keys \\r\300\365\377\nwait 300\n'
  printf 'keys \\r\303\251\303\243\342\202\254\360\237\230\200\nwait 300\n'
  printf 'keys \\r\\exbackdoor-claude\\r\nwait 300\n'
  printf 'keys \\extoggle-utf8-fix\\r\nwait 300\n'
  printf 'keys \200\nwait 200\n'
  printf 'keys \\extoggle-utf8-fix\\r\nwait 300\n'
  printf 'keys \\r\200\nwait 200\n'
  printf 'keys ^X^S\nwait 300\nkeys ^X^C\n'
} > "$work/keys"
(cd "$work"; HOME="$work/home" CHEZEMAX_NO_INIT=1 LC_ALL=C.UTF-8 "$work/pty" "$work/keys" 60 "$work/screen" "$root/chezemax" text.txt)
R='\357\277\275'
printf "${R}y\na${R}\n${R}a\n${R}${R}${R}\n\303\251\303\243\342\202\254\360\237\230\200\n\200\n${R}\n" > "$work/expected.txt"
cmp -s "$work/text.txt" "$work/expected.txt" || { od -An -tx1 "$work/expected.txt"; fail 'the text is not what was typed, with U+FFFD for each stray byte'; }
grep '^#[0-9]* C-b ' "$log" | head -n 1 | grep -q ' pt=6 ' || fail 'C-b did not step over U+FFFD whole'
grep '^#[0-9]* C-f ' "$log" | head -n 1 | grep -q ' pt=9 ' || fail 'C-f did not step over U+FFFD whole'
echo 'PASS stray bytes are typed as U+FFFD (insert and overwrite), complete characters as they are, C-b and C-f step over U+FFFD whole; toggle-utf8-fix turns it off and on'
# fe-fold: the Org fold over "é" is taken; ends inside "é" are refused, unless the fix is off
set --
if command -v timeout >/dev/null 2>&1; then set -- timeout 30; fi
got=$(CHEZEMAX_NO_INIT=1 HOME="$work/home" "$@" ./chezemax --eval '(begin (insert "x
é
y") (display (list (fe-fold 1 4) (fe-fold 2 3) (fe-fold 1 2) (fe-fold 3 4) (fe-utf8-fix 0) (fe-fold 3 4) (fe-utf8-fix 1))) (newline))' </dev/null 2>&1 | head -n 1)
[ "$got" = '(1 0 0 0 0 1 1)' ] || { echo "FAIL fe-fold: $got, not (1 0 0 0 0 1 1)"; exit 1; }
echo 'PASS fe-fold refuses ends inside a character, and takes them with the fix off'
