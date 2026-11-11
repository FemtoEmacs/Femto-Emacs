#!/bin/sh
# Publish the current master without rewriting history. Only on user request.
set -eu
cd "$(dirname "$0")/.."
origin_url=$(git remote get-url origin)
[ "${origin_url%.git}" = https://github.com/FemtoEmacs/Femto-Emacs ] || { echo 'Unexpected publishing repository' >&2;exit 1; }
# An independent checkout keeps platform work away from local documents.
if [ "${1:-}" = --windows-checkout ]; then
 [ "$#" -eq 2 ] || { echo 'Supply an empty destination path' >&2;exit 1; }
 source_root=$(pwd)
 git clone --shared --no-checkout "$source_root" "$2"
 git -C "$2" fetch "$source_root" refs/remotes/origin/windows:refs/remotes/origin/windows
 git -C "$2" switch --create windows --track origin/windows
 git -C "$2" remote set-url origin "$origin_url"
 for field in user.name user.email; do
  value=$(git config "$field" || true)
  [ -z "$value" ] || git -C "$2" config "$field" "$value"
 done
 exit
fi
if [ "${1:-}" = --delete-codemax ]; then
 [ "$#" -eq 2 ] || { echo 'Supply the verified codemax SHA' >&2;exit 1; }
 expected=$2
 current=$(git ls-remote --heads origin refs/heads/codemax | awk '{print $1}')
 [ "$current" = "$expected" ] || { echo 'codemax changed; re-inspect before deleting' >&2;exit 1; }
 # Retain its final commit in this local clone before removing the remote branch.
 if ! git show-ref --verify --quiet refs/heads/archive/codemax-before-migration; then
  git branch archive/codemax-before-migration "$expected"
 fi
 git push origin --delete codemax
 exit
fi
if [ "${1:-}" = --windows ]; then
 [ "$#" -eq 1 ] && [ "$(git branch --show-current)" = windows ] || exit 1
 if [ -s git/next-commit.txt ]; then sh git/gitcommit.sh; fi
 # The old Windows tip is a merge parent: publication is a fast-forward.
 git push -u origin windows
 exit
fi
[ "$#" -eq 0 ] || { echo 'Unsupported publishing option' >&2;exit 1; }
[ "$(git branch --show-current)" = master ] || { echo 'This publisher expects master' >&2;exit 1; }
if [ -s git/next-commit.txt ]; then sh git/gitcommit.sh; fi
git push origin master
