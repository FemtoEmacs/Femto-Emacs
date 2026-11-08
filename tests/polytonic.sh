#!/bin/sh
# M-x polytonic: polytonic Greek typed in Beta Code, through a terminal, then
# saved; the saved bytes must be the Greek (precomposed, NFC).  Breathings,
# accents, iota subscript, diaeresis, rho, capitals with *, final sigma
# before a blank, a comma, a parenthesis and RET, parentheses that stay
# parentheses, a mark typed twice, a combination Unicode has no character
# for (a combining accent), the ano teleia, and M-x polytonic again for
# Latin letters.  Disposable home, file and PTY.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-polytonic.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
cc=${CC:-cc}
$cc -O2 tests/pty-keys.c -o "$work/pty" -lutil 2>/dev/null ||
 $cc -O2 tests/pty-keys.c -o "$work/pty"
mkdir -p "$work/home/.chezemax"
: > "$work/greek.txt"
cat > "$work/keys" <<'KEYS'
await-screen [SAVE]
keys \expolytonic\r
wait 300
keys *)en a)rxh=| h)=n o( lo/gos, kai\\ o( lo/gos h)=n pro\\s to\\n qeo/n\r
keys *)/andra moi e)/nnepe, *mou=sa: w(=| r(h/twr i+/ (lo/gos) a)) e=\r
keys \expolytonic\r
wait 300
keys Latin again
keys ^X^S
wait 300
keys ^X^C
KEYS
(cd "$work"; HOME="$work/home" LC_ALL=C.UTF-8 CHEZEMAX_NO_INIT=1 "$work/pty" "$work/keys" 60 "$work/screen" "$root/chezemax" greek.txt)
printf 'Ἐν ἀρχῇ ἦν ὁ λόγος, καὶ ὁ λόγος ἦν πρὸς τὸν θεόν\nἌνδρα μοι ἔννεπε, Μοῦσα· ᾧ ῥήτωρ ΐ (λόγος) ἀ) ε\315\202\nLatin again' > "$work/expected"
if ! cmp -s "$work/greek.txt" "$work/expected"; then
 echo 'FAIL the Beta Code did not give the expected Greek'
 echo ' got:'; cat "$work/greek.txt"; echo; echo ' expected:'; cat "$work/expected"; echo
 exit 1
fi
grep -q 'Ἑλ' "$work/screen" || { echo 'FAIL the mode line did not show Ἑλ'; exit 1; }
echo 'PASS Beta Code types polytonic Greek: breathings, accents, iota subscript, diaeresis, capitals, final sigma'
