#!/bin/sh
# Random walks over the whole editor (make check-fuzz-editor; 21 November
# 2026).  The editor, built with AddressSanitizer and UndefinedBehavior-
# Sanitizer (make chezemax-sanitized) and run with CHEZWEB_CHECK=1 (it
# checks its invariants after every key: src/check.c), gets random keys in
# a terminal of its own (tests/pty-keys.c), on a disposable file:
#
#   typing   ASCII, Greek, Korean, Chinese, emoji, combining accents, and
#            bytes that are not UTF-8
#   keys     C-f C-b M-f M-b C-n C-p C-a C-e M-< M-> C-d DEL C-k C-SPC C-w
#            M-w C-y C-/ C-M-_ M-q TAB RET C-x 2 C-x 3 C-x o C-x 1 C-g
#
# Every 40 keys a checkpoint, C-c 9 (fuzz-check, tests/fuzz-editor.scm): undo, as far as it goes, must give
# back the text of the previous checkpoint byte for byte, and redo, as far
# as it goes, the text before the undo; then the history starts again.
#
# A walk fails when the editor aborts (a sanitizer, or CHEZWEB_CHECK), when
# a checkpoint answers BAD, or when it does not answer.  A failing walk is
# shrunk: keys are removed while it still breaks the same way (each try
# reruns the editor, so this takes minutes; -S skips it).  The keys, the
# file and the last run are kept in fuzz-editor-SEED/ in the repository.
#
#   sh tests/fuzz-editor.sh [-s SEED] [-n WALKS] [-k KEYS] [-f md|org|scm|txt] [-S]
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
seed=$(date +%s) walks=1 keys=400 kind= shrinking=yes
while getopts s:n:k:f:S o; do
	case $o in s) seed=$OPTARG ;; n) walks=$OPTARG ;; k) keys=$OPTARG ;; f) kind=$OPTARG ;; S) shrinking=no ;; *) exit 2 ;; esac
done
[ -x ./chezemax-sanitized ] || { echo 'make chezemax-sanitized first (make check-fuzz-editor does)'; exit 2; }
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-fuzz-editor.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
cc=${CC:-cc}
$cc -O2 tests/pty-keys.c -o "$work/pty" -lutil 2>/dev/null || $cc -O2 tests/pty-keys.c -o "$work/pty"
export ASAN_OPTIONS=${ASAN_OPTIONS:-detect_leaks=0:abort_on_error=1}
export UBSAN_OPTIONS=${UBSAN_OPTIONS:-print_stacktrace=1}
export LC_ALL=C.UTF-8

# the checkpoints (tests/fuzz-editor.scm), compiled into the editor once, as
# a user's script (some three minutes), and kept in build/fuzz-editor-home
template="$root/build/fuzz-editor-home"
if [ ! -s "$template/.chezemax/chezemax.cwasm" ] || [ chezemax.wasm -nt "$template/.chezemax/chezemax.wasm" ] ||
   [ tests/fuzz-editor.scm -nt "$template/.chezemax/chezemax.wasm" ]; then
	echo "Compiling the checkpoints into the editor (a few minutes, once)"
	rm -rf "$template"; mkdir -p "$template/.chezemax/users"
	cp tests/fuzz-editor.scm "$template/.chezemax/users/fuzz.scm"
	HOME="$template" ./chezemax --compile-scripts > "$work/compile.txt" 2>&1 || { cat "$work/compile.txt"; exit 1; }
fi
export CHEZWEB_CHECK=1


# what broke in the run in $1, in a few words (empty: nothing), so that
# shrinking keeps a sequence that breaks the same way
failure_of() {
	if [ -s "$1/check.txt" ]; then sed -n '1s/^CHEZWEB_CHECK: \([^(]*\) (.*/\1/p' "$1/check.txt"
	elif grep -aq 'ERROR: AddressSanitizer' "$1/screen" "$1/pty.txt" 2>/dev/null; then
		grep -aoh 'ERROR: AddressSanitizer: [a-z-]*' "$1/screen" "$1/pty.txt" | head -1
	elif grep -aq 'runtime error:' "$1/screen" "$1/pty.txt" 2>/dev/null; then
		grep -aoh 'runtime error: [a-z ]*' "$1/screen" "$1/pty.txt" | head -1
	elif grep -aq '(FUZZ [0-9]* BAD' "$1/screen"; then echo "a checkpoint: undo or redo did not give back the text"
	elif [ "$(cat "$1/status")" -ne 0 ]; then echo "no answer: the walk did not finish"
	fi
}
# the details: the whole message, or the sanitizer's report
details_of() {
	if [ -s "$1/check.txt" ]; then cat "$1/check.txt"
	else sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' "$1/screen" "$1/pty.txt" | grep -a 'ERROR: AddressSanitizer\|runtime error:\|^ *#[0-9]* \|(FUZZ [0-9]* BAD' | head -30
	fi
}
# run the keys of unit file $2 (one key, or one checkpoint, a line) on a
# fresh copy of $1/orig.KIND, in $1/run
run_units() {
	run="$1/run"; rm -rf "$run"; mkdir -p "$run/home/.chezemax"
	cp "$template/.chezemax/chezemax.wasm" "$template/.chezemax/chezemax.cwasm" "$run/home/.chezemax/"
	k=$(cat "$1/kind"); cp "$1/orig.$k" "$run/t.$k"
	awk 'BEGIN { print "await-screen [SAVE]"; print "keys ^C8"; print "await-screen FUZZ-START" }
	     $0 == "CHECK" { c++; print "keys ^G^C9"; print "await-screen (FUZZ " c " "; next }
	     { print }
	     END { print "keys ^G^X^C"; print "wait 300"; print "keys y"; print "wait 300"; print "keys y" }' "$2" > "$run/keys"
	n=$(grep -c '^keys' "$run/keys")
	status=0
	HOME="$run/home" CHEZWEB_CHECK_FILE="$run/check.txt" \
		"$work/pty" "$run/keys" $((60 + n / 4)) "$run/screen" "$root/chezemax-sanitized" "$run/t.$k" > "$run/pty.txt" 2>&1 || status=$?
	echo "$status" > "$run/status"
	failure_of "$run"
}
# remove units while the walk still breaks the same way: chunks first,
# then one at a time, as fuzz-core does
shrink() {
	dir=$1 want=$2 units="$1/units"
	total=$(wc -l < "$units") chunk=$((total / 2))
	while [ "$chunk" -ge 1 ]; do
		i=0 removed=0
		while [ "$i" -lt "$(wc -l < "$units")" ]; do
			awk -v a="$i" -v n="$chunk" 'NR <= a || NR > a + n' "$units" > "$dir/trial"
			if [ -s "$dir/trial" ] && [ "$(run_units "$dir" "$dir/trial")" = "$want" ]; then
				cp "$dir/trial" "$units"; removed=1
			else i=$((i + chunk)); fi
		done
		[ "$removed" -eq 1 ] || chunk=$((chunk / 2))
	done
}

w=0
while [ "$w" -lt "$walks" ]; do
	s=$((seed + w))
	dir="$work/walk-$s"
	mkdir -p "$dir"
	# the file, and the keys: one key, or CHECK, a line
	awk -v seed="$s" -v keys="$keys" -v kind="$kind" -v dir="$dir" '
	# a generator of its own (Park and Miller): the awks of Linux and macOS
	# differ, and mawk 1.3.4 is not reproducible from srand(seed)
	function pick(n) { x = (x * 16807) % 2147483647; return int(x / 2147483647 * n) }
	function rand_() { x = (x * 16807) % 2147483647; return x / 2147483647 }
	BEGIN {
		x = seed % 2147483646 + 1
		for (i = 0; i < 20; i++) pick(2)          # away from the small numbers of a small seed
		split("md org scm txt", kinds, " ")
		k = kind != "" ? kind : kinds[pick(4) + 1]
		file = dir "/orig." k
		printf "%s\n", k > (dir "/kind")
		# a text with every width, and the structure of the kind
		split("Olá, mundo.|αβγ δεζ|가나다 한국어|中文 字符|🙂 🌍 emoji|e\xcc\x81 n\xcc\x83 accents|plain ascii line", lines, "|")
		for (i = 0; i < 12; i++) {
			if (k == "org" && i % 4 == 0) printf "* Heading %d\n", i > file
			else if (k == "md" && i % 4 == 0) printf "## Heading %d\n", i > file
			else if (k == "scm" && i % 3 == 0) printf "(define (f%d x) ; %s\n  (+ x %d))\n", i, lines[pick(7) + 1], i > file
			printf "%s %s\n", lines[pick(7) + 1], lines[pick(7) + 1] > file
		}
		n = split("a|z| |\\r|α|ω|가|힣|中|文|🙂|\xcc\x81|\xff|\x80|\xc3", typed, "|")
		m = split("^F|^B|\\ef|\\eb|^N|^P|^A|^E|\\e<|\\e>|^D|^?|^K|^@|^W|\\ew|^Y|^_|\\e^_|\\eq|\\t|^X2|^X3|^Xo|^X1|^G", cmds, "|")
		for (i = 0; i < keys; i++) {
			if (rand_() < 0.45) print "keys " typed[pick(n) + 1]
			else print "keys " cmds[pick(m) + 1]
			if (i % 40 == 39 || i == keys - 1) print "CHECK"
		}
	}' > "$dir/units"
	kindname=$(cat "$dir/kind")
	why=$(run_units "$dir" "$dir/units")
	if [ -n "$why" ]; then
		keep="$root/fuzz-editor-$s"
		echo "FAIL walk seed $s (.$kindname file): $why"
		details_of "$dir/run" | sed 's/^/  /' | head -12
		# the keys after the first checkpoint that did not answer cannot matter
		answered=$(grep -ao '(FUZZ [0-9]* ' "$dir/run/screen" | sort -u | wc -l)
		awk -v keep="$((answered + 1))" '{ print } $0 == "CHECK" && ++c == keep { exit }' "$dir/units" > "$dir/trial"
		cp "$dir/trial" "$dir/units"
		if [ "$shrinking" = yes ]; then
			echo "shrinking (each try reruns the editor: some minutes)"
			shrink "$dir" "$why"
			run_units "$dir" "$dir/units" > /dev/null
			echo "shortest sequence that breaks ($(grep -c . "$dir/units") lines; CHECK is a checkpoint):"
			sed 's/^keys /  /;s/^CHECK$/  (checkpoint)/' "$dir/units"
			echo "what breaks:"; details_of "$dir/run" | sed 's/^/  /' | head -12
		fi
		rm -rf "$keep"; cp -R "$dir" "$keep"
		echo "kept in fuzz-editor-$s/ (units: the keys; orig.$kindname: the file; run/: the last run)"
		echo "replay: sh tests/fuzz-editor.sh -s $s -k $keys -f $kindname"
		exit 1
	fi
	echo "ok   walk seed $s: $keys keys on a .$kindname file, every invariant after every key, undo and redo at $(grep -c '^CHECK' "$dir/units") checkpoints"
	w=$((w + 1))
done
echo "PASS fuzz-editor: $walks random walks of $keys keys under the sanitizers and CHEZWEB_CHECK"
