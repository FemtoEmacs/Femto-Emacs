#!/bin/sh
# SDK routing is testable without downloading a runtime for another computer.
set -eu
cd "$(dirname "$0")/.."
check() { actual=$(sh tools/host-platform.sh "$1" "$2");[ "$actual" = "$3" ] || { echo "FAIL $1/$2: $actual";exit 1; }; }
check Darwin x86_64 x86_64-macos
check Darwin arm64 aarch64-macos
check Darwin aarch64 aarch64-macos
check Linux x86_64 x86_64-linux
check Linux aarch64 aarch64-linux
check Linux amd64 x86_64-linux
check MINGW64_NT x86_64 x86_64-windows
if sh tools/host-platform.sh Darwin i386 >/dev/null 2>&1; then echo 'FAIL accepted 32-bit target';exit 1;fi
if sh tools/host-platform.sh Plan9 x86_64 >/dev/null 2>&1; then echo 'FAIL accepted unknown OS';exit 1;fi
work=$(mktemp -d "${TMPDIR:-/tmp}/chezemax-platform.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
printf '#!/bin/sh\nprintf "x86_64-apple-darwin\\n"\n' > "$work/compiler"
chmod +x "$work/compiler"
[ "$(CC="$work/compiler" sh tools/host-platform.sh Darwin)" = x86_64-macos ] || { echo 'FAIL compiler target was ignored';exit 1; }
echo 'PASS host platform: Intel/ARM Macs, Intel/ARM Linux, aliases and unsupported targets'
