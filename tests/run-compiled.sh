#!/bin/sh
# Test the Wasmtime host against Schemer's compiler fixtures; no Node.js.
# Run: make check-compiled
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
task_tmp=$(mktemp -d "${TMPDIR:-/tmp}/chezemax-tests.XXXXXX")
trap 'rm -rf "$task_tmp"' EXIT HUP INT TERM
for expected in tests/compiled-fixtures/*.out; do
    name=$(basename "$expected" .out)
    ./schemer-compile --source \
        "$root/tests/compiled-fixtures/$name.scm" "$task_tmp/test.wasm" "$root"
    status=0
    ./tests/native-host-test "$task_tmp/test.wasm" --output > "$task_tmp/got" || status=$?
    if [ "$name" = errors ]; then [ "$status" = 1 ]; else [ "$status" = 0 ]; fi
    if ! cmp -s "$expected" "$task_tmp/got"; then
        diff -u "$expected" "$task_tmp/got"
        exit 1
    fi
    echo "ok    compiled $name"
done
CHEZEMAX_SCHEME=femtoscheme CHEZEMAX_TEST_DIR="$task_tmp" CHEZEMAX_NO_INIT=1 ./chezemax --eval '(load "tests/compiled.scm")'
