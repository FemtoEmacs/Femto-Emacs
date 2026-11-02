#!/bin/sh
# Prove self-rebuilding and compilation without linking the old Scheme VM.
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/schemer-proof.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
sh "$root/schemer/build-compiler.sh" "$work/a.wasm"
mkdir -p "$work/seed/schemer"
cp "$work/a.wasm" "$work/seed/schemer/compiler.wasm"
SCHEMER_SEED_DIRECTORY="$work/seed" sh "$root/schemer/build-compiler.sh" "$work/b.wasm"
cmp "$work/a.wasm" "$work/b.wasm"
if nm -g "$root/schemer-compile" | grep -E '[_ ]fl_(init|applyn|toplevel_eval)( |$)' >/dev/null; then
 echo 'FAIL: compiler links the old interpreter' >&2; exit 1
fi
printf '(begin (open-output-file "%s/should-not-exist") (+ 20 22))\n' "$work" > "$work/source.scm"
"$root/schemer-compile" --source "$work/source.scm" "$work/result.wasm" "$root"
test ! -e "$work/should-not-exist"
printf '(undefined-migration-procedure 1)\n' > "$work/bad.scm"
if "$root/schemer-compile" --source --strict "$work/bad.scm" "$work/bad.wasm" "$root" > "$work/invalid.log" 2>&1; then
 echo 'FAIL: strict compilation accepted an undefined procedure' >&2; exit 1
fi
test ! -e "$work/bad.wasm"
echo 'PASS compiled compiler: byte-identical self-rebuild, no interpreter linkage, no source execution, strict errors'
