#!/bin/sh
# cluster-motion.sh -- C-f, C-b, the arrows and C-n over what is drawn as
# one character (25 November 2026): a letter and its accent, emoji joined
# by U+200D (a family), a flag (two regional letters, paired from the
# start of their run: two flags in a row are two steps), an emoji and its
# variation selector (the red heart).  Eduardo found that the arrows took
# two presses over a flag, and that typing between its two letters split
# it.  src/display.c, cluster_boundary.  Disposable files, in a PTY.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-cluster-motion.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
cc=${CC:-cc}
$cc -O2 tests/pty-keys.c -o "$work/pty" -lutil 2>/dev/null ||
	$cc -O2 tests/pty-keys.c -o "$work/pty"
mkdir -p "$work/home/.chezemax"
printf 'repeats keep\nwatch none\n' > "$work/home/.chezemax/backdoor-claude.conf"
log="$work/home/.chezemax/backdoor.txt"
failed=0

# x é x 👨‍👩‍👧 x 🇧🇷 x ❤️ x 🇧🇷🇯🇵 x, then "abc" and "x🇧🇷y"
printf 'xe\314\201x\360\237\221\250\342\200\215\360\237\221\251\342\200\215\360\237\221\247x\360\237\207\247\360\237\207\267x\342\235\244\357\270\217x\360\237\207\247\360\237\207\267\360\237\207\257\360\237\207\265x\nabc\nx\360\237\207\247\360\237\207\267y\n' > "$work/text.txt"
cp "$work/text.txt" "$work/orig.txt"
{
	echo 'await-screen [SAVE]'
	echo 'keys \exbackdoor-claude\r'
	echo 'wait 300'
	for i in 1 2 3 4 5 6 7 8 9 10 11 12; do echo 'keys \e[C'; echo 'wait 100'; done
	for i in 1 2 3 4 5 6 7 8 9 10 11 12; do echo 'keys \e[D'; echo 'wait 100'; done
	echo 'keys ^N^F^F'; echo 'wait 200'
	echo 'keys ^N'; echo 'wait 200'
	echo 'keys ^P^P^E^B^B'; echo 'wait 200'
	echo 'keys z'; echo 'wait 200'
	echo 'keys \exbackdoor-claude\r'
	echo 'wait 300'
	echo 'keys ^X^S'
	echo 'wait 300'
	echo 'keys ^X^C'
	echo 'wait 300'
} > "$work/keys"
(cd "$work"; HOME="$work/home" CHEZEMAX_NO_INIT=1 LC_ALL=C.UTF-8 "$work/pty" "$work/keys" 60 "$work/screen" "$root/chezemax" text.txt) > "$work/pty.out" 2>&1 ||
	{ echo "FAIL cluster-motion: the session did not finish"; exit 1; }
pts=$(grep -a '^#' "$log" | grep -av 'esc x b' | sed 's/.* pt=\([0-9]*\) .*/\1/' | tr '\n' ' ')
check() {   # check WHAT EXPECTED GOT
	if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1"; echo "  expected: $2"; echo "  got:      $3"; failed=1; fi
}
set -- $pts
check "the right arrow: one press over é, the family, the flag, the heart, each of two flags in a row" \
	"1 4 5 23 24 32 33 39 40 48 56 57" "$1 $2 $3 $4 $5 $6 $7 $8 $9 ${10} ${11} ${12}"
shift 12
check "the left arrow: the same stops, back" \
	"56 48 40 39 33 32 24 23 5 4 1 0" "$1 $2 $3 $4 $5 $6 $7 $8 $9 ${10} ${11} ${12}"
shift 12
# C-n C-f C-f: column 2 of "abc" (60); C-n: column 2 of "x🇧🇷y" is inside
# the flag, so the cursor goes past it, before y (62 + 1 + 8 = 71)
check "C-n to a column inside a flag: the cursor after the flag" "71" "$4"
# C-p C-p C-e C-b C-b: before the second flag of the pair (48), and z there
printf 'xe\314\201x\360\237\221\250\342\200\215\360\237\221\251\342\200\215\360\237\221\247x\360\237\207\247\360\237\207\267x\342\235\244\357\270\217x\360\237\207\247\360\237\207\267z\360\237\207\257\360\237\207\265x\nabc\nx\360\237\207\247\360\237\207\267y\n' > "$work/want.txt"
if cmp -s "$work/want.txt" "$work/text.txt"; then
	echo "PASS typing after C-e C-b C-b goes between the two flags, not inside one"
else
	echo "FAIL typing after C-e C-b C-b went inside a flag"; od -c "$work/text.txt" | head -8; failed=1
fi
# the terminal is not sent U+FE0F (EF B8 8F): with it, the heart is drawn
# two columns wide where the cursor counts one; the file keeps it (above)
if LC_ALL=C grep -aq "$(printf '\357\270\217')" "$work/screen"; then
	echo "FAIL the terminal was sent U+FE0F: the heart is drawn two columns wide, the cursor counts one"; failed=1
else
	echo "PASS the terminal is not sent U+FE0F, so the heart takes the one column the cursor counts"
fi
exit $failed
