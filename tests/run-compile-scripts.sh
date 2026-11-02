#!/bin/sh
# run-compile-scripts.sh -- make check-compile-scripts: chezemax
# --compile-scripts and M-x compile-scripts, with a disposable home folder.
#   1. your code in ~/.chezemax/users is compiled with the scripts into
#      ~/.chezemax/chezemax.wasm, and the next start uses it;
#   2. code that does not compile leaves the compiled program as it was,
#      and M-x compile-scripts says so (in the background, as in the editor);
#   3. a compiled program older than Chezemax's own is not used, and the
#      editor says why.
# Each compilation takes a few minutes: Schemer compiles the whole program.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/chezemax-compile.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
fail() { echo "FAIL $1"; exit 1; }
export HOME="$work/home"
mkdir -p "$HOME/.chezemax/users/statistics"
cat > "$HOME/.chezemax/users/statistics/mean.scm" <<'EOF'
;; nothing to do with the editor: a statistic
(define (mean xs) (/ (apply + xs) (length xs)))
EOF

# 1. compiled, and used at the next start
./chezemax --compile-scripts > "$work/log" 2>&1 || { cat "$work/log"; fail "--compile-scripts"; }
[ -s "$HOME/.chezemax/chezemax.wasm" ] && [ -s "$HOME/.chezemax/chezemax.cwasm" ] || fail "no compiled program in ~/.chezemax"
grep -q "1 of yours" "$work/log" || { cat "$work/log"; fail "your file was not compiled"; }
[ "$(./chezemax --eval '(mean (list 1 2 3 6))')" = 3 ] || fail "the next start does not use your compiled code"
echo "ok    your code is compiled with the scripts and used at the next start"

# 2. code that does not compile: M-x compile-scripts, in the background
before=$(cksum < "$HOME/.chezemax/chezemax.wasm")
printf '(define (broken) (no-such-procedure-anywhere 1))\n' > "$HOME/.chezemax/users/statistics/broken.scm"
./chezemax --eval '(compile-scripts)' > /dev/null
status="$HOME/.chezemax/compile-scripts.log.status"
k=0
while [ ! -f "$status" ] && [ $k -lt 600 ]; do sleep 1; k=$((k + 1)); done
[ "$(cat "$status" 2>/dev/null)" = failed ] || fail "M-x compile-scripts did not report the failure"
grep -q "no-such-procedure-anywhere" "$HOME/.chezemax/compile-scripts.log" || fail "the log does not name the error"
[ "$(cksum < "$HOME/.chezemax/chezemax.wasm")" = "$before" ] || fail "a failed compilation replaced the program"
[ "$(./chezemax --eval '(mean (list 2 4))')" = 3 ] || fail "the program that worked is no longer used"
echo "ok    a failed compilation is reported and changes nothing"

# 3. older than Chezemax's own: not used, and said
touch -t 200001010000 "$HOME/.chezemax/chezemax.wasm"
got=$(./chezemax --eval '(list (top-level-bound? (quote mean)) (car *init-errors*))')
case $got in "(#f \"Your compiled scripts"*) ;; *) fail "an old compiled program was used ($got)" ;; esac
echo "PASS chezemax --compile-scripts and M-x compile-scripts"
