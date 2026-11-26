#!/bin/sh
# sexp-scan.sh -- C-M-f, C-M-b and the paren highlight read Lisp as Lisp
# (src/sexp.c; 26 November 2026).  The cases Claude found by hand on 25
# November: a ) in a ; comment, #| |# with a paren inside, a paren in a
# string, #\( and #\), nested #| |#.  Each case: the point after each key,
# from the backdoor.  Disposable files, in a PTY.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-sexp-scan.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
cc=${CC:-cc}
$cc -O2 tests/pty-keys.c -o "$work/pty" -lutil 2>/dev/null ||
	$cc -O2 tests/pty-keys.c -o "$work/pty"
mkdir -p "$work/home/.chezemax"
printf 'repeats keep\nwatch none\n' > "$work/home/.chezemax/backdoor-claude.conf"
failed=0

# run NAME FILE KEYS...: the points after the keys (each a line of the script)
run() {
	name=$1 file=$2
	shift 2
	{
		echo 'await-screen [SAVE]'
		echo 'keys \exbackdoor-claude\r'
		echo 'wait 300'
		for k in "$@"; do echo "keys $k"; echo 'wait 400'; done
		echo 'keys \exbackdoor-claude\r'
		echo 'wait 300'
		echo 'keys ^G^X^C'
		echo 'wait 300'
		echo 'keys y'
		echo 'wait 300'
	} > "$work/$name.script"
	rm -f "$work/home/.chezemax/backdoor.txt"
	(cd "$work"; HOME="$work/home" CHEZEMAX_NO_INIT=1 LC_ALL=C.UTF-8 \
		"$work/pty" "$work/$name.script" 60 "$work/$name.screen" "$root/chezemax" "$file") > "$work/$name.pty" 2>&1 ||
		{ echo "FAIL $name: the session did not finish"; failed=1; return 1; }
	grep -a '^#' "$work/home/.chezemax/backdoor.txt" | grep -av 'esc x b' |
		sed 's/.* pt=\([0-9]*\) .*/\1/' | tr '\n' ' ' | sed 's/ $//' > "$work/$name.pts"
}
check() {   # check NAME WHAT EXPECTED
	got=$(cat "$work/$1.pts")
	if [ "$got" = "$3" ]; then echo "PASS $1: $2"
	else echo "FAIL $1: $2"; echo "  expected points: $3"; echo "  got:             $got"; failed=1; fi
}

# 1: C-M-b over a ) in a ; comment (it said "No expression before")
printf '(define (f x)\n  ; a smiley :)\n  x)\n(define (g y) y)\n' > "$work/comment.scm"
# M-< C-n C-n C-e: after "x)" (14, 30, 34); C-M-b: the start (0); C-M-f: back (34)
run comment comment.scm '\e<' '^N^N^E' '\e^B' '\e^F'
check comment "C-M-b over a ) in a ; comment goes to the start of the definition" "0 14 30 34 0 34"

# 2: #| |# with an open paren inside (C-M-f found no expression, C-M-b
# stopped in the comment)
printf '(define (f x)\n  #| an open ( |#\n  x)\n(define (g y) y)\n' > "$work/block.scm"
run block block.scm '\e^F' '\e^B' '\e^F\e^F' '\e^B'
check block "C-M-f and C-M-b over #| ( |#" "36 0 36 53 37"

# 3: #| |# with a close paren inside (C-M-f stopped inside it, and C-M-k
# would have cut half a definition)
printf '(define (f x)\n  #| a smiley :) |#\n  x)\n(define (g y) y)\n' > "$work/smiley.scm"
run smiley smiley.scm '\e^F' '\e^B'
check smiley "C-M-f over #| :) |# goes to the end of the definition" "38 0"

# 4: parens in strings and as characters
printf '(display ")" #\\( #\\) "(")\n(next)\n' > "$work/chars.scm"
run chars chars.scm '\e^F' '\e^B' '\e^F\e^F' '\e^B\e^B'
check chars "C-M-f and C-M-b over \")\", #\\( #\\) and \"(\"" "25 0 25 32 26 0"

# 5: nested #| #| |# |#
printf '(a #| one #| two ) |# still ( comment |# b)\n(c)\n' > "$work/nested.scm"
run nested nested.scm '\e^F' '\e^B'
check nested "C-M-f over nested #| #| |# |# with parens" "43 0"

# 6: the paren highlight: a definition taller than the window, a ")" in a
# string and a ) in a comment; after its last ) the editor names the line
# of the match, when it is off the screen
{
	printf '(define (tall)\n  (display ")")   ; a ) in a comment, and "("\n'
	i=0; while [ $i -lt 60 ]; do printf '  (line %d)\n' $i; i=$((i + 1)); done
	printf '  done)\n(after)\n'
} > "$work/tall.scm"
run tall tall.scm '\e<' '\e^F'
if grep -aq 'Matches line 1: (define (tall)' "$work/tall.screen"; then
	echo "PASS tall: the paren highlight matches the definition's open paren, past the parens in a string and a comment"
else
	echo "FAIL tall: no 'Matches line 1: (define (tall)' after C-M-f over the definition"; failed=1
fi

# 7: in a string, C-M-f reads the text from the cursor, as before
printf '(f "a (b) c")\n' > "$work/instr.scm"
run instr instr.scm '^F^F^F^F^F' '\e^F'
check instr "C-M-f inside a string reads from the cursor: over (b), as before" "1 2 3 4 5 9"

# 8: good Scheme, and demanding (a small dem-balanced.scm, demanding/): a
# quoted list 100,000 deep, closed, with a string at the bottom; nested
# #| |# with parens; a table of 8,000 rows with ) and ( in strings,
# characters, |symbols| and comments; then a short definition
awk 'BEGIN {
	print ";;;; balanced"; print ""; print "(define deep"
	printf "  \047"; for (i = 0; i < 100000; i++) printf "("
	printf "\"the bottom, with ) and ( in a string\""
	for (i = 0; i < 100000; i++) printf ")"; print ")"
	print ""; print "#| A block comment with ( and ) in it,"
	print "   #| a comment nested in it, with a ) |#"; print "   and still a ( in the outer one. |#"
	print ""; print "(define table"; print "  (quote ("
	for (i = 1; i <= 8000; i++)
		printf "    (row %06d \"a ) in a string\" #\\( #\\) |a (symbol| 3.14) ; a ( in a comment\n", i
	print "  )))"; print ""; print "(define (after-all) (vector-length (list->vector table)))"
}' > "$work/balanced.scm"
deep=$(head -2 "$work/balanced.scm" | wc -c | tr -d ' ')
deep_end=$(( $(head -4 "$work/balanced.scm" | wc -c | tr -d ' ') - 1 ))
table=$(grep -abo '^(define table' "$work/balanced.scm" | cut -d: -f1)
after=$(grep -abo '^(define (after-all)' "$work/balanced.scm" | cut -d: -f1)
size=$(wc -c < "$work/balanced.scm" | tr -d ' ')
run balanced balanced.scm '^N^N' '\e^F' '\e^B' '\e>' '\e^B' '\e^B' '\e^B' '\e^B'
check balanced "C-M-f and C-M-b over a quoted list 100,000 deep and a table of 8,000 rows with parens in strings, characters, |symbols| and comments" \
	"14 $deep $deep_end $deep $size $after $table $deep $deep"

exit $failed
