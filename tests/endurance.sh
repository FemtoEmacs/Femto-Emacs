#!/bin/sh
# Long sessions (make check-endurance; 22 November 2026).  The editor runs
# a scenario and writes its meters as it goes (src/meters.c); this script
# reads the curve.  A leak is a slope: after a warm-up, what grows with the
# work done.
#
#   churn   open, show, use and kill (C-x k) buffers in one session:
#           Markdown, Org (a fold), Scheme (narrowing), text (read mode), a
#           big file in shards, a second window, an M-x term shell every 25
#           cycles (tests/endurance.scm, compiled into the editor as a
#           user's script).  The C heap must not grow by more than 64 bytes
#           a cycle, RSS by 4 KB (ordinary build), the descriptors and
#           buffers must come back, and no Scheme table that keeps
#           something by buffer may grow with the cycles.
#   flood   three times, M-x term floods the editor: yes (3 million lines), base64 of 20
#           MB of random bytes while the terminal is resized three times,
#           C-c b to another buffer and back during the flood, then 4 MB of
#           raw random bytes (invalid UTF-8, random escape sequences: the
#           shell is replaced by head, so that nothing reads them back as
#           commands), then C-x k of the terminal.  The C heap must stay
#           bounded during the flood (the terminal keeps 10000 lines) and
#           come back after the kill, the descriptors too, no shell or
#           child may be left, and the throughput must not fall by more
#           than four times from the start to the end of the flood.
#
# With -a the editor is the sanitized one (make chezemax-sanitized):
# AddressSanitizer and UndefinedBehaviorSanitizer stop it at the first
# fault, and LeakSanitizer must find nothing that no pointer reaches, in
# the middle of the churn and at the end of each session.
#
#   undo    in one buffer, chunks of 1 to 3 MB inserted and deleted, each a
#           command, so that the history passes *undo-limit* (8 MB) again
#           and again and drops its oldest groups; a 20 MB chunk every
#           tenth cycle, which no history keeps; undos and redos.  The
#           history must stay under the limit, and what it drops must be
#           freed: neither the C heap nor RSS may grow with the cycles.
#
#   big     a cut (C-w) and a yank (C-y) of 21 MB: memory may rise by the
#           copy C keeps for C-y, and little more (make check-big-edit, in
#           make check).
#
#   sh tests/endurance.sh [-t churn|flood|undo|big|all] [-n CYCLES] [-u UNDO-CYCLES] [-a]
# A failing run keeps its curve in endurance-meters.txt (ignored by git).
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
cycles=1000 undo_cycles=100 editor=./chezemax sanitized=no which=all
while getopts t:n:u:a o; do
	case $o in t) which=$OPTARG ;; n) cycles=$OPTARG ;; u) undo_cycles=$OPTARG ;; a) editor=./chezemax-sanitized sanitized=yes ;; *) exit 2 ;; esac
done
[ -x "$editor" ] || { echo "make $(basename "$editor") first"; exit 2; }
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-endurance.XXXXXX")
if [ -n "${ENDURANCE_KEEP:-}" ]; then echo "endurance diagnostics: $work"; fi
trap '[ -n "${ENDURANCE_KEEP:-}" ] || rm -rf "$work"' EXIT HUP INT TERM
cc=${CC:-cc}
$cc -O2 tests/pty-keys.c -o "$work/pty" -lutil 2>/dev/null || $cc -O2 tests/pty-keys.c -o "$work/pty"
export LC_ALL=C.UTF-8
export ASAN_OPTIONS=${ASAN_OPTIONS:-detect_leaks=1:abort_on_error=1}
export UBSAN_OPTIONS=${UBSAN_OPTIONS:-print_stacktrace=1}

# what the sanitizers said, if anything
sanitizer_report() {
	sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' "$1" | grep -a 'ERROR: \(Address\|Leak\)Sanitizer\|runtime error:\|Direct leak\|Indirect leak\|SUMMARY: \|^ *#[0-9]' | head -40 || true
}
keep() { cp "$1" "$root/endurance-meters.txt" 2>/dev/null || true; sanitizer_report "$2"; }

# the scenarios of tests/endurance.scm, compiled into the editor once
# (some three minutes), kept in build/endurance-home
template="$root/build/endurance-home"
compile_scenarios() {
	if [ ! -s "$template/.chezemax/chezemax.cwasm" ] || [ chezemax.wasm -nt "$template/.chezemax/chezemax.wasm" ] ||
	   [ tests/endurance.scm -nt "$template/.chezemax/chezemax.wasm" ]; then
		echo "Compiling the scenarios into the editor (a few minutes, once)"
		rm -rf "$template"; mkdir -p "$template/.chezemax/users"
		cp tests/endurance.scm "$template/.chezemax/users/endurance.scm"
		HOME="$template" ./chezemax --compile-scripts > "$work/compile.txt" 2>&1 || { cat "$work/compile.txt"; exit 1; }
	fi
}

# ------------------------------------------------------------------ churn
churn() {
	compile_scenarios
	dir="$work/churn"
	mkdir -p "$dir/home/.chezemax" "$dir/files"
	cp "$template/.chezemax/chezemax.wasm" "$template/.chezemax/chezemax.cwasm" "$dir/home/.chezemax/"
	# the files: each name used once, as in a long session
	awk -v n="$cycles" -v dir="$dir/files" 'BEGIN {
		for (i = 0; i < n; i++) {
			k = i % 5
			if (k == 0) { f = dir "/f-" i ".md"; printf "# Notes %d\n\nSome *text* with `code` and a [link](x).\n\n- an item\n- αβγ 가나다 中文 🙂\n", i > f }
			else if (k == 1) { f = dir "/f-" i ".org"; printf "* Heading %d\nText under it.\n** Sub\nMore text, é.\n* Next\nEnd.\n", i > f }
			else if (k == 2) { f = dir "/f-" i ".scm"; printf "(define (f%d x)\n  ;; a comment\n  (if (> x 0) \"pos\" #\\\\n))\n", i > f }
			else if (k == 3) { f = dir "/f-" i ".txt"; printf "Plain text %d.\nA second line.\n", i > f }
			else { f = dir "/big-" i ".txt"; for (j = 0; j < 800; j++) printf "line %d of a file in shards, %d\n", j, i > f }
			close(f)
		}
	}'
	meters="$dir/meters.txt"
	cat > "$dir/keys" <<KEYS
await-screen [SAVE]
keys ^C6
await-screen (ENDURANCE DONE $cycles)
wait 300
keys ^G^X^C
wait 300
keys y
KEYS
	start=$(date +%s) status=0
	HOME="$dir/home" CHEZWEB_METERS="$meters" ENDURANCE_DIR="$dir/files" ENDURANCE_CYCLES="$cycles" \
	ENDURANCE_EVERY=$((cycles / 20 > 0 ? cycles / 20 : 1)) ENDURANCE_SHELLS=25 \
		"$work/pty" "$dir/keys" $((120 + cycles / 5)) "$dir/screen" "$root/$editor" "$dir/files/f-0.md" > "$dir/pty.txt" 2>&1 || status=$?
	seconds=$(( $(date +%s) - start ))
	if [ "$status" -ne 0 ] || ! grep -q "^churn $cycles " "$meters" 2>/dev/null; then
		echo "FAIL churn: the session did not finish (status $status)"; keep "$meters" "$dir/screen"; exit 1
	fi
	if sanitizer_report "$dir/screen" | grep -q .; then
		echo "FAIL churn: the sanitizers reported"; keep "$meters" "$dir/screen"; exit 1
	fi
	# "churn CYCLE LEAKS T1..T8 HEAP RSS FDS BUFFERS WINDOWS"; the warm-up
	# is the first quarter, the slope is taken over the rest
	awk -v cycles="$cycles" -v sanitized="$sanitized" -v seconds="$seconds" '
	$1 == "churn" { n++; c[n] = $2; leak += $3; for (k = 1; k <= 8; k++) t[n, k] = $(3 + k)
		heap[n] = $12; rss[n] = $13; fds[n] = $14; bufs[n] = $15 }
	END {
		w = 1; while (w < n && c[w] < cycles / 4) w++
		dc = c[n] - c[w]; if (dc <= 0) dc = 1
		hs = (heap[n] - heap[w]) / dc; rs = (rss[n] - rss[w]) / dc
		split("undo-histories buffer-faces buffer-menus buffer-hints vim-states vim-kinds language-overrides word-wrap-overrides", names, " ")
		printf "churn: %d cycles in %d s; after cycle %d: C heap %+.1f bytes a cycle (%d -> %d), RSS %+.0f bytes a cycle (%.1f -> %.1f MB), descriptors %d -> %d, buffers %d -> %d\n", cycles, seconds, c[w], hs, heap[w], heap[n], rs, rss[w] / 1048576, rss[n] / 1048576, fds[w], fds[n], bufs[w], bufs[n]
		bad = 0
		if (hs > 64) { print "  the C heap grows with the buffers killed"; bad = 1 }
		# under AddressSanitizer RSS holds the quarantine of freed memory
		# and its shadow: it is a bound only in the ordinary build
		if (rs > 4096 && sanitized != "yes") { print "  RSS grows by more than 4 KB a cycle"; bad = 1 }
		if (fds[n] > fds[w]) { print "  descriptors are left open"; bad = 1 }
		if (bufs[n] > bufs[w]) { print "  buffers are left alive"; bad = 1 }
		for (k = 1; k <= 8; k++) if (t[n, k] > t[w, k] + 2) { printf "  the Scheme table *%s* grows: %d -> %d entries\n", names[k], t[w, k], t[n, k]; bad = 1 }
		if (leak > 0) { print "  LeakSanitizer found memory that nothing reaches"; bad = 1 }
		exit bad
	}' "$meters" || { echo "FAIL churn"; keep "$meters" "$dir/screen"; exit 1; }
	echo "PASS churn: $cycles buffers opened and killed in one session; the heap, descriptors, buffers and Scheme tables do not grow with them$( [ "$sanitized" = yes ] && echo ', and LeakSanitizer finds nothing unreachable')"
}

# ------------------------------------------------------------------ flood
flood() {
	dir="$work/flood"
	mkdir -p "$dir/home"
	meters="$dir/meters.txt"
	printf 'A file to come back to.\n' > "$dir/note.txt"
	# the markers are printed by $((...)): the typed command does not contain them
	# one round: a terminal flooded, resized, left and taken back, then killed;
	# three rounds, so that what stays after the first ones is told from a leak
	round() {   # N
		a=$(( $1 * 2 - 1 )) b=$(( $1 * 2 ))
		cat <<KEYS
keys \\exterm\\r
await-screen READY\$
keys yes | head -n 3000000; echo FL-\$((0+$a))-OK\\r
wait 1000
keys ^Cb
wait 400
keys \\r
wait 1500
keys \\exterm\\r
await-screen FL-$a-OK
keys head -c 20000000 /dev/urandom | base64; echo FL-\$((0+$b))-OK\\r
wait 700
resize 20 60
wait 700
resize 45 150
wait 700
resize 30 100
await-screen FL-$b-OK
keys exec head -c 4000000 /dev/urandom\\r
await-screen [Process exited
wait 500
keys ^G^Xk
wait 800
keys \\e:(fe-meter-note "killed-$1")\\r
await-file $dir/checked-$1
KEYS
	}
	{ echo 'await-screen [SAVE]'; round 1; round 2; round 3; printf 'keys ^G^X^C\nwait 300\nkeys y\n'; } > "$dir/keys"
	# the sanitized editor reads the floods some three times more slowly
	limit=300; [ "$sanitized" = no ] || limit=900
	status=0
	HOME="$dir/home" CHEZEMAX_NO_INIT=1 CHEZWEB_METERS="$meters" CHEZWEB_METERS_MS=250 SHELL=/bin/sh PS1='READY$ ' ENV= \
		"$work/pty" "$dir/keys" "$limit" "$dir/screen" "$root/$editor" "$dir/note.txt" > "$dir/pty.txt" 2>&1 &
	runner=$!
	# after each kill, from outside: the editor's children
	children=
	for r in 1 2 3; do
		k=0
		while ! grep -q "^killed-$r " "$meters" 2>/dev/null; do
			sleep 1; k=$((k + 1))
			if [ $k -gt "$limit" ] || ! kill -0 "$runner" 2>/dev/null; then break; fi
		done
		grep -q "^killed-$r " "$meters" 2>/dev/null || break
		pid=$(awk '$1 == "tick" { p = $4 } END { print p }' "$meters")
		sleep 1
		children="$children $(pgrep -P "$pid" 2>/dev/null | wc -l | tr -d ' ')"
		echo checked > "$dir/checked-$r"
	done
	wait "$runner" || status=$?
	if [ "$status" -ne 0 ] || [ "$(echo $children | wc -w)" -ne 3 ]; then
		echo "FAIL flood: the session did not finish (status $status)"; keep "$meters" "$dir/screen"; exit 1
	fi
	if sanitizer_report "$dir/screen" | grep -q .; then
		echo "FAIL flood: the sanitizers reported"; keep "$meters" "$dir/screen"; exit 1
	fi
	# "tick MS TERM-BYTES PID HEAP RSS FDS BUFFERS WINDOWS", and
	# "killed-R HEAP RSS FDS BUFFERS WINDOWS" after round R
	awk -v children="$children" '
	$1 == "tick" { n++; ms[n] = $2; bytes[n] = $3; if (n == 1) { base_heap = $5; base_fds = $7 } if ($5 > peak) peak = $5 }
	$1 == "killed-1" { k1 = $2; f1 = $4 }
	$1 == "killed-2" { k2 = $2; f2 = $4 }
	$1 == "killed-3" { k3 = $2; f3 = $4 }
	END {
		# the rate of each interval in which the shells wrote
		for (i = 2; i <= n; i++) if (bytes[i] > bytes[i - 1] && ms[i] > ms[i - 1]) { r++; rate[r] = (bytes[i] - bytes[i - 1]) / (ms[i] - ms[i - 1]) }
		third = int(r / 3); if (third < 1) third = 1
		for (i = 1; i <= third; i++) first += rate[i]
		for (i = r - third + 1; i <= r; i++) last += rate[i]
		first /= third; last /= third
		split(children, left, " ")
		printf "flood: %.1f MB from the shells in %.1f s, %.1f MB/s in the first third, %.1f in the last; C heap %.1f MB before, %.1f at the peak, %.1f after the first kill, %.1f after the second, %.1f after the third; descriptors %d, %d, %d, %d; children left: %d, %d, %d\n", bytes[n] / 1048576, ms[n] / 1000, first / 1048.576, last / 1048.576, base_heap / 1048576, peak / 1048576, k1 / 1048576, k2 / 1048576, k3 / 1048576, base_fds, f1, f2, f3, left[1], left[2], left[3]
		bad = 0
		if (bytes[n] < 90000000) { print "  the shells wrote less than expected: the floods did not run"; bad = 1 }
		if (peak - base_heap > 64 * 1048576) { print "  the C heap grew by more than 64 MB during a flood (the terminal keeps 10000 lines)"; bad = 1 }
		# what the first rounds leave may be kept for good (caches, the
		# buffer of the bridge); the third must add nothing
		if (k3 - k2 > 262144) { print "  the C heap grows with each terminal flooded and killed"; bad = 1 }
		if (f1 > base_fds || f2 > base_fds || f3 > base_fds) { print "  descriptors are left open after a kill"; bad = 1 }
		if (left[1] > 0 || left[2] > 0 || left[3] > 0) { print "  a shell or one of its children is left"; bad = 1 }
		if (last < first / 4) { print "  the terminal got more than four times slower during the floods"; bad = 1 }
		exit bad
	}' "$meters" || { echo "FAIL flood"; keep "$meters" "$dir/screen"; exit 1; }
	echo "PASS flood: M-x term took yes, base64 and raw random bytes, resized and switched away, then was killed: memory bounded and given back, no descriptor or process left$( [ "$sanitized" = yes ] && echo ', nothing for the sanitizers')"
}

# ------------------------------------------------------------------ undo
undo_eviction() {
	compile_scenarios
	dir="$work/undo"
	mkdir -p "$dir/home/.chezemax"
	cp "$template/.chezemax/chezemax.wasm" "$template/.chezemax/chezemax.cwasm" "$dir/home/.chezemax/"
	printf 'Undo eviction.\n' > "$dir/u.txt"
	meters="$dir/meters.txt"
	rounds=$undo_cycles
	cat > "$dir/keys" <<KEYS
await-screen [SAVE]
keys ^C5
await-screen (ENDURANCE UNDO DONE $rounds)
wait 300
keys ^G^X^C
wait 300
keys y
KEYS
	limit=600; [ "$sanitized" = no ] || limit=1800
	start=$(date +%s) status=0
	HOME="$dir/home" CHEZWEB_METERS="$meters" ENDURANCE_UNDO_CYCLES="$rounds" \
		"$work/pty" "$dir/keys" "$limit" "$dir/screen" "$root/$editor" "$dir/u.txt" > "$dir/pty.txt" 2>&1 || status=$?
	seconds=$(( $(date +%s) - start ))
	if [ "$status" -ne 0 ] || ! grep -q "^undo $rounds " "$meters" 2>/dev/null; then
		echo "FAIL undo: the session did not finish (status $status)"; keep "$meters" "$dir/screen"; exit 1
	fi
	if sanitizer_report "$dir/screen" | grep -q .; then
		echo "FAIL undo: the sanitizers reported"; keep "$meters" "$dir/screen"; exit 1
	fi
	# "undo CYCLE HISTORY-BYTES GROUPS LIMIT HEAP RSS FDS BUFFERS WINDOWS"
	awk -v sanitized="$sanitized" -v seconds="$seconds" '
	$1 == "undo" { n++; c[n] = $2; hb[n] = $3; g[n] = $4; lim = $5; heap[n] = $6; rss[n] = $7
		if ($3 > maxhb) maxhb = $3; if ($4 > maxg) maxg = $4; if ($7 > peak) peak = $7 }
	END {
		# the first 20 MB chunks raise the high-water marks; the slope is
		# taken over the second half
		w = int(n / 2) + 1; dc = c[n] - c[w]; if (dc <= 0) dc = 1
		hs = (heap[n] - heap[w]) / dc; rs = (rss[n] - rss[w]) / dc
		printf "undo: %d cycles in %d s (1 to 3 MB a cycle, 20 MB every tenth); history at most %.1f MB in %d groups (limit %.1f MB); after cycle %d: C heap %+.0f bytes a cycle (%.1f -> %.1f MB), RSS %+.0f bytes a cycle (%.1f -> %.1f MB, peak %.1f)\n", n, seconds, maxhb / 1048576, maxg, lim / 1048576, c[w], hs, heap[w] / 1048576, heap[n] / 1048576, rs, rss[w] / 1048576, rss[n] / 1048576, peak / 1048576
		if (n >= 10) printf "  the first 20 MB chunk (cycle 10) raised RSS by %.0f MB and the C heap by %.0f MB: high-water marks, kept\n", (rss[10] - rss[9]) / 1048576, (heap[10] - heap[9]) / 1048576
		bad = 0
		if (maxhb > lim) { print "  the history held more than *undo-limit*"; bad = 1 }
		if (maxg > 200) { print "  the history held more than 200 groups"; bad = 1 }
		if (hs > 65536) { print "  the C heap grows with the chunks undo dropped"; bad = 1 }
		# the chunks are megabytes: a dropped chunk kept would grow RSS by as much
		if (rs > 262144 && sanitized != "yes") { print "  RSS grows with the chunks undo dropped: they are not freed"; bad = 1 }
		exit bad
	}' "$meters" || { echo "FAIL undo"; keep "$meters" "$dir/screen"; exit 1; }
	echo "PASS undo: $rounds cycles of megabytes through undo: the history stays under *undo-limit*, and what it drops is freed$( [ "$sanitized" = yes ] && echo ', nothing for the sanitizers')"
}

# ------------------------------------------------------------------ big
# A cut of 21 MB, and its yank: undo cannot keep either (8 MB), and the
# kill ring keeps nothing over 1 MB.  The editor once copied both into the
# compiled program all the same (four bytes a character there), only to
# drop them: C-w of 21 MB raised RSS by 231 MB for good.  Now neither is
# sent (src/undo.c 'o', core.scm remember-kill): memory may rise by the
# copy C keeps for C-y and little more.
#
# The system clipboard is a stand-in (pbcopy, pbpaste and xclip on PATH,
# keeping the text in a file), so the test takes the clipboard's path on
# every system, and never touches the user's own clipboard.  On macOS the
# real pbcopy once made this test fail: C-w put the 21 MB on the clipboard,
# and C-y read them back (pbpaste) into C and into the compiled program, as
# if another program had copied them.  Now C compares what the clipboard
# holds with what C-y inserts as it reads, and copies nothing when they are
# the same (src/term.c, screen_get_clipboard_unless).  A second session
# pastes 21 MB that another program copied: they go from the clipboard to
# what C-y inserts without passing through the compiled program
# (core.scm adopt-system-clipboard).  No compiled scenario: some seconds.
fake_clipboard() {
	mkdir -p "$1"
	printf '#!/bin/sh\ncat > "%s/clipboard.txt"\n' "$1" > "$1/pbcopy"
	printf '#!/bin/sh\ncat "%s/clipboard.txt" 2>/dev/null\n' "$1" > "$1/pbpaste"
	printf '#!/bin/sh\ncase "$*" in *-in*) exec cat > "%s/clipboard.txt" ;; esac\ncat "%s/clipboard.txt" 2>/dev/null\n' "$1" "$1" > "$1/xclip"
	chmod +x "$1/pbcopy" "$1/pbpaste" "$1/xclip"
}

# the meters of one session: base, peak, and the verdict against the limits
big_verdict() {
	awk -v size="$2" -v sanitized="$sanitized" -v what="$3" -v heap="$4" -v rss="$5" '
	$1 == "tick" { n++; if (n == 1) { h0 = $5; r0 = $6 } if ($5 > hp) hp = $5; if ($6 > rp) rp = $6 }
	END {
		printf "big: %s of %.1f MB: C heap %.1f -> %.1f MB at the peak, RSS %.1f -> %.1f MB\n", what, size / 1048576, h0 / 1048576, hp / 1048576, r0 / 1048576, rp / 1048576
		bad = 0
		if (h0 < 0) printf "  SKIP C heap bound: allocator meter unavailable on this platform\n"; else if (hp - h0 > heap * size) { printf "  the C heap rose by more than %s copies of the text\n", heap; bad = 1 }
		if (r0 < 0) printf "  SKIP RSS bound: resident-memory meter unavailable on this platform\n"; else if (rp - r0 > rss * size && sanitized != "yes") { printf "  RSS rose by more than %s copies: the text was copied into the compiled program\n", rss; bad = 1 }
		exit bad
	}' "$1"
}

big_edit() {
	dir="$work/big"
	mkdir -p "$dir/home"
	fake_clipboard "$dir/clip"
	meters="$dir/meters.txt"
	awk 'BEGIN { for (i = 0; i < 400000; i++) printf "line %06d of a twenty megabyte text, ascii only.....\n", i }' > "$dir/big.txt"
	size=$(wc -c < "$dir/big.txt" | tr -d ' ')
	cat > "$dir/keys" <<'KEYS'
await-screen [SAVE]
wait 1500
keys ^Xh
wait 500
keys ^W
wait 2500
keys ^Y
wait 2500
keys ^_
wait 1000
keys ^X^W
wait 300
keys ^A^K
KEYS
	# the text after C-w, C-y and C-/ (nothing to undo: both were larger
	# than undo keeps), written to a new file: it must be the same
	printf 'keys %s\\r\nwait 3000\nkeys ^G^X^C\nwait 300\nkeys y\n' "$dir/after.txt" >> "$dir/keys"
	status=0
	( unset WAYLAND_DISPLAY; PATH="$dir/clip:$PATH" DISPLAY="${DISPLAY:-:0}" \
	  HOME="$dir/home" CHEZEMAX_NO_INIT=1 CHEZWEB_METERS="$meters" CHEZWEB_METERS_MS=250 \
		"$work/pty" "$dir/keys" 300 "$dir/screen" "$root/$editor" "$dir/big.txt" ) > "$dir/pty.txt" 2>&1 || status=$?
	if [ "$status" -ne 0 ] || [ ! -s "$dir/after.txt" ]; then
		echo "FAIL big: the session did not finish (status $status)"; cat "$dir/pty.txt"; tail -c 4096 "$dir/screen"; keep "$meters" "$dir/screen"; exit 1
	fi
	cmp -s "$dir/big.txt" "$dir/after.txt" || { echo "FAIL big: after C-w and C-y the text is not the same"; exit 1; }
	cmp -s "$dir/big.txt" "$dir/clip/clipboard.txt" || { echo "FAIL big: C-w did not put the text on the system clipboard"; exit 1; }
	# C keeps one copy for C-y (the scrap); the text itself is already counted
	big_verdict "$meters" "$size" "C-w and C-y" 1.5 2.5 || { echo "FAIL big"; keep "$meters" "$dir/screen"; exit 1; }

	# another program copied 21 MB; C-y in an empty buffer, then save
	awk 'BEGIN { for (i = 0; i < 400000; i++) printf "row %06d that another program copied, ascii too....\n", i }' > "$dir/clip/clipboard.txt"
	cp "$dir/clip/clipboard.txt" "$dir/other.txt"
	osize=$(wc -c < "$dir/other.txt" | tr -d ' ')
	meters2="$dir/meters-paste.txt"
	cat > "$dir/keys2" <<'KEYS'
await-screen [SAVE]
wait 1500
keys ^Y
wait 3500
keys ^X^W
wait 300
keys ^A^K
KEYS
	printf 'keys %s\\r\nwait 3000\nkeys ^G^X^C\nwait 300\nkeys y\n' "$dir/pasted.txt" >> "$dir/keys2"
	: > "$dir/empty.txt"
	status=0
	( unset WAYLAND_DISPLAY; PATH="$dir/clip:$PATH" DISPLAY="${DISPLAY:-:0}" \
	  HOME="$dir/home" CHEZEMAX_NO_INIT=1 CHEZWEB_METERS="$meters2" CHEZWEB_METERS_MS=250 \
		"$work/pty" "$dir/keys2" 300 "$dir/screen2" "$root/$editor" "$dir/empty.txt" ) > "$dir/pty2.txt" 2>&1 || status=$?
	if [ "$status" -ne 0 ] || [ ! -s "$dir/pasted.txt" ]; then
		echo "FAIL big: the paste session did not finish (status $status)"; cat "$dir/pty2.txt"; tail -c 4096 "$dir/screen2"; keep "$meters2" "$dir/screen2"; exit 1
	fi
	cmp -s "$dir/other.txt" "$dir/pasted.txt" || { echo "FAIL big: C-y did not insert what the other program copied"; exit 1; }
	# the buffer's text and the scrap: two copies, and the gap
	big_verdict "$meters2" "$osize" "C-y of what another program copied" 2.5 3.5 || { echo "FAIL big"; keep "$meters2" "$dir/screen2"; exit 1; }
	# and a few words another program copied: C-y adopts them as before (on
	# the kill ring too), and a second C-y, the clipboard now the same as
	# what C-y inserts, inserts them again
	printf 'a few words from another program' > "$dir/clip/clipboard.txt"
	cat > "$dir/keys3" <<'KEYS'
await-screen [SAVE]
wait 1000
keys ^Y^Y
wait 500
keys ^X^W
wait 300
keys ^A^K
KEYS
	printf 'keys %s\\r\nwait 1500\nkeys ^G^X^C\nwait 300\nkeys y\n' "$dir/small.txt" >> "$dir/keys3"
	status=0
	( unset WAYLAND_DISPLAY; PATH="$dir/clip:$PATH" DISPLAY="${DISPLAY:-:0}" \
	  HOME="$dir/home" CHEZEMAX_NO_INIT=1 \
		"$work/pty" "$dir/keys3" 120 "$dir/screen3" "$root/$editor" "$dir/empty.txt" ) > "$dir/pty3.txt" 2>&1 || status=$?
	[ "$(cat "$dir/small.txt" 2>/dev/null)" = "a few words from another programa few words from another program" ] ||
		{ echo "FAIL big: C-y did not insert the few words another program copied (status $status)"; exit 1; }
	echo "PASS big: a cut and a yank of 21 MB, and a paste of 21 MB another program copied, cost the copies C keeps, not the compiled program's four bytes a character"
}

case $which in
churn) churn ;;
flood) flood ;;
undo) undo_eviction ;;
big) big_edit ;;
all) churn; flood; undo_eviction; big_edit ;;
*) echo "unknown scenario: $which"; exit 2 ;;
esac
