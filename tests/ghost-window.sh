#!/bin/sh
# The ghost window (8 November 2026): the wheel scrolls a file until its
# last line is at the top and the rest of the window is blank; a click on
# the blank part puts the cursor at the end of the text.  The window must
# stay where it is (it reframed with the cursor on its last row), and the
# wheel must then scroll it up, the cursor still at the end, visible.  With
# and without a final newline.  The backdoor records the page and cursor.
# Disposable home, file and PTY.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-ghost.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
cc=${CC:-cc}
$cc -O2 tests/pty-keys.c -o "$work/pty" -lutil 2>/dev/null ||
 $cc -O2 tests/pty-keys.c -o "$work/pty"
mkdir -p "$work/home/.chezemax"
# one line for each mouse event, in order: the records are counted below
printf 'repeats keep\nmouse clicks\nwatch none\n' > "$work/home/.chezemax/backdoor-claude.conf"
{ echo 'await-screen [SAVE]'; echo 'keys \exbackdoor-claude\r'; echo 'wait 300'
  i=0; while [ $i -lt 20 ]; do echo 'keys \e[<65;10;5M'; i=$((i+1)); done
  echo 'wait 300'; echo 'keys \e[<0;10;15M'; echo 'keys \e[<0;10;15m'; echo 'wait 300'
  echo 'keys \e[<64;10;5M'; echo 'wait 200'; echo 'keys \e[<64;10;5M'; echo 'wait 200'
  echo 'keys \exbackdoor-claude\r'; echo 'wait 300'; echo 'keys ^X^C'; } > "$work/keys"
check() {   # $1 file name, $2 what it is
 what=$2 log="$work/home/.chezemax/backdoor.txt"
 (cd "$work"; HOME="$work/home" CHEZEMAX_NO_INIT=1 "$work/pty" "$work/keys" 60 "$work/screen" "$root/chezemax" "$1")
 # the mouse records: 20 wheel notches, the click, its release, two notches up
 records=$(grep '^#[0-9]* mouse ' "$log" | sed 's/.*pt=\([0-9]*\) page=\([0-9]*\) cur=\([0-9]*\),.* size=\([0-9]*\) .*/\1 \2 \3 \4/')
 scrolled=$(printf '%s\n' "$records" | sed -n 20p); clicked=$(printf '%s\n' "$records" | sed -n 21p)
 up1=$(printf '%s\n' "$records" | sed -n 23p); up2=$(printf '%s\n' "$records" | sed -n 24p)
 set -- $scrolled; page=$2; size=$4
 set -- $clicked
 [ "$1" = "$size" ] && [ "$2" = "$page" ] || { echo "FAIL $what: the click moved the window (page $page, then $2; point $1)"; cat "$log"; exit 1; }
 set -- $up1; p1=$2; [ "$1" = "$size" ] && [ "$p1" -lt "$page" ] || { echo "FAIL $what: the wheel did not scroll up"; cat "$log"; exit 1; }
 set -- $up2; [ "$1" = "$size" ] && [ "$2" -lt "$p1" ] || { echo "FAIL $what: the wheel stopped scrolling up"; cat "$log"; exit 1; }
}
awk 'BEGIN{for(i=1;i<=50;i++) print "line " i}' > "$work/newline.c"
check newline.c 'with a final newline'
awk 'BEGIN{for(i=1;i<=50;i++) printf "%sline %d", (i>1?"\n":""), i}' > "$work/no-newline.c"
check no-newline.c 'without a final newline'
echo 'PASS a click below the text of a scrolled window keeps it in place, and the wheel scrolls it up'
