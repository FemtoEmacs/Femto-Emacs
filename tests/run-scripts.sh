#!/bin/sh
# run-scripts.sh -- make check-scripts: the scripts' own procedures, case by
# case (tests/scripts-cases.scm), compiled with the scripts into one
# program and run at the key C-c 9, against the answers recorded in
# tests/scripts-expected.txt.  Those were femtoscheme's, from the scripts of
# scheme/, when both runtimes still ran them (27 November 2026, the last
# commit with femtoscheme): the compiled scripts gave the same, case by
# case, and must go on giving them.  A case whose answer changes on
# purpose is changed there too, with the reason in the commit.
#
#   KEEP=1 sh tests/run-scripts.sh     keeps the work folder
set -eu
cd "$(dirname "$0")/.."
work=$(mktemp -d "${TMPDIR:-/tmp}/chezemax-scripts.XXXXXX")
trap '[ -n "${KEEP:-}" ] || rm -rf "$work"' EXIT HUP INT TERM
sh tools/build-program.sh "$work/scripts.wasm" compiled/bridge.scm compiled/editor-functions.scm \
   compiled/system.scm compiled/syntax.scm compiled/compat.scm compiled/editor.scm \
   $(cat compiled/scripts/ORDER) compiled/eval-compiled.scm \
   tests/scripts-compiled.scm tests/scripts-cases.scm
CHEZEMAX_REPORT="$work/c" CHEZEMAX_PROGRAM="$work/scripts.wasm" CHEZEMAX_NO_INIT=1 \
  ./chezemax --test event key "C-c 9" > "$work/out" 2>&1 || { cat "$work/out"; echo "FAIL the cases did not run"; exit 1; }
[ -s "$work/c" ] || { echo "FAIL no report of the cases"; exit 1; }
# Three answers depend on the machine, not on the scripts: where sh is
# (/usr/bin/sh on Linux, /bin/sh on macOS), the temporary folder (TMPDIR)
# and what pwd prints in /tmp (/private/tmp on macOS).  They are recorded
# as SH, TMP and SLASH-TMP, and this machine's values are named so here.
sh_path=$(command -v sh)
tmp=${TMPDIR:-/tmp}; tmp=${tmp%/}
slash_tmp=$(cd /tmp && pwd -P)
SH_PATH=$sh_path TMP_PATH=$tmp SLASH_TMP=$slash_tmp awk '
    function swap(s, from, to,   i) {
        i = index(s, from)
        return i ? substr(s, 1, i - 1) to substr(s, i + length(from)) : s
    }
    BEGIN { q = "\""; bs = "\\" }
    /^"programs" / { $0 = swap($0, q ENVIRON["SH_PATH"] q, q "SH" q)
                     $0 = swap($0, q ENVIRON["TMP_PATH"] q, q "TMP" q) }
    /^"shell runs" / { $0 = swap($0, q ENVIRON["SLASH_TMP"] bs "n", q "SLASH-TMP" bs "n") }
    { print }' "$work/c" > "$work/c.named"
mv "$work/c.named" "$work/c"
if ! cmp -s tests/scripts-expected.txt "$work/c"; then
    echo "FAIL the compiled scripts differ from the answers recorded (< recorded, > now):"
    diff tests/scripts-expected.txt "$work/c" || true
    exit 1
fi
echo "ok    $(grep -c . "$work/c") cases give the answers recorded"
echo "PASS the compiled scripts: $(sed 's|.*/||' compiled/scripts/ORDER | tr '\n' ' ')"
