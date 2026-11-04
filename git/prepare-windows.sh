#!/bin/sh
# Preserve local work and old Windows history before developing its replacement.
set -eu
cd "$(dirname "$0")/.."
[ "$(git branch --show-current)" = master ] || { echo 'Expected master'; exit 1; }
sh git/gitcommit.sh
git fetch origin master windows
old=$(git rev-parse origin/windows)
git branch archive/windows-before-chezweb "$old"
# Include remote master fixes without rewriting the local work.
git merge --no-edit origin/master
git switch -c windows
# Keep the old Windows implementation recoverable in this branch's history.
git merge -s ours --no-edit --allow-unrelated-histories "$old" -m "Replace SBEmacs Windows tree with Chezweb, retaining the old installer history"
