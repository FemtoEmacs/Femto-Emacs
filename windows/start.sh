#!/bin/bash
# Executed inside the bundled POSIX environment, never a login shell.
set -eu
script=${BASH_SOURCE[0]}
root=$(cd -- "${script%/*}/.." && pwd -P)
# //bin is a UNC server path on Cygwin, not a synonym for /bin.
root=${root%/}
export PATH="$root/bin:$root/app:$PATH"
export HOME=$(cygpath -u "$USERPROFILE")
export TMPDIR="$root/tmp" TERM=xterm-256color LANG=C.UTF-8
mkdir -p "$TMPDIR"
editor=chezweb.exe
if [ "${1:-}" = --gui ]; then editor=chezweb-gui.exe; shift; fi
# Preserve the caller's directory and quote every filename argument.
if [ "$#" -eq 0 ]; then cd "$HOME"; fi
exec "$root/app/$editor" "$@"
