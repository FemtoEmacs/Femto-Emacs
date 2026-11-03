#!/bin/sh
# Verify a disposable source export: restoration, corruption and stale inputs.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-bundle-test.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$work/tools"
cp tools/browser-assets.sh "$work/tools/"
while read -r digest file; do mkdir -p "$work/$(dirname "$file")";cp "$file" "$work/$file";done < web/prebuilt/SHA256SUMS
cp web/prebuilt/SHA256SUMS "$work/web/prebuilt/"
cd "$work"
sh tools/browser-assets.sh install
cmp build/chezweb.wasm web/prebuilt/chezweb.wasm
rm build/chezweb.js
sh tools/browser-assets.sh install
cmp build/chezweb.js web/prebuilt/chezweb.js
echo 'PASS portable browser assets install and missing outputs are restored'
rm build/chezweb.js build/chezweb.wasm
pending=''
for attempt in 1 2 3 4; do sh tools/browser-assets.sh install & pending="$pending $!";done
for job in $pending; do wait "$job";done
cmp build/chezweb.js web/prebuilt/chezweb.js
cmp build/chezweb.wasm web/prebuilt/chezweb.wasm
echo 'PASS concurrent restoration installs complete assets without temporary-file races'
# Parallel make regenerates these files; authoritative generator inputs,
# rather than half-written generated outputs, determine bundle freshness.
printf 'regenerating' > src/bridge-functions.c
printf 'regenerating' > compiled/editor-functions.scm
sh tools/browser-assets.sh check
echo 'PASS generated bridge outputs do not race the bundle verifier'
printf 'corruption' >> web/prebuilt/chezweb.wasm
if sh tools/browser-assets.sh install > failure 2>&1; then echo 'FAIL corrupt bundle accepted';exit 1;fi
cmp build/chezweb.wasm "$root/web/prebuilt/chezweb.wasm"
cp "$root/web/prebuilt/chezweb.wasm" web/prebuilt/chezweb.wasm
printf '\n/* changed */\n' >> src/app.c
if sh tools/browser-assets.sh check > failure 2>&1; then echo 'FAIL stale source accepted';exit 1;fi
cp "$root/src/app.c" src/app.c
printf '/* new source */\n' > src/new-browser-source.c
if sh tools/browser-assets.sh check > failure 2>&1; then echo 'FAIL new unbundled source accepted';exit 1;fi
grep -q 'source file list changed' failure
rm src/new-browser-source.c
sh tools/browser-assets.sh check
echo 'PASS corrupt assets, changed sources and new source files are rejected without replacing valid output'
