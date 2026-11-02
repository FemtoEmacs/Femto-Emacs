#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
[ "$(git branch --show-current)" = legacy ]
git add -A
git commit -F git/next-commit.txt
