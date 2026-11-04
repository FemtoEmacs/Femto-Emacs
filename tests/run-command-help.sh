#!/bin/sh
# Help resolves live Scheme bindings and C defaults without invoking either.
set -eu
cd "$(dirname "$0")/.."
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-command-help.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
HOME="$work" CHEZEMAX_NO_INIT=1 ./chezweb --eval '(begin
 (if (not (equal? (list (key-command-name "C-x C-f") (key-command-name "C-h")
                       (mode-line-action-description "C-x C-s"))
                  (list "find-file" "help" "save-buffer (C-x C-s)")))
     (error "Incorrect default command names"))
 (global-set-key "C-x C-s" (quote forward-char))
 (if (not (equal? (mode-line-action-description "C-x C-s") "forward-char (C-x C-s)"))
     (error "Button help ignored a live binding"))
 (let ((text (help-text)))
   (if (not (and (string-search "Command: forward-char" text)
                 (string-search "Command: find-file" text)
                 (string-search "open a file" text)
                 (every (lambda (l) (<= (string-length l) 80)) (split-lines text))))
       (error "Help must contain names and descriptions in readable lines")))
 "command help passed")' > "$work/result"
grep -q 'command help passed' "$work/result"
echo 'PASS command help: native defaults, live rebinding, button descriptions and readable C-h text'
