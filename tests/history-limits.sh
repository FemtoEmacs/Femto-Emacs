#!/bin/sh
# Policy tests run in the actual owning Scheme module, not serialized RPC copies.
set -eu
cd "$(dirname "$0")/.."
work=$(mktemp -d "${TMPDIR:-/tmp}/chezemax-history.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
CHEZEMAX_NO_INIT=1 CHEZEMAX_SCHEME=femtoscheme ./chezemax --eval \
 '(define payload "abcd") (load "tests/history-limits.scm")' > "$work/legacy"
grep -q 'PASS bounded kill ring' "$work/legacy"
printf '(define payload (string->utf8 "abcd"))\n' > "$work/body.scm"
cat tests/history-limits.scm >> "$work/body.scm"
set -- $(awk -f tools/program-files.awk compiled/PROGRAM)
sh tools/build-program.sh "$work/policy.wasm" "$@" "$work/body.scm"
CHEZEMAX_NO_INIT=1 CHEZEMAX_PROGRAM="$work/policy.wasm" ./chezemax --eval '(history-limit-test-passed)' > "$work/compiled"
grep -qx '#t' "$work/compiled"
echo 'PASS compiled and legacy kill-ring/undo/redo retention policies and exact accounting'

CHEZEMAX_NO_INIT=1 ./chezemax --eval '(begin (insert "a\nb") (goto-line 2) (point))' | grep -qx 2
CHEZEMAX_NO_INIT=1 ./chezemax --eval '(begin (insert "a\n") (goto-line 2) (point))' | grep -qx 2
CHEZEMAX_NO_INIT=1 ./chezemax --eval '(begin (goto-line 1) (point))' | grep -qx 0
echo 'PASS M-g positions: unterminated last line, trailing empty line, empty buffer'
