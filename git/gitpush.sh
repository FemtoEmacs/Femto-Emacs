#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
[ "$(git branch --show-current)" = legacy ]
[ "$(git remote get-url origin)" = https://github.com/FemtoEmacs/Femto-Emacs.git ]
git push origin legacy
