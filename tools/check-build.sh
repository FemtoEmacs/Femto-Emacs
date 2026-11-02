#!/bin/sh
# Check the terminal toolchain without running a terminal or installing files.
set -eu
cd "$(dirname "$0")/.."
sh tools/host-platform.sh >/dev/null
work=$(mktemp -d "${TMPDIR:-/tmp}/chezemax-toolchain.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
cat > "$work/probe.c" <<'C'
#include <curses.h>
#include <assert.h>
static_assert(sizeof(void *) == 8, "A 64-bit C11 compiler is required");
typedef char require_64_bit_pointers[(sizeof(void *) == 8) ? 1 : -1];
int main(void) { return initscr() == 0; }
C
if ! ${CC:-cc} ${CPPFLAGS:-} ${CFLAGS:-} ${CURSES_CFLAGS:-} "$work/probe.c" ${LDFLAGS:-} ${CURSES_LIBS:--lncurses} -o "$work/probe" > "$work/log" 2>&1; then
 cat "$work/log" >&2
 echo 'Cannot build the terminal backend. Install a C compiler and ncurses development files.' >&2
 echo 'macOS: xcode-select --install. Debian/Ubuntu: apt install build-essential libncurses-dev.' >&2
 exit 1
fi
