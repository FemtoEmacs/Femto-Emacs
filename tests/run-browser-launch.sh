#!/bin/sh
# A real C-c d in a PTY must execute the browser command found on PATH.
# No actual browser opens; every launch writes into this disposable HOME.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-launch-test.XXXXXX")
cleanup() {
 status=$?
 if [ "$status" -ne 0 ]; then
  echo "Browser launch test failed; diagnostics retained in $work" >&2
  if [ -f "$work/screen" ]; then cat "$work/screen" >&2; fi
 else
  rm -rf "$work"
 fi
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM
${CC:-cc} -O2 tests/pty-keys.c -o "$work/pty-keys" -lutil 2>/dev/null || ${CC:-cc} -O2 tests/pty-keys.c -o "$work/pty-keys"
mkdir "$work/bin"
printf 'Browser launch fixture\n' > "$work/source.txt"
cat > "$work/keys" <<KEYS
await-screen Browser launch fixture
keys ^Cd
await-file $work/url
await-screen Browser: http://127.0.0.1:
keys ^X^C
KEYS
cat > "$work/bin/fixture-browser" <<'SH'
#!/bin/sh
# Deliberately exceed the former 1.8-second completion delay.
"$CHEZWEB_TEST_SLEEP" 2
printf '%s\n' "$1" > "$CHEZWEB_TEST_LAUNCH_LOG"
SH
chmod +x "$work/bin/fixture-browser"
sleep_program=$(command -v sleep)
# Also exceed the former 1.5-second startup delay before the editor can
# accept keys. Readiness, rather than machine speed, must control the test.
cat > "$work/delayed-editor" <<'SH'
#!/bin/sh
"$CHEZWEB_TEST_SLEEP" 2
exec "$CHEZWEB_TEST_EDITOR" "$@"
SH
chmod +x "$work/delayed-editor"
case $(uname -s) in
 Linux) unset CHEZWEB_BROWSER;names='google-chrome google-chrome-stable chromium chromium-browser xdg-open' ;;
 *) export CHEZWEB_BROWSER=fixture-browser;names=fixture-browser ;;
esac
for browser in $names; do
 if [ "$browser" != fixture-browser ];then cp "$work/bin/fixture-browser" "$work/bin/$browser";fi
 HOME="$work" CHEZEMAX_NO_INIT=1 PATH="$work/bin" CHEZWEB_TEST_LAUNCH_LOG="$work/url" CHEZWEB_TEST_SLEEP="$sleep_program" CHEZWEB_TEST_EDITOR="$root/chezweb" \
  "$work/pty-keys" "$work/keys" 20 "$work/screen" "$work/delayed-editor" "$work/source.txt"
 grep -q '^http://127\.0\.0\.1:[0-9][0-9]*/[0-9a-f][0-9a-f]*/$' "$work/url"
 grep -q 'Browser: http://127.0.0.1:' "$work/screen"
 rm "$work/url"
 if [ "$browser" != fixture-browser ];then rm "$work/bin/$browser";fi
 echo "PASS C-c d launches $browser through PATH and displays its local URL"
done
