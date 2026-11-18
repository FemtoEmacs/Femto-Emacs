#!/bin/sh
# RET and TAB inside an Org #+begin_src block follow the block's language
# (17 November 2026): after "(define (fib n)" RET indented nothing in an
# Org block, while a .scm file indented the next line.  The same keys
# typed in a .scm file and in a "#+begin_src Scheme" block (any case)
# must give the same code; the Org lines around the block stay as they
# were, prose after it is not indented, and a block whose language has
# no rules (or none named) is left alone.  Disposable files and PTY.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-org-src.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
cc=${CC:-cc}
$cc -O2 tests/pty-keys.c -o "$work/pty" -lutil 2>/dev/null ||
 $cc -O2 tests/pty-keys.c -o "$work/pty"
mkdir -p "$work/home"
fail() { echo "FAIL $1"; exit 1; }
run() { (cd "$work"; HOME="$work/home" LC_ALL=C.UTF-8 CHEZEMAX_NO_INIT=1 "$work/pty" "$work/keys" 60 "$work/screen" "$root/chezemax" "$1") || true; }
# the keys: after "(define (fib n)", the body typed with RET, as a person
# would, with no indentation of its own
body='keys \r(if (< n 2)\rn\r(+ (fib (- n 2))\r(fib (- n 1)))))'
printf '(define (fib n)\n' > "$work/fib.scm"
printf 'await-screen [SAVE]\nkeys ^E\n%s\nwait 300\nkeys ^X^S\nwait 300\nkeys ^X^C\n' "$body" > "$work/keys"
run fib.scm
cat > "$work/expected.scm" <<'SCM'
(define (fib n)
  (if (< n 2)
      n
      (+ (fib (- n 2))
         (fib (- n 1)))))
SCM
cmp -s "$work/fib.scm" "$work/expected.scm" || { diff "$work/expected.scm" "$work/fib.scm"; fail 'the .scm file itself is not indented as expected'; }

cat > "$work/fib.org" <<'ORG'
* Fibonacci
  Some prose, indented by hand.
#+begin_src Scheme
(define (fib n)
#+end_src
After the block.
ORG
printf 'await-screen [SAVE]\nkeys ^S(fib n)\\r^E\n%s\nwait 300\nkeys ^S\nkeys After the block.\\r^E\\rmore prose\nwait 300\nkeys ^X^S\nwait 300\nkeys ^X^C\n' "$body" > "$work/keys"
run fib.org
cat > "$work/expected.org" <<'ORG'
* Fibonacci
  Some prose, indented by hand.
#+begin_src Scheme
(define (fib n)
  (if (< n 2)
      n
      (+ (fib (- n 2))
         (fib (- n 1)))))
#+end_src
After the block.
more prose
ORG
cmp -s "$work/fib.org" "$work/expected.org" || { diff "$work/expected.org" "$work/fib.org"; fail 'the Org block is not indented as the .scm file'; }
echo 'PASS RET in an Org #+begin_src Scheme block indents as in a .scm file; prose after the block is not indented'

# TAB on a badly indented line of the block; and a block with no language
cat > "$work/tab.org" <<'ORG'
#+BEGIN_SRC scheme
(let ((x 1))
x)
#+END_SRC
#+begin_src
(let ((x 1))
x)
#+end_src
ORG
printf 'await-screen [SAVE]\nkeys ^Sx)\\r^A\\t\nwait 300\nkeys ^Sx)\\r^A\\t\nwait 300\nkeys ^X^S\nwait 300\nkeys ^X^C\n' > "$work/keys"
run tab.org
sed -n 3p "$work/tab.org" | grep -q '^  x)$' || { cat "$work/tab.org"; fail 'TAB in a #+BEGIN_SRC scheme block did not indent by Scheme rules'; }
sed -n 7p "$work/tab.org" | grep -q '^x)$' || { cat "$work/tab.org"; fail 'a block without a language must not be indented by any rules'; }
echo 'PASS TAB re-indents a line of the block by its language; a block with no language is left alone'
