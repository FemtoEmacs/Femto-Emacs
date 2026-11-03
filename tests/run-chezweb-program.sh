#!/bin/sh
# run-chezweb-program.sh -- make check-browser: your compiled scripts in the
# browser editor.  Compiles a program with a users/ file defining (mean xs)
# in a disposable home folder (chezweb --compile-scripts, a few minutes),
# then runs tests/chezweb-program.cjs on it.
set -eu
cd "$(dirname "$0")/.."
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-program.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$work/.chezemax/users/statistics"
printf '(define (mean xs) (/ (apply + xs) (length xs)))\n' > "$work/.chezemax/users/statistics/mean.scm"
HOME="$work" ./chezweb --compile-scripts > "$work/log" 2>&1 || { cat "$work/log"; echo "FAIL --compile-scripts"; exit 1; }
CHEZWEB_TEST_PROGRAM="$work/.chezemax/chezemax.wasm" node tests/chezweb-program.cjs
