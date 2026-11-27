#!/bin/sh
# run-bridge.sh -- make check-bridge: compiled Scheme and the C core
set -eu
cd "$(dirname "$0")/.."
work=$(mktemp -d "${TMPDIR:-/tmp}/chezemax-bridge.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
# 1. the bridge alone: both directions, errors, nesting, sizes, speed
cat compiled/bridge.scm tests/bridge-test.scm > "$work/bridge-test.scm"
./schemer-compile --source --strict "$work/bridge-test.scm" "$work/bridge-test.wasm" "$(pwd)"
./tests/bridge-test "$work/bridge-test.wasm"
# 2. in the editor: a key bound in compiled Scheme calls the C core
sh tools/build-program.sh "$work/editor.wasm" compiled/bridge.scm compiled/editor-functions.scm \
   compiled/editor.scm tests/compiled-editor.scm
# each step of chezemax --test calls a hook as the C core does (test-hooks.c)
run() { CHEZEMAX_PROGRAM="$work/editor.wasm" CHEZEMAX_NO_INIT=1 ./chezemax --test "$@" 2>/dev/null; }
check() { if [ "$2" = "$3" ]; then echo "ok    $1"; else echo "FAIL  $1: got $2, expected $3"; exit 1; fi; }
check "the compiled program is running" "$(run status)" '"running"'
check "a compiled key inserts through the C core" \
      "$(run event key "C-c 9" text | tail -1)" '"compiled ✓ *scratch*"'
check "an unbound key is left to the C core" "$(run event key "C-c 7")" '#f'
check "a failing compiled command is handled, the editor goes on" "$(run event key "C-c 8")" '#t'
check "colours: a compiled highlighter" "$(run highlight a.shout "ab!")" '(5 5 4)'
check "colours: another file is not coloured there" "$(run highlight a.txt "ab!")" '#f'
check "mode line: compiled" "$(run mode-line special f 80)" "\"$(printf '0\0370\037')compiled: special L. 1\""
check "mode line: another buffer is not written there" "$(run mode-line other f 80)" '#f'
check "undo: recorded in compiled Scheme" "$(run change 1 record-me)" '#t'
check "undo: not recorded there" "$(run change 1 ação)" '#f'
check "word wrap: does the file wrap?" "$(run wrap a.wrap - 10)" '-1'
check "word wrap: bytes in the row" "$(run wrap a.wrap "hello world, again" 10)" '10'
check "word wrap: another file does not wrap there" "$(run wrap a.md - 10)" '#f'
# the editor's own program registers none of these yet: they cost nothing
sh tools/build-program.sh "$work/plain.wasm" compiled/bridge.scm compiled/editor-functions.scm compiled/editor.scm
plain() { CHEZEMAX_PROGRAM="$work/plain.wasm" CHEZEMAX_NO_INIT=1 ./chezemax --test "$@" 2>/dev/null; }
check "unregistered hooks are not called" \
      "$(plain highlight a.shout a mode-line special f 80 change 1 x wrap a.wrap - 10 | tr '\n' ' ')" '#f #f #f #f '
CHEZEMAX_PROGRAM= CHEZEMAX_NO_INIT=1 ./chezemax --test status | grep -q 'no compiled program'
echo "ok    CHEZEMAX_PROGRAM= runs without one"
CHEZEMAX_PROGRAM= CHEZEMAX_NO_INIT=1 ./chezemax --eval 1 2> "$work/err" && { echo "FAIL the editor ran without its scripts"; exit 1; }
grep -q 'the compiled scripts did not start' "$work/err" || { echo "FAIL no word of the missing scripts"; cat "$work/err"; exit 1; }
echo "ok    without the compiled scripts the editor says why and stops"
# 3. the C functions beyond src/editor-functions.def (compiled/system.scm),
# each answering as femtoscheme's builtin of the same name did
sh tools/build-program.sh "$work/system.wasm" compiled/bridge.scm compiled/editor-functions.scm \
   compiled/system.scm compiled/editor.scm tests/compiled-system.scm
got=$(CHEZEMAX_PROGRAM="$work/system.wasm" CHEZEMAX_NO_INIT=1 ./chezemax --test event key "C-c s" text 2>/dev/null | tail -1)
os=$(uname -s | tr 'A-Z' 'a-z')
expected="\"xy\\\"$os\\\"\\n(#t #f)\\n#t\\n#f\\n#t\\n(\\\"hello world\\\\n\\\" \\\"\\\" 0)\\n(\\\"piped\\\" \\\"\\\" 0)\\n\\\"v1\\\"\\n#f\\n#t\\n#t\\n\\\"abc\\\"\\n(1 4 4 4 4 4 4 1 5 1 1 7 7 7)\\n((14 18 \\\"scheme\\\"))\\n\\\"xy\\\"\\n16\\n#t\\n#t\\n(#f #f)\\n\""
check "files, programs, the system, highlighters" "$got" "$expected"
echo "PASS bridge between compiled Scheme and the C core"
