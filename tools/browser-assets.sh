#!/bin/sh
# Install the portable browser build, or record one rebuilt by a maintainer.
set -eu
cd "$(dirname "$0")/.."
manifest=web/prebuilt/SHA256SUMS
hash_files() {
 if command -v sha256sum >/dev/null 2>&1; then sha256sum "$@"; else shasum -a 256 "$@"; fi
}
source_files() {
 (
  find src femtoscheme schemer compiled scheme web -type d -name bkp -prune -o \
   -type d -path web/prebuilt -prune -o \
   -type f \( -name '*.c' -o -name '*.h' -o -name '*.scm' -o -name '*.js' \) \
   ! -path src/bridge-functions.c ! -path compiled/editor-functions.scm -print
  printf '%s\n' compiled/PROGRAM compiled/scripts/ORDER web/makefile.inc web/shell.html \
   femtoscheme/femtoscheme.boot schemer/compiler.wasm tools/gen-bridge.awk tools/gen-bridge-scheme.awk
 ) | LC_ALL=C sort -u
}
verify() {
 if [ ! -s "$manifest" ]; then
  echo 'The bundled browser files are missing. Restore web/prebuilt from this checkout.' >&2
  exit 1
 fi
 check_dir=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-browser-check.XXXXXX")
 trap 'rm -rf "$check_dir"' EXIT HUP INT TERM
 source_files > "$check_dir/expected"
 awk '$2 !~ /^web\/prebuilt\// {print $2}' "$manifest" | LC_ALL=C sort > "$check_dir/listed"
 if ! cmp -s "$check_dir/expected" "$check_dir/listed"; then
  echo 'The editor source file list changed; rebuild the browser bundle before publishing.' >&2
  exit 1
 fi
 if command -v sha256sum >/dev/null 2>&1; then
  if sha256sum -c "$manifest" > "$check_dir/log" 2>&1; then return;fi
 else
  if shasum -a 256 -c "$manifest" > "$check_dir/log" 2>&1; then return;fi
 fi
 cat "$check_dir/log" >&2
 echo 'The browser bundle does not match these editor sources.' >&2
 echo 'Restore the matching files, or, as a maintainer, run make browser-rebuild.' >&2
 exit 1
}
case ${1:-} in
 check) verify ;;
 install)
  verify
  mkdir -p build
  for file in chezweb.js chezweb.wasm; do
   cp "web/prebuilt/$file" "build/$file.new.$$"
   mv -f "build/$file.new.$$" "build/$file"
  done
  touch build/browser-assets.stamp
  ;;
 record)
  input=${2:?Supply the directory containing the rebuilt browser files}
  [ -s "$input/chezweb.js" ] && [ -s "$input/chezweb.wasm" ]
  mkdir -p web/prebuilt/bkp
  for file in chezweb.js chezweb.wasm SHA256SUMS; do
   if [ -f "web/prebuilt/$file" ]; then cp "web/prebuilt/$file" "web/prebuilt/bkp/$file";fi
  done
  cp "$input/chezweb.js" web/prebuilt/chezweb.js
  cp "$input/chezweb.wasm" web/prebuilt/chezweb.wasm
  # Track authoritative C/JS and Scheme inputs, never generated bridge files
  # (their generators/native.c are tracked), native objects or caches.
  # The compiler and boot image are portable Wasm/data, not native executables.
  (
   hash_files web/prebuilt/chezweb.js web/prebuilt/chezweb.wasm
   source_files | while IFS= read -r file; do hash_files "$file";done
  ) > "$manifest.new"
  mv -f "$manifest.new" "$manifest"
  chmod 644 web/prebuilt/chezweb.js web/prebuilt/chezweb.wasm "$manifest"
  ;;
 *) echo 'Usage: browser-assets.sh check|install|record DIRECTORY' >&2;exit 2 ;;
esac
