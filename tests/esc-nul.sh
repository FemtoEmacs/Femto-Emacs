#!/bin/sh
# Esc then NUL (what a terminal sends for C-M-SPC, mark-sexp; C-x C-SPC is
# C-x then NUL) froze the editor (20 November 2026, found by
# tests/speed.sh): the key reader compared C strings, the NUL ended them, and
# every byte after was read into the key unseen.  Now the NUL ends the key
# ("esc C-space"): the keys after it arrive.  Disposable file and PTY.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-esc-nul.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
cc=${CC:-cc}
$cc -O2 tests/pty-keys.c -o "$work/pty" -lutil 2>/dev/null ||
 $cc -O2 tests/pty-keys.c -o "$work/pty"
mkdir -p "$work/home/.chezemax"
printf '(define (f x)\n  (g x))\n' > "$work/t.scm"
cat > "$work/keys" <<'EOF'
await-screen [SAVE]
keys \e^@
wait 300
keys ^X^@
wait 300
keys Q
wait 300
keys ^X^S
wait 300
keys ^X^C
EOF
status=0
(cd "$work"; HOME="$work/home" CHEZEMAX_NO_INIT=1 LC_ALL=C.UTF-8 "$work/pty" "$work/keys" 20 "$work/screen" "$root/chezemax" t.scm) || status=$?
[ $status -eq 0 ] || { echo "FAIL the editor did not quit after Esc NUL (status $status): it stopped reading keys"; exit 1; }
head -c 1 "$work/t.scm" | grep -q Q || { echo 'FAIL the key typed after Esc NUL and C-x NUL did not arrive'; exit 1; }
echo 'PASS Esc NUL (C-M-SPC) and C-x NUL are keys of their own; the keys after them arrive'
