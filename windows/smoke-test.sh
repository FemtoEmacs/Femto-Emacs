#!/bin/bash
# Test an installed tree, with no compiler or system Cygwin tools on PATH.
set -euxo pipefail
root=$(cd -- "$(cygpath -u "$1")" && pwd -P)
root=${root%/}
helper=$(cygpath -u "$2")
cd -- "${root:-/}"
export CHEZEMAX_NO_INIT=1
export PATH="$root/bin:$root/app" HOME="$root/tmp/test-home" TERM=xterm-256color
mkdir -p "$HOME"
[ "$(chezweb --eval '(+ 20 22)')" = 42 ]
[ "$(chezweb --eval '(let fib ((n 20)) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))')" = 6765 ]
# Start processes after Wasmtime is active, using only packaged executables.
[ "$(chezweb --eval '(run-program "/bin/sh" (list "-c" "cat; printf err >&2; exit 7") "input" 5 #f)')" = '("input" "err" 7)' ]
cat > "$root/tmp/process-check.scm" <<'SCHEME'
(let ((r (run-program "/bin/sh"
             (list "-c" "printf '<%s>\\n' \"$@\"" "fixture" "a b" "a\"b" "end\\" "") "" 5 #f)))
  (if (and (equal? (car r) "<a b>\n<a\"b>\n<end\\>\n<>\n")
           (= (caddr r) 0)) 42 0))
SCHEME
[ "$(chezweb --eval "$(cat "$root/tmp/process-check.scm")")" = 42 ]
[ "$(chezweb --eval '(let ((r (run-program "/bin/sh" (list "-c" "while :; do :; done") "" 1 #f))) (caddr r))')" = -1 ]
echo 'PASS installed process input/output/status, argument quoting and timeout'
mkdir -p "$HOME/.chezemax/users"
printf '(define (installed-answer) 42)\n' > "$HOME/.chezemax/users/answer.scm"
chezweb --compile-scripts "$HOME/compile.log"
[ "$(chezweb --eval '(installed-answer)')" = 42 ]
echo 'PASS personal scripts compile using only the installed package'
# The second distinct request starts a compiler after Wasmtime has run.
[ "$(CHEZEMAX_SCHEME=femtoscheme chezweb --eval '(list (schemer-eval-string "(+ 20 22)") (schemer-eval-string "(+ 21 22)"))')" = '(42 43)' ]
echo 'PASS installed compatibility compiler launches after Wasmtime activation'
# The packaged browser bundle is genuinely present, and the compiler starts.
[ -s "$root/app/build/chezweb.wasm" ] && [ -s "$root/app/build/chezweb.js" ]
[ -s "$root/app/schemer/compiler.wasm" ]
[ -s "$root/app/Chinese/pinyin.txt" ] && [ -s "$root/app/Chinese/lianxiang.txt" ]
[ "$(chezweb --eval '(list (fe-char-width 769) (fe-char-width 20013))')" = '(0 2)' ]
[ "$(chezweb-gui --eval '(fe-screen-probe)')" = 1 ]
chezweb --version
printf 'PASS installed Windows editor: compiled Scheme, Fibonacci, browser assets\n'

cp "$helper" "$root/tmp/pty-test.exe"
printf 'Windows installed terminal fixture\n' > "$root/tmp/source.txt"
cat > "$root/tmp/browser" <<'BROWSER'
#!/bin/sh
printf '%s\n' "$1" > "$HOME/launched-url"
BROWSER
chmod +x "$root/tmp/browser"
export CHEZWEB_BROWSER="$root/tmp/browser"
cat > "$root/tmp/keys" <<KEYS
await-screen Windows installed terminal fixture
keys Saved through installed editor\r
keys ^X^S
await-file $root/tmp/source.txt
keys ^Cd
await-file $HOME/launched-url
await-screen Browser: http://127.0.0.1:
keys ^X^C
KEYS
"$root/tmp/pty-test.exe" "$root/tmp/keys" 90 "$root/tmp/screen" "$root/app/chezweb.exe" "$root/tmp/source.txt"
grep -q 'Saved through installed editor' "$root/tmp/source.txt"
grep -q '^http://127.0.0.1:' "$HOME/launched-url"
echo 'PASS installed terminal keyboard/save/quit and C-c d server/browser launch'

# Exercise M-x term through the installed executable, including ConPTY
# input, output and exit status after the compiled editor has started.
cat > "$root/tmp/term-keys" <<'KEYS'
await-screen [SAVE]
keys \exterm\r
await-screen Terminal: C-c C-c interrupts
keys set "CHEZWEB_TAIL=PTY-OK"\r
keys echo CHEZWEB-CON%CHEZWEB_TAIL%\r
await-screen CHEZWEB-CONPTY-OK
keys exit 7\r
await-screen [Process exited with status 7]
keys ^X^C
KEYS
if ! "$root/tmp/pty-test.exe" "$root/tmp/term-keys" 90 "$root/tmp/term-screen" "$root/app/chezweb.exe"; then
  tail -c 32768 "$root/tmp/term-screen"
  exit 1
fi
echo 'PASS installed M-x term through ConPTY'
