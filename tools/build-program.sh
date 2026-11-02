#!/bin/sh
# build-program.sh OUT.wasm FILE.scm ... -- compile Scheme files, in order,
# into one program with Schemer (make chezemax.wasm; tests/run-bridge.sh).
set -eu
out=$1; shift
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/chezemax-program.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
for f in "$@"; do cat "$f" >> "$work/program.scm"; printf '\n' >> "$work/program.scm"; done
printf 'bridge-dispatch\n' >> "$work/program.scm"
"$root/schemer-compile" --source --strict "$work/program.scm" "$work/program.wasm" "$root"
cp "$work/program.wasm" "$out.new"
mv "$out.new" "$out"
