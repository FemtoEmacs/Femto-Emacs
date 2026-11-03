#!/bin/sh
# A real C-c d in a PTY must execute the browser command found on PATH.
# No actual browser opens; every launch writes into this disposable HOME.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-launch-test.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
${CC:-cc} -O2 tests/pty-keys.c -o "$work/pty-keys" -lutil 2>/dev/null || ${CC:-cc} -O2 tests/pty-keys.c -o "$work/pty-keys"
mkdir "$work/bin"
printf 'Browser launch fixture\n' > "$work/source.txt"
cat > "$work/keys" <<'KEYS'
wait 1500
keys ^Cd
wait 1800
keys ^X^C
KEYS
cat > "$work/bin/fixture-browser" <<'SH'
#!/bin/sh
printf '%s\n' "$1" > "$CHEZWEB_TEST_LAUNCH_LOG"
SH
chmod +x "$work/bin/fixture-browser"
case $(uname -s) in
 Linux) unset CHEZWEB_BROWSER;names='google-chrome google-chrome-stable chromium chromium-browser xdg-open' ;;
 *) export CHEZWEB_BROWSER=fixture-browser;names=fixture-browser ;;
esac
for browser in $names; do
 if [ "$browser" != fixture-browser ];then cp "$work/bin/fixture-browser" "$work/bin/$browser";fi
 HOME="$work" CHEZEMAX_NO_INIT=1 PATH="$work/bin" CHEZWEB_TEST_LAUNCH_LOG="$work/url" \
  "$work/pty-keys" "$work/keys" 20 "$work/screen" "$root/chezweb" "$work/source.txt"
 grep -q '^http://127\.0\.0\.1:[0-9][0-9]*/[0-9a-f][0-9a-f]*/$' "$work/url"
 grep -q 'Browser: http://127.0.0.1:' "$work/screen"
 rm "$work/url"
 if [ "$browser" != fixture-browser ];then rm "$work/bin/$browser";fi
 echo "PASS C-c d launches $browser through PATH and displays its local URL"
done
