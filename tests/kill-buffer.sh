#!/bin/sh
# C-x k shows the buffer used most recently, as in Emacs, not the next in
# the list: from a.txt, C-x C-f b.txt and C-x k must come back to a.txt
# (it showed *backdoor*, 15 November 2026).  Also with three files, after
# C-x b, and with C-x 3, where the other pane's buffer comes after the
# rest; with no other buffer used, *scratch*, never *backdoor*.  Disposable home, files and PTY; the backdoor says the buffer.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-kill-buffer.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
cc=${CC:-cc}
$cc -O2 tests/pty-keys.c -o "$work/pty" -lutil 2>/dev/null ||
 $cc -O2 tests/pty-keys.c -o "$work/pty"
mkdir -p "$work/home/.chezemax"
printf 'watch none\nrepeats keep\n' > "$work/home/.chezemax/backdoor-claude.conf"
for f in a b c d; do echo "file $f" > "$work/$f.txt"; done
log="$work/home/.chezemax/backdoor.txt"
fail() { echo "FAIL $1"; cat "$log" 2>/dev/null; exit 1; }
run() {   # $1: the keys after the backdoor opens
 { echo 'await-screen [SAVE]'; echo 'keys \exbackdoor-claude\r'; echo 'wait 300'
   printf '%s\n' "$1"; echo 'wait 300'; echo 'keys \exbackdoor-claude\r'; echo 'wait 500'; echo 'keys ^X^C'; } > "$work/keys"
 (cd "$work"; HOME="$work/home" CHEZEMAX_NO_INIT=1 LC_ALL=C.UTF-8 "$work/pty" "$work/keys" 60 "$work/screen" "$root/chezemax" a.txt)
}
# the buffer after the Nth C-x k
after_kill() { grep '^#[0-9]* C-x k ' "$log" | sed -n "${1}p" | sed 's/.* size=[0-9]* \([^ ]*\).*/\1/'; }
f() { printf 'keys ^X^F^A^K%s/%s\\r\nwait 300' "$work" "$1"; }

run "$(f b.txt)
keys ^Xk
wait 300"
[ "$(after_kill 1)" = a.txt ] || fail "C-x k from b.txt showed $(after_kill 1), not a.txt"
echo 'PASS C-x k after C-x C-f comes back to the buffer before'

run "$(f b.txt)
$(f c.txt)
$(f d.txt)
keys ^Xb
wait 200
keys b.txt\\r
wait 300
keys ^Xk
wait 300
keys ^Xk
wait 300"
[ "$(after_kill 1)" = d.txt ] && [ "$(after_kill 2)" = c.txt ] ||
 fail "C-x k twice after d.txt, C-x b b.txt showed $(after_kill 1), $(after_kill 2), not d.txt, c.txt"
echo 'PASS C-x k goes back through the buffers in the order they were used'

run "$(f b.txt)
keys ^X3
wait 300
keys ^Xo
wait 200
$(f c.txt)
keys ^Xk
wait 300"
[ "$(after_kill 1)" = a.txt ] || fail "C-x k in the right pane showed $(after_kill 1), not a.txt (b.txt is in the left pane)"
echo "PASS with C-x 3, C-x k prefers a buffer the other pane does not show"

run "keys ^Xk
wait 300"
[ "$(after_kill 1)" = '*scratch*' ] || fail "C-x k of the only file showed $(after_kill 1), not *scratch*"
echo 'PASS C-x k of the only buffer used shows *scratch*'
