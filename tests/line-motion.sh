#!/bin/sh
# line-motion.sh -- M-x move-beginning-of-line and M-x move-end-of-line
# (src/command.c), the ends of the line however many rows it takes, where
# C-a and C-e go to the ends of the row shown (24 November 2026).
#
#   1  a line of 200 KB of wide characters: from inside it, the line's ends;
#      C-e still stops at the end of the row
#   2  narrowed (C-x n n) inside that line: the ends of the narrowed part
#   3  a folded Org heading: the end of the heading's own text
#
# The point after each key is read from the backdoor.  Disposable files.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-line-motion.XXXXXX")
[ "${LM_KEEP:-}" = 1 ] && echo "work: $work" || trap 'rm -rf "$work"' EXIT HUP INT TERM
cc=${CC:-cc}
$cc -O2 tests/pty-keys.c -o "$work/pty" -lutil 2>/dev/null ||
	$cc -O2 tests/pty-keys.c -o "$work/pty"
mkdir -p "$work/home/.chezemax"
printf 'repeats keep\nwatch none\n' > "$work/home/.chezemax/backdoor-claude.conf"
failed=0

# session NAME FILE: the keys of NAME.keys; the points, one a line, in NAME.pts
session() {
	{
		echo 'await-screen [SAVE]'
		echo 'keys \exbackdoor-claude\r'
		echo 'wait 300'
		cat "$work/$1.keys"
		echo 'keys \exbackdoor-claude\r'
		echo 'wait 300'
		echo 'keys ^G^X^C'
		echo 'wait 300'
		echo 'keys y'
		echo 'wait 300'
	} > "$work/$1.script"
	rm -f "$work/home/.chezemax/backdoor.txt"
	(cd "$work"; HOME="$work/home" CHEZEMAX_NO_INIT=1 LC_ALL=C.UTF-8 \
		"$work/pty" "$work/$1.script" 60 "$work/$1.screen" "$root/chezemax" "$2") \
		> "$work/$1.pty" 2>&1 || { echo "FAIL $1: the session did not finish"; failed=1; return 1; }
	grep -a '^#' "$work/home/.chezemax/backdoor.txt" | grep -av 'esc x b' |
		sed 's/.* pt=\([0-9]*\) .*/\1/' > "$work/$1.pts"
}

# check NAME WHAT EXPECTED: the points, joined by spaces
check() {
	got=$(tr '\n' ' ' < "$work/$1.pts" | sed 's/ $//')
	if [ "$got" = "$3" ]; then echo "PASS $1: $2"
	else echo "FAIL $1: $2"; echo "  expected points: $3"; echo "  got:             $got"; failed=1; fi
}

mx() { printf 'paste \\ex%s\\r\nwait 500\n' "$1"; }

# ------------------------------------------------------------ 1
awk 'BEGIN { print "first line"; s = "ção€😀ñ中 "; for (i = 0; i < 10; i++) s = s s
             for (i = 0; i < 11; i++) printf "%s", s; printf "END\n"; print "last line" }' > "$work/long.txt"
nl=$(grep -abo END "$work/long.txt" | cut -d: -f1); nl=$((nl + 3))   # the long line's newline
{ printf 'keys ^N^N^N\nwait 300\n'; mx move-end-of-line; mx move-beginning-of-line
  printf 'keys ^E\nwait 300\n'; mx move-end-of-line
  printf 'keys ^N\nwait 300\n'; mx move-beginning-of-line; } > "$work/long.keys"
if session long long.txt; then
	set -- $(cat "$work/long.pts")
	# C-n C-n C-n, end, beginning, C-e, end, C-n, beginning
	check long "a line of 200 KB: its ends from inside it; C-e at the end of the row" \
		"11 $2 $3 $nl 11 $6 $nl $8 $((nl + 1))"
	[ "$6" -gt 11 ] && [ "$6" -lt 400 ] || { echo "FAIL long: C-e went to $6, not to the end of the first row"; failed=1; }
fi

# ------------------------------------------------------------ 2
# the mark 5 characters into the line (C-f counts characters, not bytes),
# the region to three rows down, C-x n n
{ printf 'keys ^N^F^F^F^F^F\nwait 300\nkeys ^@\nwait 300\nkeys ^N^N^N\nwait 300\nkeys ^Xnn\nwait 500\n'
  mx move-end-of-line; mx move-beginning-of-line; mx move-end-of-line; } > "$work/narrow.keys"
if session narrow long.txt; then
	set -- $(cat "$work/narrow.pts")
	start=$7 end=${10}
	# the region began at the mark ($7) and ended at ${10} (three rows down)
	got=$(sed -n '12,14p' "$work/narrow.pts" | tr '\n' ' ' | sed 's/ $//')
	if [ "$got" = "$end $start $end" ] && [ "$start" -gt 11 ] && [ "$end" -lt "$nl" ]; then
		echo "PASS narrow: narrowed inside the line, the ends of the narrowed part ($start, $end)"
	else
		echo "FAIL narrow: narrowed to [$start, $end), the ends went to: $got"; failed=1
	fi
fi

# ------------------------------------------------------------ 3
printf '* Heading with text\nbody one\nbody two\n* Second\nmore\n' > "$work/fold.org"
{ printf 'keys \\t\nwait 500\nkeys ^F^F^F\nwait 300\n'; mx move-end-of-line; mx move-beginning-of-line; mx move-end-of-line
  printf 'keys ^F\nwait 300\n'; } > "$work/fold.keys"
if session fold fold.org; then
	# TAB folds at 0; C-f C-f C-f; end (19, the heading's newline); beginning; end;
	# C-f goes past the fold to the second heading (38)
	check fold "a folded Org heading: the end of the heading's own text" "0 1 2 3 19 0 19 38"
fi

exit $failed
