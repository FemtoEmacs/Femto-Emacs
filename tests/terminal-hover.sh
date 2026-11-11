#!/bin/sh
# A disposable terminal must request passive motion, describe SAVE, and disable
# passive reporting on exit. Injecting motion alone would miss a 1002-only bug.
set -eu
cd "$(dirname "$0")/.."
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-hover.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
cc=${CC:-cc}
$cc -O2 tests/pty-keys.c -o "$work/pty" -lutil 2>/dev/null ||
 $cc -O2 tests/pty-keys.c -o "$work/pty"
cat > "$work/keys" <<'KEYS'
await-screen [SAVE]
keys \e[<35;22;23M
await-screen Button runs save-buffer (C-x C-s)
keys \e[<35;1;1M
keys ^X^C
KEYS
editor=${CHEZWEB_HOVER_EDITOR:-./chezemax}
for runtime in compiled femtoscheme; do
 CHEZEMAX_NO_INIT=1 CHEZEMAX_SCHEME=$runtime "$work/pty" "$work/keys" 30 "$work/screen" "$editor" || { cat "$work/screen" >&2; exit 1; }
 grep -Fq "$(printf '\033[?1003h')" "$work/screen"
 grep -Fq "$(printf '\033[?1003l')" "$work/screen"
 echo "PASS $runtime terminal passive hover, SAVE description and mouse cleanup"
done
