#!/bin/sh
# Fetch a pinned, checksum-verified Wasmtime C SDK for this computer.
# Run: make fetch-wasmtime (curl, tar; unzip on Windows/MSYS2).
set -eu
cd "$(dirname "$0")/.."
dest=${WASMTIME_ROOT:-runtime/wasmtime}
target=$(sh tools/host-platform.sh)
case $target in *-windows) os=windows ;; *) os=posix ;; esac
if [ -f "$dest/include/wasmtime.h" ] && [ -d "$dest/lib" ]; then
 if [ -f "$dest/.chezemax-target" ] && [ "$(cat "$dest/.chezemax-target")" != "$target" ]; then
  echo "Wasmtime SDK in $dest belongs to another architecture. Set WASMTIME_ROOT to a $target SDK." >&2
  exit 1
 fi
 exit 0
fi
version=50.0.1
case $target in
    aarch64-linux) digest=1a36140a016a9cc098f02a37bb0cc7be6451032861ba70049127928d2f31ef84 ;;
    aarch64-macos) digest=a49327ca596fae51cd92e230265132112bb7896c5a24e4d58cd05b56612e26bb ;;
    aarch64-windows) digest=84580636d4896df45d6a21d8c60ad9cf702d3934c6c70d98d49c21eba0470253 ;;
    x86_64-linux) digest=e2c0c26e1aef52f82f0b9918ad6f34cc30f4b557aee3e261cb127a9462be8f4d ;;
    x86_64-macos) digest=b6d436cba5c0964785c6ff7c9b5a743131555a0227b4f742185c4fb520c502c5 ;;
    x86_64-windows) digest=8b461d9dc12b076d0414b1023433bbb2dc08d3b1c0f0a156853ede35f0147802 ;;
    *) echo "No pinned Wasmtime package for $target" >&2; exit 1 ;;
esac
suffix=tar.xz
if [ "$os" = windows ]; then suffix=zip; fi
name=wasmtime-v$version-$target-c-api
archive=$name.$suffix
task_tmp=$(mktemp -d "${TMPDIR:-/tmp}/chezemax-wasmtime.XXXXXX")
trap 'rm -rf "$task_tmp"' EXIT HUP INT TERM
echo "Downloading Wasmtime $version for $target..."
curl -fL "https://github.com/bytecodealliance/wasmtime/releases/download/v$version/$archive" -o "$task_tmp/$archive"
if command -v sha256sum >/dev/null 2>&1; then
    actual=$(sha256sum "$task_tmp/$archive" | cut -d ' ' -f 1)
else
    actual=$(shasum -a 256 "$task_tmp/$archive" | cut -d ' ' -f 1)
fi
[ "$actual" = "$digest" ] || { echo "Wasmtime checksum mismatch" >&2; exit 1; }
if [ "$suffix" = zip ]; then unzip -q "$task_tmp/$archive" -d "$task_tmp"; else tar -xf "$task_tmp/$archive" -C "$task_tmp"; fi
mkdir -p "$dest"
cp -R "$task_tmp/$name/include" "$dest/"
cp -R "$task_tmp/$name/lib" "$dest/"
for license in LICENSE README.md; do
    if [ -f "$task_tmp/$name/$license" ]; then cp "$task_tmp/$name/$license" "$dest/"; fi
done
printf '%s\n' "$target" > "$dest/.chezemax-target"
echo "Wasmtime installed in $dest ($target)"
