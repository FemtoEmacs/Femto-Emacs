#!/bin/sh
# Native terminal editor; C-c d opens Chrome without closing this window.
set -eu
cd "$(dirname "$0")"
if [ ! -x ./chezweb ]; then make; fi
exec ./chezweb "$@"
