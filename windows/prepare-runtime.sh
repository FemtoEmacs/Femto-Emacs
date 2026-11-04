#!/bin/sh
# Windows builder only. Link the native Wasmtime C DLL through its exports.
set -eu
cd "$(dirname "$0")/.."
case $(uname -s) in CYGWIN*) ;; *) echo 'Use a Cygwin x86_64 build host' >&2; exit 1;; esac
sh tools/fetch-wasmtime.sh
dll=$(find runtime/wasmtime -iname '*wasmtime*.dll' -print | head -1)
[ -n "$dll" ] || { echo 'Wasmtime DLL missing' >&2; exit 1; }
mkdir -p build/windows
# GNU ld can consume a Microsoft DLL directly through this import library.
{ echo "LIBRARY $(basename "$dll")"; echo EXPORTS; objdump -p "$dll" | awk '/^\[Ordinal\/Name Pointer\] Table/{on=1;next} on && /^\t\[/{print $NF}'; } > build/windows/wasmtime.def
grep -q wasmtime_module_new build/windows/wasmtime.def
dlltool -d build/windows/wasmtime.def -l runtime/wasmtime/lib/libwasmtime.dll.a
# Both make-time tools and installed executables need the DLL on PATH.
chmod +x "$dll"
cp "$dll" .
chmod +x "$(basename "$dll")"
