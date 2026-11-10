#!/bin/sh
# M-x korean-input: Korean typed on the 2-set keyboard (두벌식), through a
# terminal, then saved; the saved bytes must be the syllables.  Initials,
# vowels, finals, Shift's double consonants and vowels, compound vowels and
# finals, a final that moves into the next syllable (and of a double final
# its second part), DEL taking back one jamo, lone jamo, a blank and a
# digit that end the syllable, and M-x korean-input again for Latin
# letters.  Disposable home, file and PTY.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-korean.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
cc=${CC:-cc}
$cc -O2 tests/pty-keys.c -o "$work/pty" -lutil 2>/dev/null ||
 $cc -O2 tests/pty-keys.c -o "$work/pty"
mkdir -p "$work/home/.chezemax"
: > "$work/korean.txt"
# 한글 안녕하세요 / 닭이 갈라 / 왜 쉬어 의타 / 달가 (닭 + ㅏ) / 꽃 짜다 ㅋㅋ ㅠ / 값 많아 3갬
# DEL: 갈 DEL -> 가, then 각; 한 DEL DEL -> ㅎ, then 호
cat > "$work/keys" <<'KEYS'
await-screen [SAVE]
keys \exkorean-input\r
wait 300
keys gksrmf dkssudgktpdy\r
keys ekfrdl rkffk\r
keys dho tnldj dmlxk\r
keys ekfrk\r
keys Rhc Wkek zz b\r
keys rkqt aksgdk 3roa\r
keys rkf
keys ^?
keys r gks
keys ^?^?
keys h\r
keys \exkorean-input\r
wait 300
keys Latin again
keys ^X^S
wait 300
keys ^X^C
KEYS
(cd "$work"; HOME="$work/home" LC_ALL=C.UTF-8 CHEZEMAX_NO_INIT=1 "$work/pty" "$work/keys" 60 "$work/screen" "$root/chezemax" korean.txt)
printf '한글 안녕하세요\n닭이 갈라\n왜 쉬어 의타\n달가\n꽃 짜다 ㅋㅋ ㅠ\n값 많아 3갬\n각 호\nLatin again' > "$work/expected"
if ! cmp -s "$work/korean.txt" "$work/expected"; then
 echo 'FAIL the 2-set keys did not give the expected Hangul'
 echo ' got:'; cat "$work/korean.txt"; echo; echo ' expected:'; cat "$work/expected"; echo
 exit 1
fi
grep -q 'L\. [0-9]* 한' "$work/screen" || { echo 'FAIL the mode line did not show 한'; exit 1; }
echo 'PASS the 2-set keyboard types Hangul: finals moved and split, compound vowels and finals, Shift, DEL by jamo'
