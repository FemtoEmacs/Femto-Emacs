#!/bin/sh
# Record the current state of Chezemax in git (on this computer only).
#
#   sh git/gitcommit.sh
#
# The first time, it creates the repository.  The commit message is the
# text of git/next-commit.txt (written by the AI that made the change);
# the file is emptied after the commit.  Nothing is sent to GitHub.
set -e
cd "$(dirname "$0")/.."
if [ ! -d .git ]; then
	echo "Creating the git repository in $(pwd)"
	git init -q -b master
fi
if [ ! -s git/next-commit.txt ]; then
	echo "git/next-commit.txt is empty: nothing to describe the commit with."
	echo "Ask the AI to write it, then run this again."
	exit 1
fi
git add -A
if git diff --cached --quiet; then
	echo "Nothing changed since the last commit."
	exit 0
fi
git commit -q -F git/next-commit.txt
: > git/next-commit.txt
echo "Committed:"
git log --oneline -1
