#!/bin/sh
# Random walks over the C core under AddressSanitizer and
# UndefinedBehaviorSanitizer (tests/fuzz-core.c explains the invariants).
#   sh tests/fuzz-core.sh                 a short walk with seed 1 (make check)
#   sh tests/fuzz-core.sh -t 300          5 minutes, a new seed (make check-fuzz-core)
# Any option is passed to fuzz-core.  Without the sanitizers (a compiler
# that lacks them) the invariants are still checked, and it says so.
set -eu
cd "$(dirname "$0")/.."
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-fuzz.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
cc=${CC:-cc}
# PE unwind tables can retain otherwise unused editor functions.  This
# standalone C harness needs only its reachable core, not UI/process code.
case $(uname -s) in
 Darwin) gc=-Wl,-dead_strip ;;
 CYGWIN*|MINGW*|MSYS*) gc="-Wl,--gc-sections,--exclude-all-symbols -fno-asynchronous-unwind-tables -fno-unwind-tables" ;;
 *) gc=-Wl,--gc-sections ;;
esac
files="tests/fuzz-core.c tests/no-terminal.c src/data.c src/command.c src/gap.c src/display.c src/width.c src/buffer.c src/narrow.c src/fold.c src/undo.c src/interface.c src/sexp.c"
if $cc -g -O1 -fsanitize=address,undefined -fno-sanitize-recover=undefined -fno-omit-frame-pointer \
     -ffunction-sections -fdata-sections $gc -Isrc $files -o "$work/fuzz" 2> "$work/log"; then
	sanitizers="AddressSanitizer and UndefinedBehaviorSanitizer"
else
	$cc -g -O1 -ffunction-sections -fdata-sections $gc -Isrc $files -o "$work/fuzz"
	sanitizers="no sanitizers ($cc has none)"
fi
echo "fuzz-core under $sanitizers"
if [ $# -eq 0 ]; then set -- -s 1 -n 300 -k 300; fi
ASAN_OPTIONS=${ASAN_OPTIONS:-detect_leaks=0} "$work/fuzz" "$@"
