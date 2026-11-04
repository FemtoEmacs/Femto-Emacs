#!/bin/sh
# Completion must appear without a keystroke after a background job finishes.
# Use deterministic status files; the real compiler is covered separately.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-compile-notify.XXXXXX")
worker=
cleanup() {
 result=$?
 if [ -n "$worker" ]; then kill "$worker" 2>/dev/null || true; wait "$worker" 2>/dev/null || true; fi
 if [ "$result" -ne 0 ]; then
  echo "Compilation notification test failed; diagnostics: $work" >&2
  for screen in "$work"/*/screen; do [ ! -f "$screen" ] || cat "$screen" >&2; done
 else rm -rf "$work"; fi
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM
${CC:-cc} -O2 tests/pty-keys.c -o "$work/pty-keys" -lutil 2>/dev/null || ${CC:-cc} -O2 tests/pty-keys.c -o "$work/pty-keys"
unset CHEZEMAX_NO_INIT
for result in ok failed; do
 case_dir="$work/$result"
 mkdir -p "$case_dir/.chezemax"
 printf 'Idle compilation fixture\n' > "$case_dir/source.txt"
 printf 'Disposable compiler diagnostic\n' > "$case_dir/compile.log"
 cat > "$case_dir/.chezemax/init.scm" <<'SCM'
(set! *compile-scripts-log* (os.getenv "CHEZWEB_TEST_COMPILE_LOG"))
SCM
 case "$result" in
  ok) expected='Scripts compiled: restart Chezemax to use them' ;;
  failed) expected='The scripts were not compiled' ;;
 esac
 cat > "$case_dir/keys" <<KEYS
await-screen Idle compilation fixture
await-screen $expected
keys ^X
wait 700
keys ^C
KEYS
 # Do not finish the simulated worker before startup has drawn the fixture.
 # The PTY script sends no input until after the notification is visible.
 (
  tries=0
  until grep -q 'Idle compilation fixture' "$case_dir/screen" 2>/dev/null; do
   tries=$((tries + 1)); [ "$tries" -lt 600 ] || exit 1; sleep 0.05
  done
  sleep 0.5
  printf '%s\n' "$result" > "$case_dir/compile.log.status.tmp"
  mv "$case_dir/compile.log.status.tmp" "$case_dir/compile.log.status"
 ) &
 worker=$!
 HOME="$case_dir" CHEZWEB_TEST_COMPILE_LOG="$case_dir/compile.log" \
  "$work/pty-keys" "$case_dir/keys" 40 "$case_dir/screen" "$root/chezweb" "$case_dir/source.txt"
 wait "$worker"; worker=
 echo "PASS idle compilation notification: $result, with no keyboard or mouse input"
done
