#!/bin/sh
# Real editor dispatch + bounded reports. Optional: requires built Lean checker.
set -eu
cd "$(dirname "$0")/../.."
root=$(pwd)
unset CHEZ_TESTER_KEEP_REFERENCE
export CHEZ_TESTER_CHECKER="$root/Lean/chez-tester" CHEZEMAX_PROGRAM="$root/chezemax.wasm"
work=$(mktemp -d "${TMPDIR:-/tmp}/chez-tester-native.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
cc=${CC:-cc}
$cc -O2 tests/pty-keys.c -o "$work/pty" -lutil 2>/dev/null || $cc -O2 tests/pty-keys.c -o "$work/pty"
printf 'Original user-like fixture; never save it.\n' > "$work/origin.txt"
cp "$work/origin.txt" "$work/original"
printf 'wait 50\n' > "$work/keys"
export CHEZEMAX_NO_INIT=1 CHEZ_TESTER_NONINTERACTIVE=1 CHEZ_TESTER_AUTORUN=1 CHEZ_TESTER_EXIT=1
export CHEZ_TESTER_LINES=32 CHEZ_TESTER_PASSES=4 CHEZ_TESTER_DELAY_MS=0
budget() {
 p=$(wc -c < "$CHEZ_TESTER_DIR/pending.trace");f=$(wc -c < "$CHEZ_TESTER_DIR/failure.trace");s=$(wc -c < "$CHEZ_TESTER_DIR/summary.txt")
 [ "$p" -le 8192 ] && [ "$f" -le 8192 ] && [ "$s" -le 4096 ] && [ $((p+f+s)) -le 20480 ]
 [ ! -e "$CHEZ_TESTER_DIR/run.lock" ]
 cmp "$work/origin.txt" "$work/original"
}
run() { "$work/pty" "$work/keys" 30 "$work/screen" ./chezemax "$work/origin.txt"; }
for profile in 1 2 3; do
 export CHEZ_TESTER_PROFILE=$profile CHEZ_TESTER_DIR="$work/result-$profile"
 run;grep -q '^status=PASS$' "$CHEZ_TESTER_DIR/summary.txt";grep -q '^acknowledged=164$' "$CHEZ_TESTER_DIR/summary.txt";budget
 [ ! -s "$CHEZ_TESTER_DIR/pending.trace" ] && [ ! -s "$CHEZ_TESTER_DIR/failure.trace" ]
 echo "PASS visible native profile $profile, exact contents and bounded acknowledged output"
done
# Reproduce the original long-file sequence repeatedly across both modes.
export CHEZ_TESTER_PROFILE=3 CHEZ_TESTER_LINES=1829 CHEZ_TESTER_PASSES=4 CHEZ_TESTER_DIR="$work/long-file"
"$work/pty" "$work/keys" 60 "$work/screen" ./chezemax "$work/origin.txt"
grep -q '^status=PASS$' "$CHEZ_TESTER_DIR/summary.txt"
grep -q '^acknowledged=7352$' "$CHEZ_TESTER_DIR/summary.txt";budget
echo 'PASS four 1829-line Vim/READ passes, including repeated EOF Enter'
export CHEZ_TESTER_LINES=32
# Reuse the same directory: output does not grow with runs or completed steps.
export CHEZ_TESTER_PASSES=50 CHEZ_TESTER_DIR="$work/reused"
for i in 1 2; do run;grep -q '^status=PASS$' "$CHEZ_TESTER_DIR/summary.txt";budget;done
[ "$(find "$CHEZ_TESTER_DIR" -type f | wc -l | tr -d ' ')" = 3 ]
echo 'PASS repeated intensive runs keep only three quota-limited files'
export CHEZ_TESTER_PASSES=4
export CHEZ_TESTER_NONINTERACTIVE=1 CHEZ_TESTER_AUTORUN=1 CHEZ_TESTER_LINES=32 CHEZ_TESTER_PASSES=4 CHEZ_TESTER_DELAY_MS=0
printf 'wait 50\n' > "$work/keys"
cat > "$work/wrong-ack" <<'CHECKER'
#!/bin/sh
printf 'READY\n'
while IFS= read -r line;do case "$line" in B*) printf 'ACK 0\n';exit 0 ;; esac;done
CHECKER
chmod +x "$work/wrong-ack"
export CHEZ_TESTER_CHECKER="$work/wrong-ack" CHEZ_TESTER_DIR="$work/rejected"
run;grep -q '^status=FAIL$' "$CHEZ_TESTER_DIR/summary.txt";grep -q '^acknowledged=0$' "$CHEZ_TESTER_DIR/summary.txt";budget
[ -s "$CHEZ_TESTER_DIR/pending.trace" ] && cmp "$CHEZ_TESTER_DIR/pending.trace" "$CHEZ_TESTER_DIR/failure.trace"
echo 'PASS wrong ACK cannot erase pending evidence or claim success'
cat > "$work/hang" <<'CHECKER'
#!/bin/sh
printf 'READY\n'
while IFS= read -r line;do case "$line" in B*) exec sleep 30 ;; esac;done
CHECKER
chmod +x "$work/hang"
export CHEZ_TESTER_CHECKER="$work/hang" CHEZ_TESTER_DIR="$work/timeout"
run;grep -q '^status=FAIL$' "$CHEZ_TESTER_DIR/summary.txt";budget
[ -s "$CHEZ_TESTER_DIR/pending.trace" ]
echo 'PASS missing acknowledgment times out with bounded retained evidence'
export CHEZ_TESTER_CHECKER="$root/Lean/chez-tester"
export CHEZ_TESTER_DIR="$work/cancelled" CHEZ_TESTER_LINES=128 CHEZ_TESTER_DELAY_MS=50
printf 'wait 1500\nkeys ^G\n' > "$work/keys"
run;grep -q '^status=CANCELLED$' "$CHEZ_TESTER_DIR/summary.txt";budget
echo 'PASS C-g cancels without reporting a completed run'
# Refuse to truncate a report that is a hard link to a user document.
export CHEZ_TESTER_DIR="$work/hard-link" CHEZ_TESTER_DELAY_MS=0
mkdir -m 700 "$CHEZ_TESTER_DIR";ln "$work/origin.txt" "$CHEZ_TESTER_DIR/pending.trace"
printf 'wait 50\n' > "$work/keys"
run;grep -q '^status=FAIL$' "$CHEZ_TESTER_DIR/summary.txt";cmp "$work/origin.txt" "$work/original"
echo 'PASS unsafe report link cannot overwrite a user document'

export CHEZ_TESTER_DIR="$work/reference" CHEZ_TESTER_LINES=4 CHEZ_TESTER_PASSES=1 CHEZ_TESTER_PROFILE=1 CHEZ_TESTER_KEEP_REFERENCE=1
run;grep -q '^status=PASS$' "$CHEZ_TESTER_DIR/summary.txt";budget
"$root/Lean/chez-tester" < "$CHEZ_TESTER_DIR/pending.trace" > "$work/replay"
grep -q '^PASS 13$' "$work/replay"
echo 'PASS tiny complete actual trace survives and is independently replayable'

# Public workflow: the current Lean buffer is the protocol; a prompt chooses text.
unset CHEZ_TESTER_AUTORUN CHEZ_TESTER_KEEP_REFERENCE
sed -e 's/def passes : Nat := 4/def passes : Nat := 2/' \
 -e 's/def delayMilliseconds : Nat := 10/def delayMilliseconds : Nat := 0/' \
 "$root/Lean/rdonly-tester.lean" > "$work/protocol.base"
cp "$work/protocol.base" "$work/protocol.lean"
{
 printf 'A short line\r\n\n'
 awk 'BEGIN {for(i=0;i<30;i++)printf "Long Markdown prose with tabs\tand Unicode αβ🙂 for visual wrapping. ";printf "\n"}'
 printf 'Final line without newline'
} > "$work/chosen text.md"
cp "$work/chosen text.md" "$work/chosen.original"
file_keys() {
 cat > "$work/keys" <<'KEYS'
wait 700
keys \exchez-tester\r
wait 100
KEYS
 printf 'keys ^A^K%s\\r\n' "$1" >> "$work/keys"
}
file_run() { "$work/pty" "$work/keys" 90 "$work/screen" ./chezemax "$work/protocol.lean"; }
source_safe() { cmp "$work/protocol.lean" "$work/protocol.original";cmp "$work/chosen text.md" "$work/chosen.original";budget; }
export CHEZ_TESTER_DIR="$work/chosen-unsaved"
cp "$work/protocol.lean" "$work/protocol.original"
cat > "$work/keys" <<'KEYS'
wait 700
keys \e<
keys ^Sdef passes : Nat :=
keys \r
keys ^A^Kdef passes : Nat := 1 + 1
keys \exchez-tester\r
wait 100
KEYS
printf 'keys ^A^K%s\\r\n' "$work/chosen text.md" >> "$work/keys"
file_run;grep -q '^status=PASS$' "$CHEZ_TESTER_DIR/summary.txt"
grep -q '^passes=2$' "$CHEZ_TESTER_DIR/summary.txt";source_safe
echo 'PASS chez-tester runs unsaved Lean expressions on a chosen wrapped Unicode file without saving either'
for mode in readOnly vim;do
 sed "s/def mode : Mode := .alternating/def mode : Mode := .$mode/" "$work/protocol.base" > "$work/protocol.lean"
 cp "$work/protocol.lean" "$work/protocol.original"
 export CHEZ_TESTER_DIR="$work/chosen-$mode"
 file_keys "$work/chosen text.md";file_run
 grep -q '^status=PASS$' "$CHEZ_TESTER_DIR/summary.txt";source_safe
 echo "PASS chosen existing file, $mode profile"
done
cp "$work/protocol.base" "$work/protocol.lean";cp "$work/protocol.lean" "$work/protocol.original"
: > "$work/empty.txt"
export CHEZ_TESTER_DIR="$work/chosen-empty"
file_keys "$work/empty.txt";file_run
grep -q '^status=PASS$' "$CHEZ_TESTER_DIR/summary.txt"
grep -q '^observations=18$' "$CHEZ_TESTER_DIR/summary.txt";source_safe
echo 'PASS empty existing file holds EOF for eight Enter presses per pass'
# Accept the real filename prompt's default and exercise the reported document.
export CHEZ_TESTER_DIR="$work/chosen-doc"
cp "$root/docs/chezemax.md" "$work/document.original"
printf 'wait 700\nkeys \\exchez-tester\\r\nwait 100\nkeys \\r\n' > "$work/keys"
file_run;grep -q '^status=PASS$' "$CHEZ_TESTER_DIR/summary.txt"
cmp "$root/docs/chezemax.md" "$work/document.original";source_safe
echo 'PASS default filename prompt, two complete passes through existing docs/chezemax.md'
export CHEZ_TESTER_DIR="$work/source-error"
cat > "$work/keys" <<'KEYS'
wait 700
keys \e>
keys \rthis is invalid Lean\r
keys \exchez-tester\r
wait 100
KEYS
printf 'keys ^A^K%s\\r\n' "$work/chosen text.md" >> "$work/keys"
file_run;grep -q '^status=FAIL$' "$CHEZ_TESTER_DIR/summary.txt"
grep -q '^acknowledged=0$' "$CHEZ_TESTER_DIR/summary.txt";source_safe
echo 'PASS unsaved Lean errors prevent navigation and never save the source'
printf '\377' > "$work/binary.txt"
awk 'BEGIN {for(i=0;i<1048577;i++)printf "x"}' > "$work/oversized.txt"
for name in missing binary oversized;do
 export CHEZ_TESTER_DIR="$work/reject-$name"
 file_keys "$work/$name.txt";file_run
 grep -q '^status=FAIL$' "$CHEZ_TESTER_DIR/summary.txt";source_safe
done
echo 'PASS missing, non-UTF-8, and oversized inputs fail without navigation'
sed 's/def maxEnterPressesPerPass : Nat := 10000/def maxEnterPressesPerPass : Nat := 8/' "$work/protocol.base" > "$work/protocol.lean"
cp "$work/protocol.lean" "$work/protocol.original"
export CHEZ_TESTER_DIR="$work/step-limit"
file_keys "$work/chosen text.md";file_run
grep -q '^status=FAIL$' "$CHEZ_TESTER_DIR/summary.txt";source_safe
echo 'PASS Enter safety limit cannot certify an unfinished traversal'
# Never truncate the selected text even when its name is a managed report.
cp "$work/protocol.base" "$work/protocol.lean";cp "$work/protocol.lean" "$work/protocol.original"
export CHEZ_TESTER_DIR="$work/reserved-input"
mkdir -m 700 "$CHEZ_TESTER_DIR"
printf 'Keep this selected text unchanged.\n' > "$CHEZ_TESTER_DIR/pending.trace"
cp "$CHEZ_TESTER_DIR/pending.trace" "$work/reserved.original"
file_keys "$CHEZ_TESTER_DIR/pending.trace";file_run
grep -q '^status=FAIL$' "$CHEZ_TESTER_DIR/summary.txt"
cmp "$CHEZ_TESTER_DIR/pending.trace" "$work/reserved.original";source_safe
echo 'PASS choosing a managed report as text cannot truncate the chosen file'
export CHEZ_TESTER_DIR="$work/reserved-protocol"
mkdir -m 700 "$CHEZ_TESTER_DIR"
printf 'def main : IO Unit := pure ()\n' > "$CHEZ_TESTER_DIR/summary.txt"
cp "$CHEZ_TESTER_DIR/summary.txt" "$work/protected-protocol.original"
file_keys "$work/chosen text.md"
"$work/pty" "$work/keys" 30 "$work/screen" ./chezemax "$CHEZ_TESTER_DIR/summary.txt"
cmp "$CHEZ_TESTER_DIR/summary.txt" "$work/protected-protocol.original"
grep -aq 'chez-tester FAIL' "$work/screen";source_safe
echo 'PASS report generation cannot truncate the currently visited Lean source file'


sed -e 's/def passes : Nat := 2/def passes : Nat := 1/' \
 -e 's/def keepReference : Bool := false/def keepReference : Bool := true/' \
 "$work/protocol.base" > "$work/protocol.lean"
cp "$work/protocol.lean" "$work/protocol.original"
printf 'αβ🙂\n\nlast' > "$work/tiny.txt"
export CHEZ_TESTER_DIR="$work/file-reference"
file_keys "$work/tiny.txt";file_run
grep -q '^status=PASS$' "$CHEZ_TESTER_DIR/summary.txt"
grep -q '^reference_kept=1$' "$CHEZ_TESTER_DIR/summary.txt";source_safe
"$root/Lean/chez-tester" --check-file "$work/tiny.txt" < "$CHEZ_TESTER_DIR/pending.trace" > "$work/replay"
grep -q '^PASS 12$' "$work/replay"
echo 'PASS selected-file reference trace replays independently against its original bytes'
reject_file_trace() {
 if "$root/Lean/chez-tester" --check-file "$work/tiny.txt" < "$work/bad" > "$work/replay";then echo "FAIL accepted $1";exit 1;fi
 if grep -q '^PASS ' "$work/replay";then echo "FAIL false PASS $1";exit 1;fi
 echo "PASS chosen-file checker rejects $1"
}
trace="$CHEZ_TESTER_DIR/pending.trace"
awk '$1=="S"&&$2==1 {$5=0} {print}' "$trace" > "$work/bad";reject_file_trace 'stalled Enter before EOF'
awk '$1=="S"&&$2==1 {$6++} {print}' "$trace" > "$work/bad";reject_file_trace 'wrong logical line'
awk '$1=="S"&&$2==1 {$5=14;$6=3} {print}' "$trace" > "$work/bad";reject_file_trace 'jump over a logical line'
awk '$1=="S"&&$2==1 {$7=0} {print}' "$trace" > "$work/bad";reject_file_trace 'modified text'
awk '$1=="S"&&$2==1 {$8=1} {print}' "$trace" > "$work/bad";reject_file_trace 'runtime failure'
head -n 2 "$trace" > "$work/bad";printf 'B 1\nZ 1\n' >> "$work/bad";reject_file_trace 'premature completion'
sed '/^Z /d' "$trace" > "$work/bad";reject_file_trace 'truncated run'
