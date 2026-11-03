#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-spawn-test.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
${CC:-cc} -std=gnu11 -Isrc tests/spawn-program.c src/system.c -o "$work/spawn-test"
mkdir "$work/bin"
cat > "$work/bin/google-chrome" <<'SH'
#!/bin/sh
printf '%s\n' "$@" > "$SPAWN_TEST_LOG"
SH
chmod +x "$work/bin/google-chrome"
url='http://127.0.0.1:12345/token/'
literal='spaces ; $(not-a-shell-command)'
PATH="$work/bin:$PATH" SPAWN_TEST_LOG="$work/result" "$work/spawn-test" google-chrome "$url" "$literal"
for attempt in 1 2 3 4 5 6 7 8 9 10; do [ ! -s "$work/result" ] || break;sleep 0.1;done
printf '%s\n' "$url" "$literal" > "$work/expected"
cmp "$work/expected" "$work/result"
if "$work/spawn-test" "$work/nonexistent-browser" > "$work/error" 2>&1;then echo 'FAIL missing executable was accepted';exit 1;fi
grep -q 'No such file' "$work/error"
echo 'PASS detached browser command lookup uses PATH, preserves literal arguments, and reports missing programs'
