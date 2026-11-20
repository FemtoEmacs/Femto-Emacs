#!/bin/sh
# C-x C-e in a block of code of an Org or Markdown file: a lone " in the
# prose above the block opened a string that hid the code ("No expression
# before the cursor", 21 Nov 2026).  The scan now starts at the block.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-org-eval.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
cc=${CC:-cc}
$cc -O2 tests/pty-keys.c -o "$work/pty" -lutil 2>/dev/null || $cc -O2 tests/pty-keys.c -o "$work/pty"
mkdir -p "$work/home"
printf '* Title\nHe said "hello.\n#+begin_src Scheme\n(* 6\n   (+ 3 4))\n#+end_src\n' > "$work/t.org"
printf 'He said "hello.\n\n```scheme\n(* 6\n   (+ 3 4))\n```\n' > "$work/t.md"
for f in t.org t.md; do
	cat > "$work/keys" <<'KEYS'
await-screen [SAVE]
keys \eg5\r^E^X^E
await-screen 42
wait 200
keys ^X^C
KEYS
	(cd "$work"; HOME="$work/home" CHEZEMAX_NO_INIT=1 LC_ALL=C.UTF-8 "$work/pty" "$work/keys" 20 "$work/screen" "$root/chezemax" "$f") >/dev/null 2>&1 || true
	if grep -aq 'No expression before' "$work/screen" || ! grep -aq '42' "$work/screen"; then
		echo "FAIL C-x C-e in a block of $f"; exit 1
	fi
done
echo 'PASS C-x C-e evaluates the code of an Org or Markdown block after a lone quote'
