#!/bin/sh
# C-M-f and C-M-b over one long list (20 November 2026): over the module
# of a 9.7 MB .wat file they took 42 and 53 seconds; Emacs is instant.
# Each byte cost a bridge call (fe-char-at) and two string-index calls;
# the scanners now read 64 KB blocks (buffer-reader) and test bytes with
# plain comparisons (emacs-keys.scm).  Here: a 2.8 MB list, C-M-f from its
# start lands after its end and C-M-b comes back, each within 6 seconds
# (under a second now); the backdoor gives the times.  Disposable file and PTY.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-sexp-speed.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
cc=${CC:-cc}
$cc -O2 tests/pty-keys.c -o "$work/pty" -lutil 2>/dev/null ||
 $cc -O2 tests/pty-keys.c -o "$work/pty"
mkdir -p "$work/home/.chezemax"
printf 'time\nrepeats keep\nwatch point\n' > "$work/home/.chezemax/backdoor-claude.conf"
# (module, then 32768 functions with a string holding \" and (, then ): 2.8 MB
printf '  (func $f (param i32) (result i32) (i32.add (local.get 0) (i32.const 1)) "a \\"b\\" ( c")\n' > "$work/line"
i=0; while [ $i -lt 15 ]; do cat "$work/line" "$work/line" > "$work/l2"; mv "$work/l2" "$work/line"; i=$((i + 1)); done
{ printf '(module\n'; cat "$work/line"; printf ')\n'; } > "$work/m.wat"
size=$(wc -c < "$work/m.wat")
cat > "$work/keys" <<'EOF'
await-screen [SAVE]
keys \exbackdoor-claude\r
wait 300
keys \e^F
wait 300
keys \e^B
wait 300
keys \exbackdoor-claude\r
wait 300
keys ^X^C
EOF
(cd "$work"; HOME="$work/home" CHEZEMAX_NO_INIT=1 LC_ALL=C.UTF-8 "$work/pty" "$work/keys" 120 "$work/screen" "$root/chezemax" m.wat)
log="$work/home/.chezemax/backdoor.txt"
fail() { echo "FAIL $1"; grep -a '^#' "$log" || true; exit 1; }
f=$(grep -a '^#[0-9]* esc C-f ' "$log") || fail 'no C-M-f in the record'
b=$(grep -a '^#[0-9]* esc C-b ' "$log") || fail 'no C-M-b in the record'
echo "$f" | grep -q " pt=$((size - 1)) " || fail "C-M-f did not land after the list (at $((size - 1)))"
echo "$b" | grep -q ' pt=0 ' || fail 'C-M-b did not come back to the start'
ms() { echo "$1" | sed 's/.*command \([0-9]*\)\..*/\1/'; }
[ "$(ms "$f")" -lt 6000 ] && [ "$(ms "$b")" -lt 6000 ] || fail 'C-M-f or C-M-b took 6 seconds or more'
echo "PASS C-M-f and C-M-b over a list of $((size / 1024)) KB: $(ms "$f") and $(ms "$b") ms"
