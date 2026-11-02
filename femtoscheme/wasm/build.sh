#!/bin/sh
# Build femtoscheme.js: the interpreter, compiled to WebAssembly, with its
# boot image, in one JavaScript file (the WebAssembly is embedded).
# Requires Emscripten (macOS: brew install emscripten).
set -eu
cd "$(dirname "$0")"
OUT=${1:-femtoscheme.js}
LLT="bitvector.c hashing.c socket.c timefuncs.c ptrhash.c utf8.c ios.c dirpath.c
     htable.c bitvector-ops.c int2str.c dump.c random.c lltinit.c"
SRCS="../flisp.c ../builtins.c ../string.c ../equalhash.c ../table.c ../iostream.c fsweb.c"
for f in $LLT; do SRCS="$SRCS ../llt/$f"; done

# Emscripten renamed TOTAL_STACK to STACK_SIZE in 3.1.27.
VERSION=$(emcc -dumpversion)
STACK=STACK_SIZE
case "$VERSION" in
  1.*|2.*|3.0.*|3.1.[0-9]|3.1.1[0-9]|3.1.2[0-6]) STACK=TOTAL_STACK ;;
esac

emcc ${OPT:--Oz} -Wno-everything -I../llt -I.. -DNDEBUG $SRCS -o "$OUT" \
  --embed-file ../femtoscheme.boot@/femtoscheme.boot \
  --embed-file web.scm@/web.scm \
  -s MODULARIZE=1 -s EXPORT_NAME=createFemtoscheme \
  -s SINGLE_FILE=1 -s ENVIRONMENT=web,node \
  -s ALLOW_MEMORY_GROWTH=1 -s "$STACK=1048576" \
  -s EXPORTED_FUNCTIONS=_fs_start,_fs_eval,_malloc,_free \
  -s EXPORTED_RUNTIME_METHODS=ccall,cwrap,UTF8ToString,stringToUTF8,lengthBytesUTF8
echo "Built $OUT"
