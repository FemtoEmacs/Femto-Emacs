#!/bin/sh
# Rebuild Schemer with its existing compiled seed; no interpreter or Node.
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
seed_root=${SCHEMER_SEED_DIRECTORY:-"$root"}
output=${1:-"$root/schemer/compiler.wasm"}
work=$(mktemp -d "${TMPDIR:-/tmp}/schemer-selfhost.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
for name in compiler-support wasm expand compiler browsered link; do
 cat "$root/schemer/$name.scm" >> "$work/compiler.scm"
 printf '\n' >> "$work/compiler.scm"
done
printf '\n(define compiled-prelude (quote (\n' >> "$work/compiler.scm"
cat "$root/schemer/prelude.scm" >> "$work/compiler.scm"
printf '\n)))\n' >> "$work/compiler.scm"
cat "$root/schemer/compiler-main.scm" >> "$work/compiler.scm"
"$root/schemer-compile" --source --strict "$work/compiler.scm" "$work/compiler.wasm" "$seed_root"
cp "$work/compiler.wasm" "$output.new"
mv "$output.new" "$output"
