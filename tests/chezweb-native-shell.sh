#!/bin/sh
# A harmless pipeline must still work in the native terminal editor.
set -eu
cd "$(dirname "$0")/.."
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-native-shell.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
${CC:-cc} -O2 tests/pty-keys.c -o "$work/pty-keys" -lutil 2>/dev/null || ${CC:-cc} -O2 tests/pty-keys.c -o "$work/pty-keys"
printf 'Disposable native shell test\n' > "$work/source.txt"
cat > "$work/keys" <<'KEYS'
wait 1500
keys \e!
wait 200
keys printf native-shell-preserved | tr a-z A-Z
keys ^Cs
wait 1000
keys ^Cq
wait 100
keys ^X^C
KEYS
HOME="$work" CHEZEMAX_NO_INIT=1 "$work/pty-keys" "$work/keys" 20 "$work/screen" ./chezweb "$work/source.txt"
grep -q NATIVE-SHELL-PRESERVED "$work/screen"
echo 'PASS native M-! keeps the full system shell, including pipelines'
