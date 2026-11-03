#!/bin/sh
# Neither missing nor obsolete browser SDKs affect users' make/browser.
set -eu
cd "$(dirname "$0")/.."
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-emcc-test.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
cat > "$work/emcc" <<'SH'
#!/bin/sh
echo called >> "$EMCC_TEST_LOG"
echo "clang-11: error: unknown argument: '-sSUPPORT_LONGJMP=wasm'" >&2
exit 1
SH
chmod +x "$work/emcc"
export EMCC_TEST_LOG="$work/calls"
make -n EMCC="$work/emcc" > "$work/plan" 2>&1
make -n EMCC="$work/missing" all > "$work/missing-plan" 2>&1
make -j2 EMCC="$work/emcc" browser > "$work/browser" 2>&1
make EMCC="$work/missing" browser > "$work/missing-browser" 2>&1
[ ! -e "$work/calls" ] || { echo 'FAIL user make invoked the browser compiler';exit 1; }
[ -s Chezweb.html ] && [ -s build/chezweb.js ] && [ -s build/chezweb.wasm ]
echo 'PASS default make and make browser install bundled assets without invoking any browser compiler'
if make -j2 EMCC="$work/emcc" browser-rebuild > "$work/developer" 2>&1; then echo 'FAIL maintainer rebuild accepted old SDK';exit 1;fi
grep -q 'JSPI and WebAssembly exceptions' "$work/developer"
grep -q 'make browser-rebuild' "$work/developer"
echo 'PASS browser toolchain checks apply only to explicit maintainer rebuilds'
