#!/bin/sh
# Going about an Org file, and narrowing (compiled/scripts/org-goto.scm,
# narrow.scm, src/narrow.c), through a terminal on a disposable notes.org:
# C-c C-j lists the headings, RET goes to one, a click goes to one, q goes
# back; C-x n s narrows to a subtree (M-< and M-> stop at its ends, search
# does not leave it, the mode line says Narrow); C-x n n narrows to the
# region; C-x n w widens.  The Ask Claude menu leaves no buffer behind.
# Disposable home, file and PTY.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-org-goto.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
cc=${CC:-cc}
$cc -O2 tests/pty-keys.c -o "$work/pty" -lutil 2>/dev/null ||
 $cc -O2 tests/pty-keys.c -o "$work/pty"
mkdir -p "$work/home/.chezemax"
cat > "$work/notes.org" <<'ORG'
* One
one text
** One.a
sub text
* Two
two text
* Three
three text
ORG
cat > "$work/keys" <<'KEYS'
await-screen [SAVE]
keys ^C^J
await-screen Headings of notes.org
keys ^N^N\r
wait 300
keys !
keys ^C^J
await-screen RET or a click
keys \e[<0;3;3M\e[<0;3;3m
wait 300
keys @
keys ^C^J
wait 300
keys ^N^Nq
wait 300
keys ~
keys ^Ssub text\r
wait 200
keys ^Xns
wait 300
keys \e<<
keys \e>>
keys ^SThree\r
wait 300
keys ^G
keys ^Xnw
wait 200
keys \e<^Stwo text\r
wait 200
keys ^A
keys \e:(set-mark (point))\r
wait 300
keys ^E^Xnn
wait 300
keys \e<[
keys ^Xnw
wait 200
keys ^Xnx
wait 300
keys \e:(list 'BEFORE (get-buffer-count))\r
wait 1500
keys ^Cr
wait 500
keys ^G
wait 300
keys \e:(list 'AFTER (get-buffer-count))\r
wait 1500
keys ^X^S
wait 300
keys ^X^C
KEYS
(cd "$work"; HOME="$work/home" LC_ALL=C.UTF-8 CHEZEMAX_NO_INIT=1 "$work/pty" "$work/keys" 90 "$work/screen" "$root/chezemax" notes.org) || true
cat > "$work/expected" <<'ORG'
@~* One
one text
<** One.a
sub text
!* Two
[two text
>* Three
three text
ORG
fail() { echo "FAIL $1"; exit 1; }
cmp -s "$work/notes.org" "$work/expected" || { echo 'FAIL notes.org'; diff "$work/expected" "$work/notes.org"; exit 1; }
grep -q 'Narrow' "$work/screen" || fail 'the mode line did not say Narrow'
grep -q 'Failing' "$work/screen" || fail 'search found text outside the narrowed part'
grep -q 'C-x n x is not bound' "$work/screen" || fail 'C-x n x'
before=$(grep -o '(BEFORE [0-9]*)' "$work/screen" | head -n 1 | tr -dc 0-9)
after=$(grep -o '(AFTER [0-9]*)' "$work/screen" | head -n 1 | tr -dc 0-9)
[ -n "$before" ] && [ "$before" = "$after" ] || fail "the Ask Claude menu left a buffer behind ($before buffers, then $after)"
echo 'PASS C-c C-j (RET, a click, q), C-x n s, C-x n n, C-x n w; search stays inside; menus leave no buffer'
