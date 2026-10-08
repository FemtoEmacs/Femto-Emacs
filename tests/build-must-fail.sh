#!/bin/sh
# build-must-fail.sh -- the release build must stop on a script that does
# not compile.
#
#   sh tests/build-must-fail.sh [sbcl command]      (after make)
#
# SBEMACS_LIB_DIR names the folder of the C libraries when they are not at
# the top of the sources (the Windows installer's build/windows/stage, with
# SBEMACS_WINDOW_APP=1 so that build.lisp takes the window's library).
#
# Copies the sources to a temporary folder, adds a script whose function
# cannot be compiled (an unknown FORMAT directive, as the CR LF line ends
# produced on Windows), runs build.lisp, and checks that the build fails,
# says why, and saves no executable.  Before this was checked, such a build
# succeeded and the error surfaced only when the function ran: C-c g's
# "Execution of a form compiled with errors" on Windows.

set -u
TOP=$(cd "$(dirname "$0")/.." && pwd)
SBCL=${1:-sbcl}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cp -R "$TOP/lisp" "$TOP/build.lisp" "$TMP/"
LIBDIR=${SBEMACS_LIB_DIR:-$TOP}
cp "$LIBDIR"/libsbemacs-term.* "$TMP/" 2>/dev/null
cp "$LIBDIR"/libsbemacs-gui.* "$TMP/" 2>/dev/null
cp "$LIBDIR"/SDL2*.dll "$TMP/" 2>/dev/null      # what the window's library needs
cat > "$TMP/lisp/extensions/zz-broken-on-purpose.lisp" <<'EOF'
(in-package #:sbemacs)
(defun broken-on-purpose () (format nil "~Q"))
EOF

cd "$TMP"
$SBCL --noinform --non-interactive --no-sysinit --no-userinit --load build.lisp > build.log 2>&1
status=$?

if [ $status -eq 0 ]; then
    echo "FAIL: the build succeeded with a script that does not compile"; exit 1
fi
if ls sbemacs sbemacs.exe >/dev/null 2>&1; then
    echo "FAIL: the build saved an executable"; exit 1
fi
if ! grep -q "zz-broken-on-purpose.lisp does not compile" build.log ||
   ! grep -q "Unknown directive" build.log; then
    echo "FAIL: the build failed without saying why:"; tail -20 build.log; exit 1
fi
echo "ok: the build stops on a script that does not compile, and says why:"
grep -A3 "does not compile" build.log | head -4
