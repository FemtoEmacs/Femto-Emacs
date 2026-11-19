#!/bin/sh
# Files in shards (src/shard.c, compiled/scripts/shards.scm), as Emacs's
# VLF: a file of 100 numbered lines in shards of about 200 bytes (4
# shards), on disposable files in a PTY.  C-c C-v n, p and g move between
# shards; M-g goes to a line of the whole file; C-s at a failing search
# looks in the shards that follow, and C-g comes back; edits in three
# shards survive moving away; C-x C-s writes the whole file, and the bytes
# of the shards not edited are the file's; undo belongs to the shard;
# C-x C-f opens a file above (fe-shard-threshold) in shards; another
# program's change stops reading a shard and asks before saving.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-shards.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
cc=${CC:-cc}
$cc -O2 tests/pty-keys.c -o "$work/pty" -lutil 2>/dev/null ||
 $cc -O2 tests/pty-keys.c -o "$work/pty"
mkdir -p "$work/home/.chezemax"
i=1; : > "$work/orig.txt"
while [ $i -le 100 ]; do echo "line $i ção" >> "$work/orig.txt"; i=$((i + 1)); done
run() { (cd "$work"; HOME="$work/home" CHEZEMAX_NO_INIT=1 LC_ALL=C.UTF-8 "$work/pty" "$1" 60 "$work/screen" "$root/chezemax" ${2:-}); }
fail() { echo "FAIL $1"; diff "$work/orig.txt" "$work/f.txt" || true; exit 1; }
open='await-screen [SAVE]
keys \e:(fe-shard-size 200)\r
wait 300
keys \exfind-file-shards\r
wait 300
keys ^A^Kf.txt\r
wait 500'

# 1. moving and editing in three shards, a search across shards, saving
cp "$work/orig.txt" "$work/f.txt"
cat > "$work/k1" <<EOF
$open
keys ^C^Vn
wait 300
keys ^C^Vn
wait 300
keys XYZ
wait 200
keys ^C^Vp
wait 300
keys \eg50\r
wait 300
keys ABC
wait 200
keys ^Sline 90 ^S
wait 500
keys \r
wait 200
keys QQ
wait 200
keys ^X^S
wait 800
keys ^X^C
EOF
run "$work/k1"
# the first line of shard 3: shards end at the first newline after 200 bytes
third=$(awk 'BEGIN { n = 0; k = 1 } { n += length($0) + 1; if (n >= 200) { k++; n = 0; if (k == 3) { print NR + 1; exit } } }' LC_ALL=C "$work/orig.txt")
awk -v third="$third" 'NR == 50 { $0 = "ABC" $0 } NR == third { $0 = "XYZ" $0 } NR == 90 { sub(/line 90 /, "line 90 QQ") } { print }' "$work/orig.txt" > "$work/want.txt"
cmp -s "$work/f.txt" "$work/want.txt" || { diff "$work/want.txt" "$work/f.txt" || true; fail 'the saved file is not the original with the three edits'; }
grep -aq 'Shard 2/' "$work/screen" || fail 'C-c C-v n did not report shard 2'
grep -aq ' \[1/[0-9]*\]' "$work/screen" || fail 'the mode line does not show the shard'
grep -aq 'L\. 90' "$work/screen" || fail 'the mode line does not show the line of the whole file'
echo 'PASS shards: C-c C-v n/p, M-g across shards, C-s into a later shard, edits in three shards saved, the rest of the bytes as they were'

# 2. C-g after a search into another shard comes back; undo stays in the shard
cp "$work/orig.txt" "$work/f.txt"
cat > "$work/k2" <<EOF
$open
keys ^Sline 99 ^S
wait 500
keys ^G
wait 300
keys AB
wait 200
keys ^_
wait 300
keys ^_
wait 300
keys ^_
wait 300
keys ^X^S
wait 500
keys ^X^C
EOF
run "$work/k2"
cmp -s "$work/f.txt" "$work/orig.txt" || fail 'C-g and undo did not leave the file as it was'
grep -aq 'No further undo information' "$work/screen" || fail 'undo went past the shard as read'
grep -aq 'No changes need to be saved' "$work/screen" || fail 'the file is modified after undoing everything'
echo 'PASS shards: C-g comes back to the shard the search left; undo stops at the shard as read'

# 3. C-x C-f above the threshold opens in shards; C-x C-w writes the whole file elsewhere
cp "$work/orig.txt" "$work/f.txt"
cat > "$work/k3" <<'EOF'
await-screen [SAVE]
keys \e:(fe-shard-size 200)\r
wait 300
keys \e:(fe-shard-threshold 1000)\r
wait 300
keys ^X^F
wait 300
keys ^A^Kf.txt\r
wait 500
keys ^C^Vg
wait 300
keys 4\r
wait 300
keys Z
wait 200
keys ^X^W
wait 300
keys ^A^Kg.txt\r
wait 800
keys ^X^C
EOF
run "$work/k3"
cmp -s "$work/f.txt" "$work/orig.txt" || fail 'C-x C-w changed the original'
grep -aq 'Shard 1/' "$work/screen" || fail 'C-x C-f of a file above the threshold did not open it in shards'
[ "$(wc -c < "$work/g.txt")" -eq $(( $(wc -c < "$work/orig.txt") + 1 )) ] || fail 'C-x C-w did not write the whole file'
echo 'PASS shards: C-x C-f above the threshold opens in shards; C-x C-w writes the whole file to the new name'

# 4. another program changes the file: no shard is read from it, and saving asks
cp "$work/orig.txt" "$work/f.txt"
cat > "$work/k4" <<EOF
$open
keys A
wait 300
await-file changed
keys ^C^Vn
wait 300
keys ^X^S
wait 500
keys n
wait 300
keys ^X^C
wait 300
keys y
EOF
( sleep 3; echo 'another program' >> "$work/f.txt"; echo go > "$work/changed" ) &
run "$work/k4"
wait
grep -aq 'File changed on disk' "$work/screen" || fail 'a shard was read from a file another program changed'
grep -aq 'changed on disk since it was read or saved' "$work/screen" || fail 'saving did not ask'
tail -n 1 "$work/f.txt" | grep -q 'another program' || fail "the other program's version was overwritten"
echo "PASS shards: another program's change stops the reading of shards, and C-x C-s asks before saving over it"

# 5. in an Org file, C-c C-v is Org Babel's prefix, and n still goes to the next shard
i=1; : > "$work/o.org"
while [ $i -le 60 ]; do echo "* heading $i" >> "$work/o.org"; i=$((i + 1)); done
cp "$work/o.org" "$work/o-orig.org"
cat > "$work/k5" <<'EOF'
await-screen [SAVE]
keys \e:(fe-shard-size 200)\r
wait 300
keys \exfind-file-shards\r
wait 300
keys ^A^Ko.org\r
wait 800
keys ^C^V
wait 300
keys n
wait 600
keys Z
wait 300
keys ^X^S
wait 500
keys ^X^C
EOF
run "$work/k5"
# Z at the start of shard 2: the first line after 200 bytes
second=$(awk '{ n += length($0) + 1; if (n >= 200) { print NR + 1; exit } }' "$work/o-orig.org")
awk -v l="$second" 'NR == l { $0 = "Z" $0 } { print }' "$work/o-orig.org" > "$work/o-want.org"
cmp -s "$work/o.org" "$work/o-want.org" || { diff "$work/o-want.org" "$work/o.org" || true; fail 'C-c C-v n in an Org file did not go to the next shard'; }
echo 'PASS shards: in an Org file, C-c C-v n (after Babel'"'"'s prefix) goes to the next shard'

# 6. C-c C-v ] goes to the end of the last shard, C-c C-v [ to the start of the first
cp "$work/orig.txt" "$work/f.txt"
cat > "$work/k6" <<EOF
$open
keys ^C^Vn
wait 300
keys ^C^V]
wait 300
keys END
wait 200
keys ^C^V[
wait 300
keys BEGIN
wait 200
keys ^X^S
wait 800
keys ^X^C
EOF
run "$work/k6"
{ printf 'BEGIN'; cat "$work/orig.txt"; printf 'END'; } > "$work/want.txt"
cmp -s "$work/f.txt" "$work/want.txt" || { diff "$work/want.txt" "$work/f.txt" || true; fail 'C-c C-v ] and [ did not go to the end of the file and to its start'; }
echo 'PASS shards: C-c C-v ] goes to the end of the last shard, C-c C-v [ to the start of the first'
