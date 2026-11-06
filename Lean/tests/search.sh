#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
root=$(pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-search-test.XXXXXX")
trap 'status=$?; if [ "$status" -ne 0 ]; then
 for runtime in compiled femtoscheme; do
  for name in summary.txt pending.trace failure.trace; do
   if [ -f "$work/$runtime/$name" ]; then cat "$work/$runtime/$name" >&2; fi
  done
 done
 fi; rm -rf "$work"' EXIT HUP INT TERM
cc -O2 tests/pty-keys.c -o "$work/pty"
mkdir "$work/docs"
printf 'αβ🙂 café\r\nrepeat repeat repeat\nlast without newline' > "$work/docs/a.md"
printf 'a\nb\nc\n' > "$work/docs/b.markdown"
printf '🙂🙂🙂🙂🙂🙂🙂🙂\n' > "$work/docs/unicode.md"
: > "$work/docs/empty.md"
printf '\n\r\n\t\n' > "$work/docs/controls.md"
cp -R "$work/docs" "$work/original"
sed -e 's/def repetitions : Nat := 1000/def repetitions : Nat := 120/' \
 -e 's/def delayMilliseconds : Nat := 2/def delayMilliseconds : Nat := 0/' Lean/search-return.lean > "$work/protocol.lean"
cp "$work/protocol.lean" "$work/protocol.original"
export CHEZEMAX_NO_INIT=1 CHEZEMAX_PROGRAM="$root/chezemax.wasm" CHEZ_TESTER_EXIT=1
unset CHEZ_TESTER_AUTORUN CHEZ_TESTER_KEEP_REFERENCE
printf 'wait 700\nkeys \\exchez-tester\\r\nwait 100\nkeys ^A^K%s\\r\n' "$work/docs" > "$work/keys"
for runtime in compiled femtoscheme; do
 export CHEZEMAX_SCHEME=$runtime CHEZ_TESTER_DIR="$work/$runtime"
 "$work/pty" "$work/keys" 180 /dev/null ./chezemax "$work/protocol.lean"
 report="$CHEZ_TESTER_DIR/summary.txt"
 grep -q '^status=PASS$' "$report"
 grep -q '^protocol=search-return$' "$report"
 grep -q '^observations=600$' "$report"
 grep -q '^acknowledged=600$' "$report"
 grep -q '^ring_peak=1$' "$report"
 grep -q '^undo_live_bytes_peak=[1-9][0-9]*$' "$report"
 grep -q '^histories_restored=1$' "$report"
 grep -q '^search_state_restored=1$' "$report"
 grep -q '^search_bytes_peak=32$' "$report"
 grep -q '^search_capacity=64$' "$report"
 [ "$(wc -c < "$report")" -le 4096 ]
 [ ! -s "$CHEZ_TESTER_DIR/pending.trace" ] && [ ! -s "$CHEZ_TESTER_DIR/failure.trace" ]
 diff -r "$work/docs" "$work/original"
 cmp "$work/protocol.lean" "$work/protocol.original"
 echo "PASS $runtime: 600 search-return cycles, Unicode/CRLF/empty files, matches/misses, unchanged histories and source files"
done
cat Lean/search-return.lean > "$work/faults.lean"
cat >> "$work/faults.lean" <<'LEAN'
namespace SearchReturn
private def good : Observation := ⟨0,4,1,1,1,2,1,1,4,0⟩
example : checkObservation 0 4 1 2 4 good = true := by decide
example : checkObservation 0 4 1 2 4 {good with point := 3} = false := by decide
example : checkObservation 0 4 1 2 4 {good with matched := 0} = false := by decide
example : checkObservation 0 4 1 2 4 {good with textSame := 0} = false := by decide
example : checkObservation 0 4 1 2 4 {good with dirtySame := 0} = false := by decide
example : checkObservation 0 4 1 2 4 {good with returned := 1} = false := by decide
example : checkObservation 0 4 1 2 4 {good with historySame := 0} = false := by decide
example : checkObservation 0 4 1 2 4 {good with querySame := 0} = false := by decide
example : checkObservation 0 4 1 2 4 {good with queryBytes := 33} = false := by decide
example : checkObservation 0 4 1 2 4 {good with error := 1} = false := by decide
end SearchReturn
LEAN
lean "$work/faults.lean"
echo 'PASS Lean rejects wrong matches, cursor drift, text/dirty changes, history changes, query corruption and runtime errors'
