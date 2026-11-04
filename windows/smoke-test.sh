#!/bin/bash
# Test an installed tree, with no compiler or system Cygwin tools on PATH.
set -euo pipefail
root=$(cd "$1" && pwd)
export PATH="$root/bin:$root/app" HOME="$root/tmp/test-home" TERM=xterm-256color
mkdir -p "$HOME"
[ "$(chezweb --eval '(+ 20 22)')" = 42 ]
[ "$(chezweb --eval '(begin (define (fib n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2))))) (fib 20))')" = 6765 ]
# The packaged browser bundle is genuinely present, and the compiler starts.
[ -s "$root/app/build/chezweb.wasm" ] && [ -s "$root/app/build/chezweb.js" ]
[ -s "$root/app/schemer/compiler.wasm" ]
chezweb --version
printf 'PASS installed Windows editor: compiled Scheme, Fibonacci, browser assets\n'
