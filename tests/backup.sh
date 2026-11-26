#!/bin/sh
# backup.sh -- the safe save, backups and auto-save (src/backup.c; 26
# November 2026).  Disposable files and a disposable HOME, in a PTY.
#
#   1  C-x C-s writes through a temporary file renamed over the file: the
#      permissions stay, a symbolic link stays a link to the file it names,
#      no temporary file is left
#   2  the first save of a session keeps the version before it in
#      ~/.chezemax/backup (.~1~); a second save in the session does not
#      touch it; the next session's first save makes it .~2~
#   3  a file with another hard link is written in place (the link sees
#      the new text) and its backup is a copy, with the old text
#   4  auto-save after 300 keys, and after a time without a key
#      ($CHEZWEB_AUTOSAVE_IDLE_MS, 1 s here; 30 s in use): the buffer's
#      text in ~/.chezemax/auto-save/#!path#; C-x C-s removes it
#   5  a file visited with a newer auto-save says so; M-x recover-file puts
#      the auto-save's text in the buffer, and C-x C-s saves it
#   6  no backup of a file in the temporary folder ($TMPDIR), as in Emacs
#   7  M-x delete-old-backups and M-x delete-auto-saves
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-backup.XXXXXX")
if [ "${BACKUP_KEEP:-}" = 1 ]; then echo "work: $work"; else trap 'rm -rf "$work"' EXIT HUP INT TERM; fi
cc=${CC:-cc}
$cc -O2 tests/pty-keys.c -o "$work/pty" -lutil 2>/dev/null ||
	$cc -O2 tests/pty-keys.c -o "$work/pty"
mkdir -p "$work/home/.chezemax" "$work/files"
printf 'repeats keep\nwatch none\n' > "$work/home/.chezemax/backdoor-claude.conf"
work=$(cd "$work" && pwd -P)            # the real path: the backup names use it
files="$work/files"
failed=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failed=1; }

# session NAME FILE: the keys of $work/NAME.keys, then C-x C-c and y
session() {
	{
		echo 'await-screen [SAVE]'
		cat "$work/$1.keys"
		echo 'keys ^X^C'
		echo 'wait 300'
		echo 'keys y'
		echo 'wait 300'
	} > "$work/$1.script"
	# TMPDIR: another folder, or no backups of these files (they are in
	# the temporary folder, where Emacs and Chezweb make none)
	(cd "$files"; HOME="$work/home" TMPDIR="$work/home" CHEZEMAX_NO_INIT=1 LC_ALL=C.UTF-8 CHEZWEB_AUTOSAVE_IDLE_MS=${IDLE:-1000} \
		"$work/pty" "$work/$1.script" 60 "$work/$1.screen" "$root/chezemax" "$2") > "$work/$1.pty" 2>&1 ||
		fail "$1: the session did not finish"
}
mangle() { echo "$1" | tr / !; }
backup="$work/home/.chezemax/backup"
autosave="$work/home/.chezemax/auto-save"

# ------------------------------------------------------------ 1
printf 'real text\n' > "$files/real.txt"
chmod 640 "$files/real.txt"
ln -s real.txt "$files/link.txt"
printf 'keys \\e>new line\\r\nwait 200\nkeys ^X^S\nwait 500\n' > "$work/link.keys"
session link link.txt
if [ -L "$files/link.txt" ] && [ "$(cat "$files/real.txt")" = "real text
new line" ]; then pass "a save through a symbolic link writes the file it names, and the link stays"
else fail "the save through the link: link.txt $(ls -l "$files/link.txt" | cut -c1-10), real.txt: $(cat "$files/real.txt")"; fi
mode=$(ls -l "$files/real.txt" | cut -c1-10)
[ "$mode" = "-rw-r-----" ] && pass "the file keeps its permissions (-rw-r-----)" || fail "the permissions became $mode"
left=$(ls -a "$files" | grep -c 'chezweb-' || true)
[ "$left" = 0 ] && pass "no temporary file is left beside it" || fail "temporary files left: $(ls -a "$files")"

# ------------------------------------------------------------ 2
printf 'version 1\n' > "$files/a.txt"
b1="$backup/$(mangle "$files/a.txt").~1~"; b2="$backup/$(mangle "$files/a.txt").~2~"
printf 'keys \\e>two\\r\nwait 200\nkeys ^X^S\nwait 500\nkeys three\\r\nwait 200\nkeys ^X^S\nwait 500\n' > "$work/a1.keys"
session a1 a.txt
if [ "$(cat "$b1" 2>/dev/null)" = "version 1" ] && [ ! -e "$b2" ]; then
	pass "the first save of a session keeps the version before it (.~1~); the second save does not touch it"
else fail "after two saves in a session: .~1~ is '$(cat "$b1" 2>/dev/null)', .~2~ $( [ -e "$b2" ] && echo exists || echo absent)"; fi
printf 'keys \\e>four\\r\nwait 200\nkeys ^X^S\nwait 500\n' > "$work/a2.keys"
session a2 a.txt
if [ "$(cat "$b1")" = "version 1
two
three" ] && [ "$(cat "$b2" 2>/dev/null)" = "version 1" ]; then
	pass "the next session's first save: .~1~ the version before it, .~2~ the one before that"
else fail "after a second session: .~1~ '$(cat "$b1")', .~2~ '$(cat "$b2" 2>/dev/null)'"; fi

# ------------------------------------------------------------ 3
printf 'linked\n' > "$files/h.txt"
ln "$files/h.txt" "$files/h2.txt"
printf 'keys \\e>more\\r\nwait 200\nkeys ^X^S\nwait 500\n' > "$work/h.keys"
session h h.txt
hb="$backup/$(mangle "$files/h.txt").~1~"
if [ "$(cat "$files/h2.txt")" = "linked
more" ] && [ "$(cat "$hb" 2>/dev/null)" = "linked" ]; then
	pass "a file with another hard link is written in place (the other name sees it), its backup a copy of the old text"
else fail "hard link: h2.txt '$(cat "$files/h2.txt")', backup '$(cat "$hb" 2>/dev/null)'"; fi

# ------------------------------------------------------------ 4
printf 'start\n' > "$files/s.txt"
as="$autosave/#$(mangle "$files/s.txt")#"
keys=$(awk 'BEGIN { for (i = 0; i < 300; i++) printf "k" }')
{ printf 'keys \\e>\nwait 200\n'; printf 'keys %s\nwait 1500\n' "$keys"; } > "$work/s1.keys"
# no auto-save for a time without a key here.  IDLE is set and unset on
# lines of their own: an assignment before a function call stays after it
# in the Mac's sh (bash), not in dash, and then the next session waited
# 60 s for its auto-save (25 November 2026)
IDLE=60000
session s1 s.txt
IDLE=1000
got=$(cat "$as" 2>/dev/null || true)
want="start
$(awk 'BEGIN { for (i = 0; i < 299; i++) printf "k" }')"
# the 300th key is M->: the auto-save comes after it, with 299 k
grep -aq 'Auto-saving s.txt...done' "$work/s1.screen" && pass "and it says so: Auto-saving s.txt...done" ||
	fail "no word of the auto-save after 300 keys"
[ "$got" = "$want" ] && pass "after 300 keys the buffer is auto-saved" ||
	fail "after 300 keys the auto-save holds $(printf %s "$got" | wc -c) bytes, not $(printf %s "$want" | wc -c)"
rm -f "$as"
printf 'keys \\e>idle\nwait 2500\n' > "$work/s2.keys"
session s2 s.txt
grep -aq 'Auto-saving s.txt...done' "$work/s2.screen" && pass "and it says so, though no key came" ||
	fail "no word of the auto-save after a time without a key"
[ "$(cat "$as" 2>/dev/null)" = "start
idle" ] && pass "after a time without a key the buffer is auto-saved" ||
	fail "after a time without a key: '$(cat "$as" 2>/dev/null)'"
printf 'keys \\e>x\nwait 2500\nkeys ^X^S\nwait 500\n' > "$work/s3.keys"
session s3 s.txt
[ ! -e "$as" ] && pass "C-x C-s removes the auto-save" || fail "the auto-save is still there after C-x C-s"

# ------------------------------------------------------------ 5
printf 'saved text\n' > "$files/r.txt"
ra="$autosave/#$(mangle "$files/r.txt")#"
sleep 1
printf 'saved text\nwork not saved\n' > "$ra"
printf 'wait 500\npaste \\exrecover-file\\r\nwait 500\nkeys y\nwait 500\nkeys ^X^S\nwait 500\n' > "$work/r.keys"
session r r.txt
grep -aq 'auto-saved changes newer than the file' "$work/r.screen" &&
	pass "a file with a newer auto-save says so when visited" || fail "no word of the newer auto-save"
[ "$(cat "$files/r.txt")" = "saved text
work not saved" ] && pass "M-x recover-file puts the auto-save's text in the buffer, and C-x C-s saves it" ||
	fail "after M-x recover-file and C-x C-s: '$(cat "$files/r.txt")'"
[ ! -e "$ra" ] && pass "and the auto-save is gone" || fail "the auto-save is still there"

# ------------------------------------------------------------ 6
printf 'temporary\n' > "$files/t.txt"
printf 'keys \\e>more\\r\nwait 200\nkeys ^X^S\nwait 500\n' > "$work/t.keys"
{
	echo 'await-screen [SAVE]'; cat "$work/t.keys"; echo 'keys ^X^C'; echo 'wait 300'
} > "$work/t.script"
(cd "$files"; HOME="$work/home" TMPDIR="$work" CHEZEMAX_NO_INIT=1 LC_ALL=C.UTF-8 \
	"$work/pty" "$work/t.script" 60 "$work/t.screen" "$root/chezemax" t.txt) > "$work/t.pty" 2>&1 || fail "t: the session did not finish"
tb="$backup/$(mangle "$files/t.txt").~1~"
if [ ! -e "$tb" ] && [ "$(cat "$files/t.txt")" = "temporary
more" ]; then pass "a file in the temporary folder is saved without a backup, as in Emacs"
else fail "the file in the temporary folder: backup $( [ -e "$tb" ] && echo made || echo none), text '$(cat "$files/t.txt")'"; fi

# ------------------------------------------------------------ 7
# M-x delete-old-backups (30 days, the answer offered) and M-x
# delete-auto-saves, each asking y/n
rm -rf "$backup" "$autosave"; mkdir -p "$backup" "$autosave"
printf old > "$backup/!x!old.txt.~1~"; touch -t 202001010000 "$backup/!x!old.txt.~1~"
printf new > "$backup/!x!new.txt.~1~"
printf mine > "$backup/notes-of-mine.txt"                  # not a backup: left alone
printf a > "$autosave/#!x!a.txt#"; touch -t 202001010000 "$autosave/#!x!a.txt#"
printf b > "$autosave/#!x!b.txt#"
printf 'text\n' > "$files/c.txt"
{ printf 'paste \\exdelete-old-backups\\r\nwait 500\nkeys \\r\nwait 500\nkeys y\nwait 500\n'
  printf 'paste \\exdelete-auto-saves\\r\nwait 500\nkeys \\r\nwait 500\nkeys y\nwait 500\n'; } > "$work/c.keys"
session c c.txt
if [ ! -e "$backup/!x!old.txt.~1~" ] && [ -e "$backup/!x!new.txt.~1~" ] && [ -e "$backup/notes-of-mine.txt" ]; then
	pass "M-x delete-old-backups deletes the backups older than 30 days, keeps the newer and what is not a backup"
else fail "M-x delete-old-backups left: $(ls "$backup" | tr '\n' ' ')"; fi
if [ ! -e "$autosave/#!x!a.txt#" ] && [ -e "$autosave/#!x!b.txt#" ]; then
	pass "M-x delete-auto-saves deletes the auto-saves older than 30 days, after y, and keeps the newer"
else fail "M-x delete-auto-saves left: $(ls "$autosave" | tr '\n' ' ')"; fi
# 0: all of them
printf 'paste \\exdelete-auto-saves\\r\nwait 500\nkeys ^A^K0\\r\nwait 500\nkeys y\nwait 500\n' > "$work/c2.keys"
session c2 c.txt
[ -z "$(ls "$autosave")" ] && pass "M-x delete-auto-saves with 0 days deletes them all" ||
	fail "M-x delete-auto-saves with 0 left: $(ls "$autosave" | tr '\n' ' ')"

# the auto-save of a buffer open with changes stays, and it says which
printf 'open\n' > "$files/o.txt"
printf 'keys \\e>work\nwait 2500\npaste \\exdelete-auto-saves\\r\nwait 500\nkeys ^A^K0\\r\nwait 800\n' > "$work/o.keys"
session o o.txt
oa="$autosave/#$(mangle "$files/o.txt")#"
if [ -e "$oa" ] && grep -aq 'kept: o.txt, open with changes' "$work/o.screen"; then
	pass "M-x delete-auto-saves keeps the auto-save of a buffer open with changes, and says which and why"
else fail "the open buffer's auto-save: $( [ -e "$oa" ] && echo kept || echo deleted), and no word of why"; fi

# a buffer above 10 MB is not auto-saved, and its first change says so
awk 'BEGIN { for (i = 0; i < 180000; i++) printf "line %06d of eleven megabytes, too large to be auto-saved..\n", i }' > "$files/big.txt"
printf 'keys \\e>typed\nwait 2500\n' > "$work/big.keys"
session big big.txt
ba="$autosave/#$(mangle "$files/big.txt")#"
if [ ! -e "$ba" ] && grep -aq 'big.txt: not auto-saved (11 MB > 10 MB); \*\* until C-x C-s saves' "$work/big.screen"; then
	pass "a buffer of 11 MB is not auto-saved, and its first change says so"
else fail "the buffer of 11 MB: auto-save $( [ -e "$ba" ] && echo made || echo none), and no word that it is not auto-saved"; fi
grep -aq '\*\*, L\. 180001' "$work/big.screen" && pass "and its mode line shows ** after the name, not *" ||
	fail "no ** on the mode line of the buffer of 11 MB"

exit $failed
