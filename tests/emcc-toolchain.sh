#!/bin/sh
# An obsolete or missing optional browser compiler must not break native make.
set -eu
cd "$(dirname "$0")/.."
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-emcc-test.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
cat > "$work/emcc" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$EMCC_TEST_LOG"
if [ "$EMCC_TEST_MODE" = old ]; then
 echo "clang-11: error: unknown argument: '-sSUPPORT_LONGJMP=wasm'" >&2
 exit 1
fi
# Simulate a compatible compiler for make's dependency-selection test.
exit 0
SH
chmod +x "$work/emcc"
export EMCC_TEST_LOG="$work/calls" EMCC_TEST_MODE=old
if EMCC="$work/emcc" sh tools/check-emcc.sh > "$work/error" 2>&1; then echo 'FAIL accepted obsolete emcc';exit 1;fi
grep -q 'emsdk activate latest' "$work/error"
grep -q 'terminal and SDL editors' "$work/error"
if EMCC="$work/emcc" sh tools/check-emcc.sh --quiet > "$work/quiet" 2>&1; then echo 'FAIL quiet probe accepted obsolete emcc';exit 1;fi
[ ! -s "$work/quiet" ] || { echo 'FAIL quiet probe emitted compiler noise';exit 1; }
echo 'PASS obsolete emcc: clear explicit diagnostic and quiet automatic probe'
make -n EMCC="$work/emcc" > "$work/plan" 2>&1
grep -q 'Browser build skipped' "$work/plan"
grep -q 'cp chezemax chezweb' "$work/plan"
if grep -q -- '-sJSPI=1' "$work/plan"; then echo 'FAIL old SDK still selected browser compilation';exit 1;fi
make -n EMCC="$work/missing" all > "$work/missing-plan" 2>&1
grep -q 'cp chezemax chezweb' "$work/missing-plan"
if grep -q -- '-sJSPI=1' "$work/missing-plan"; then echo 'FAIL missing SDK selected browser compilation';exit 1;fi
echo 'PASS default native make works with an obsolete or absent emcc'
: > "$work/calls"
if make -j2 EMCC="$work/emcc" browser > "$work/browser-error" 2>&1; then echo 'FAIL browser build accepted old SDK';exit 1;fi
grep -q 'JSPI and WebAssembly exceptions' "$work/browser-error"
if grep -q 'src/app.c' "$work/calls"; then echo 'FAIL browser compilation started before toolchain rejection';exit 1;fi
echo 'PASS parallel make browser rejects old SDK before compiling editor sources'
EMCC_TEST_MODE=new EMCC="$work/emcc" sh tools/check-emcc.sh
EMCC_TEST_MODE=new make -n EMCC="$work/emcc" all > "$work/current-plan" 2>&1
grep -q 'check-emcc.sh' "$work/current-plan"
echo 'PASS a compatible compiler retains automatic browser builds'
