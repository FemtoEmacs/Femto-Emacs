#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-script-installer.XXXXXX")
cleanup() {
 result=$?
 if [ "$result" -ne 0 ]; then
  echo "Installer test diagnostics retained in $work" >&2
  [ ! -f "$work/screen" ] || cat "$work/screen" >&2
 else rm -rf "$work"; fi
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM
mkdir "$work/atomic" "$work/home"
${CC:-cc} -O2 -std=gnu11 -Isrc tests/script-installer.c src/script-installer.c -o "$work/atomic-test"
"$work/atomic-test" "$work/atomic"
${CC:-cc} -O2 tests/pty-keys.c -o "$work/pty-keys" -lutil 2>/dev/null || ${CC:-cc} -O2 tests/pty-keys.c -o "$work/pty-keys"
printf '(define (installed-answer) 42)\n' > "$work/source.scm"
cat > "$work/keys" <<KEYS
await-screen installed-answer
keys ;unsaved\r
keys \\exscript-installer\\r
await-screen Install script as:
keys \\r
await-screen compile-scripts, then restart
keys \\exscript-installer\\r
await-screen Install script as:
keys \\r
await-screen Replace source.scm?
keys n\\r
await-screen Script installation cancelled
keys \\exscript-installer\\r
await-screen Install script as:
keys ^G
await-screen Script installation cancelled
keys \\exscript-installer\\r
await-screen Install script as:
keys ^A^K$work/home/.chezemax/users/cop\\t\\r
await-screen Replace copied.scm?
keys y\\r
await-screen compile-scripts, then restart
keys ^X^C
wait 200
keys y
KEYS
# Existing filename completion must work in the editable destination.
mkdir -p "$work/home/.chezemax/users"
printf 'old contents\n' > "$work/home/.chezemax/users/copied.scm"
HOME="$work/home" CHEZEMAX_NO_INIT=1 "$work/pty-keys" "$work/keys" 40 "$work/screen" "$root/chezweb" "$work/source.scm"
printf ';unsaved\n(define (installed-answer) 42)\n' > "$work/expected"
cmp "$work/expected" "$work/home/.chezemax/users/source.scm"
cmp "$work/expected" "$work/home/.chezemax/users/copied.scm"
printf '(define (installed-answer) 42)\n' > "$work/source-original"
cmp "$work/source-original" "$work/source.scm"
echo 'PASS script-installer: unsaved buffer snapshot, unchanged source, editable path/Tab, overwrite refusal/approval and cancellation'
