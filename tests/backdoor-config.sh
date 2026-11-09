#!/bin/sh
# The configurable backdoor (src/backdoor.c).  Without a configuration it
# leaves bare mouse motion out, collapses repeated keys, and says who moved
# the page.  ~/.chezemax/backdoor-claude.conf sets the lines kept, all the
# mouse, the watches, the inserted text, times and allocation, and an
# option it does not understand is reported.  Closed, nothing more is
# written.  Disposable home, file and PTY.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-backdoor-config.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
cc=${CC:-cc}
$cc -O2 tests/pty-keys.c -o "$work/pty" -lutil 2>/dev/null ||
 $cc -O2 tests/pty-keys.c -o "$work/pty"
mkdir -p "$work/home/.chezemax"
awk 'BEGIN { for (i = 1; i <= 80; i++) print "linha " i }' > "$work/text.txt"
log="$work/home/.chezemax/backdoor.txt"
fail() { echo "FAIL $1"; tail -c 2500 "$log" 2>/dev/null; exit 1; }
run() { (cd "$work"; HOME="$work/home" CHEZEMAX_NO_INIT=1 LC_ALL=C.UTF-8 "$work/pty" "$1" 60 "$work/screen" "$root/chezemax" text.txt) }

# 1. no configuration: the defaults
cat > "$work/keys" <<'KEYS'
await-screen [SAVE]
keys \exbackdoor-claude\r
wait 300
keys \e[<35;10;5M\e[<35;11;5M\e[<35;12;5M\e[<35;13;5M\e[<35;14;5M
wait 300
keys ^E^E^E^E^E
wait 300
keys ^V
wait 300
keys \exbackdoor-claude\r
wait 300
keys ^N^N^N
wait 1500
keys ^X^C
KEYS
run "$work/keys"
[ -s "$log" ] || fail 'no ~/.chezemax/backdoor.txt'
grep -q '^options (no backdoor.conf: the defaults): mouse clicks, repeats collapse, watch page, text 0, time off, alloc off$' "$log" ||
 fail 'the defaults are not said'
grep -q '^front end terminal, screen [0-9]* rows x [0-9]* columns, window [0-9]* rows from row 0, buffer text.txt (text.txt)$' "$log" ||
 fail 'the front end and the window are not said'
! grep -q 'mouse move' "$log" || fail 'bare mouse motion was recorded by default'
grep -q '^#[0-9]*\.\.[0-9]* C-e .* (5 times)$' "$log" || fail 'five identical C-e were not collapsed'
grep -q '^  page 0 -> [0-9]* by the command (forward-page)$' "$log" || fail 'C-v moved the page and the command was not named'
[ "$(tail -n 1 "$log")" = 'backdoor closed' ] || fail 'keys after closing were recorded'
echo 'PASS the default backdoor: no bare motion, repeats collapsed, the page change and its command named'

# 2. a configuration written by the assistant
cat > "$work/home/.chezemax/backdoor-claude.conf" <<'CONF'
# for a diagnosis of the cursor
lines 400
mouse all
watch page point mark
text 20
time
alloc
colour red
CONF
cat > "$work/keys" <<'KEYS'
await-screen [SAVE]
keys \exbackdoor-claude\r
wait 300
keys \e[<35;10;5M\e[<35;10;5M\e[<35;10;5M
wait 300
keys \e[<0;5;3M
wait 100
keys \e[<0;5;3m
wait 300
keys \e<^N^N^N^N^A^K^K
wait 300
keys ^Y
wait 300
keys \e<
wait 200
keys ^N^N^N^N^N^N^N^N^N^N^N^N^N^N^N^N^N^N^N^N^N^N^N^N^N^N^N^N^N^N
wait 300
keys \e:(goto-char 30)\r
wait 300
keys \exbackdoor-claude\r
wait 1500
keys ^X^C
KEYS
rm -f "$log"
run "$work/keys" || true      # the buffer was changed: C-x C-c asks, the run times out
grep -q '^options (backdoor-claude.conf): mouse all, repeats collapse, watch page point mark, text 20, time on, alloc on$' "$log" ||
 fail 'the configuration was not read'
grep -q '^not understood in backdoor-claude.conf: line 8: "colour" not understood;$' "$log" || fail 'the unknown option was not reported'
grep -q '^#[0-9.]* mouse move at 4,9 .* | [a-z ]*[0-9.]* ms: command [0-9.]*, display [0-9.]* | faults [0-9]*$' "$log" || fail 'mouse all: the motion was not recorded'
grep -q '^#[0-9]* mouse press 1 at 2,4 ' "$log" && grep -q '^#[0-9]* mouse release at 2,4 ' "$log" || fail 'the click was not named'
grep -q '^  text +8 at [0-9]* "linha 5\\n"$' "$log" || fail 'the yanked text was not shown, escaped'
grep -q '^  point [0-9]* -> [0-9]* by the command (next-line)$' "$log" || fail 'watch point: C-n'
grep -q '^  mark [0-9-]* -> [0-9]* by the command' "$log" || fail 'watch mark: the click or C-y set no mark'
grep -q "^  display text.txt: page 0 -> [0-9]*, point [0-9]* at or past the page's end [0-9]* (as last drawn): point on the last row$" "$log" &&
 grep -q '^  page 0 -> [0-9]* by the C core during the display, before a script called [a-z-]* ([0-9]* changes)$' "$log" ||
 fail 'the display did not say why it moved the page'
grep -q '^  point [0-9]* -> 30 in fe-set-point (a C function a script called) during the command$' "$log" || fail 'the C function a script called was not named'
grep -q '^#[0-9]* C-n .* | [0-9.]* ms: command [0-9.]*, display [0-9.]* | faults [0-9]*$' "$log" || fail 'no times and faults on the key lines'
echo 'PASS the configured backdoor: all the mouse, watches with who moved them, text, time, alloc, unknown options reported'

# 3. lines: the cap counts the header, which is never dropped
printf 'lines 30\nwatch point\n' > "$work/home/.chezemax/backdoor-claude.conf"
{ echo 'await-screen [SAVE]'; echo 'keys \exbackdoor-claude\r'; i=0
  while [ $i -lt 10 ]; do echo 'keys ^N^N^N^N^N^P^P^P^P^P'; i=$((i+1)); done
  echo 'wait 300'; echo 'keys \exbackdoor-claude\r'; echo 'wait 1500'; echo 'keys ^X^C'; } > "$work/keys"
rm -f "$log"
run "$work/keys"
lines=$(wc -l < "$log")
[ "$lines" -le 30 ] && [ "$lines" -ge 25 ] || fail "lines 30, and $lines were kept"
head -n 1 "$log" | grep -q '^backdoor opened for Claude' && grep -q '^options (backdoor-claude.conf): .*watch point,' "$log" ||
 fail 'the header was dropped'
[ "$(tail -n 1 "$log")" = 'backdoor closed' ] || fail 'the last line is not the closing'
echo 'PASS lines 30: at most 30 lines, the header kept'

