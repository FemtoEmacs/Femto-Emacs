#!/bin/sh
# complexity.sh -- the classic traps of an editor, each key within 2 seconds
# (22 November 2026; Eduardo's third test).  C-M-f over a 9.7 MB list once
# took 42 seconds (tests/sexp-speed.sh): a cost linear in the text paid for
# every byte, or for every key, is quadratic, and a large file shows it.
# Here every key of every scenario must finish, command and display, within
# COMPLEXITY_LIMIT_MS (2000); the backdoor's `time` gives both.
#
#   delimiters  10 MB of ( on one line, and 100,000 lines of them, never
#               closed (.scm): C-M-f and C-M-b at the start and at the end,
#               typing at the start and at the end (the highlighter must not
#               read the text again from the top for every key)
#   search      50 MB: C-s and C-r with a pattern that fails, one key at a
#               time; M-% of a pattern that is not there
#   replace     100,000 occurrences, on 100,000 lines and on one line: M-%
#               with ! growing and shrinking the text, then C-/ of it all;
#               the files written after each are checked
#   longline    one line of 5 MB of minified JSON (with accents and CJK):
#               C-e, C-a, C-f, C-b, M->, C-n, clicks, typing
#               (open-line and longline run twice: the second time
#               display.c scans long lines from their start, as before it
#               remembered them, and every point, page and cursor must be
#               the same)
#   fill        M-q on one paragraph of 50,000 words on one line, and on
#               items of nested Markdown and Org lists (12,000 items)
#
#   sh tests/complexity.sh [delimiters|search|replace|longline|fill|all]
#
# A key that does not finish at all ends the scenario at its timeout.
# Keys that read a prompt are pasted, all at once (pty-keys `paste`), so
# that their time is their work and not the 30 ms each typed key waits.
# Disposable files and PTY.  COMPLEXITY_KEEP=1 keeps the work folder.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
limit=${COMPLEXITY_LIMIT_MS:-2000}
which=${1:-all}
editor=${COMPLEXITY_EDITOR:-./chezemax}
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-complexity.XXXXXX")
if [ "${COMPLEXITY_KEEP:-}" = 1 ]; then
	echo "work folder: $work"
else
	trap 'rm -rf "$work"' EXIT HUP INT TERM
fi
cc=${CC:-cc}
$cc -O2 tests/pty-keys.c -o "$work/pty" -lutil 2>/dev/null ||
	$cc -O2 tests/pty-keys.c -o "$work/pty"
mkdir -p "$work/home/.chezemax"
printf 'time\nrepeats keep\nwatch none\nlines 5000\n' > "$work/home/.chezemax/backdoor-claude.conf"
failed=0

# session NAME FILE TIMEOUT: runs the editor on FILE with the keys of
# $work/NAME.keys between the backdoor's opening and closing, then quits
# (answering y to the question of modified buffers); the record is
# $work/NAME.log
session() {
	name=$1 file=$2 timeout=$3
	{
		echo 'await-screen [SAVE]'
		echo 'keys \exbackdoor-claude\r'
		echo 'wait 300'
		cat "$work/$name.keys"
		echo 'wait 300'
		echo 'keys \exbackdoor-claude\r'
		echo 'wait 300'
		echo 'keys ^G^X^C'
		echo 'wait 300'
		echo 'keys y'
		echo 'wait 300'
	} > "$work/$name.script"
	rm -f "$work/home/.chezemax/backdoor.txt"
	status=0
	(cd "$work"; HOME="$work/home" CHEZEMAX_NO_INIT=1 LC_ALL=C.UTF-8 CHEZWEB_LONG_LINES="${long_lines:-}" \
		"$work/pty" "$work/$name.script" "$timeout" "$work/$name.screen" "$root/$editor" "$file") \
		> "$work/$name.pty" 2>&1 || status=$?
	cp "$work/home/.chezemax/backdoor.txt" "$work/$name.log" 2>/dev/null || : > "$work/$name.log"
	if [ "$status" -ne 0 ]; then
		echo "FAIL $name: the session did not finish in $timeout s (status $status): a key hangs"
		grep -a '^#' "$work/$name.log" | tail -3
		failed=1
		return 1
	fi
	return 0
}

# key_times NAME WHAT: every key of the record within the limit; prints the
# slowest.  The M-x that closes the backdoor is left out (typed, not pasted).
key_times() {
	name=$1 what=$2
	awk -v limit="$limit" -v what="$what" -v name="$name" '
	/^#/ && / ms: command / && !/ esc x / {
		line = $0; sub(/.*\| /, "", line); ms = line + 0
		key = $0; sub(/^#[0-9.]* /, "", key); sub(/ pt=.*/, "", key)
		n++
		if (ms > worst) { worst = ms; wkey = key }
		if (ms > limit) { printf "  %s: %s took %.0f ms (limit %d)\n", name, key, ms, limit; bad = 1 }
	}
	END {
		if (n == 0) { printf "FAIL %s: no key in the record\n", name; exit 1 }
		if (bad) { printf "FAIL %s: %s\n", name, what; exit 1 }
		printf "PASS %s: %s; %d keys, the slowest %s in %.0f ms\n", name, what, n, wkey, worst
	}' "$work/$name.log" || failed=1
}

# same_display NAME FILE: the keys of NAME again, with CHEZWEB_LONG_LINES=scan
# (display.c remembers nothing of long lines, and scans them from the start
# as before): point, page and cursor after every key must be the same
same_display() {
	base=$1 basefile=$2
	cp "$work/$base.keys" "$work/$base-scan.keys"
	long_lines=scan
	if session "$base-scan" "$basefile" 600; then
		for n in "$base" "$base-scan"; do
			grep -a '^#' "$work/$n.log" | sed 's/ size=.*//' > "$work/$n.places"
		done
		check "$base" "the display remembering the long line put point, page or cursor elsewhere than the scan from the start" \
			cmp -s "$work/$base.places" "$work/$base-scan.places"
	fi
	long_lines=
}

# the point after the Nth key of the record named KEY
point_after() {
	grep -a "^#[0-9]* $2 pt=" "$work/$1.log" | sed -n "${3}p" | sed 's/.* pt=\([0-9]*\) .*/\1/'
}

check() {   # check NAME CONDITION-TEXT COMMAND...
	name=$1 text=$2; shift 2
	if "$@"; then :; else echo "FAIL $name: $text"; failed=1; fi
}

# ------------------------------------------------------------ delimiters
delimiters() {
	# 10 MB of ( on one line
	awk 'BEGIN { s = "(((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((("; for (i = 0; i < 14; i++) s = s s; for (i = 0; i < 10; i++) printf "%s", s; printf "\n" }' > "$work/open-line.scm"
	size=$(wc -c < "$work/open-line.scm" | tr -d ' ')
	cat > "$work/open-line.keys" <<'KEYS'
keys \e^F
wait 300
keys \e^B
wait 300
keys x
wait 300
keys \e>
wait 300
keys \e^B
wait 300
keys \e^F
wait 300
keys y
wait 300
keys ^?
wait 300
keys ^A
wait 300
keys ^E
wait 300
KEYS
	if session open-line open-line.scm 300; then
		key_times open-line "C-M-f, C-M-b and typing at both ends of $((size / 1048576)) MB of ( on one line, never closed"
		same_display open-line open-line.scm
	fi

	# 100,000 lines of 100 ( each
	awk 'BEGIN { s = "(((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((("; for (i = 0; i < 100000; i++) print s }' > "$work/open-lines.scm"
	cat > "$work/open-lines.keys" <<'KEYS'
keys \e^F
wait 300
keys \e^B
wait 300
keys x
wait 300
keys ^N
wait 300
keys \e>
wait 300
keys \e^B
wait 300
keys ^P
wait 300
keys y
wait 300
keys \e^F
wait 300
keys \e<
wait 300
KEYS
	if session open-lines open-lines.scm 300; then
		key_times open-lines "C-M-f, C-M-b, typing and moving in 100,000 lines of (, never closed"
	fi
}

# ------------------------------------------------------------ search
search() {
	# 50 MB of text without the letters q and z
	awk 'BEGIN { for (i = 0; i < 880000; i++) printf "line %06d of fifty megabytes of plain text, all the same.\n", i }' > "$work/big.txt"
	size=$(wc -c < "$work/big.txt" | tr -d ' ')
	cat > "$work/search.keys" <<'KEYS'
paste ^Szqxj
wait 500
paste \r
wait 300
paste ^Sline 879999\r
wait 500
paste ^Rzqxj
wait 500
paste \r
wait 300
paste \e<
wait 300
paste \e%zqxj\rfound\r
wait 500
KEYS
	if session search big.txt 300; then
		key_times search "C-s, C-r and M-% of a pattern that fails, over $((size / 1048576)) MB"
		p=$(point_after search C-s 2)
		check search "C-s did not find the last line (point $p)" [ "${p:-0}" -gt $((size - 100)) ]
	fi
}

# ------------------------------------------------------------ replace
replace_session() {   # NAME FILE TO: M-% foo -> TO with !, written; C-/, written
	name=$1 file=$2 to=$3
	{
		printf 'paste \\e%%foo\\r%s\\r!\n' "$to"
		echo 'wait 1000'
		printf 'paste ^X^W^A^K%s\\r\n' "$work/$name-replaced.txt"
		echo 'wait 1000'
		echo 'paste ^_'
		echo 'wait 1000'
		printf 'paste ^X^W^A^K%s\\r\n' "$work/$name-undone.txt"
		echo 'wait 1000'
	} > "$work/$name.keys"
	session "$name" "$file" 600 || return 0
	key_times "$name" "$4"
	sed "s/foo/$to/g" "$work/$file" > "$work/$name-expected.txt"
	check "$name" "M-% foo -> $to with ! did not give the text expected" cmp -s "$work/$name-replaced.txt" "$work/$name-expected.txt"
	check "$name" "C-/ after it did not give the text back" cmp -s "$work/$name-undone.txt" "$work/$file"
	grep -aq '100000 substitutions' "$work/$name.screen" ||
		{ echo "FAIL $name: M-% did not say 100000 substitutions"; failed=1; }
}
replace() {
	# 100,000 occurrences: on 100,000 lines, and on one line (each 1 to 2 MB:
	# the text before and after fits in what undo keeps, 8 MB)
	awk 'BEGIN { for (i = 0; i < 100000; i++) printf "%06d: a foo on the line\n", i }' > "$work/lines.txt"
	awk 'BEGIN { for (i = 0; i < 100000; i++) printf "%06d foo ", i; printf "\n" }' > "$work/line.txt"
	replace_session replace-lines-grow lines.txt barbaz "M-% foo -> barbaz with ! on 100,000 lines, and C-/"
	replace_session replace-lines-shrink lines.txt x "M-% foo -> x with ! on 100,000 lines, and C-/"
	replace_session replace-line-grow line.txt barbaz "M-% foo -> barbaz with ! on one line of 100,000, and C-/"
	replace_session replace-line-shrink line.txt x "M-% foo -> x with ! on one line of 100,000, and C-/"
}

# ------------------------------------------------------------ longline
longline() {
	# one line of 5 MB of JSON, with accents and CJK in the strings
	awk 'BEGIN { printf "{"; for (i = 0; i < 125000; i++) printf "\"k%d\":[1,2.5,\"café 中文\",{\"x\":null}],", i; printf "\"end\":true}\n" }' > "$work/min.json"
	size=$(wc -c < "$work/min.json" | tr -d ' ')
	cat > "$work/longline.keys" <<'KEYS'
keys ^E
wait 500
keys ^A
wait 500
keys ^F
wait 200
keys ^F
wait 200
keys ^F
wait 200
keys ^E
wait 500
keys ^B
wait 200
keys ^B
wait 200
keys x
wait 300
keys \e<
wait 300
keys \e>
wait 500
keys ^P
wait 300
keys ^N
wait 300
keys \e[<0;30;5M\e[<0;30;5m
wait 500
keys \e[<0;70;12M\e[<0;70;12m
wait 500
keys y
wait 300
keys ^A
wait 300
keys \e[<0;10;20M\e[<0;10;20m
wait 500
keys ^E
wait 500
KEYS
	if session longline min.json 300; then
		key_times longline "moving, clicking and typing in one line of $((size / 1048576)) MB of JSON"
		# C-a and C-e go to the ends of the row shown, as with Emacs's
		# visual-line-mode; M-> to the end of the text
		e=$(point_after longline 'esc >' 1)
		check longline "M-> did not go to the end of the text ($e, the text ends at $((size + 1)))" [ "${e:-0}" -eq $((size + 1)) ]
		same_display longline min.json
	fi
}

# ------------------------------------------------------------ fill
fill() {
	awk 'BEGIN { for (i = 0; i < 50000; i++) printf "%s%s", (i ? " " : ""), "word" (i % 97); printf "\n" }' > "$work/para.txt"
	cat > "$work/fill-paragraph.keys" <<'KEYS'
paste \eq
wait 1000
paste \e<
wait 300
paste \eq
wait 1000
KEYS
	printf 'paste ^X^W^A^K%s\\r\nwait 1000\n' "$work/para-filled.txt" >> "$work/fill-paragraph.keys"
	if session fill-paragraph para.txt 300; then
		key_times fill-paragraph "M-q on a paragraph of 50,000 words on one line, and again on the filled paragraph"
		tr -s ' \n' '\n\n' < "$work/para.txt" > "$work/para.words"
		tr -s ' \n' '\n\n' < "$work/para-filled.txt" > "$work/para-filled.words" 2>/dev/null || :
		check fill-paragraph "M-q lost or changed words" cmp -s "$work/para.words" "$work/para-filled.words"
		check fill-paragraph "M-q left lines longer than 70 columns" sh -c "! awk 'length > 70' '$work/para-filled.txt' | grep -q ."
		check fill-paragraph "M-q left the paragraph on one line" sh -c "[ \$(wc -l < '$work/para-filled.txt') -gt 1000 ]"
	fi

	# nested lists: 12,000 items, eight levels deep, a long line each
	for kind in md org; do
		awk -v kind=$kind 'BEGIN {
			if (kind == "org") print "* A heading over the list\n"
			for (i = 0; i < 12000; i++) {
				d = i % 8; pad = ""; for (j = 0; j < d; j++) pad = pad "  "
				printf "%s- item %d, at depth %d, with a line long enough to be refilled by M-q into two or three lines of the list\n", pad, i, d
			}
		}' > "$work/list.$kind"
		cat > "$work/fill-$kind.keys" <<'KEYS'
paste \eq
wait 500
paste \e>
wait 300
paste ^P^P
wait 300
paste \eq
wait 500
paste \e<
wait 300
paste ^N^N^N^N^N^N^N
wait 300
paste \eq
wait 500
KEYS
		if session "fill-$kind" "list.$kind" 300; then
			key_times "fill-$kind" "M-q on items of a nested $kind list of 12,000 items"
		fi
	done
}

case $which in
delimiters) delimiters ;;
search) search ;;
replace) replace ;;
longline) longline ;;
fill) fill ;;
all) delimiters; search; replace; longline; fill ;;
*) echo "usage: sh tests/complexity.sh [delimiters|search|replace|longline|fill|all]"; exit 2 ;;
esac
exit $failed
