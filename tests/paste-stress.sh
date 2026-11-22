#!/bin/sh
# paste-stress.sh -- huge and malformed pastes (22 November 2026; Eduardo's
# fourth test, second half).  Text that is not text -- NUL bytes, UTF-16
# surrogates written as UTF-8 (ED A0 80, never valid), bytes no UTF-8 has
# (FF FE), an overlong NUL (C0 80), a lone continuation byte (80), a
# character cut short (E2 82) -- comes in through the terminal's bracketed
# paste (command.c, paste_bracketed) and through the system clipboard and
# C-y (interface.c, core.scm adopt-system-clipboard).  The editor must not
# hang, must not stop at a NUL, and must keep every byte: each file written
# after is compared, byte for byte, with what went in.  Each key within
# PASTE_LIMIT_MS (2000), as the backdoor's time measures it.
#
#   1  a paste of 15 MB of such text: inserted whole
#   2  a paste of 50 MB: over the limit of a paste (16 MB), refused whole,
#      said so, and the keys after it work
#   3  a paste and the keys after it in one write: the keys are not lost
#   4  50 MB of such text copied by another program, then C-y
#   5  a few bytes with a NUL, copied by another program, then C-y
#   6  C-w of a text with NUL bytes (the clipboard keeps it cut at the
#      first NUL), C-y gives the whole of it back; then another program
#      copies, and C-y takes that in
#
#   sh tests/paste-stress.sh [quick]    quick: 3, 5 and 6 only (make check)
#
# The system clipboard is a stand-in (pbcopy, pbpaste, xclip on PATH); the
# user's own is never touched.  Disposable files and PTY.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
limit=${PASTE_LIMIT_MS:-2000}
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-paste-stress.XXXXXX")
if [ "${PASTE_KEEP:-}" = 1 ]; then echo "work folder: $work"; else trap 'rm -rf "$work"' EXIT HUP INT TERM; fi
cc=${CC:-cc}
$cc -O2 tests/pty-keys.c -o "$work/pty" -lutil 2>/dev/null ||
	$cc -O2 tests/pty-keys.c -o "$work/pty"
mkdir -p "$work/home/.chezemax" "$work/clip"
printf 'time\nrepeats keep\nwatch none\nlines 5000\n' > "$work/home/.chezemax/backdoor-claude.conf"
failed=0

# the stand-in clipboard: pbcopy writes what it is given to clipboard.txt
# (the editor gives it a C string: up to the first NUL); pbpaste counts its
# calls, and on call N first copies foreign.N there, if there is one
# (another program copying)
clip="$work/clip"
cat > "$clip/pbcopy" <<EOF
#!/bin/sh
cat > "$clip/clipboard.txt"
EOF
cat > "$clip/pbpaste" <<EOF
#!/bin/sh
n=\$(cat "$clip/count" 2>/dev/null || echo 0); n=\$((n + 1)); echo \$n > "$clip/count"
[ -f "$clip/foreign.\$n" ] && cp "$clip/foreign.\$n" "$clip/clipboard.txt"
cat "$clip/clipboard.txt" 2>/dev/null
EOF
cat > "$clip/xclip" <<EOF
#!/bin/sh
case "\$*" in *-in*) exec "$clip/pbcopy" ;; esac
exec "$clip/pbpaste"
EOF
chmod +x "$clip/pbcopy" "$clip/pbpaste" "$clip/xclip"

# a block of malformed text (68 bytes), doubled to TOTAL bytes in FILE
malformed() {
	printf 'abc\000def \355\240\200 \355\260\200 \377\376 \300\200 \200 \303\247\303\243o \342\202\n' > "$1"
	while [ "$(wc -c < "$1" | tr -d ' ')" -lt "$2" ]; do cat "$1" "$1" > "$1.2"; mv "$1.2" "$1"; done
	head -c "$2" "$1" > "$1.2"; mv "$1.2" "$1"
}

# session NAME FILE TIMEOUT: the keys of NAME.keys between the backdoor's
# opening and closing; the record is NAME.log
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
	rm -f "$work/home/.chezemax/backdoor.txt" "$clip/count"
	status=0
	(cd "$work"; unset WAYLAND_DISPLAY; PATH="$clip:$PATH" DISPLAY="${DISPLAY:-:0}" \
		HOME="$work/home" CHEZEMAX_NO_INIT=1 LC_ALL=C.UTF-8 \
		"$work/pty" "$work/$name.script" "$timeout" "$work/$name.screen" "$root/chezemax" "$file") \
		> "$work/$name.pty" 2>&1 || status=$?
	cp "$work/home/.chezemax/backdoor.txt" "$work/$name.log" 2>/dev/null || : > "$work/$name.log"
	if [ "$status" -ne 0 ]; then
		echo "FAIL $name: the session did not finish in $timeout s (status $status): the editor hangs"
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

same() {   # same NAME WHAT EXPECTED GOT
	if cmp -s "$3" "$4"; then :; else
		echo "FAIL $1: $2 ($(wc -c < "$3" | tr -d ' ') bytes expected, $(wc -c < "$4" 2>/dev/null | tr -d ' ') written)"
		cmp "$3" "$4" 2>&1 | head -1
		failed=1
	fi
}

save_as() { printf 'paste ^X^W^A^K%s\\r\nwait 1500\n' "$1"; }

quick=${1:-}
# ------------------------------------------------------------ 1
if [ "$quick" != quick ]; then
malformed "$work/m15" 15000000
{ printf '\033[200~'; cat "$work/m15"; printf '\033[201~'; } > "$work/paste15"
: > "$work/empty1.txt"
{ printf 'send-file %s\nwait 1500\n' "$work/paste15"; save_as "$work/out1.txt"; } > "$work/paste-15mb.keys"
if session paste-15mb empty1.txt 300; then
	key_times paste-15mb "a bracketed paste of 15 MB with NUL bytes, surrogates and bytes that are not UTF-8"
	same paste-15mb "the paste is not in the buffer byte for byte" "$work/m15" "$work/out1.txt"
fi

# ------------------------------------------------------------ 2
malformed "$work/m50" 50000000
{ printf '\033[200~'; cat "$work/m50"; printf '\033[201~'; } > "$work/paste50"
printf 'before\n' > "$work/two.txt"
{ printf 'keys \\e>\n'; printf 'send-file %s\nwait 1500\n' "$work/paste50"; printf 'keys after\nwait 300\n'; save_as "$work/out2.txt"; } > "$work/paste-50mb.keys"
if session paste-50mb two.txt 300; then
	key_times paste-50mb "a bracketed paste of 50 MB, refused"
	printf 'before\nafter' > "$work/want2.txt"
	same paste-50mb "the refused paste changed the text, or the keys after it were lost" "$work/want2.txt" "$work/out2.txt"
	grep -aq 'Paste exceeds' "$work/paste-50mb.screen" || { echo "FAIL paste-50mb: no word that the paste was refused"; failed=1; }
fi

fi
# ------------------------------------------------------------ 3
printf 'x\000y \355\240\200 ok' > "$work/small"
{ printf '\033[200~'; cat "$work/small"; printf '\033[201~'; printf 'typed\033<'; printf 'first '; } > "$work/paste3"
: > "$work/empty3.txt"
{ printf 'send-file %s\nwait 1000\n' "$work/paste3"; save_as "$work/out3.txt"; } > "$work/paste-then-keys.keys"
if session paste-then-keys empty3.txt 120; then
	key_times paste-then-keys "a paste and the keys after it, in one write"
	{ printf 'first '; cat "$work/small"; printf 'typed'; } > "$work/want3.txt"
	same paste-then-keys "the keys after the paste were lost or changed" "$work/want3.txt" "$work/out3.txt"
fi

# ------------------------------------------------------------ 4
if [ "$quick" != quick ]; then
cp "$work/m50" "$clip/clipboard.txt"
: > "$work/empty4.txt"
{ printf 'keys ^Y\nwait 3000\n'; save_as "$work/out4.txt"; } > "$work/clipboard-50mb.keys"
if session clipboard-50mb empty4.txt 300; then
	key_times clipboard-50mb "C-y of 50 MB of malformed text another program copied"
	same clipboard-50mb "C-y did not insert the clipboard's bytes, all of them" "$work/m50" "$work/out4.txt"
fi

fi
# ------------------------------------------------------------ 5
cp "$work/small" "$clip/clipboard.txt"
: > "$work/empty5.txt"
{ printf 'keys ^Y\nwait 500\n'; save_as "$work/out5.txt"; } > "$work/clipboard-nul.keys"
if session clipboard-nul empty5.txt 120; then
	key_times clipboard-nul "C-y of a few bytes with a NUL another program copied"
	same clipboard-nul "C-y stopped at the NUL, or changed a byte" "$work/small" "$work/out5.txt"
fi

# ------------------------------------------------------------ 6
cp "$work/small" "$work/kill.txt"
printf 'from another program' > "$clip/foreign.2"
rm -f "$clip/clipboard.txt"
{ printf 'keys ^Xh\nwait 300\nkeys ^W\nwait 500\nkeys ^Y\nwait 500\nkeys ^Y\nwait 500\n'; save_as "$work/out6.txt"; } > "$work/kill-nul.keys"
if session kill-nul kill.txt 120; then
	key_times kill-nul "C-w of a text with NUL bytes, C-y, then another program's copy and C-y"
	{ cat "$work/small"; printf 'from another program'; } > "$work/want6.txt"
	same kill-nul "C-y gave the clipboard's cut image instead of the kill, or missed the other program's copy" "$work/want6.txt" "$work/out6.txt"
fi
rm -f "$clip/foreign.2"

exit $failed
