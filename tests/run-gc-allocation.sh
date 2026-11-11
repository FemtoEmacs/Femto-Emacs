#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-gc.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
./schemer-compile --source --strict tests/gc-allocation.scm "$work/gc.wasm" "$(pwd)"
./tests/gc-allocation-test "$work/gc.wasm"
