#!/bin/sh
# Double-tilde prose styling, including UTF-8 and code boundaries.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-strike.XXXXXX")
trap '[ -n "${KEEP:-}" ] || rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$work/home"
ev() { HOME="$work/home" CHEZEMAX_NO_INIT=1 ./chezemax --eval "$1"; }
# Assert the complete runs, so a painted code span or a wrong byte boundary fails.
for mode in md org; do
 got=$(ev "(highlight-string \"before ~~ação 中😀~~ after\" \"x.$mode\")")
 want='((5 . "before ") (35 . "~~ação 中😀~~") (5 . " after"))'
 [ "$got" = "$want" ] || { echo "FAIL $mode UTF-8 strikethrough: $got"; exit 1; }
 got=$(ev "(highlight-string \"~~unfinished\" \"x.$mode\")")
 [ "$got" = '((5 . "~~unfinished"))' ] || { echo "FAIL $mode unmatched delimiter: $got"; exit 1; }
done
[ "$(ev '(highlight-string "~code~ ~~gone~~" "x.org")')" = '((9 . "~code~") (5 . " ") (35 . "~~gone~~"))' ]
[ "$(ev '(highlight-string "`~~code~~` \\~~literal~~" "x.md")')" = '((9 . "`~~code~~`") (5 . " \\~~literal~~"))' ]
[ "$(ev '(highlight-string "=~~code~~=" "x.org")')" = '((9 . "=~~code~~="))' ]
[ "$(ev '(highlight-string "~~one~~ and ~~two~~" "x.md")')" = '((35 . "~~one~~") (5 . " and ") (35 . "~~two~~"))' ]
[ "$(ev '(cdr (assq (quote strike) *face-attributes*))')" = 32 ]
echo 'PASS double-tilde strike in Markdown and Org; UTF-8, code spans, escapes and unmatched pairs'
# Exercise the real terminal renderer and the edit/redisplay path.
cc=${CC:-cc}
$cc -O2 tests/pty-keys.c -o "$work/pty" -lutil 2>/dev/null || $cc -O2 tests/pty-keys.c -o "$work/pty"
printf 'plain ~~ação 中😀~~ plain\n' > "$work/strike.md"
cat > "$work/keys" <<'KEYS'
await-screen [SAVE]
keys \e>\rplain after strike
keys ^X^S
keys ^X^C
KEYS
HOME="$work/home" CHEZEMAX_NO_INIT=1 TERM=xterm-256color "$work/pty" "$work/keys" 60 "$work/screen" "$root/chezemax" "$work/strike.md"
grep -q "$(printf '\033')\[0;9" "$work/screen"
grep -q 'plain after strike' "$work/strike.md"
echo 'PASS terminal strike decoration, subsequent ordinary text, editing and save'
# addch(newline) clears a row without going through screen_clrtoeol.
# This used to leave copies of the struck words in each vacated row.
$cc -O2 -Ilibvterm/include tests/strike-screen.c libvterm/src/*.o -lm -o "$work/strike-screen"
for mode in org md; do
 cat > "$work/ghost.$mode" <<'TEXT'
** Introdução

A Hipótese do Sistema de Símbolos Físicos (PSSH, na sigla em inglês) não é nova. Entre seus adeptos estão Herbert Simon e Allen Newell. Em 1976, ao receberem o Prêmio Turing, eles disseram ~~STRIKEWORD~~ palestra de aceitação:

- Um sistema de símbolos físicos tem os meios necessários e suficientes para a ação inteligente geral.
TEXT
 cat > "$work/ghost-keys" <<'KEYS'
await-screen [SAVE]
keys ^SSTRIKEWORD\r\eb^B^B\r\r\r\r
keys ^X^S
keys ^X^C
KEYS
 HOME="$work/home" CHEZEMAX_NO_INIT=1 TERM=xterm-256color "$work/pty" "$work/ghost-keys" 60 "$work/ghost-screen" "$root/chezemax" "$work/ghost.$mode"
 "$work/strike-screen" "$work/ghost-screen"
 [ "$(grep -o STRIKEWORD "$work/ghost.$mode" | wc -l | tr -d ' ')" = 1 ]
done
# Removing only the markup changes styling while retaining the same word.
cat > "$work/remove-keys" <<'KEYS'
await-screen [SAVE]
keys ^SSTRIKEWORD\r\eb^B^B^D^D\ef^D^D
keys ^X^S
keys ^X^C
KEYS
HOME="$work/home" CHEZEMAX_NO_INIT=1 TERM=xterm-256color "$work/pty" "$work/remove-keys" 60 "$work/remove-screen" "$root/chezemax" "$work/ghost.md"
"$work/strike-screen" "$work/remove-screen" 0
