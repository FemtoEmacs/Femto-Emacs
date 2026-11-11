#!/bin/sh
# TAB on Org headings (compiled/scripts/org-fold.scm, src/fold.c), against
# Emacs: tests/org-fold/expected.txt is what Emacs's Org showed for each
# TAB of tests/org-fold/sequences.txt (tests/org-fold/oracle.el made it;
# Emacs is not needed to run this test).  The same files and TABs here
# must show the same lines.  Then, in a terminal, on a disposable file:
# the folded heading shows "...", C-n and C-p step over it, a search
# opens it, typing in a folded heading's line keeps the fold; C-c C-n,
# C-c C-f, C-c C-u move between headings; M-x org-mode (off) shows all.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
dir=tests/org-fold
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-org-fold.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$work/home/.chezemax"
# 1. Emacs as the oracle
: > "$work/got"
while IFS= read -r line; do
  file=${line%% *}; headings=${line#* }
  text=$(awk 'BEGIN { RS = "^$" } { gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\n/, "\\n"); printf "\"%s\"", $0 }' "$dir/$file")
  steps=$(printf '%s' "$headings" | awk -F, -v f="$file" '{ for (i = 1; i <= NF; i++) printf "(goto-char (string-search-forward \"%s\\n\" (buffer-substring 0 (buffer-size)) 0)) (org-cycle) (display \"%s %s: \") (display (org-visible-outline)) (newline) ", $i, f, $i }')
  CHEZEMAX_NO_INIT=1 HOME="$work/home" ./chezemax --eval "(begin (insert $text) (goto-char 0) $steps)" 2>&1 | sed '$d' >> "$work/got"
done < "$dir/sequences.txt"
if ! cmp -s "$dir/expected.txt" "$work/got"; then
  echo 'FAIL TAB does not show what Emacs shows (< Emacs, > Chezemax):'; diff "$dir/expected.txt" "$work/got"; exit 1
fi
echo "PASS TAB shows what Emacs's Org shows: $(wc -l < "$dir/expected.txt") states, $(wc -l < "$dir/sequences.txt") sequences"

# 2. in a terminal
cc=${CC:-cc}
$cc -O2 tests/pty-keys.c -o "$work/pty" -lutil 2>/dev/null ||
 $cc -O2 tests/pty-keys.c -o "$work/pty"
cp "$dir/outline.org" "$work/notes.org"
cat > "$work/keys" <<'KEYS'
await-screen [SAVE]
keys \t
wait 300
keys ^N
keys \e:(list 'Q1 (buffer-substring (line-start) (line-end)))\r
wait 1500
keys ^P
keys \e:(list 'Q2 (buffer-substring (line-start) (line-end)) (point))\r
wait 800
keys ^E!
keys \e:(list 'Q3 (fe-folded-at (line-end)))\r
wait 800
keys ^Sa1 text\r
wait 300
keys ^G
keys \e:(list 'Q4 (fe-hidden-p (point)))\r
wait 800
keys \e<^C^N
keys \e:(list 'Q5 (buffer-substring (line-start) (line-end)))\r
wait 800
keys ^C^F
keys \e:(list 'Q6 (buffer-substring (line-start) (line-end)))\r
wait 800
keys ^C^U
keys \e:(list 'Q7 (buffer-substring (line-start) (line-end)))\r
wait 800
keys \t
wait 300
keys \exorg-mode\r
wait 300
keys \e:(list 'Q8 (fe-folded-at (line-end)))\r
wait 800
keys \exorg-mode\r
wait 300
keys ^X^S
wait 300
keys ^X^C
KEYS
(cd "$work"; HOME="$work/home" LC_ALL=C.UTF-8 CHEZEMAX_NO_INIT=1 "$work/pty" "$work/keys" 90 "$work/screen" "$root/chezemax" notes.org) || true
fail() { echo "FAIL $1"; exit 1; }
seen() { grep -q -- "$1" "$work/screen" || fail "$2"; }
seen '\.\.\.' 'a folded heading shows no ...'
seen '(Q1 "\* B")' 'C-n from a folded heading must go to the next heading shown'
seen '(Q2 "\* A" 0)' 'C-p must come back to the folded heading'
seen '(Q3 [0-9]' 'typing at the end of a folded heading must keep it folded'
seen '(Q4 0)' 'a search into folded text must open it'
seen '(Q5 "\*\* A1")' 'C-c C-n: the next heading'
seen '(Q6 "\*\* A2")' 'C-c C-f: the next heading of the same level'
seen '(Q7 "\* A!")' 'C-c C-u: the parent heading'
seen '(Q8 -1)' 'M-x org-mode off must show everything'
sed '1s/^\* A$/* A!/' "$dir/outline.org" > "$work/expected"
cmp -s "$work/notes.org" "$work/expected" || { echo 'FAIL folding changed the text'; diff "$work/expected" "$work/notes.org"; exit 1; }
echo 'PASS ... on a folded heading, C-n and C-p over it, a search opens it, C-c C-n C-f C-u, off shows all; the text unchanged'
