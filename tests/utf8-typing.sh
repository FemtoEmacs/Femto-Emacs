#!/bin/sh
# A centred cursor must stay centred while an accented character is typed.
# Disposable file and PTY; no system clipboard or user init file is used.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-utf8-typing.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
cc=${CC:-cc}
$cc -O2 tests/pty-keys.c -o "$work/pty" -lutil 2>/dev/null ||
 $cc -O2 tests/pty-keys.c -o "$work/pty"
awk 'BEGIN { for(i=1;i<=60;i++) if(i==32) print "4. **Refinamento e Corrosã**"; else print "Prose line " i ": another short line."; }' > "$work/text.md"
sed '32s/ã/ãã/' "$work/text.md" > "$work/expected"
cat > "$work/keys" <<'KEYS'
await-screen [SAVE]
keys \exgoto-line\r32\r
keys ^E
keys ^B^B
keys ^L
keys ã
keys ^X^S
wait 200
keys ^X^C
KEYS
(cd "$work"; CHEZEMAX_NO_INIT=1 "$work/pty" "$work/keys" 30 "$work/screen" "$root/chezemax" text.md)
cmp "$work/text.md" "$work/expected"
# C-x C-s restores the actual cursor after writing the save message. In the
# runner's 24-row PTY, C-l centres this line on row 12. The old bug moved it
# to row 22 after displaying the incomplete first byte of the typed character.
rest=$(LC_ALL=C sed -n 's/.*bytes saved\.//p' "$work/screen")
case "$rest" in
 *"$(printf '\033[12;')"*) ;;
 *) echo 'FAIL accented typing reframed the centred cursor';exit 1 ;;
esac
echo 'PASS accented typing preserves text, point and the centred viewport'
