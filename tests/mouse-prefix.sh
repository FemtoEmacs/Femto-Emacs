#!/bin/sh
# The mouse in the middle of a key (16 November 2026): Pedro pressed C-c,
# moved the mouse, then d.  The window reports each motion as a sequence
# that starts with Esc; the prefix took the Esc, the rest of the report
# went into the text ("[<35;46;13M"), and C-c d was lost.  Now a mouse
# report inside a key is dropped whole, as in Emacs: C-x, motion, h is
# C-x h; Esc, motion, f is M-f; both encodings (SGR and the old X10), and
# the text stays as it was; C-x <left>, an Esc sequence
# after a prefix that is no mouse report, still arrives.  Disposable home, file and PTY; the backdoor
# names the keys.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-mouse-prefix.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
cc=${CC:-cc}
$cc -O2 tests/pty-keys.c -o "$work/pty" -lutil 2>/dev/null ||
 $cc -O2 tests/pty-keys.c -o "$work/pty"
mkdir -p "$work/home/.chezemax"
printf 'watch page point mark\nmouse all\nrepeats keep\n' > "$work/home/.chezemax/backdoor-claude.conf"
printf 'one two three\nfour five six\n' > "$work/text.txt"
cp "$work/text.txt" "$work/before.txt"
log="$work/home/.chezemax/backdoor.txt"
fail() { echo "FAIL $1"; cat "$log" 2>/dev/null; cat -A "$work/text.txt"; exit 1; }
cat > "$work/keys" <<'KEYS'
await-screen [SAVE]
keys \exbackdoor-claude\r
wait 300
keys ^X
wait 100
keys \e[<35;46;13M\e[<35;47;13M
wait 100
keys h
wait 300
keys ^G\e<
wait 200
keys \e
wait 100
keys \e[<35;20;5M
wait 100
keys f
wait 300
keys \e
wait 100
keys \e[MC!!
wait 100
keys f
wait 300
keys ^X\e[D
wait 300
keys ^X\e[C
wait 300
keys ^X^S
wait 300
keys \exbackdoor-claude\r
wait 500
keys ^X^C
KEYS
(cd "$work"; HOME="$work/home" CHEZEMAX_NO_INIT=1 LC_ALL=C.UTF-8 "$work/pty" "$work/keys" 60 "$work/screen" "$root/chezemax" text.txt)
cmp -s "$work/text.txt" "$work/before.txt" || fail 'a mouse report inside a key went into the text'
grep -q '^#[0-9]* C-x h ' "$log" || fail 'C-x, the mouse, h is not C-x h'
[ "$(grep -c '^#[0-9]* esc f ' "$log")" = 2 ] || fail 'Esc, the mouse, f is not M-f (SGR and X10)'
grep '^#[0-9]* esc f ' "$log" | head -n 1 | grep -q ' pt=3 ' || fail 'the first M-f did not move point after "one"'
grep -q '^#[0-9]* C-x left ' "$log" || fail 'C-x <left>, an Esc sequence after a prefix, was lost'
echo 'PASS the mouse in the middle of a key is dropped: C-x h and M-f arrive whole, and no text is typed'
