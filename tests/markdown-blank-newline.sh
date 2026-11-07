#!/bin/sh
# Real RET: blank prose stays blank; lists and fenced code retain their rules.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-markdown-blank.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
cc=${CC:-cc}
$cc -O2 tests/pty-keys.c -o "$work/pty" -lutil 2>/dev/null ||
 $cc -O2 tests/pty-keys.c -o "$work/pty"
run_case() {
 name=$1
 printf '%b' "$2" > "$work/$name.md"
 printf '%b' "$3" > "$work/expected"
 cat > "$work/keys" <<'KEYS'
await-screen [SAVE]
keys \e>
KEYS
 i=0
 while [ "$i" -lt "$4" ]; do printf 'keys \\r\n' >> "$work/keys";i=$((i+1));done
 cat >> "$work/keys" <<'KEYS'
keys ^X^S
wait 150
keys ^X^C
KEYS
 (cd "$work"; CHEZEMAX_NO_INIT=1 CHEZEMAX_SCHEME=$runtime "$work/pty" "$work/keys" 30 "$work/screen" "$root/chezemax" "$name.md")
 cmp "$work/$name.md" "$work/expected"
 echo "PASS $runtime Markdown RET: $name"
}
for runtime in compiled femtoscheme; do
 run_case prose-blank '3. **Heading**\n   Paragraph.\n\n' '3. **Heading**\n   Paragraph.\n\n\n\n' 2
 run_case indented-blank '3. **Heading**\n   Paragraph.\n   ' '3. **Heading**\n   Paragraph.\n\n\n' 2
 run_case continue-item '- item' '- item\n- ' 1
 run_case end-item '- item\n- ' '- item\n\n' 1
 run_case code-blank '```\n    code\n    ' '```\n    code\n\n    ' 1
done
