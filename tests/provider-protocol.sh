#!/bin/sh
# Local provider protocol tests; never contacts an external service.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
cat > "$tmp/claude" <<'PROVIDER'
#!/bin/sh
cat > "$SBEMACS_TEST_PROMPT"
printf '%s\n' 'Verified Claude protocol.'
PROVIDER
cat > "$tmp/codex" <<'PROVIDER'
#!/bin/sh
out=
while [ "$#" -gt 0 ]; do
 if [ "$1" = --output-last-message ]; then shift; out=$1; fi
 shift
done
cat > "$SBEMACS_TEST_PROMPT"
printf '%s\n' 'Verified Codex protocol.' > "$out"
PROVIDER
chmod +x "$tmp/claude" "$tmp/codex"
export SBEMACS_TEST_PROMPT="$tmp/prompt"
SBEMACS_CLAUDE="$tmp/claude" "$root/chezemax" --eval '(assistant-request "claude" "question alpha")' | grep 'Verified Claude protocol'
printf '%s' 'question alpha' > "$tmp/expected"
cmp "$tmp/expected" "$tmp/prompt"
SBEMACS_CODEX="$tmp/codex" "$root/chezemax" --eval '(assistant-request "codex" "question beta")' | grep 'Verified Codex protocol'
printf '%s' 'question beta' > "$tmp/expected"
cmp "$tmp/expected" "$tmp/prompt"
SBEMACS_CLAUDE=/usr/bin/false "$root/chezemax" --eval '(assistant-request "claude" "failure test")' | grep 'Assistant failed'
echo 'PASS: Claude and Codex protocol, exact request bytes, provider failure reporting'

# The editor's assistants (scheme/extensions/assistant.scm, codex.scm): the
# arguments that keep Claude without tools and Codex read-only, the context
# on standard input, and the answer from standard output.
cat > "$tmp/claude2" <<'PROVIDER'
#!/bin/sh
printf '%s\n' "$@" > "$SBEMACS_TEST_ARGS"
cat > "$SBEMACS_TEST_PROMPT"
printf '%s\n' 'Claude answer.'
PROVIDER
cat > "$tmp/codex2" <<'PROVIDER'
#!/bin/sh
printf '%s\n' "$@" > "$SBEMACS_TEST_ARGS"
cat > "$SBEMACS_TEST_PROMPT"
printf '%s\n' 'Codex answer.'
PROVIDER
chmod +x "$tmp/claude2" "$tmp/codex2"
export SBEMACS_TEST_ARGS="$tmp/args"
CHEZEMAX_CLAUDE="$tmp/claude2" "$root/chezemax" --eval '(claude-cli-ask "Why?" "CONTEXT-1")' | grep 'Claude answer'
grep -x -- '--tools' "$tmp/args" > /dev/null
grep -x -- '--no-session-persistence' "$tmp/args" > /dev/null
grep -x 'Why?' "$tmp/args" > /dev/null
grep 'CONTEXT-1' "$tmp/prompt" > /dev/null
CHEZEMAX_CODEX="$tmp/codex2" "$root/chezemax" --eval '(codex-cli-ask "Translate" "CONTEXT-2")' | grep 'Codex answer'
grep -x 'read-only' "$tmp/args" > /dev/null
grep -x -- '--ephemeral' "$tmp/args" > /dev/null
grep 'USER REQUEST' "$tmp/prompt" > /dev/null
grep 'CONTEXT-2' "$tmp/prompt" > /dev/null
CHEZEMAX_CLAUDE=/usr/bin/false "$root/chezemax" --eval '(guard (e (#t (describe-error e))) (claude-cli-ask "Q" "C"))' | grep 'claude exited with code 1'
echo 'PASS: editor assistants: Claude without tools, Codex read-only, context on stdin'
