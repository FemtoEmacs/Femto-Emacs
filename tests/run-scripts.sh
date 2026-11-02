#!/bin/sh
# run-scripts.sh -- make check-scripts: the scripts compiled so far
# (compiled/scripts/, PORT-TO-SCHEMER.md step 4) give the same values as
# femtoscheme's originals (scheme/), case by case (tests/scripts-cases.scm)
set -eu
cd "$(dirname "$0")/.."
work=$(mktemp -d "${TMPDIR:-/tmp}/chezemax-scripts.XXXXXX")
trap '[ -n "${KEEP:-}" ] || rm -rf "$work"' EXIT HUP INT TERM
sh tools/build-program.sh "$work/scripts.wasm" compiled/bridge.scm compiled/editor-functions.scm \
   compiled/system.scm compiled/syntax.scm compiled/femtoscheme.scm compiled/editor.scm \
   $(cat compiled/scripts/ORDER) compiled/eval-compiled.scm \
   tests/scripts-compiled.scm tests/scripts-cases.scm
CHEZEMAX_REPORT="$work/f" CHEZEMAX_SCHEME=legacy CHEZEMAX_NO_INIT=1 ./chezemax --eval \
  '(begin (load "tests/scripts-femtoscheme.scm") (write-script-report))' > /dev/null
CHEZEMAX_REPORT="$work/c" CHEZEMAX_PROGRAM="$work/scripts.wasm" CHEZEMAX_SCHEME=legacy CHEZEMAX_NO_INIT=1 \
  ./chezemax --eval '(fe-compiled-event "key" "C-c 9")' > /dev/null
[ -s "$work/f" ] && [ -s "$work/c" ] || { echo "FAIL a report is missing"; exit 1; }
if ! cmp -s "$work/f" "$work/c"; then
    echo "FAIL the compiled scripts differ from femtoscheme's (< femtoscheme, > compiled):"
    diff "$work/f" "$work/c" || true
    exit 1
fi
echo "ok    $(grep -c . "$work/c") cases give the same values in both"
echo "PASS the compiled scripts: $(sed 's|.*/||' compiled/scripts/ORDER | tr '\n' ' ')"
