#!/bin/sh
# Complaint 2 of 9 November 2026: near the end of a text whose last line is
# on the window's last row, C-y on an empty "### " header made the window
# jump, the cursor on its last row.  The display decided from the end of
# the page as last drawn, before the yank: point, after the inserted text,
# was past that stale end.  The window must stay: the header keeps its row.
# The backdoor records page and cursor.  Disposable home, file and PTY.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-yank.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
cc=${CC:-cc}
$cc -O2 tests/pty-keys.c -o "$work/pty" -lutil 2>/dev/null ||
 $cc -O2 tests/pty-keys.c -o "$work/pty"
mkdir -p "$work/home/.chezemax"
printf 'repeats keep\nwatch page\n' > "$work/home/.chezemax/backdoor-claude.conf"
awk 'BEGIN { for (i = 1; i <= 50; i++) print "linha " i; printf "### \n\n\n" }' > "$work/text.md"
log="$work/home/.chezemax/backdoor.txt"
fail() { echo "FAIL $1"; cat "$log" 2>/dev/null; exit 1; }
check() {   # $1: the keys that place the window, $2: what it is
CENTRE=$1
cat > "$work/keys" <<KEYS
await-screen [SAVE]
keys \e>
wait 300
keys Standardizing the Internal Data Structure
wait 300
keys ^A^K
wait 300
keys ^P^P^P^E
wait 300
keys \exbackdoor-claude\r
wait 300
$CENTRE
keys \e>^P^P^P^E
wait 300
keys ^Y
wait 300
keys \exbackdoor-claude\r
wait 1500
keys ^X^C
KEYS
(cd "$work"; HOME="$work/home" CHEZEMAX_NO_INIT=1 "$work/pty" "$work/keys" 60 "$work/screen" "$root/chezemax" text.md) || true
before=$(sed -n 's/^#[0-9]* C-e .*page=\([0-9]*\) cur=\([0-9]*\),.*/\1 \2/p' "$log" | tail -n 1)
after=$(sed -n 's/^#[0-9]* C-y .*page=\([0-9]*\) cur=\([0-9]*\),.*/\1 \2/p' "$log")
[ -n "$before" ] && [ -n "$after" ] || fail 'no record of C-e and C-y'
[ "${before#* }" -lt 21 ] || fail "the header is on the last row already ($before)"
[ "${before% *}" = "${after% *}" ] || fail "the window moved on C-y (page, row: $before, then $after)"
[ "${before#* }" = "${after#* }" ] || fail "the header changed rows on C-y ($before, then $after)"
echo "PASS C-y near the end of the text leaves the window where it is: $2"
rm -f "$log"
}
check 'wait 100' 'the header on row 18, the end of the text on the last row (the complaint)'
check 'keys ^L^L^L' 'the header centred'

