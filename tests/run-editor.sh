#!/bin/sh
# run-editor.sh -- make check: Chezemax edits with every script compiled
# (PORT-TO-SCHEMER.md, step 4).  The editor runs in a terminal of its own
# (tests/pty-keys.c) on a disposable file, with a disposable home folder whose
# ~/.chezemax/init.scm is compiled at start-up; keys are typed into
# it as a person would, then the saved file is checked.  No real document is
# touched, and no assistant is contacted.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/chezemax-editor.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
CC=${CC:-cc}
$CC -O2 -Wall tests/pty-keys.c -o "$work/pty-keys" -lutil 2>/dev/null ||
    $CC -O2 -Wall tests/pty-keys.c -o "$work/pty-keys"

fail() { echo "FAIL $1"; exit 1; }
# never the real home folder: compiled files go to ~/.chezemax/cache
export HOME="$work/home"
mkdir -p "$HOME"

# --eval, compiled: values, output, errors, definitions
[ "$(./chezemax --eval '(+ 20 22)')" = 42 ] || fail "--eval (+ 20 22)"
[ "$(./chezemax --eval '(define (twice x) (* 2 x)) (twice 21)')" = 42 ] || fail "--eval: a definition"
[ "$(./chezemax --eval '(begin (display "hi") 7)')" = "hi
7" ] || fail "--eval: what it printed, then its value"
got=$(./chezemax --eval '(error "expected test error" 1)' || true)
[ "$got" = 'Error: expected test error 1' ] || fail "--eval: an error ($got)"
got=$(./chezemax --eval '(car 5)' || true)
case $got in Error:*) ;; *) fail "--eval: a trap is an error ($got)" ;; esac
case $(./chezemax --eval '(time (+ 1 2))') in "Elapsed time: "*" seconds
3") ;; *) fail "--eval (time ...)" ;; esac
# (fib 25): some 250,000 calls of a procedure defined by eval
[ "$(./chezemax --eval '(define (fib n) (if (< n 2) 1 (+ (fib (- n 2)) (fib (- n 1))))) (fib 25)')" = 121393 ] ||
    fail "--eval (fib 25)"
# what defines or loops is compiled: (fib 30) far faster than femtoscheme's 0.07 s ...
got=$(./chezemax --eval '(define (fib n) (if (< n 2) 1 (+ (fib (- n 2)) (fib (- n 1))))) (time (fib 30))')
secs=$(printf '%s\n' "$got" | sed -n 's/^Elapsed time: \([0-9.]*\) seconds$/\1/p')
[ "$(printf '%s\n' "$got" | tail -1)" = 1346269 ] && [ -n "$secs" ] || fail "(fib 30) compiled ($got)"
# Correctness must not depend on a recent CPU. Performance limits are opt-in.
if [ -n "${CHEZEMAX_FIB30_MAX_SECONDS:-}" ]; then
 awk -v s="$secs" -v limit="$CHEZEMAX_FIB30_MAX_SECONDS" 'BEGIN { exit !(s < limit) }' || fail "(fib 30) performance ($got)"
fi
printf 'ok    compiled fib(30): %s seconds\n' "$secs"
# ... calls the editor by name, and cannot redefine or set its names
[ "$(./chezemax --eval '(define (twice-size) (* 2 (buffer-size))) (begin (insert "abc") (twice-size))')" = 6 ] ||
    fail "compiled code calls the editor"
got=$(./chezemax --eval '(define (insert . args) 1)' || true)
[ "$got" = "Error: insert is the editor's: change it in a script" ] || fail "redefining insert ($got)"
got=$(./chezemax --eval '(set! *fill-column* 70)' || true)
[ "$got" = "Error: *fill-column* is the editor's: change it in a script" ] || fail "setting *fill-column* ($got)"
got=$(./chezemax --eval '(define (f) (set! *fill-column* 70)) (f)' || true)
[ "$got" = "Error: *fill-column* is the editor's: change it in a script" ] || fail "setting *fill-column* from compiled code ($got)"
[ "$(./chezemax --eval '(list (procedure? car) *fill-column* (string? (get-buffer-name)))')" = "(#t 70 #t)" ] ||
    fail "--eval sees the editor's variables and procedures"
echo "ok    --eval runs in the compiled program"

# a home folder of its own, with an init.scm of the user's
mkdir -p "$work/home/.chezemax"
cat > "$work/home/.chezemax/init.scm" <<'EOF'
;; compiled at start-up (and kept in ~/.chezemax/cache): your settings may
;; set the editor's variables and bind its keys
(define (twice n) (* 2 n))
(set! *fill-column* (twice 33))
(global-set-key "C-c 8" 'upcase-word)
EOF
printf 'abc\n' > "$work/a.txt"

cat > "$work/keys" <<'EOF'
wait 8000
keys \e>
keys typed word
keys \eb
keys ^C8
keys \r
keys \e:
wait 300
keys (insert (number->string *fill-column*))\r
wait 2500
keys \e:
wait 300
keys (insert (number->string (+ 40 2)))\r
wait 300
keys \e:
wait 300
keys (define (sq x) (* x x))\r
wait 2500
keys \e:
wait 300
keys (insert (number->string (sq 7)))\r
wait 2500
keys \e:
wait 300
keys (define counter 10)\r
wait 2500
keys \e:
wait 300
keys (set! counter (+ counter 1))\r
wait 2500
keys \e:
wait 300
keys (insert (number->string counter))\r
wait 2500
keys ^X^S
wait 300
keys ^X^C
wait 500
EOF
status=0
"$work/pty-keys" "$work/keys" 90 "$work/screen" ./chezemax "$work/a.txt" || status=$?
[ "$status" = 0 ] || { tail -c 2000 "$work/screen" | tr -c '[:print:]\n' '.'; fail "the editor exited with $status"; }
expected='abc
typed WORD
66424911'
got=$(cat "$work/a.txt")
[ "$got" = "$expected" ] || { printf 'got:\n%s\n' "$got"; fail "the keys did not make the expected file"; }
echo "ok    typed, a key and a variable set by ~/.chezemax/init.scm, M-: compiled (a session), C-x C-s, C-x C-c"

# femtoscheme still runs the scripts when asked to (until step 5)
[ "$(CHEZEMAX_SCHEME=femtoscheme CHEZEMAX_NO_INIT=1 ./chezemax --eval '(bound? (quote load-scripts))')" = "#t" ] ||
    fail "CHEZEMAX_SCHEME=femtoscheme"
echo "PASS the editor runs on the compiled program"
