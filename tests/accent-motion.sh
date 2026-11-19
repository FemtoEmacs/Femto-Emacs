#!/bin/sh
# C-f and C-b over combining accents (18 November 2026), as Emacs does:
# a letter and the accents typed after it (e + U+0301) are one press;
# backspace and C-d still delete one code point (as in Emacs), so DEL
# after "é" leaves "e".  The positions are what Emacs 29 (emacs -nw -Q) gave on the same
# line.  Line 2 of Lean/utf8-comb.txt, on a disposable copy, in a PTY.
# The scripts' forward-char and backward-char still move one code point,
# as Emacs's do (the Lean edit experiment counts on it): only the commands
# bound to C-f, C-b and the arrows take the accent with the letter.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-accent-motion.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
cc=${CC:-cc}
$cc -O2 tests/pty-keys.c -o "$work/pty" -lutil 2>/dev/null ||
 $cc -O2 tests/pty-keys.c -o "$work/pty"
mkdir -p "$work/home/.chezemax"
printf 'watch point\nrepeats keep\n' > "$work/home/.chezemax/backdoor-claude.conf"
cp Lean/utf8-comb.txt "$work/text.txt"
log="$work/home/.chezemax/backdoor.txt"
fail() { echo "FAIL $1"; cat "$log" 2>/dev/null; exit 1; }
cat > "$work/keys" <<'KEYS'
await-screen [SAVE]
keys \exbackdoor-claude\r
wait 300
keys ^N^A^F^F^F^F^F^F^F^F^F^F^F
wait 200
keys ^F
wait 150
keys ^F
wait 150
keys ^F
wait 150
keys ^B
wait 150
keys ^B
wait 150
keys ^B
wait 150
keys ^F^?
wait 200
keys \extoggle-utf8-fix\r
wait 300
keys ^A^F^F^F^F^F^F^F^F^F^F^F^F^F
wait 200
keys ^F
wait 150
keys ^F
wait 150
keys ^B
wait 150
keys \extoggle-utf8-fix\r
wait 300
keys \exbackdoor-claude\r
wait 300
keys ^X^S
wait 300
keys ^X^C
KEYS
(cd "$work"; HOME="$work/home" CHEZEMAX_NO_INIT=1 LC_ALL=C.UTF-8 "$work/pty" "$work/keys" 60 "$work/screen" "$root/chezemax" text.txt)
got=$(grep -E '^#[0-9]+ C-(f|b) ' "$log" | sed -n '12,17p' | sed 's/.* pt=\([0-9]*\) .*/\1/' | tr '\n' ' ')
[ "$got" = '51 52 55 52 51 48 ' ] || fail "C-f, C-f, C-f, C-b, C-b, C-b from before \"é\" gave $got, not 51 52 55 52 51 48 (Emacs)"
printf 'Combining: e n\314\203 (accent after the letter)\n' > "$work/line2"
sed -n 2p "$work/text.txt" | cmp -s - "$work/line2" || { sed -n 2p "$work/text.txt" | od -c; fail 'DEL after "é" did not delete the accent alone'; }
got=$(grep -E '^#[0-9]+ C-(f|b) ' "$log" | sed -n '32,34p' | sed 's/.* pt=\([0-9]*\) .*/\1/' | tr '\n' ' ')
[ "$got" = '51 53 51 ' ] || fail "with toggle-utf8-fix off, C-f, C-f, C-b over \"ñ\" (n + U+0303) gave $got, not 51 53 51 (stopping before the accent, as before)"
echo 'PASS C-f and C-b step over a letter and its combining accent in one press, as Emacs; DEL deletes the accent alone; toggle-utf8-fix off brings back the stop before the accent'
# the primitives: one code point a step, in a script
got=$(CHEZEMAX_NO_INIT=1 HOME="$work/home" ./chezemax --eval "$(printf '(begin (insert "e\314\201 x") (goto-char 0) (forward-char 1) (display (list (point))) (forward-char 1) (display (list (point))) (backward-char 1) (display (list (point))) (newline))')" </dev/null 2>&1 | head -n 1)
[ "$got" = '(1)(3)(1)' ] || { echo "FAIL forward-char and backward-char in a script gave $got, not (1)(3)(1): one code point a step"; exit 1; }
echo 'PASS forward-char and backward-char in a script move one code point, as in Emacs'
