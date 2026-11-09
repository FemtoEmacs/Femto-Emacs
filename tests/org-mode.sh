#!/bin/sh
# The tiny Org mode (compiled/scripts/org*.scm), through a terminal, on a
# disposable notes.org: C-c C-c computes and aligns a sexp table; C-c C-t
# cycles TODO, DONE; M-RET makes a new item and a new heading; C-c C-v t
# tangles a block to fib.scm.  M-x org-mode turns it off: its keys are
# unbound again, and nothing changes.  In a .txt file, its keys are not
# bound.  The colours, the table language and the switch are checked with
# --eval.  Disposable home, files and PTY.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-org.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
cc=${CC:-cc}
$cc -O2 tests/pty-keys.c -o "$work/pty" -lutil 2>/dev/null ||
 $cc -O2 tests/pty-keys.c -o "$work/pty"
mkdir -p "$work/home/.chezemax"
fail() { echo "FAIL $1"; [ -f "${2:-/dev/null}" ] && cat "$2"; exit 1; }
ev() { CHEZEMAX_NO_INIT=1 HOME="$work/home" ./chezemax --eval "$1" 2>&1; }

# 1. the table language and the colours, without a window
got=$(ev '(display (org-table-redo "((( Name ) ( Age ) ( Half ))\n (( - ) ( - ) ( - ))\n (( João ) ( 30 ) ( ))\n ((\"Ana Paula\") (7) ()))\n#+TBLFM: (set! Half (/ Age 2))\n"))' | sed '$d')
want='(
 (( Name        ) ( Age ) ( Half ))
 (( ----------- ) ( --- ) ( ---- ))
 (( João        ) ( 30  ) ( 15   ))
 (( "Ana Paula" ) ( 7   ) ( 3.5  ))
)
#+TBLFM: (set! Half (/ Age 2))'
[ "$got" = "$want" ] || { echo "FAIL a formula by name"; echo "$got"; exit 1; }
# Complaint 3 (bug_events/orgmode-bugs.org): a rule of several pieces a
# column, and a header without a rule, were computed as rows ("#ERROR")
table() { ev "(display (org-table-redo $(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/^/"/; s/$/\\n"/' | tr -d '\n' | sed 's/""/" "/g; s/^/(string-append /; s/$/)/')))" | sed '$d'; }
got=$(table '(
 ((Title: "Org table:"))
 (( Name  ) ( Phone ) ( Age ) (    ))
 ((= ----- =) ( ----- ) ( --- ) ( -- ))
 (( Peter ) ( 1234  ) ( 24  ) ( 9  ))
 (( Susan ) ( 9876  ) ( 18  ) ( 9 ))
)
#+TBLFM: $4=(- $3 24)')
want='(
 ((Title: "Org table:"))
 (( Name  ) ( Phone ) ( Age ) (    ))
 (( ----- ) ( ----- ) ( --- ) ( -- ))
 (( Peter ) ( 1234  ) ( 24  ) ( 0  ))
 (( Susan ) ( 9876  ) ( 18  ) ( -6 ))
)
#+TBLFM: $4=(- $3 24)'
[ "$got" = "$want" ] || { echo "FAIL a rule of several pieces a column"; echo "$got"; exit 1; }
got=$(table '(
 ((Title: "Org table:"))
 (( Name  ) ( Phone ) ( Age ) (  ))
 (( Peter ) ( 1234  ) ( 24  ) ( 0        ))
 (( Susan ) ( 9876  ) ( 18  ) ( -6       ))
)
#+TBLFM: $4=(- $3 24)')
want='(
 ((Title: "Org table:"))
 (( Name  ) ( Phone ) ( Age ) (    ))
 (( Peter ) ( 1234  ) ( 24  ) ( 0  ))
 (( Susan ) ( 9876  ) ( 18  ) ( -6 ))
)
#+TBLFM: $4=(- $3 24)'
[ "$got" = "$want" ] || { echo "FAIL a header without a rule"; echo "$got"; exit 1; }
got=$(table '(
 (( Peter ) ( 1234 ) ( 24 ) (   ))
 (( Susan ) ( 9876 ) ( 18 ) (  ))
)
#+TBLFM: $4=(- $3 24)')
want='(
 (( Peter ) ( 1234 ) ( 24 ) ( 0  ))
 (( Susan ) ( 9876 ) ( 18 ) ( -6 ))
)
#+TBLFM: $4=(- $3 24)'
[ "$got" = "$want" ] || { echo "FAIL no header, no rule"; echo "$got"; exit 1; }
got=$(table '(
 (( "Full name" ) ( Age ))
 (( ===== ) ( === ))
 (( Ana ) ( 3 ))
 (( --- ) ( --- ))
 (( Total ) ( 9 ))
)
#+TBLFM: $2=(* Age 2)')
want='(
 (( "Full name" ) ( Age ))
 (( =========== ) ( === ))
 (( Ana         ) ( 6   ))
 (( ----------- ) ( --- ))
 (( Total       ) ( 18  ))
)
#+TBLFM: $2=(* Age 2)'
[ "$got" = "$want" ] || { echo "FAIL rules of = and -, a second rule, a header with a space"; echo "$got"; exit 1; }
got=$(ev '(org-table-describe "(((A) (B)) ((-) (-)) ((1) (2)))\n#+TBLFM: $2=(* A 3) :: $1=(system \"rm\") :: $1=(+ C 1)\n")')
[ "$got" = '(#f ("A" "B") ((2 * A 3)) ("$1=(system \"rm\")" "$1=(+ C 1)"))' ] ||
 fail "formulas outside the table language must be refused, not run: $got"
got=$(ev '(highlight-string "* TODO Buy *milk*\n- [ ] /it/ =v= [[l][d]]\n#+BEGIN_SRC scheme\n(define x 1)\n#+END_SRC\n" "x.org")')
for run in '(11 . "* ")' '(4 . "TODO")' '(4 . "- [ ]")' '(12 . "/it/")' '(9 . "=v=")' '(14 . "[[l][d]]")' \
           '(7 . "#+BEGIN_SRC scheme")' '(4 . "define")' '(7 . "#+END_SRC")'; do
  case "$got" in *"$run"*) ;; *) fail "the colour run $run is missing: $got" ;; esac
done
got=$(ev '(list (begin (org-off!) (language-name (language-for-file "x.org"))) (key-binding "C-c C-t") (begin (org-on!) (language-name (language-for-file "x.org"))))')
[ "$got" = '("Text" #f "Org")' ] || fail "M-x org-mode off must remove the language and the keys: $got"
echo 'PASS the table language (names, $N, Unicode widths, refused formulas, rules and headers), the colours, the switch'

# 2. the keys, in a terminal
cat > "$work/notes.org" <<'ORG'
* Groceries
- milk
#+BEGIN_SEXP_TABLE
(
 ((Title: "Org table"))
 (( Name  ) ( Phone ) ( Age ) ( Age-24   ))
 (( ----- ) ( ----- ) ( --- ) ( -------- ))
 (( Peter ) ( 1234  ) ( 24  ) ( -1       ))
 (( Anna  ) ( 4321  ) ( 25  ) ( 7        ))
 (( Susan ) ( 9876  ) ( 18  ) (          ))
)
#+TBLFM: $4=(- $3 24)
#+END_SEXP_TABLE
#+BEGIN_SRC scheme :tangle fib.scm
  (define (fib n)
    (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))
#+END_SRC
ORG
printf 'plain text\n' > "$work/plain.txt"
cat > "$work/keys" <<'KEYS'
await-screen [SAVE]
keys ^C^T
wait 300
keys ^N\e\r
wait 300
keys eggs
keys ^SAnna\r
wait 300
keys ^C^C
wait 500
keys ^C^Vt
wait 500
keys ^C^V^T
wait 500
keys \e>\e\r
wait 300
keys Next
keys \e<^C^T
wait 300
keys ^X^S
wait 300
keys \exorg-mode\r
wait 300
keys ^C^T^C^C
wait 300
keys ^X^S
wait 300
keys \exorg-mode\r
wait 300
keys ^X^Fplain.txt\r
wait 300
keys ^C^C
wait 300
keys ^C^T
wait 300
keys ^X^S
wait 300
keys ^X^C
KEYS
(cd "$work"; HOME="$work/home" LC_ALL=C.UTF-8 CHEZEMAX_NO_INIT=1 "$work/pty" "$work/keys" 60 "$work/screen" "$root/chezemax" notes.org) || true
cat > "$work/expected" <<'ORG'
* DONE Groceries
- milk
- eggs
#+BEGIN_SEXP_TABLE
(
 ((Title: "Org table"))
 (( Name  ) ( Phone ) ( Age ) ( Age-24 ))
 (( ----- ) ( ----- ) ( --- ) ( ------ ))
 (( Peter ) ( 1234  ) ( 24  ) ( 0      ))
 (( Anna  ) ( 4321  ) ( 25  ) ( 1      ))
 (( Susan ) ( 9876  ) ( 18  ) ( -6     ))
)
#+TBLFM: $4=(- $3 24)
#+END_SEXP_TABLE
#+BEGIN_SRC scheme :tangle fib.scm
  (define (fib n)
    (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))
#+END_SRC
ORG
printf '\n* Next' >> "$work/expected"
cmp -s "$work/notes.org" "$work/expected" || { echo 'FAIL notes.org'; diff "$work/expected" "$work/notes.org"; exit 1; }
printf '(define (fib n)\n  (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))\n' > "$work/fib-expected"
cmp -s "$work/fib.scm" "$work/fib-expected" || { echo 'FAIL fib.scm'; cat "$work/fib.scm" 2>/dev/null; exit 1; }
grep -q 'Tangled 1 block to fib.scm' "$work/screen" || fail 'the tangle message'
grep -q 'C-c C-c is not bound' "$work/screen" && grep -q 'C-c C-t is not bound' "$work/screen" || fail 'outside Org, the keys must be unbound'
[ "$(cat "$work/plain.txt")" = 'plain text' ] || fail 'plain.txt changed'
echo 'PASS C-c C-t, M-RET, C-c C-c (formulas, alignment), C-c C-v t; off: the keys do nothing; plain.txt untouched'
