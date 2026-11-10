#!/bin/sh
# M-x latex-export: Markdown and Org to LaTeX, through a terminal.  A .md
# file and a .org file (with Greek, Korean, math, money, lists, tables, an
# Org sexp table with a formula, code) are exported beside themselves;
# the .tex files are compared with what they must say.  The second export
# of the .md asks before replacing its .tex (n keeps it, y replaces it);
# C-c C-e l l exports the .org, as in Emacs; a .txt file is refused.
# With xelatex on the PATH, both .tex files are also compiled.
# Disposable home, files and PTY.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-latex.XXXXXX")
trap '[ -n "${KEEP:-}" ] || rm -rf "$work"' EXIT HUP INT TERM
cc=${CC:-cc}
$cc -O2 tests/pty-keys.c -o "$work/pty" -lutil 2>/dev/null ||
 $cc -O2 tests/pty-keys.c -o "$work/pty"
mkdir -p "$work/home/.chezemax"
fail() { echo "FAIL $1"; exit 1; }
cat > "$work/paper.md" <<'MD'
# Notes on *Chezweb*

It is **simple**, _small_ and `C-x C-s` saves. It costs US$5 and $6, but
$x^2 + y_1$ is math. 100% & #1 done. See [the site](https://example.com/a#x).

## Lists

- one
  - nested **bold**
- two

1. first
2. second

| Name | Age |
|:-----|----:|
| Ann  | 24  |

```scheme
(define (f x) (* x x))   ; 100% $
```

λόγος, 한글.
MD
cat > "$work/notes.org" <<'ORG'
#+TITLE: Org to /LaTeX/
#+AUTHOR: Nia
# a comment
* Introduction                                                  :intro:
:PROPERTIES:
:ID: 42
:END:
Org has *bold*, /italic/, =verbatim $5= and [[https://orgmode.org][a link]].
** TODO Lists
- [ ] milk
- [X] paper
#+BEGIN_SEXP_TABLE
(
 ((Title: "Ages"))
 (( Name  ) ( Age ) ( Age-24 ))
 (( ----- ) ( --- ) ( ------ ))
 (( Peter ) ( 34  ) ( 0      ))
)
#+TBLFM: $3=(- $2 24)
#+END_SEXP_TABLE
#+BEGIN_SRC scheme
(car '(a b))
#+END_SRC
ORG
echo plain > "$work/plain.txt"
cat > "$work/keys" <<'KEYS'
await-screen [SAVE]
keys \exlatex-export\r
wait 1000
keys ^Xbpaper.md\r
wait 500
keys \exlatex-export\r
wait 500
keys n\r
wait 500
keys \exlatex-export\r
wait 500
keys y\r
wait 1000
keys ^X^Fplain.txt\r
wait 500
keys \exlatex-export\r
wait 500
keys ^X^Fnotes.org\r
wait 500
keys ^C^Ell
wait 1000
keys ^X^C
KEYS
(cd "$work"; HOME="$work/home" LC_ALL=C.UTF-8 CHEZEMAX_NO_INIT=1 "$work/pty" "$work/keys" 60 "$work/screen" "$root/chezemax" paper.md) || true
[ -f "$work/paper.tex" ] || fail 'paper.tex was not written'
[ -f "$work/notes.tex" ] || fail 'C-c C-e l l did not write notes.tex'
grep -q 'paper.tex exists; replace it?' "$work/screen" || fail 'the second export did not ask'
grep -q 'not an Org or a Markdown file' "$work/screen" || fail 'plain.txt was not refused'
[ ! -f "$work/plain.tex" ] || fail 'plain.txt was exported'
has() { grep -qF -- "$2" "$work/$1" || fail "$1 lacks: $2"; }
has paper.tex '\title{Notes on \emph{Chezweb}}'
has paper.tex 'It is \textbf{simple}, \emph{small} and \texttt{C-x C-s} saves. It costs US\$5 and \$6, but'
has paper.tex '$x^2 + y_1$ is math. 100\% \& \#1 done. See \href{https://example.com/a\#x}{the site}.'
has paper.tex '\section{Lists}'
has paper.tex '\item nested \textbf{bold}'
has paper.tex '\begin{enumerate}'
has paper.tex '\begin{tabular}{lr}'
has paper.tex '(define (f x) (* x x))   ; 100% $'
has paper.tex '\setmainfont{LibertinusSerif}'
has paper.tex '\usepackage{kotex}'
has paper.tex 'λόγος, 한글.'
has notes.tex '\title{Org to \emph{LaTeX}}'
has notes.tex '\author{Nia}'
has notes.tex '\section{Introduction}'
has notes.tex 'Org has \textbf{bold}, \emph{italic}, \texttt{verbatim \$5} and \href{https://orgmode.org}{a link}.'
has notes.tex '\subsection{\texttt{TODO} Lists}'
has notes.tex '\item[$\square$] milk'
has notes.tex '\caption{Ages}'
has notes.tex 'Peter & 34 & 10 \\'
has notes.tex "(car '(a b))"
! grep -q 'comment\|PROPERTIES\|intro\|TBLFM' "$work/notes.tex" || fail 'notes.tex kept what Org leaves out'
echo 'PASS M-x latex-export and C-c C-e l l: Markdown and Org to LaTeX beside the file; asks before replacing; refuses plain text'
if command -v xelatex >/dev/null 2>&1; then
 for f in paper notes; do
  (cd "$work"; xelatex -interaction=nonstopmode -halt-on-error "$f.tex" >/dev/null 2>&1) ||
   { tail -20 "$work/$f.log"; fail "xelatex could not compile $f.tex"; }
 done
 echo 'PASS xelatex compiles both'
fi
