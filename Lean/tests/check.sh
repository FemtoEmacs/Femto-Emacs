#!/bin/sh
# Kernel-check proofs, then test the bounded IO adapter against corrupt streams.
set -eu
cd "$(dirname "$0")/.."
work=$(mktemp -d "${TMPDIR:-/tmp}/chez-tester-proof.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
# One line, one READ pass: reset, one move, seven further EOF moves.
{
 echo 'H 1 1 1 1 4'
 echo 'S 0 0 1 0 1 1 0'
 for i in 1 2 3; do echo "S $i 1 1 16 2 1 0";done
 echo 'B 4'
 for i in 4 5 6 7; do echo "S $i 1 1 16 2 1 0";done
 echo 'B 8'
 for i in 8 9; do echo "S $i 1 1 16 2 1 0";done
 echo 'B 10'
 echo 'Z 10'
} > "$work/pass.trace"
./chez-tester < "$work/pass.trace" > "$work/out"
grep -q '^PASS 10$' "$work/out"
reject() {
 if ./chez-tester < "$work/bad" > "$work/out";then echo "FAIL accepted $1";exit 1;fi
 if grep -q '^PASS ' "$work/out";then echo "FAIL false PASS for $1";exit 1;fi
 echo "PASS rejects $1"
}
sed 's/S 1 1 1 16/S 1 1 1 0/' "$work/pass.trace" > "$work/bad";reject 'wrong cursor'
sed 's/S 1 1 1 16 2 1 0/S 1 1 1 16 2 0 0/' "$work/pass.trace" > "$work/bad";reject 'changed bytes'
sed 's/S 1 1 1 16 2 1 0/S 1 1 1 16 2 1 1/' "$work/pass.trace" > "$work/bad";reject 'runtime failure'
sed '/^S 1 /d' "$work/pass.trace" > "$work/bad";reject 'missing event'
sed 's/^S 1 /S 0 /' "$work/pass.trace" > "$work/bad";reject 'duplicate event'
sed 's/^S 1 1 1/S 1 1 2/' "$work/pass.trace" > "$work/bad";reject 'wrong mode'
sed 's/^S 1 1 /S 1 0 /' "$work/pass.trace" > "$work/bad";reject 'wrong action'
sed 's/^B 4/B 3/' "$work/pass.trace" > "$work/bad";reject 'wrong acknowledgment counter'
sed '/^B 10/d' "$work/pass.trace" > "$work/bad";reject 'unacknowledged final batch'
sed '/^Z /d' "$work/pass.trace" > "$work/bad";reject 'truncated prefix'
head -n 2 "$work/pass.trace" > "$work/bad";echo 'Z 10' >> "$work/bad";reject 'premature success'
cat "$work/pass.trace" > "$work/bad";echo 'S 10 1 1 16 2 1 0' >> "$work/bad";reject 'trailing records'
sed 's/^H 1 1 1 1 4/H 1 1 1 1 63/' "$work/pass.trace" > "$work/bad";reject 'oversized batch configuration'
awk 'BEGIN {for(i=0;i<129;i++)printf "9";printf "\n"}' > "$work/bad";reject 'oversized input line'
# Kernel proofs must be explicit, without placeholders or application axioms.
if grep -nE '\b(sorry|axiom)\b' rdonly-tester.lean;then echo 'FAIL proof placeholder';exit 1;fi
cmp "$work/pass.trace" examples/read-enter.trace
printf 'PASS bounded checker and adversarial protocol tests\n'
./chez-tester --check-file examples/native-file.txt < examples/native-file.trace > "$work/out"
grep -q '^PASS 12$' "$work/out"
printf 'PASS replay of captured existing-file protocol\n'
if ./chez-tester --check-file "$work/不存在🙂不存在🙂不存在🙂不存在🙂不存在🙂不存在🙂" < /dev/null > "$work/out";then
 echo 'FAIL accepted missing Unicode input';exit 1
fi
[ "$(wc -c < "$work/out")" -le 128 ]
echo 'PASS exception replies remain within one bounded line'
