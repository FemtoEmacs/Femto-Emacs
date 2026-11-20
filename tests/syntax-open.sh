#!/bin/sh
# M-; reads where a line's text stands (inside a string or a comment begun
# above, or not) from the C tokenizer (fe-syntax-open, src/highlight.c),
# and the language of a Markdown ``` block or an Org #+BEGIN_SRC block from
# the lines C finds (fe-buffer-search), instead of lexing the whole text
# before the line in Scheme.  Both must answer what the slow way answers:
# here, line by line, on the scripts, a C file and tricky fixtures.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-syntax-open.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
cc=${CC:-cc}
$cc -O2 tests/pty-keys.c -o "$work/pty" -lutil 2>/dev/null || $cc -O2 tests/pty-keys.c -o "$work/pty"
mkdir -p "$work/home"

cat > "$work/tricky.scm" <<'SCM'
(define a "x ; not a comment" ) ; one
(define b "esc \" ; still string
(fake def ; inside
end") ; two
#| block ; comment
(define c 1) ; in block
|# (define d #\") ; three
(define e #\;) ; four
(define f 'x) ; five "
(display "a\\") ; six
#;(skip) ; seven
"open
SCM
cat "$work/tricky.scm" compiled/scripts/org.scm > "$work/all.scm"
cp src/highlight.c "$work/all.c"
cat > "$work/t.md" <<'MD'
Text with `code` and ``inline``.
```scheme
(define x 1) ; in Scheme
```
    ``` indented four: not a fence
  ```c
int f(void); /* C */
  ```
~~~python
x = 1  # Python
~~~
````
four ``` inside
````
```nosuch
y
```
end ```
MD
cat > "$work/t.org" <<'ORG'
#+TITLE: test
* Heading
#+BEGIN_SRC scheme
(define x 1) ; Scheme
#+END_SRC
  #+begin_src c
int f(void);
  #+end_src
#+BEGIN_SRC nosuch
z
#+END_SRC
#+BEGIN_SRC python
x = 1
text #+END_SRC not an end
#+end_SRC
after
ORG

# On lines BYTES apart: the slow way and the fast way must agree.
comment_check() {   # bytes between lines checked (the prompt takes 512 bytes: two expressions)
cat <<KEYS
keys \\e:(define (so-at lang from ls le) (let ((at (line-comment-position-bytes (buffer-bytes from le) (- ls from) lang))) (and at (+ at from))))\\r
wait 300
keys \\e:(let* ((lang (language-at-point)) (id (language-token-id lang)) (n (buffer-size))) (let loop ((ls 0) (bad 0) (k 0)) (if (>= ls n) (list 'CHECKED k 'BAD bad) (let ((le (line-end ls)) (o (fe-syntax-open id 0 ls))) (loop (if (> $1 1) (max (+ le 1) (line-start (min n (+ ls $1)))) (+ le 1)) (if (equal? (so-at lang 0 ls le) (so-at lang (if (>= o 0) o ls) ls le)) bad (+ bad 1)) (+ k 1))))))\\r
KEYS
}
place_check() {     # slow fast
cat <<KEYS
keys \\e:(define (place-of x) (and x (list (language-name (car x)) (cdr x))))\\r
wait 300
keys \\e:(let ((n (buffer-size))) (let loop ((ls 0) (bad 0) (k 0) (in 0)) (if (>= ls n) (list 'CHECKED k 'BAD bad 'IN in) (let* ((le (line-end ls)) (a (place-of ($1 (buffer-bytes 0 le) ls)))) (loop (+ le 1) (if (equal? a (place-of ($2 ls))) bad (+ bad 1)) (+ k 1) (if a (+ in 1) in))))))\\r
KEYS
}
run() {   # file keys-producing command...
	f=$1; shift
	{ echo 'await-screen [SAVE]'; "$@"; echo 'await-screen (CHECKED'; echo 'wait 300'; echo 'keys ^X^C'; } > "$work/keys"
	(cd "$work"; HOME="$work/home" CHEZEMAX_NO_INIT=1 LC_ALL=C.UTF-8 "$work/pty" "$work/keys" 120 "$work/screen" "$root/chezemax" "$f") >/dev/null 2>&1 || true
	r=$(grep -ao '(CHECKED [0-9]* BAD [0-9]*[ A-Z0-9]*)' "$work/screen" | tail -1)
	case "$r" in
	"(CHECKED 0 "*|"") echo "FAIL $f: no answer"; exit 1;;
	*" BAD 0)"|*" BAD 0 IN "[1-9]*) echo "ok   $f: $r";;
	*) echo "FAIL $f: $r"; exit 1;;
	esac
}
run tricky.scm comment_check 1
run all.scm comment_check 1000
run all.c comment_check 2000
run t.md place_check md-code-place md-buffer-code-place
run t.org place_check org-code-place org-buffer-code-place
echo 'PASS M-; and the inner languages read the text before the line as before'
