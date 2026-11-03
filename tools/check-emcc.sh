#!/bin/sh
# Test the features we actually use, not a guessed minimum SDK version.
set -eu
quiet=false
case ${1:-} in '') ;; --quiet) quiet=true ;; *) echo 'Usage: check-emcc.sh [--quiet]' >&2;exit 2 ;; esac
compiler=${EMCC:-emcc}
fail() {
 if [ "$quiet" = false ]; then
  echo "Chezweb's browser editor requires Emscripten with JSPI and WebAssembly exceptions." >&2
  echo "Compiler: $compiler" >&2
  echo 'Update and activate your emsdk, then run make browser-rebuild again:' >&2
  echo '  ./emsdk install latest' >&2
  echo '  ./emsdk activate latest' >&2
  echo '  source ./emsdk_env.sh' >&2
  echo 'Ordinary make uses the bundled browser files; no browser SDK is needed.' >&2
 fi
 exit 1
}
command -v "$compiler" >/dev/null 2>&1 || fail
probe_dir=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-emcc.XXXXXX")
trap 'rm -rf "$probe_dir"' EXIT HUP INT TERM
cat > "$probe_dir/probe.c" <<'C'
#include <emscripten.h>
#include <setjmp.h>
EM_ASYNC_JS(int, wait_for_browser, (void), { return 0; });
int main(void) { jmp_buf point; if (setjmp(point)) return 1; return wait_for_browser(); }
C
if ! "$compiler" "$probe_dir/probe.c" -fwasm-exceptions -sSUPPORT_LONGJMP=wasm \
    -sJSPI=1 -sJSPI_EXPORTS=main -o "$probe_dir/probe.js" > "$probe_dir/log" 2>&1; then
 if [ "$quiet" = false ]; then cat "$probe_dir/log" >&2; fi
 fail
fi
