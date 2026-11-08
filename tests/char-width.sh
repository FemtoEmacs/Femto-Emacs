#!/bin/sh
# Combining accents take no column, wide characters (CJK) two: the cursor
# columns the backdoor records after C-e, C-n, C-f and C-p must be where the
# characters are drawn -- decomposed Greek and Portuguese, CJK, and a wide
# character that does not fit at the end of a row and starts the next one.
# Disposable home, file and PTY.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-width.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
cc=${CC:-cc}
$cc -O2 tests/pty-keys.c -o "$work/pty" -lutil 2>/dev/null ||
 $cc -O2 tests/pty-keys.c -o "$work/pty"
mkdir -p "$work/home/.chezemax"
# line 1: a, b, c each followed by U+0301; line 2: 中文x; line 3: abcdefgh;
# line 4: 79 a's, then 中z (中 cannot fit in column 79 of 80); line 5: end
{ printf 'a\314\201b\314\201c\n\344\270\255\346\226\207x\nabcdefgh\n'
  awk 'BEGIN { for (i = 0; i < 79; i++) printf "a"; printf "\344\270\255z\nend\n" }'; } > "$work/t.c"
cat > "$work/keys" <<'KEYS'
await-screen [SAVE]
keys \exbackdoor-claude\r
wait 300
keys \e<
keys ^E
keys ^N
keys ^E
keys ^P
keys ^N^N^N^E
keys ^F
keys ^F
keys ^P
wait 300
keys \exbackdoor-claude\r
wait 300
keys ^X^C
KEYS
(cd "$work"; HOME="$work/home" CHEZEMAX_NO_INIT=1 "$work/pty" "$work/keys" 60 "$work/screen" "$root/chezemax" t.c)
got=$(sed -n 's/^#[0-9]* \([^ ]*\) .*cur=\([0-9]*,[0-9]*\).*/\1 \2/p' "$work/home/.chezemax/backdoor.txt" | tr '\n' ' ')
# down from column 3 lands after 文 (columns 2-3), at 4, as Emacs's
# move-to-column does, and keeps column 4 below
want='esc < 0,0 C-e 0,3 C-n 1,4 C-e 1,5 C-p 0,3 C-n 1,4 C-n 2,4 C-n 3,4 C-e 3,78 C-f 4,0 C-f 4,2 C-p 3,2 '
# esc < is recorded as its key name, "esc <"
got=$(printf '%s' "$got" | sed 's/^esc 0,0/esc < 0,0/')
[ "$got" = "$want" ] || { echo "FAIL cursor columns"; echo " got:  $got"; echo " want: $want"; cat "$work/home/.chezemax/backdoor.txt"; exit 1; }
! grep -q '^\(guard\|reframe\):' "$work/home/.chezemax/backdoor.txt" || { echo 'FAIL the cursor was lost'; exit 1; }
echo 'PASS combining accents take no column, CJK two, and a wide character at the edge starts the next row'
