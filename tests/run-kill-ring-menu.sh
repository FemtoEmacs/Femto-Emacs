#!/bin/sh
# Disposable PTY regression: an empty ring must not trap keyboard input;
# a populated menu accepts the usual cancellation keys and preserves windows.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-kill-menu.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
${CC:-cc} -O2 tests/pty-keys.c -o "$work/pty-keys" -lutil 2>/dev/null || ${CC:-cc} -O2 tests/pty-keys.c -o "$work/pty-keys"
printf 'kill-menu fixture\n' > "$work/source.txt"
cat > "$work/keys" <<'KEYS'
await-screen kill-menu fixture
keys ^Ck
await-screen The kill ring is empty
keys returned-from-empty
keys ^A^K
keys ^X2
keys ^Ck
await-screen q/x/C-g exits
keys q
keys returned-from-q
keys ^Ck
keys ^G
keys returned-from-cancel
keys ^X^S
keys ^X^C
KEYS
HOME="$work" CHEZEMAX_NO_INIT=1 "$work/pty-keys" "$work/keys" 30 "$work/screen" "$root/chezweb" "$work/source.txt"
grep -q 'returned-from-qreturned-from-cancel' "$work/source.txt"
echo 'PASS terminal kill ring: empty returns; q/C-g exit and editing/saving continue'
