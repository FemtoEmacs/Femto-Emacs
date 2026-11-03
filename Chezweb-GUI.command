#!/bin/sh
set -eu
cd "$(dirname "$0")"
if [ ! -x ./chezweb-gui ]; then make chezweb-gui; fi
exec ./chezweb-gui "$@"
