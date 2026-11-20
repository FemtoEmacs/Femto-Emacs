#!/bin/sh
# M-; must retain syntax state across definition-looking lines in strings.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-comment-context.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
cc=${CC:-cc}
$cc -O2 tests/pty-keys.c -o "$work/pty" -lutil 2>/dev/null || $cc -O2 tests/pty-keys.c -o "$work/pty"
mkdir -p "$work/home"
cat > "$work/t.scm" <<'SCM'
(define s "start
(fake definition
end") ; actual
SCM
cat > "$work/keys" <<'KEYS'
await-screen [SAVE]
keys \eg3\r
wait 300
keys \e;
wait 300
keys ^X^S
wait 300
keys ^X^C
KEYS
{ printf '(define s "start\n(fake definition\n'; printf '%-32s; actual\n' 'end")'; } > "$work/want"
(cd "$work"; HOME="$work/home" CHEZEMAX_NO_INIT=1 LC_ALL=C.UTF-8 "$work/pty" "$work/keys" 60 "$work/screen" "$root/chezemax" t.scm)
cmp "$work/want" "$work/t.scm"
echo 'PASS M-; aligns the existing comment after a multiline string without appending another'
