#!/bin/sh
# Another program changes the file being edited (17 November 2026).  As
# in Emacs, C-x C-s over a file changed on disk since it was read or
# saved asks first: n keeps the other program's version, y saves over it.
# A file unchanged on disk saves without a question, the first time and
# after a save; so does a file the editor itself created.  A new file
# that another program created meanwhile is asked about too.  A buffer
# with nothing to save whose file another program changed (it shows an
# older text) says so at C-x C-s, instead of "No changes" (18 November
# 2026); the file is left alone.  Disposable home, files and PTY.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-disk.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
cc=${CC:-cc}
$cc -O2 tests/pty-keys.c -o "$work/pty" -lutil 2>/dev/null ||
 $cc -O2 tests/pty-keys.c -o "$work/pty"
mkdir -p "$work/home"
fail() { echo "FAIL $1"; exit 1; }
# run FILE: the editor in the background; the test changes files meanwhile
start() { (cd "$work"; HOME="$work/home" LC_ALL=C.UTF-8 CHEZEMAX_NO_INIT=1 "$work/pty" "$work/keys" 60 "$work/screen" "$root/chezemax" "$1" >/dev/null 2>&1) & pid=$!; }
until_screen() { i=0; while ! grep -q "$1" "$work/screen" 2>/dev/null; do i=$((i+1)); [ $i -lt 400 ] || fail "waited for: $1"; sleep 0.05; done; }

# 1. changed on disk: n keeps the other version, then y saves over it
printf 'first line\n' > "$work/a.txt"
cat > "$work/keys" <<KEYS
await-screen [SAVE]
keys mine 
keys \\e:(string-append "QX" "J1")\\r
await-file $work/go1
keys ^X^S
await-screen save over it (y/n)
keys n
wait 300
keys ^X^S
await-screen save over it (y/n)
keys y
wait 300
keys ^X^C
KEYS
start a.txt
until_screen QXJ1
printf 'another program wrote this\n' > "$work/a.txt"
echo go > "$work/go1"
wait $pid || true
grep -q 'a.txt changed on disk since it was read or saved; save over it (y/n)' "$work/screen" || fail 'no question when saving over a file changed on disk'
grep -q "Not saved: a.txt keeps the other program's version" "$work/screen" || fail 'n did not say the file was kept'
[ "$(cat "$work/a.txt")" = 'mine first line' ] || { cat "$work/a.txt"; fail 'y did not save over the other version'; }
echo 'PASS a file changed on disk: C-x C-s asks; n keeps the other version, y saves over it'

# 2. unchanged on disk: no question, the first save and the next
printf 'first line\n' > "$work/b.txt"
cat > "$work/keys" <<'KEYS'
await-screen [SAVE]
keys one ^X^S
wait 300
keys two ^X^S
wait 300
keys ^X^C
KEYS
start b.txt; wait $pid || true
! grep -q 'changed on disk' "$work/screen" || fail 'a question about a file that did not change'
[ "$(cat "$work/b.txt")" = 'one two first line' ] || { cat "$work/b.txt"; fail 'the saves of an unchanged file'; }
echo 'PASS an unchanged file saves without a question, again after a save'

# 3. a new file: saved by the editor, no question; created by another program, asked
cat > "$work/keys" <<KEYS
await-screen [SAVE]
keys new ^X^S
wait 300
keys ^X^C
KEYS
start c.txt; wait $pid || true
! grep -q 'changed on disk' "$work/screen" || fail 'a question about a new file the editor created'
[ "$(cat "$work/c.txt")" = 'new ' ] || fail 'the new file was not saved'
cat > "$work/keys" <<KEYS
await-screen [SAVE]
keys typed 
keys \\e:(string-append "QX" "J2")\\r
await-file $work/go2
keys ^X^S
await-screen save over it (y/n)
keys n
wait 300
keys ^X^C
keys y
KEYS
start d.txt
until_screen QXJ2
printf 'made elsewhere\n' > "$work/d.txt"
echo go > "$work/go2"
wait $pid || true
grep -q 'd.txt changed on disk' "$work/screen" || fail 'a file created elsewhere after the editor opened it as new was not asked about'
[ "$(cat "$work/d.txt")" = 'made elsewhere' ] || fail 'n must keep the file made elsewhere'
echo 'PASS a new file: the editor saves it without a question; one created meanwhile by another program is asked about'

# 4. nothing to save, but the file changed on disk: C-x C-s says so
printf 'line one\nline two\n' > "$work/s.txt"
cat > "$work/keys" <<KEYS
await-screen [SAVE]
keys \\e:(string-append "QX" "J3")\\r
await-file $work/go3
keys ^X^S
wait 400
keys ^X^C
KEYS
start s.txt
until_screen QXJ3
printf 'line one\nline two\nTeste\n' > "$work/s.txt"
echo go > "$work/go3"
wait $pid || true
grep -q 'File changed on disk; C-x C-w overwrites it. C-x C-v reads it again.' "$work/screen" || fail 'a buffer older than its file said nothing at C-x C-s'
! grep -q 'No changes need to be saved' "$work/screen" || fail 'C-x C-s said "No changes" about a buffer older than its file'
[ "$(cat "$work/s.txt")" = "$(printf 'line one\nline two\nTeste')" ] || fail "the other program's version must stay"
echo 'PASS nothing to save but the file changed on disk: C-x C-s says so, and writes nothing'

# 4b. C-x C-w overwrites, as the message says, whether the file was opened
# by its short name or by its full path (then the two names are the same)
for arg in s.txt "$work/s.txt"; do
 printf 'line one\nline two\n' > "$work/s.txt"; rm -f "$work/go3" "$work/screen"
 cat > "$work/keys" <<KEYS
await-screen [SAVE]
keys \\e:(string-append "QX" "J5")\\r
await-file $work/go3
keys ^X^S
wait 400
keys ^X^W\\r
wait 500
keys ^X^C
KEYS
 start "$arg"
 until_screen QXJ5
 printf 'another version\n' > "$work/s.txt"
 echo go > "$work/go3"
 wait $pid || true
 [ "$(cat "$work/s.txt")" = "$(printf 'line one\nline two')" ] || { cat "$work/s.txt"; fail "C-x C-w did not overwrite the file opened as $arg"; }
done
echo 'PASS C-x C-w overwrites a file changed on disk, opened by its short name or its full path'

# 5. only the time changed (touch, git): the same text is no other version
printf 'same text\n' > "$work/t.txt"
cat > "$work/keys" <<KEYS
await-screen [SAVE]
keys \\e:(string-append "QX" "J4")\\r
await-file $work/go4
keys ^X^S
wait 400
keys ^X^C
KEYS
start t.txt
until_screen QXJ4
touch -t 200001010000 "$work/t.txt"
echo go > "$work/go4"
wait $pid || true
grep -q 'No changes need to be saved' "$work/screen" || fail 'a touched file with the same text must give "No changes"'
! grep -q 'changed on disk' "$work/screen" || fail 'a touched file was taken for another version'
echo 'PASS a file only touched (its time changed, not its text) gives "No changes"'
