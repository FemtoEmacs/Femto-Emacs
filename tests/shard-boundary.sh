#!/bin/sh
# shard-boundary.sh -- edits where a file in shards is cut (22 November
# 2026; Eduardo's fourth test, first half).  src/shard.c cuts a file into
# shards that end at a newline, and a line longer than twice a shard at a
# byte that starts a character.  Here the cuts fall after a line that ends
# in a 4-byte character, inside a multi-line s-expression, and inside a
# long line of 2-, 3- and 4-byte characters; the text is edited on both
# sides of each cut, and saved.
#
#   1  shards of 4 KB: a mark typed at the start and at the end of every
#      shard, then C-x C-s.  The file, its marks taken out, must be the
#      original byte for byte (no offset moved), and with them be well-
#      formed UTF-8 (no character cut in two by a shard); the marks must
#      be where shard.c's rule puts them (an awk model of it)
#   2  the same file: DEL at the end of shard 1 (a newline, then a 4-byte
#      character), C-d at the start of shard 2 (a 2-byte character), a
#      line added in shard 1, C-M-f and C-M-b on the s-expression the cut
#      splits (they say so, and do not move), M-g to the long line, whose
#      start is in shard 2 and whose rest is cut into the shards after (it
#      went to the cut, not to the line's start), then C-x C-s: the file
#      must be the original with exactly these edits
#   3  the shards of 16 MB as they come (find-file-shards): 17 MB of lines,
#      then one line of 35 MB of characters of 2 to 4 bytes, cut inside;
#      marks at both ends of each shard, saved: as in 1
#
#   sh tests/shard-boundary.sh [quick]    quick: 1 and 2 only (make check)
#
# The marks are "|", which the files do not hold.  Disposable files, PTY.
# Each key within SHARD_LIMIT_MS (2000), as the backdoor's time measures.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
limit=${SHARD_LIMIT_MS:-2000}
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-shard-boundary.XXXXXX")
if [ "${SHARD_KEEP:-}" = 1 ]; then echo "work folder: $work"; else trap 'rm -rf "$work"' EXIT HUP INT TERM; fi
cc=${CC:-cc}
$cc -O2 tests/pty-keys.c -o "$work/pty" -lutil 2>/dev/null ||
	$cc -O2 tests/pty-keys.c -o "$work/pty"
mkdir -p "$work/home/.chezemax"
printf 'time\nrepeats keep\nwatch none\nlines 5000\n' > "$work/home/.chezemax/backdoor-claude.conf"
failed=0

session() {   # NAME TIMEOUT: NAME.keys after the file is open; record NAME.log
	name=$1 timeout=$2
	{
		echo 'await-screen [SAVE]'
		cat "$work/$name.open"
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
	(cd "$work"; HOME="$work/home" CHEZEMAX_NO_INIT=1 LC_ALL=C.UTF-8 \
		"$work/pty" "$work/$name.script" "$timeout" "$work/$name.screen" "$root/chezemax") \
		> "$work/$name.pty" 2>&1 || status=$?
	cp "$work/home/.chezemax/backdoor.txt" "$work/$name.log" 2>/dev/null || : > "$work/$name.log"
	if [ "$status" -ne 0 ]; then
		echo "FAIL $name: the session did not finish in $timeout s (status $status)"
		failed=1
		return 1
	fi
}

key_times() {
	awk -v limit="$limit" -v name="$1" -v what="$2" '
	/^#/ && / ms: command / && !/ esc x / {
		line = $0; sub(/.*\| /, "", line); ms = line + 0
		key = $0; sub(/^#[0-9.]* /, "", key); sub(/ pt=.*/, "", key)
		n++; if (ms > worst) { worst = ms; wkey = key }
		if (ms > limit) { printf "  %s: %s took %.0f ms (limit %d)\n", name, key, ms, limit; bad = 1 }
	}
	END {
		if (n == 0) { printf "FAIL %s: no key in the record\n", name; exit 1 }
		if (bad) { printf "FAIL %s: %s\n", name, what; exit 1 }
		printf "PASS %s: %s; the slowest key %s in %.0f ms\n", name, what, wkey, worst
	}' "$work/$1.log" || failed=1
}

check() {   # NAME TEXT COMMAND...
	name=$1 text=$2; shift 2
	if "$@"; then :; else echo "FAIL $name: $text"; failed=1; fi
}

# Is FILE well-formed UTF-8?  A small C program of the test (iconv differs
# from one system to another): no lone or stray continuation byte, no
# overlong form, no surrogate, nothing past U+10FFFF.  When not, it says
# at which byte, and shows the bytes around it.
cat > "$work/utf8check.c" <<'C'
#include <stdio.h>
#include <stdlib.h>
int main(int argc, char **argv)
{
	FILE *f = fopen(argv[1], "rb");
	unsigned char *b;
	long n, i = 0, k;
	if (!f) return 2;
	fseek(f, 0, SEEK_END); n = ftell(f); rewind(f);
	b = malloc((size_t) n + 1);
	if (!b || fread(b, 1, (size_t) n, f) != (size_t) n) return 2;
	while (i < n) {
		unsigned c = b[i], need, cp, min;
		if (c < 0x80) { i++; continue; }
		if (c >= 0xC2 && c <= 0xDF) { need = 1; cp = c & 0x1F; min = 0x80; }
		else if (c >= 0xE0 && c <= 0xEF) { need = 2; cp = c & 0x0F; min = 0x800; }
		else if (c >= 0xF0 && c <= 0xF4) { need = 3; cp = c & 0x07; min = 0x10000; }
		else goto bad;
		for (k = 1; k <= (long) need; k++) {
			if (i + k >= n || (b[i + k] & 0xC0) != 0x80) goto bad;
			cp = (cp << 6) | (b[i + k] & 0x3F);
		}
		if (cp < min || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)) goto bad;
		i += need + 1;
	}
	return 0;
bad:
	printf("not UTF-8 at byte %ld:", i);
	for (k = i - 8 < 0 ? 0 : i - 8; k < n && k < i + 8; k++) printf(k == i ? " [%02x]" : " %02x", b[k]);
	printf("\n");
	return 1;
}
C
$cc -O2 "$work/utf8check.c" -o "$work/utf8check"
utf8_ok() { "$work/utf8check" "$1"; }

# the starts of the shards of FILE in bytes, one a line, by shard.c's rule
# (build_index), written again here: a shard ends after the first newline
# at SIZE bytes or more, or, SIZE * 2 bytes without one, before a byte that
# starts a character
cat > "$work/starts.c" <<'C'
#include <stdio.h>
#include <stdlib.h>
int main(int argc, char **argv)
{
	FILE *f = fopen(argv[1], "rb");
	long long size = atoll(argv[2]), at = 0, start = 0;
	int c;
	if (!f) return 2;
	printf("0\n");
	while ((c = getc(f)) != EOF) {
		if (at - start >= 2 * size && (c & 0xC0) != 0x80) { printf("%lld\n", at); start = at; }
		if (c == '\n' && at + 1 - start >= size) { start = at + 1; printf("%lld\n", start); }
		at++;
	}
	fclose(f);
	return 0;
}
C
$cc -O2 "$work/starts.c" -o "$work/starts"
shard_starts() {   # FILE SIZE: the starts, the end of the file left out
	total=$(wc -c < "$1" | tr -d ' ')
	"$work/starts" "$1" "$2" | awk -v total="$total" '$1 < total'
}

# FILE with a | at the start and at the end of each shard: what the marks
# typed must give
marked() {   # FILE STARTS-FILE OUT
	total=$(wc -c < "$1" | tr -d ' ')
	: > "$3"
	{ cat "$2"; echo "$total"; } | awk 'NR > 1 { print prev, $1 } { prev = $1 }' |
	while read a b; do
		printf '|' >> "$3"
		tail -c +$((a + 1)) "$1" | head -c $((b - a)) >> "$3"
		printf '|' >> "$3"
	done
}

# --------------------------------------------------------------- the file
# 130 lines of text, each ending in a 4-byte character; a multi-line
# s-expression across the first cut (each line starting with a 2-byte
# character, ending with a 4-byte one); more lines; one line of 20,000
# bytes of 2-, 3- and 4-byte characters (cut inside: more than 2 x 4 KB);
# 400 lines after
make_small() {
	{
		i=1; while [ $i -le 125 ]; do printf 'line %03d: ção € fin 😀\n' $i; i=$((i + 1)); done
		printf '(define (across-the-cut x)\n'
		i=1; while [ $i -le 40 ]; do printf 'ç(list "ção" %d € x) ; ¿ 😀\n' $i; i=$((i + 1)); done
		printf 'çx))\n'
		i=1; while [ $i -le 100 ]; do printf 'after %03d: ñ ü 中文 😀\n' $i; i=$((i + 1)); done
		i=0; while [ $i -lt 1700 ]; do printf 'ção€😀'; i=$((i + 1)); done; printf '\n'
		i=1; while [ $i -le 400 ]; do printf 'tail %03d: ção 😀\n' $i; i=$((i + 1)); done
	} > "$1"
}
make_small "$work/orig.scm"
grep -q '|' "$work/orig.scm" && { echo "FAIL the test file holds a |"; exit 1; }
small_open='keys \e:(fe-shard-size 4096)\r
wait 300
keys \exfind-file-shards\r
wait 300
keys ^A^Kf.scm\r
wait 800'

# --------------------------------------------------------------- 1
shard_starts "$work/orig.scm" 4096 > "$work/starts1"
n=$(wc -l < "$work/starts1" | tr -d ' ')
cp "$work/orig.scm" "$work/f.scm"
printf '%s\n' "$small_open" > "$work/marks-small.open"
: > "$work/marks-small.keys"
k=1
while [ $k -le "$n" ]; do
	printf 'keys \\e<|\nwait 200\nkeys \\e>|\nwait 300\n' >> "$work/marks-small.keys"
	[ $k -lt "$n" ] && printf 'keys ^C^Vn\nwait 400\n' >> "$work/marks-small.keys"
	k=$((k + 1))
done
printf 'keys ^X^S\nwait 1500\n' >> "$work/marks-small.keys"
if session marks-small 120; then
	key_times marks-small "marks at both ends of $n shards of 4 KB, saved"
	tr -d '|' < "$work/f.scm" > "$work/f-unmarked.scm"
	check marks-small "the file without its marks is not the original: an offset moved" cmp -s "$work/f-unmarked.scm" "$work/orig.scm"
	check marks-small "a mark cut a character in two: a shard split a UTF-8 sequence" utf8_ok "$work/f.scm"
	marked "$work/orig.scm" "$work/starts1" "$work/want1.scm"
	check marks-small "the marks are not where shard.c's rule puts the cuts" cmp -s "$work/want1.scm" "$work/f.scm"
	check marks-small "no cut inside the long line" sh -c "grep -a 'ção€😀' '$work/f.scm' | grep -q '||'"
	check marks-small "no cut inside the s-expression" sh -c "sed -n '/^(define (across/,/^çx))/p' '$work/f.scm' | grep -q '^|'"
fi

# --------------------------------------------------------------- 2
# the line that ends shard 1, the line of "(define", and the line M-g goes
# to: the one shard 3 starts inside (one more: the line added).  The newline after
# the DELs is pasted: Return in a .scm file would indent the lines.
first=$(sed -n 2p "$work/starts1")
endline=$(head -c "$first" "$work/orig.scm" | wc -l | tr -d ' ')
dline=$(( $(grep -n '^(define (across' "$work/orig.scm" | cut -d: -f1) + 1 ))
third=$(sed -n 3p "$work/starts1")
goline=$(( $(head -c "$third" "$work/orig.scm" | wc -l | tr -d ' ') + 1 + 1 ))
cp "$work/orig.scm" "$work/f.scm"
printf '%s\n' "$small_open" > "$work/edit-small.open"
cat > "$work/edit-small.keys" <<KEYS
keys added line\r
wait 200
keys \eg$dline\r
wait 400
keys \e^F
wait 400
keys \e>
wait 300
keys ^?^?«»\e[200~\r\e[201~
wait 300
keys ^C^Vn
wait 400
keys ^D
wait 200
keys \e^B
wait 300
keys \eg$goline\r
wait 500
keys @
wait 200
keys ^X^S
wait 1500
KEYS
if session edit-small 120; then
	key_times edit-small "edits at both sides of a cut, C-M-f and C-M-b on the split s-expression, M-g to a line cut across shards"
	LC_ALL=C awk -v endline="$endline" '
		NR == 1 { print "added line" }
		NR == endline { sub(/😀$/, "«»") }
		NR == endline + 1 { sub(/^ç/, "") }
		{ print }' "$work/orig.scm" | LC_ALL=C awk -v l="$goline" 'NR == l { $0 = "@" $0 } { print }' > "$work/want2.scm"
	check edit-small "the saved file is not the original with exactly the edits" cmp -s "$work/want2.scm" "$work/f.scm"
	check edit-small "the saved file is not well-formed UTF-8" utf8_ok "$work/f.scm"
	# C-M-b at the start of shard 2 and C-M-f inside the split s-expression:
	# no expression whole in the shard, said so, and point did not move
	pts=$(grep -a '^#' "$work/edit-small.log" | sed 's/^#[0-9]* \(.*\) pt=\([0-9]*\) .*/\1|\2/')
	before_f=$(echo "$pts" | grep -B1 '^esc C-f|' | head -1 | cut -d'|' -f2)
	after_f=$(echo "$pts" | grep '^esc C-f|' | head -1 | cut -d'|' -f2)
	after_b=$(echo "$pts" | grep '^esc C-b|' | head -1 | cut -d'|' -f2)
	check edit-small "C-M-f on the s-expression the cut splits moved ($before_f -> $after_f)" [ "${before_f:-x}" = "${after_f:-y}" ]
	check edit-small "C-M-f did not say there is no expression whole" grep -aq 'No expression after the cursor' "$work/edit-small.screen"
	check edit-small "C-M-b at the start of a shard moved (to $after_b)" [ "${after_b:-x}" = 0 ]
	check edit-small "C-M-b did not say there is no expression" grep -aq 'No expression before the cursor' "$work/edit-small.screen"
fi

# --------------------------------------------------------------- 3
[ "${1:-}" = quick ] && exit $failed
# 17 MB of lines, the one at the 16 MB cut ending in a 4-byte character
# and the next starting with a 2-byte one; a line of 35 MB of characters
# (cut at 32 MB inside, at a character); 1,000 lines after
{
	awk 'BEGIN { for (i = 0; i < 400000; i++) printf "ç line %06d of the first shard, ends 😀\n", i }'
	awk 'BEGIN { s = "ção€😀ñ中"; for (i = 0; i < 12; i++) s = s s; for (i = 0; i < 500; i++) printf "%s", s; printf "\n" }'
	awk 'BEGIN { for (i = 0; i < 1000; i++) printf "ç tail %04d 😀\n", i }'
} > "$work/big.txt"
shard_starts "$work/big.txt" 16777216 > "$work/starts3"
n=$(wc -l < "$work/starts3" | tr -d ' ')
cp "$work/big.txt" "$work/g.txt"
printf 'keys \\exfind-file-shards\\r\nwait 300\nkeys ^A^Kg.txt\\r\nwait 3000\n' > "$work/marks-16mb.open"
: > "$work/marks-16mb.keys"
k=1
while [ $k -le "$n" ]; do
	printf 'keys \\e<|\nwait 300\nkeys \\e>|\nwait 1500\n' >> "$work/marks-16mb.keys"
	[ $k -lt "$n" ] && printf 'keys ^C^Vn\nwait 3000\n' >> "$work/marks-16mb.keys"
	k=$((k + 1))
done
printf 'keys ^X^S\nwait 8000\n' >> "$work/marks-16mb.keys"
if session marks-16mb 600; then
	key_times marks-16mb "marks at both ends of $n shards of 16 MB (a cut after a 4-byte character, one inside a line of 35 MB), saved"
	tr -d '|' < "$work/g.txt" > "$work/g-unmarked.txt"
	check marks-16mb "the file without its marks is not the original: an offset moved" cmp -s "$work/g-unmarked.txt" "$work/big.txt"
	check marks-16mb "a mark cut a character in two: a shard split a UTF-8 sequence" utf8_ok "$work/g.txt"
	marked "$work/big.txt" "$work/starts3" "$work/want3.txt"
	check marks-16mb "the marks are not where shard.c's rule puts the cuts" cmp -s "$work/want3.txt" "$work/g.txt"
	check marks-16mb "the 16 MB cut is not after a line ending in 😀, before one starting with ç" \
		sh -c "grep -a -B1 '^||ç' '$work/g.txt' | head -1 | grep -q '😀$'"
fi

exit $failed
