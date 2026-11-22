#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-clip-capacity.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
cc=${CC:-cc}
unwind=""
case $(uname -s) in Darwin) gc=-Wl,-dead_strip ;; CYGWIN*|MINGW*|MSYS*) gc="-Wl,--gc-sections,--exclude-all-symbols"; unwind="-fno-asynchronous-unwind-tables -fno-unwind-tables" ;; *) gc=-Wl,--gc-sections ;; esac
awk 'BEGIN {for(i=0;i<1024*1024+17;i++)printf "x"}' > "$work/text"
printf '#!/bin/sh\ncat "%s/text"\n' "$work" > "$work/pbpaste"
cp "$work/pbpaste" "$work/xclip"
chmod +x "$work/pbpaste" "$work/xclip"
for variant in native cygwin; do
 awk 'BEGIN {for(i=0;i<1024*1024+17;i++)printf "x"}' > "$work/text"
 defs=""
 [ "$variant" != cygwin ] || defs=-DCHEZWEB_TEST_CYGWIN_CLIPBOARD
 $cc -O1 $unwind -ffunction-sections -fdata-sections -Isrc $defs -Dmalloc=clip_test_malloc -Drealloc=clip_test_realloc -Dfree=clip_test_free -c src/term.c -o "$work/term.o"
 $cc -O1 $unwind -Isrc $defs $gc tests/clipboard-capacity.c "$work/term.o" -o "$work/check"
 (unset WAYLAND_DISPLAY; PATH="$work:$PATH" DISPLAY=:0 CLIPBOARD_TEST_TEXT="$work/text" "$work/check")
done
