#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
root=$(pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-edit-test.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
cc -O2 tests/pty-keys.c -o "$work/pty"
mkdir "$work/docs"
printf 'αβ🙂 first\r\nsecond line\nlast without newline' > "$work/docs/a.md"
printf 'a\nb\nc\n' > "$work/docs/b.markdown"
cp -R "$work/docs" "$work/original"
sed -e 's/def repetitions : Nat := 1000/def repetitions : Nat := 100/' \
 -e 's/def delayMilliseconds : Nat := 2/def delayMilliseconds : Nat := 0/' Lean/mv-cp-mv-paste-undo.lean > "$work/protocol.lean"
cp "$work/protocol.lean" "$work/protocol.original"
export CHEZEMAX_NO_INIT=1 CHEZEMAX_PROGRAM="$root/chezemax.wasm" CHEZ_TESTER_EXIT=1
unset CHEZ_TESTER_AUTORUN CHEZ_TESTER_KEEP_REFERENCE
printf 'wait 700\nkeys \\exchez-tester\\r\nwait 100\nkeys ^A^K%s\\r\n' "$work/docs" > "$work/keys"
for runtime in compiled femtoscheme;do
 export CHEZEMAX_SCHEME=$runtime CHEZ_TESTER_DIR="$work/$runtime"
 "$work/pty" "$work/keys" 180 /dev/null ./chezemax "$work/protocol.lean"
 grep -q '^status=PASS$' "$CHEZ_TESTER_DIR/summary.txt"
 grep -q '^observations=200$' "$CHEZ_TESTER_DIR/summary.txt"
 grep -q '^ring_peak=60$' "$CHEZ_TESTER_DIR/summary.txt"
 grep -q '^histories_restored=1$' "$CHEZ_TESTER_DIR/summary.txt"
 [ "$(wc -c < "$CHEZ_TESTER_DIR/summary.txt")" -le 4096 ]
 [ ! -s "$CHEZ_TESTER_DIR/pending.trace" ] && [ ! -s "$CHEZ_TESTER_DIR/failure.trace" ]
 cmp "$work/docs/a.md" "$work/original/a.md";cmp "$work/docs/b.markdown" "$work/original/b.markdown"
 cmp "$work/protocol.lean" "$work/protocol.original"
 echo "PASS $runtime: 200 seeded edit cycles, UTF-8, trailing/unterminated lines, exact restoration and bounded histories"
done
# Inject corrupt observations into the pure checker, independently of C.
cat Lean/mv-cp-mv-paste-undo.lean > "$work/faults.lean"
cat >> "$work/faults.lean" <<'LEAN'
namespace EditStress
private def good : Observation := ⟨0,0,4,0,1,1,1,0,1,4,0,1,4,4,1,1,0⟩
example : checkObservation 0 4 good = true := by decide
example : checkObservation 0 4 {good with copied := 0} = false := by decide
example : checkObservation 0 4 {good with pasted := 0} = false := by decide
example : checkObservation 0 4 {good with restored := 0} = false := by decide
example : checkObservation 0 4 {good with home := 1} = false := by decide
example : checkObservation 0 4 {good with ringCount := 61} = false := by decide
example : checkObservation 0 4 {good with ringBytes := 48001} = false := by decide
example : checkObservation 0 4 {good with accounted := 8} = false := by decide
example : checkObservation 0 4 {good with undone := 2} = false := by decide
example : checkObservation 0 4 {good with histories := 2} = false := by decide
example : checkObservation 0 4 {good with error := 1} = false := by decide
end EditStress
LEAN
lean "$work/faults.lean"
echo 'PASS Lean rejects text damage, cursor drift, history growth, accounting drift and runtime failure'
