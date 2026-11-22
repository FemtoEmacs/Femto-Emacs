#!/bin/sh
# Faults that tests/fuzz-editor.sh found (21 November 2026), as fixed tests.
# The editor runs with CHEZWEB_CHECK=1 (src/check.c): it aborts at the first
# key that breaks an invariant.
#  1. Two windows on one text: in one, C-w of a region that ends at the
#     cursor; the other window's point followed the text the wrong way,
#     to -10 (record_change now moves every window's point, undo.c).
#  2. A long text, M->, C-x 2, then C-w of all of it: the start of the
#     page stayed far past the end of the text, and the display read there
#     (heap-use-after-free under AddressSanitizer; undo.c moves it now).
#  3. C-x 3, a byte that is not a character, C-x o, ω, C-/: the undo of ω
#     put point where it was in the other window, inside U+FFFD: a typed
#     character beyond ASCII did not start a command for undo (main.c,
#     core.scm "typed").
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-fuzz-found.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
cc=${CC:-cc}
$cc -O2 tests/pty-keys.c -o "$work/pty" -lutil 2>/dev/null || $cc -O2 tests/pty-keys.c -o "$work/pty"
mkdir -p "$work/home"
export HOME="$work/home" CHEZEMAX_NO_INIT=1 LC_ALL=C.UTF-8 CHEZWEB_CHECK=1 CHEZWEB_CHECK_FILE="$work/check.txt"
fail() { echo "FAIL $1"; if [ -s "$work/check.txt" ]; then cat "$work/check.txt"; fi; exit 1; }
run() {   # file; the keys (pty-keys lines) on standard input
	rm -f "$work/check.txt"
	{ echo 'await-screen [SAVE]'; cat; echo 'keys \e:(list (quote POINT) (point) (buffer-size))\r'; echo 'await-screen (POINT'; echo 'wait 200'; echo 'keys ^G^X^C'; echo 'wait 300'; echo 'keys y'; } > "$work/keys"
	(cd "$work"; "$work/pty" "$work/keys" 60 "$work/screen" "$root/chezemax" "$1") > /dev/null 2>&1 || true
	grep -ao '(POINT [0-9]* [0-9]*)' "$work/screen" | tail -1 || true
}

printf 'abcdefghijklmnopqrst\n' > "$work/a.txt"
got=$(printf 'keys ^X2\nkeys ^F^F^F^F^F^F^F^F^F^F\nkeys ^Xo\nkeys \\e>\nkeys ^@\nkeys \\e<\nkeys ^W\nkeys ^Xo\nkeys x\n' | run a.txt)
[ ! -s "$work/check.txt" ] || fail "the other window's point after C-w"
[ "$got" = "(POINT 1 1)" ] || fail "the other window's point after C-w: $got, not (POINT 1 1)"
echo 'PASS after C-w in one window, the other window on the same text keeps its point in the text'

awk 'BEGIN { for (i = 1; i <= 200; i++) printf "line %d of a text that scrolls\n", i }' > "$work/c.txt"
got=$(printf 'keys \\e<\nkeys ^@\nkeys \\e>\nkeys ^X2\nkeys ^W\n' | run c.txt)
[ ! -s "$work/check.txt" ] || fail "the page start after C-w of the whole text"
[ "$got" = "(POINT 0 0)" ] || fail "C-w of the whole text: $got, not (POINT 0 0)"
echo 'PASS after C-w of the whole text, the start of the page is in the text'

printf 'Olá\n' > "$work/b.txt"
got=$(printf 'keys ^X3\nkeys \303\nkeys ^Xo\nkeys ω\nkeys ^_\n' | run b.txt)
[ ! -s "$work/check.txt" ] || fail "undo after a character beyond ASCII"
[ "$got" = "(POINT 0 8)" ] || fail "undo of ω typed after C-x o: $got, not (POINT 0 8)"
echo 'PASS C-/ of a character beyond ASCII typed after C-x o puts point back in this window'
