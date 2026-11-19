#!/bin/sh
# Visiting a file holds one copy of it (19 November 2026, Lean/undo-visit.lean).
# insert_file used to report the whole file to the undo history, which the
# caller erased at once ('r'); the copies made a 100 MB file take 650 MB.
# Here: a generated 64 MB file opens with less than its size twice over the
# editor's memory with a tiny file; and after typing and undoing everything,
# the buffer is unmodified, as before the fix.  Disposable files and PTY.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-visit-memory.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
cc=${CC:-cc}
$cc -O2 tests/pty-keys.c -o "$work/pty" -lutil 2>/dev/null ||
 $cc -O2 tests/pty-keys.c -o "$work/pty"
mkdir -p "$work/home/.chezemax"
line='Linha: ação, coração, € 漢字 — the quick brown fox jumps over the lazy dog.'
printf '%s\n' "$line" > "$work/small.txt"
# 64 MB: 2^20 lines of 64 bytes (doubling a file 20 times)
printf '%-63s\n' 'the quick brown fox jumps over the lazy dog, again and again' > "$work/big.txt"
i=0; while [ $i -lt 20 ]; do cat "$work/big.txt" "$work/big.txt" > "$work/b2"; mv "$work/b2" "$work/big.txt"; i=$((i + 1)); done
size_kb=$(( $(wc -c < "$work/big.txt") / 1024 ))
printf 'await-screen [SAVE]\nwait 500\nkeys ^X^C\n' > "$work/open.keys"
# The largest resident size, in KB, of the editor (the child of pty-keys,
# and no other process) while it opens FILE and types KEYS (open.keys); it
# must finish with status 0.  HOME, if given, has an init.scm, read.
peak() {
  keys=${2:-$work/open.keys}
  if [ -n "${3:-}" ]; then
    (cd "$work" && HOME="$3" LC_ALL=C.UTF-8 exec "$work/pty" "$keys" 60 "$work/screen" "$root/chezemax" "$1") &
  else
    (cd "$work" && HOME="$work/home" CHEZEMAX_NO_INIT=1 LC_ALL=C.UTF-8 exec "$work/pty" "$keys" 60 "$work/screen" "$root/chezemax" "$1") &
  fi
  pid=$!; most=0; child=
  while kill -0 $pid 2>/dev/null; do
    [ -n "$child" ] || child=$(ps -A -o pid= -o ppid= | awk -v p=$pid '$2 == p { print $1; exit }')
    if [ -n "$child" ]; then
      r=$(ps -o rss= -p "$child" 2>/dev/null | tr -d ' ')
      [ -n "$r" ] && [ "$r" -gt "$most" ] && most=$r
    fi
    sleep 0.1
  done
  if wait $pid; then status=0; else status=$?; fi
  echo "$status $most"
}
measure() {
  set -- $(peak "$@")
  [ "$1" -eq 0 ] || { echo "FAIL the editor did not open and quit cleanly (status $1)" >&2; exit 1; }
  [ "$2" -gt 0 ] || { echo 'FAIL the editor'"'"'s memory was not measured' >&2; exit 1; }
  echo "$2"
}
base=$(measure small.txt)
big=$(measure big.txt)
limit=$((base + 2 * size_kb))
[ "$big" -lt "$limit" ] || { echo "FAIL a ${size_kb} KB file took ${big} KB (the editor alone ${base} KB; limit ${limit} KB)"; exit 1; }
echo "PASS visiting a ${size_kb} KB file takes $((big - base)) KB more than an empty editor (less than twice its size)"
# undo back to the file as read: unmodified, nothing to save
cp "$work/small.txt" "$work/u.txt"
printf 'await-screen [SAVE]\nkeys abc\nwait 200\nkeys ^_\nwait 300\nkeys ^_\nwait 300\nkeys ^_\nwait 300\nkeys ^_\nwait 300\nkeys ^X^S\nwait 300\nkeys ^X^C\nwait 300\nkeys n\n' > "$work/undo.keys"
(cd "$work"; HOME="$work/home" CHEZEMAX_NO_INIT=1 LC_ALL=C.UTF-8 "$work/pty" "$work/undo.keys" 60 "$work/screen" "$root/chezemax" u.txt)
cmp -s "$work/u.txt" "$work/small.txt" || { echo 'FAIL undo did not bring back the file as read'; exit 1; }
grep -aq 'No further undo information' "$work/screen" || { echo 'FAIL undo went past the file as read'; exit 1; }
grep -aq 'No changes need to be saved' "$work/screen" || { echo 'FAIL the buffer is modified after undoing everything'; exit 1; }
echo 'PASS undo stops at the file as read, and the buffer is then unmodified'
# C-x i of a file larger than undo keeps (8 MB) is refused before any copy;
# a small one is inserted, and undo takes it back
cp "$work/small.txt" "$work/i.txt"
printf 'await-screen [SAVE]\nkeys ^Xi\nwait 300\nkeys ^A^Kbig.txt\r\nwait 800\nkeys ^Xi\nwait 300\nkeys ^A^Ksmall.txt\r\nwait 500\nkeys ^X^S\nwait 300\nkeys ^_\nwait 300\nkeys ^X^W\nwait 300\nkeys ^A^Kj.txt\r\nwait 500\nkeys ^X^C\n' > "$work/insert.keys"
(cd "$work"; HOME="$work/home" CHEZEMAX_NO_INIT=1 LC_ALL=C.UTF-8 "$work/pty" "$work/insert.keys" 60 "$work/screen" "$root/chezemax" i.txt)
grep -aq "Not inserted: 64 MB is over \*undo-limit\*" "$work/screen" || { echo 'FAIL C-x i of a 64 MB file was not refused'; exit 1; }
cat "$work/small.txt" "$work/small.txt" | cmp -s - "$work/i.txt" || { echo 'FAIL C-x i of a small file did not insert it (once)'; exit 1; }
cmp -s "$work/j.txt" "$work/small.txt" || { echo 'FAIL undo did not take the small insertion back'; exit 1; }
echo 'PASS C-x i refuses a file larger than undo keeps, and inserts a small one that undo takes back'
# With undo off (*undo-mode* #f), C-x i of the 64 MB file is inserted and
# its bytes are not sent to undo.scm to be discarded: the editor holds the
# text once (the gap buffer), not four times
mkdir -p "$work/home-noundo/.chezemax"
printf '(set! *undo-mode* #f)\n' > "$work/home-noundo/.chezemax/init.scm"
cp "$work/small.txt" "$work/n.txt"
printf 'await-screen [SAVE]\nkeys ^Xi\nwait 300\nkeys ^A^Kbig.txt\r\nwait 1500\nkeys ^X^S\nwait 1500\nkeys ^X^C\n' > "$work/noundo.keys"
# the same editor without the insertion: init.scm is compiled on the first
# run (Schemer's compiler in the editor's memory) and cached for the next,
# so a first run warms the cache and a second gives this case's base
measure n.txt "$work/open.keys" "$work/home-noundo" > /dev/null
base_init=$(measure n.txt "$work/open.keys" "$work/home-noundo")
noundo=$(measure n.txt "$work/noundo.keys" "$work/home-noundo")
grep -aq 'Not inserted' "$work/screen" && { echo 'FAIL C-x i was refused with undo off'; exit 1; }
[ "$(wc -c < "$work/n.txt")" -eq $(( $(wc -c < "$work/small.txt") + $(wc -c < "$work/big.txt") )) ] || { echo 'FAIL C-x i with undo off did not insert the file'; exit 1; }
limit=$((base_init + 2 * size_kb))
[ "$noundo" -lt "$limit" ] || { echo "FAIL C-x i of ${size_kb} KB with undo off took ${noundo} KB (the editor alone ${base_init} KB; limit ${limit} KB): its bytes went to undo"; exit 1; }
echo "PASS with undo off, C-x i of a ${size_kb} KB file takes $((noundo - base_init)) KB more than the same editor without it: no copies for undo"
# The C core learns *undo-mode* before each event: off, it sends no bytes of
# any change to undo (typing, C-y, scripts); on again after C-x C-r
cp "$work/small.txt" "$work/m.txt"
printf '(set! *undo-mode* #f)\n' > "$work/home-noundo/.chezemax/init.scm"
cat > "$work/flag.keys" <<'EOF'
await-screen [SAVE]
keys abc
wait 300
keys \e:(fe-undo-recording -1)\r
wait 600
await-file go
keys ^X^R
wait 1500
keys d
wait 300
keys \e:(fe-undo-recording -1)\r
wait 600
keys ^X^C
wait 300
keys y
EOF
rm -f "$work/go"
( sleep 4; printf '(set! *undo-mode* #t)\n' > "$work/home-noundo/.chezemax/init.scm"; echo go > "$work/go" ) &
(cd "$work"; HOME="$work/home-noundo" LC_ALL=C.UTF-8 "$work/pty" "$work/flag.keys" 60 "$work/screen" "$root/chezemax" m.txt)
wait
told=$(grep -ao "$(printf '\r')[01]$(printf '\033')\[K" "$work/screen" | tr -cd '01')
[ "$told" = 01 ] || { echo "FAIL the C core was told undo is off, then on, as $told (not 01)"; exit 1; }
echo 'PASS the C core stops sending changes to undo while *undo-mode* is off, and starts again when it is on'
