#!/bin/sh
# Real terminal framing: pasted newlines bypass Markdown Return handlers.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-paste.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
cc=${CC:-cc}
$cc -O2 tests/pty-keys.c -o "$work/pty" -lutil 2>/dev/null ||
 $cc -O2 tests/pty-keys.c -o "$work/pty"
for runtime in compiled femtoscheme; do
 for scenario in literal undo readonly; do
  printf 'Start\n' > "$work/text.md"
  cp "$work/text.md" "$work/expected"
  cat > "$work/keys" <<'KEYS'
await-screen [SAVE]
keys \e>
KEYS
  if [ "$scenario" = readonly ]; then printf 'keys ^X^Q\n' >> "$work/keys"; fi
  cat >> "$work/keys" <<'KEYS'
keys \e[200~1. **ã**\r   paragraph\r\r2. end\r\e[201~
KEYS
  if [ "$scenario" = undo ]; then printf 'keys ^U\n' >> "$work/keys"; fi
  if [ "$scenario" = literal ]; then
   printf '1. **ã**\n   paragraph\n\n2. end\n' >> "$work/expected"
  fi
  cat >> "$work/keys" <<'KEYS'
keys ^X^S
wait 150
keys ^X^C
KEYS
  (cd "$work"; CHEZEMAX_NO_INIT=1 CHEZEMAX_SCHEME=$runtime "$work/pty" "$work/keys" 30 "$work/screen" "$root/chezemax" text.md)
  cmp "$work/text.md" "$work/expected"
  echo "PASS $runtime bracketed paste: $scenario"
 done
done
