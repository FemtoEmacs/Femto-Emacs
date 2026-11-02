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
run() { CHEZEMAX_PROGRAM="$work/editor.wasm" CHEZEMAX_SCHEME=legacy CHEZEMAX_NO_INIT=1 ./chezemax --eval "$1"; }
check() { if [ "$2" = "$3" ]; then echo "ok    $1"; else echo "FAIL  $1: got $2, expected $3"; exit 1; fi; }
check "the compiled program is running" "$(run '(fe-compiled-status)')" '"running"'
check "a compiled key inserts through the C core" \
      "$(run '(begin (fe-compiled-event "key" "C-c 9") (buffer-substring 0 (buffer-size)))')" '"compiled ✓ *scratch*"'
check "an unbound key goes on to the scripts" "$(run '(fe-compiled-event "key" "C-c 7")')" '#f'
check "a failing compiled command is handled, the editor goes on" "$(run '(fe-compiled-event "key" "C-c 8")')" '#t'
check "colours: a compiled highlighter" "$(run '(fe-compiled-highlight "a.shout" "" "ab!")')" '(5 5 4)'
check "colours: another file goes on to the scripts" "$(run '(fe-compiled-highlight "a.txt" "" "ab!")')" '#f'
check "mode line: compiled" "$(run '(fe-compiled-mode-line "special" "f" 80)')" '"0\x1f;0\x1f;compiled: special L. 1"'
check "mode line: another buffer goes on to the scripts" "$(run '(fe-compiled-mode-line "other" "f" 80)')" '#f'
check "undo: recorded in compiled Scheme" "$(run '(fe-compiled-change 1 "record-me")')" '#t'
check "undo: not recorded there goes on to the scripts" "$(run '(fe-compiled-change 1 "ação")')" '#f'
check "word wrap: does the file wrap?" "$(run '(fe-compiled-wrap "a.wrap" #f 10)')" '-1'
check "word wrap: bytes in the row" "$(run '(fe-compiled-wrap "a.wrap" "hello world, again" 10)')" '10'
check "word wrap: another file goes on to the scripts" "$(run '(fe-compiled-wrap "a.md" #f 10)')" '#f'
# the editor's own program registers none of these yet: they cost nothing
sh tools/build-program.sh "$work/plain.wasm" compiled/bridge.scm compiled/editor-functions.scm compiled/editor.scm
plain() { CHEZEMAX_PROGRAM="$work/plain.wasm" CHEZEMAX_SCHEME=legacy CHEZEMAX_NO_INIT=1 ./chezemax --eval "$1"; }
check "unregistered hooks are not called" \
      "$(plain '(list (fe-compiled-highlight "a.shout" "" "a") (fe-compiled-mode-line "special" "f" 80) (fe-compiled-change 1 "x") (fe-compiled-wrap "a.wrap" #f 10))')" '(#f #f #f #f)'
CHEZEMAX_PROGRAM= CHEZEMAX_SCHEME=legacy CHEZEMAX_NO_INIT=1 ./chezemax --eval '(fe-compiled-status)' | grep -q 'no compiled program'
echo "ok    CHEZEMAX_PROGRAM= runs without one"
# 3. the C functions beyond native.c's table (compiled/system.scm), each
# answering as femtoscheme's builtin of the same name
sh tools/build-program.sh "$work/system.wasm" compiled/bridge.scm compiled/editor-functions.scm \
   compiled/system.scm compiled/editor.scm tests/compiled-system.scm
got=$(CHEZEMAX_PROGRAM="$work/system.wasm" CHEZEMAX_SCHEME=legacy CHEZEMAX_NO_INIT=1 ./chezemax --eval \
      '(begin (fe-compiled-event "key" "C-c s") (buffer-substring 0 (buffer-size)))')
os=$(uname -s | tr 'A-Z' 'a-z')
expected="\"xy\\\"$os\\\"\\n(#t #f)\\n#t\\n#f\\n#t\\n(\\\"hello world\\\\n\\\" \\\"\\\" 0)\\n(\\\"piped\\\" \\\"\\\" 0)\\n\\\"v1\\\"\\n#f\\n#t\\n#t\\n\\\"abc\\\"\\n(1 4 4 4 4 4 4 1 5 1 1 7 7 7)\\n((14 18 \\\"scheme\\\"))\\n\\\"xy\\\"\\n16\\n#t\\n#t\\n(#f #f)\\n\""
check "files, programs, the system, highlighters" "$got" "$expected"
femto=$(CHEZEMAX_SCHEME=legacy CHEZEMAX_NO_INIT=1 ./chezemax --eval \
  '(let* ((id (fe-define-token-language "-" (list ";") (list (cons "#|" "|#")) (list "\"") 92 #f #f #f (list "define"))) (colors (make-colors 14))) (fe-highlight-tokens id "(define x) ; c" colors) (let loop ((i 0) (acc (list))) (if (= i 14) (reverse acc) (loop (+ i 1) (cons (aref colors i) acc)))))')
check "the same colours as femtoscheme's builtin" "$femto" '(1 4 4 4 4 4 4 1 5 1 1 7 7 7)'
echo "PASS bridge between compiled Scheme and the C core"
