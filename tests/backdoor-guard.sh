#!/bin/sh
# The backdoor (M-x backdoor-claude) and the display's guard.  A script puts
# point inside the two bytes of "ç" in a centred line, as a byte offset
# computed from a character count would.  The window must not move: the
# guard draws the cursor on that character, and the backdoor's record says
# so (a "guard:" note, the same page before and after, no "reframe:").  The
# mode line shows B/D while the backdoor is open, and closing it leaves its
# lines in ~/.chezemax/backdoor.txt.  Disposable home, file and PTY.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-backdoor.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
cc=${CC:-cc}
$cc -O2 tests/pty-keys.c -o "$work/pty" -lutil 2>/dev/null ||
 $cc -O2 tests/pty-keys.c -o "$work/pty"
mkdir -p "$work/home/.chezemax"
awk 'BEGIN { for(i=1;i<=60;i++) if(i==50) print "coração e ação"; else print "linha " i; }' > "$work/text.txt"
cat > "$work/keys" <<'KEYS'
await-screen [SAVE]
keys \exbackdoor-claude\r
wait 300
keys ^Saç\r
wait 300
keys ^L
wait 300
keys \e:
wait 300
keys (goto-char (+ (line-start) 5))\r
wait 2500
keys ^F
wait 300
keys \exbackdoor-claude\r
wait 300
keys ^X^C
KEYS
(cd "$work"; HOME="$work/home" CHEZEMAX_NO_INIT=1 "$work/pty" "$work/keys" 60 "$work/screen" "$root/chezemax" text.txt)
log="$work/home/.chezemax/backdoor.txt"
fail() { echo "FAIL $1"; cat "$log" 2>/dev/null; exit 1; }
[ -s "$log" ] || fail 'closing the backdoor left no ~/.chezemax/backdoor.txt'
grep -q '^backdoor opened for Claude' "$log" && grep -q '^backdoor closed' "$log" || fail 'the backdoor did not open and close'
grep -q 'B/D' "$work/screen" || fail 'the mode line did not show B/D'
grep -q '^guard: point [0-9]* was inside the character at ' "$log" || fail 'the guard did not see point inside ç'
sed -n '/^#[0-9]* C-l /,$p' "$log" > "$work/centred-log"
grep -q '^guard: point [0-9]* was inside the character at ' "$work/centred-log" || fail 'the injected bad point was not detected'
! grep -q '^reframe:' "$work/centred-log" || fail 'the centred window reframed: the jump of 7 November' 
# the page after C-l (centred) and after the script moved point: the same
centred=$(sed -n 's/^#[0-9]* C-l .*page=\([0-9]*\) .*/\1/p' "$log")
after=$(sed -n 's/^#[0-9]* esc : .*page=\([0-9]*\) .*/\1/p' "$log")
[ -n "$centred" ] && [ "$centred" = "$after" ] || fail "the window moved (page $centred, then $after)"
lines=$(wc -l < "$log")
[ "$lines" -le 120 ] || fail "the backdoor kept $lines lines (at most 120)"
# the cap: 300 keys with the backdoor open leave the last 120 lines at most
{ echo 'await-screen [SAVE]'; echo 'keys \exbackdoor-codex\r'; i=0
  while [ $i -lt 30 ]; do echo 'keys ^N^N^N^N^N^P^P^P^P^P'; i=$((i+1)); done
  echo 'wait 300'; echo 'keys \exbackdoor-codex\r'; echo 'wait 300'; echo 'keys ^X^C'; } > "$work/keys2"
(cd "$work"; HOME="$work/home" CHEZEMAX_NO_INIT=1 "$work/pty" "$work/keys2" 60 "$work/screen2" "$root/chezemax" text.txt)
lines=$(wc -l < "$log")
[ "$lines" -le 120 ] && [ "$lines" -ge 100 ] || fail "after 300 keys the backdoor kept $lines lines (the cap is 120)"
grep -q '^backdoor closed' "$log" && grep -q '^backdoor opened' "$log" && ! grep -q '^#1 ' "$log" ||
 fail 'the oldest keys were not the ones dropped, or the header (kept) was'
echo 'PASS the backdoor records keys and notes, B/D shows, and point inside ç no longer moves the window'
