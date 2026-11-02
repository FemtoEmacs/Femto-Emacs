#!/bin/sh
# Verify native PDF rendering and provider attachment protocols, offline.
# Run from make check-ui. No live provider is contacted.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
[ "$(uname -s)" = Darwin ] || { echo 'SKIP: native PDF renderer is macOS-only'; exit 0; }
[ -f "$root/ttfy/benedetto.pdf" ] || { echo 'SKIP: the seven-page fixture ttfy/benedetto.pdf is missing'; exit 0; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
cat > "$tmp/provider" <<'PROVIDER'
#!/bin/sh
printf '%s\n' "$@" > "$TTFY_TEST_ARGS"
cat > "$TTFY_TEST_PROMPT"
out=
while [ "$#" -gt 0 ]; do
 if [ "$1" = --output-last-message ]; then shift; out=$1; fi
 shift
done
if [ -n "$out" ]; then
 printf '# Test conversion\n\nRendered PDF inspected by mock provider.\n' > "$out"
else
 printf '# Test conversion\n\nRendered PDF inspected by mock provider.\n'
fi
PROVIDER
chmod +x "$tmp/provider"
export TTFY_TEST_ARGS="$tmp/args" TTFY_TEST_PROMPT="$tmp/prompt"
cd "$root"
SBEMACS_CODEX="$tmp/provider" ./chezemax --eval '(ttfy-request "codex" "ttfy/benedetto.pdf" "" (ttfy-read-guidelines))' | grep 'Test conversion'
[ "$(grep -c '^-i$' "$tmp/args")" -eq 7 ]
grep 'read-only' "$tmp/args"
grep 'Selected PDF pages: 1-7' "$tmp/prompt"
grep 'Kaplan-Meier' "$tmp/prompt" > /dev/null
image=$(awk 'seen {print;exit} $0=="-i" {seen=1}' "$tmp/args")
[ -s "$image" ]
SBEMACS_CLAUDE="$tmp/provider" ./chezemax --eval '(ttfy-request "claude" "ttfy/benedetto.pdf" "3-4" (ttfy-read-guidelines))' | grep 'Test conversion'
grep -- '--allowedTools' "$tmp/args"
grep '^Read$' "$tmp/args" > /dev/null
grep 'Selected PDF pages: 3-4' "$tmp/prompt"
./chezemax --eval '(ttfy-request "codex" "ttfy/benedetto.pdf" "8-9" "rules")' | grep 'Invalid page range'
./chezemax --eval '(ttfy-request "codex" "/nonexistent/file.pdf" "" "rules")' | grep 'cannot read PDF'
SBEMACS_CODEX=/usr/bin/false ./chezemax --eval '(ttfy-request "codex" "ttfy/benedetto.pdf" "1" "rules")' | grep 'Diagnostics:'
echo 'PASS: seven rendered pages, Codex images, Claude Read, ranges and failures'
