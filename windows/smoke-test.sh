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
mkdir -p "$HOME/.chezemax/users"
printf '(define (installed-answer) 42)\n' > "$HOME/.chezemax/users/answer.scm"
chezweb --compile-scripts "$HOME/compile.log"
[ "$(chezweb --eval '(installed-answer)')" = 42 ]
echo 'PASS personal scripts compile using only the installed package'
# The packaged browser bundle is genuinely present, and the compiler starts.
[ -s "$root/app/build/chezweb.wasm" ] && [ -s "$root/app/build/chezweb.js" ]
[ -s "$root/app/schemer/compiler.wasm" ]
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
