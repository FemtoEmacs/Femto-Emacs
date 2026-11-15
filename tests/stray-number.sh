#!/bin/sh
# A number with a period first on a line (15 November 2026): a reference
# pasted from the Internet, filled with M-q, put "1935." first on a line,
# and C-c C-e l l made it an enumerate item, printing 1. for the year.
#  1. M-q never breaks a line before a word that would make it a list
#     item (Org and Markdown), as Org's fill does in Emacs.
#  2. Inside a paragraph only 1. starts a list (CommonMark): M-q joins a
#     pasted "1935." line to its paragraph, in Markdown and in Org, and
#     the Markdown export keeps it as text.  A list after a blank line, or
#     one that starts at 1, is still a list.
#  3. Org keeps Org's syntax (the line is an item, as in Emacs), and
#     latex-export says which line starts a list inside a paragraph.
# Disposable home, files and PTY.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-stray.XXXXXX")
trap '[ -n "${KEEP:-}" ] || rm -rf "$work"' EXIT HUP INT TERM
cc=${CC:-cc}
$cc -O2 tests/pty-keys.c -o "$work/pty" -lutil 2>/dev/null ||
 $cc -O2 tests/pty-keys.c -o "$work/pty"
mkdir -p "$work/home/.chezemax"
fail() { echo "FAIL $1"; exit 1; }
run() { (cd "$work"; HOME="$work/home" LC_ALL=C.UTF-8 CHEZEMAX_NO_INIT=1 "$work/pty" "$work/keys" 60 "$work/screen" "$root/chezemax" "$1") || true; }
long='Quoted from Plato. Republic. Vol. 2, Books VI-X. Loeb Classical Library 276. Bla, bla, bla. Cambridge, MA: Harvard University Press, 1935. Book VII, 525b.'
# a plain fill at 70 columns puts "1935." first on the third line
starts_number() { grep -q '^[0-9][0-9]*[.)] ' "$1"; }

# 1. M-q in Org and in Markdown
for f in fill.org fill.md; do
 printf '%s\n' "$long" > "$work/$f"
 printf 'await-screen [SAVE]\nkeys \\eq\nwait 300\nkeys ^X^S\nwait 300\nkeys ^X^C\n' > "$work/keys"
 run "$f"
 [ "$(wc -l < "$work/$f")" -gt 1 ] || fail "M-q did not fill $f"
 ! starts_number "$work/$f" || { cat "$work/$f"; fail "M-q in $f put a number first on a line"; }
 [ "$(tr '\n' ' ' < "$work/$f" | sed 's/  */ /g; s/ $//')" = "$long" ] || { cat "$work/$f"; fail "M-q in $f changed the words"; }
done
echo 'PASS M-q never starts a line with 1935. (Org and Markdown)'

# 2. Markdown: the pasted break; M-q joins it, and the export keeps it as text
pasted='[19] Plato. Republic. Vol. 2, Books VI-X. Loeb Classical Library 276.
Bla, bla, bla. Cambridge, MA: Harvard University Press,
1935. Book VII, 525b.'
# M-q on the reference's first line, and on its second (where Eduardo
# pressed it), in Markdown and in Org
for f in joined.md joined.org second.md second.org; do
 case $f in *.md) heading='# References';; *) heading='* References';; esac
 printf '%s\n%s\n' "$heading" "$pasted" > "$work/$f"
 case $f in second.*) down='^N^N^E';; *) down='^N';; esac
 printf 'await-screen [SAVE]\nkeys %s\\eq\nwait 300\nkeys ^X^S\nwait 300\nkeys ^X^C\n' "$down" > "$work/keys"
 run "$f"
 ! starts_number "$work/$f" || { cat "$work/$f"; fail "M-q in $f left 1935. first on a line"; }
 grep -q 'Press, 1935\. Book' "$work/$f" || { cat "$work/$f"; fail "M-q in $f did not join 1935. to its paragraph"; }
done
cat > "$work/paper.md" <<MD
$pasted

Steps:
1. first
2. second

Later:

5. fifth
6. sixth
MD
printf 'await-screen [SAVE]\nkeys \\exlatex-export\\r\nwait 800\nkeys ^X^C\n' > "$work/keys"
run paper.md
tex="$work/paper.tex"
[ -s "$tex" ] || fail 'no paper.tex'
grep -q '^1935\. Book VII' "$tex" || { cat "$tex"; fail 'Markdown export lost the year'; }
[ "$(grep -c 'begin{enumerate}' "$tex")" = 2 ] || { cat "$tex"; fail 'Markdown export: the two real lists (1. after text, 5. after a blank line) must stay lists'; }
grep -q 'item fifth' "$tex" || fail 'the list after a blank line was lost'
echo 'PASS M-q joins a pasted 1935. line (Markdown and Org); the Markdown export keeps it as text and keeps the real lists'

# 3. Org: Org's syntax, and a warning that names the line
cat > "$work/refs.org" <<ORG
* References
$pasted

Steps:
1. first
2. second
ORG
printf 'await-screen [SAVE]\nkeys \\exlatex-export\\r\nwait 800\nkeys ^X^C\n' > "$work/keys"
run refs.org
grep -q 'line 4: 1935\. starts a list inside a paragraph' "$work/screen" ||
 { tail -c 600 "$work/screen"; fail 'latex-export did not name line 4 of the Org file'; }
! grep -q 'line 6\|lines 4' "$work/screen" || fail 'a list that starts at 1 after "Steps:" is not a stray number'
echo 'PASS Org: latex-export names the line where 1935. starts a list inside a paragraph'
