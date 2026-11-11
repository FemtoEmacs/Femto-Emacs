#!/bin/sh
# M-x term (src/terminal.c, compiled/scripts/terminal.scm, libvterm/), in a
# PTY: a shell runs in *terminal*; its output and colours show; the history
# keeps what scrolled off; a full-screen program (less: the alternate
# screen) comes and goes; C-c C-c interrupts; C-c 2 splits the window and the
# shell learns its new size; C-c C-j and C-c C-k switch to copy mode and
# back; C-c b goes to another buffer and M-x term back to the same shell;
# C-x C-c asks while the shell runs; when it exits the buffer is an
# ordinary one, and is saved to be checked.  With vim, a file is edited in
# it.  Disposable home, files and PTY.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-terminal.XXXXXX")
trap '[ -n "${KEEP:-}" ] || rm -rf "$work"' EXIT HUP INT TERM
cc=${CC:-cc}
$cc -O2 tests/pty-keys.c -o "$work/pty" -lutil 2>/dev/null ||
 $cc -O2 tests/pty-keys.c -o "$work/pty"
mkdir -p "$work/home"
fail() { echo "FAIL $1"; exit 1; }
printf 'printf "X\\033[31mRED\\033[0mY\\n"\n' > "$work/color.sh"
# lines as wide as the terminal, on a blue background (Neovim paints its
# whole screen so)
cat > "$work/wide.sh" <<'SH'
c=$(stty size | cut -d' ' -f2)
for i in 1 2 3; do printf "\033[44m%-${c}s\033[0m\n" "wide $i"; done
SH
awk 'BEGIN { for (i = 1; i <= 200; i++) print "line " i }' > "$work/lines.txt"
if command -v vim > /dev/null 2>&1; then vim='vim -u NONE -i NONE v.txt'; else vim=''; fi
cat > "$work/keys" <<KEYS
await-screen [SAVE]
keys \\exterm\\r
wait 1500
keys echo hello \$((6*7))\\r
wait 600
keys less lines.txt\\r
wait 1000
keys q
wait 600
keys seq 1 60\\r
wait 600
keys sh color.sh\\r
wait 800
keys sh wide.sh\\r
wait 800
keys sleep 30\\r
wait 400
keys ^C^C
wait 600
keys echo after-interrupt\\r
wait 600
keys ^C2
wait 800
keys stty size\\r
wait 600
keys ^C^J
wait 500
keys ^C^K
wait 500
keys ^Cb*scratch*\\r
wait 600
keys \\exterm\\r
wait 800
keys echo still-here\\r
wait 600
KEYS
if [ -n "$vim" ]; then cat >> "$work/keys" <<KEYS
keys $vim\\r
wait 1500
keys ihello from vim
wait 300
keys \\e
wait 300
keys :wq\\r
wait 1000
KEYS
fi
cat >> "$work/keys" <<'KEYS'
keys ^C^X^C
wait 500
keys n
wait 400
keys exit\r
wait 1500
keys ^X^Wsession.txt\r
wait 800
keys ^X^C
wait 800
KEYS
(cd "$work"; SHELL=/bin/sh PS1='$ ' HOME="$work/home" LC_ALL=C.UTF-8 CHEZEMAX_NO_INIT=1 "$work/pty" "$work/keys" 60 "$work/screen" "$root/chezemax") ||
 fail 'the editor did not finish'
s="$work/session.txt"
[ -f "$s" ] || fail 'the terminal was not saved after its shell exited'
has() { grep -q -- "$1" "$s" || { cat "$s"; fail "$2"; }; }
has '^hello 42$' 'the shell did not answer'
has '^1$' 'the history lost what scrolled off'
has '^60$' 'seq 1 60 is missing'
! grep -q '^line 1$' "$s" || fail 'less (the alternate screen) stayed in the history'
has '^XREDY$' 'the coloured output is missing'
[ "$(grep -c '^wide [123] *$' "$s")" = 3 ] || fail 'the lines as wide as the terminal are missing'
grep -a -q "$(printf '\033')\[44mwide 1" "$work/screen" || fail 'the blue background was not drawn'
grep -a -q "$(printf '\033')\[31mRED" "$work/screen" || fail 'RED was not drawn in red'
has '^after-interrupt$' 'C-c C-c did not interrupt sleep'
has '^[0-9]* 79$' 'stty size gave nothing, or not 79 columns (80 but one)'
rows=$(grep '^[0-9]* 79$' "$s" | cut -d' ' -f1)
[ "$rows" -lt 20 ] || fail "C-c 2: the shell was not told the smaller window ($rows rows)"
has '^still-here$' 'M-x term did not go back to the same shell'
has '^\[Process exited with status 0\]$' 'the end of the shell was not shown'
grep -a -q 'L\. [0-9]* Term' "$work/screen" || fail 'the mode line did not show Term'
grep -a -q 'opy mode: the editor' "$work/screen" || fail 'C-c C-j did not enter copy mode'
grep -a -q 'A terminal is still running; quit anyway' "$work/screen" || fail 'C-x C-c did not ask while the shell ran'
grep -a -q '\*scratch\*' "$work/screen" || fail 'C-c b did not go to *scratch*'
# the cursor: the screen's own is hidden while the shell has the keys, and
# the editor draws one, black on yellow (orange with 256 colours), then the
# screen's own comes back (in *scratch*)
esc=$(printf '\033')
grep -a -q "$esc\[?25l" "$work/screen" || fail "the screen's cursor was not hidden in the terminal"
grep -a "$esc\[?25l" "$work/screen" > /dev/null && tr -d '\n' < "$work/screen" | grep -a -q "$esc\[?25l.*$esc\[?25h" ||
 fail "the screen's cursor did not come back after the terminal"
grep -a -q "43m" "$work/screen" || fail 'the cursor was not drawn on yellow'
if [ -n "$vim" ]; then
 [ "$(cat "$work/v.txt")" = 'hello from vim' ] || fail 'vim in the terminal did not write v.txt'
fi
echo "PASS M-x term: a shell with colours, history, the alternate screen, C-c C-c, resizing, copy mode, C-c b and back, the quit question${vim:+, vim}"
