#!/bin/sh
# Rebuild femtoscheme.boot from system.scm, compiler.scm and r7rs.scm.
set -e
cd "$(dirname "$0")"
cp femtoscheme.boot femtoscheme.boot.bak

echo "Creating stage 0 boot file..."
./femtoscheme mkboot0.scm system.scm compiler.scm > femtoscheme.boot.new
mv femtoscheme.boot.new femtoscheme.boot

echo "Creating stage 1 boot file..."
./femtoscheme mkboot1.scm

echo "Testing..."
make test
