#!/bin/sh
# run-library.sh -- make check-library: Schemer's library for the scripts
# (tests/schemer-library.scm), the older names and the scripts' forms
# (compiled/compat.scm, compiled/syntax.scm), compiled and run.
set -eu
cd "$(dirname "$0")/.."
work=$(mktemp -d "${TMPDIR:-/tmp}/chezemax-library.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
run() {   # NAME FILE...: compile the files as one program, run it, expect PASS
    name=$1; shift
    for f in "$@"; do cat "$f"; printf '\n'; done > "$work/$name.scm"
    ./schemer-compile --source --strict "$work/$name.scm" "$work/$name.wasm" "$(pwd)"
    ./tests/native-host-test "$work/$name.wasm" --output > "$work/$name.out" || true
    cat "$work/$name.out"
    grep -q '^PASS ' "$work/$name.out"
}
run library tests/schemer-library.scm
run compat compiled/bridge.scm compiled/syntax.scm compiled/compat.scm tests/compiled-compat.scm
echo "PASS Schemer's library for the scripts"
