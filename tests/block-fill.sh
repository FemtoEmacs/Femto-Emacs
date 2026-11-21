#!/bin/sh
# M-q in a block comment: Lean's /- -/ and /-- -/, C's /* */.  It answered
# "M-q fills comments and text, not code" inside a Lean comment (Eduardo,
# 21 Nov 2026).  The paragraph is the comment's lines between blank lines;
# the markers stay where they are.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-block-fill.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
cc=${CC:-cc}
$cc -O2 tests/pty-keys.c -o "$work/pty" -lutil 2>/dev/null || $cc -O2 tests/pty-keys.c -o "$work/pty"
mkdir -p "$work/home"

cat > "$work/t.lean" <<'LEAN'
/-- The model follows the C code: prev
size, forward character,
and the
others. -/
def x := 1

/-
A proof fails where the program does not handle a case, and this is how the specification found gaps.
Short line
again.

Second paragraph
here.
-/
  /-- Indented doc: alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu
  nu xi. -/
LEAN
cat > "$work/t.c" <<'C'
/*
 * The tokenizer's state at the end of T: the offset where a string or a
 * comment that is still open there began,
 * or -1 when none is.
 */
  /* One line: alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu */
int x; /* not a comment: "/*" */
C
# M-q from the last line up, so the line numbers above do not move
printf 'await-screen [SAVE]\n' > "$work/keys"
for line in 15 12 9 2; do printf 'keys \\eg%s\\r\\eq\nwait 200\n' $line >> "$work/keys"; done
printf 'keys ^X^S\nwait 300\nkeys ^X^C\n' >> "$work/keys"
(cd "$work"; HOME="$work/home" CHEZEMAX_NO_INIT=1 LC_ALL=C.UTF-8 "$work/pty" "$work/keys" 30 "$work/screen" "$root/chezemax" t.lean) >/dev/null 2>&1
cat > "$work/want.lean" <<'LEAN'
/-- The model follows the C code: prev size, forward character, and
the others. -/
def x := 1

/-
A proof fails where the program does not handle a case, and this is
how the specification found gaps. Short line again.

Second paragraph here.
-/
  /-- Indented doc: alpha beta gamma delta epsilon zeta eta theta iota
  kappa lambda mu nu xi. -/
LEAN
diff "$work/want.lean" "$work/t.lean" || { echo 'FAIL M-q in Lean block comments'; exit 1; }

printf 'await-screen [SAVE]\nkeys \\eg7\\r\\eq\nwait 200\nkeys \\eg6\\r\\eq\nwait 200\nkeys \\eg3\\r\\eq\nwait 200\nkeys ^X^S\nwait 300\nkeys ^X^C\n' > "$work/keys"
(cd "$work"; HOME="$work/home" CHEZEMAX_NO_INIT=1 LC_ALL=C.UTF-8 "$work/pty" "$work/keys" 30 "$work/screen" "$root/chezemax" t.c) >/dev/null 2>&1
cat > "$work/want.c" <<'C'
/*
 * The tokenizer's state at the end of T: the offset where a string or
 * a comment that is still open there began, or -1 when none is.
 */
  /* One line: alpha beta gamma delta epsilon zeta eta theta iota
  kappa lambda mu nu */
int x; /* not a comment: "/*" */
C
diff "$work/want.c" "$work/t.c" || { echo 'FAIL M-q in C block comments'; exit 1; }
echo 'PASS M-q refills the paragraph of a block comment (Lean, C)'
