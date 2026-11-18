#!/bin/sh
# Quotations (17 November 2026).  M-q fills a paragraph of an Org
# #+begin_quote block, as in Emacs: the paragraph at the cursor, between
# blank lines, never the #+begin_ and #+end_ lines; a quotation can have
# several paragraphs.  Code and verse blocks are still refused.  The
# LaTeX export writes quote for a quotation of one paragraph and
# quotation for one of several (Org's #+begin_quote and Markdown's >).
# Disposable files and PTY.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-quote.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
cc=${CC:-cc}
$cc -O2 tests/pty-keys.c -o "$work/pty" -lutil 2>/dev/null ||
 $cc -O2 tests/pty-keys.c -o "$work/pty"
mkdir -p "$work/home"
fail() { echo "FAIL $1"; exit 1; }
run() { (cd "$work"; HOME="$work/home" LC_ALL=C.UTF-8 CHEZEMAX_NO_INIT=1 "$work/pty" "$work/keys" 60 "$work/screen" "$root/chezemax" "$1") || true; }

cat > "$work/q.org" <<'ORG'
* Plato
#+begin_quote
And now, I said, let me show in a figure how far our nature is enlightened or unenlightened: Behold! human beings living in an underground den.
They have been here from their childhood.

Like ourselves, I replied; and they see only their own shadows, or the shadows of one another, which the fire throws on the opposite wall of the cave.
#+end_quote
#+begin_verse
A short line,
and another.
#+end_verse
#+begin_src scheme
(define (fib n) (if (< n 2) n (+ (fib (- n 2)) (fib (- n 1)))))
#+end_src
ORG
cp "$work/q.org" "$work/before.org"
cat > "$work/keys" <<'KEYS'
await-screen [SAVE]
keys ^Sshow in\r
wait 200
keys \eq
wait 300
keys ^SLike ourselves\r
wait 200
keys \eq
wait 300
keys ^Sanother\r
wait 200
keys \eq
wait 300
keys ^S(define\r
wait 200
keys \eq
wait 300
keys ^X^S
wait 300
keys ^X^C
KEYS
run q.org
cat > "$work/expected.org" <<'ORG'
* Plato
#+begin_quote
And now, I said, let me show in a figure how far our nature is
enlightened or unenlightened: Behold! human beings living in an
underground den. They have been here from their childhood.

Like ourselves, I replied; and they see only their own shadows, or the
shadows of one another, which the fire throws on the opposite wall of
the cave.
#+end_quote
#+begin_verse
A short line,
and another.
#+end_verse
#+begin_src scheme
(define (fib n) (if (< n 2) n (+ (fib (- n 2)) (fib (- n 1)))))
#+end_src
ORG
cmp -s "$work/q.org" "$work/expected.org" || { diff "$work/expected.org" "$work/q.org" || true; fail 'M-q in a quotation'; }
[ "$(grep -o 'Headings, tables and code are not refilled' "$work/screen" | wc -l)" -ge 2 ] ||
 fail 'M-q must still refuse a verse and a code block'
echo 'PASS M-q fills each paragraph of a #+begin_quote block; verse and code are left alone'

# the export: two paragraphs make a quotation, one a quote
cat > "$work/e.org" <<'ORG'
#+begin_quote
First paragraph.

Second paragraph.
#+end_quote

#+begin_quote
Only one.
#+end_quote
ORG
cat > "$work/m.md" <<'MD'
> First paragraph.
>
> Second paragraph.

Between.

> Only one.
MD
printf 'await-screen [SAVE]\nkeys \\exlatex-export\\r\nwait 800\nkeys ^X^C\n' > "$work/keys"
run e.org
run m.md
for t in e m; do
 tex="$work/$t.tex"
 [ -s "$tex" ] || fail "no $t.tex"
 grep -q '^\\begin{quotation}$' "$tex" && grep -q '^\\end{quotation}$' "$tex" || { cat "$tex"; fail "$t: two paragraphs must make a quotation"; }
 [ "$(grep -c '^\\begin{quote}$' "$tex")" = 1 ] || { cat "$tex"; fail "$t: one paragraph must make a quote"; }
 awk '/begin{quotation}/,/end{quotation}/' "$tex" | grep -q '^$' || fail "$t: the paragraphs of the quotation must stay apart"
done
echo 'PASS the export: quotation for a quotation of several paragraphs, quote for one (Org and Markdown)'

# #+begin_quotation, Eduardo's own name for it: M-q fills it, and the
# export makes it LaTeX's quotation, one paragraph or several
cat > "$work/qn.org" <<'ORG'
John McCarthy discovered it very early [6]:

#+begin_quotation
In 1959, McCarthy proposed a program with "common sense" that would
 represent what it knows by sentences in a suitable logical language.
 It would decide what to do by deducing a conclusion.
#+end_quotation
ORG
printf 'await-screen [SAVE]\nkeys ^S1959\r\nwait 200\nkeys \\eq\nwait 300\nkeys ^X^S\nwait 300\nkeys \\exlatex-export\\r\nwait 800\nkeys ^X^C\n' > "$work/keys"
run qn.org
cat > "$work/expected-qn.org" <<'ORG'
John McCarthy discovered it very early [6]:

#+begin_quotation
In 1959, McCarthy proposed a program with "common sense" that would
represent what it knows by sentences in a suitable logical language.
It would decide what to do by deducing a conclusion.
#+end_quotation
ORG
cmp -s "$work/qn.org" "$work/expected-qn.org" || { diff "$work/expected-qn.org" "$work/qn.org" || true; fail 'M-q in a #+begin_quotation block'; }
grep -q '^\\begin{quotation}$' "$work/qn.tex" || { cat "$work/qn.tex"; fail '#+begin_quotation must export as quotation'; }
echo 'PASS #+begin_quotation: M-q fills it, and the export makes it a quotation'
