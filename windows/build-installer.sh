#!/bin/bash
# Run on a Windows Cygwin builder, not on an end user's computer.
set -euo pipefail
cd "$(dirname "$0")/.."
sh windows/prepare-runtime.sh
bash windows/prepare-sdl.sh
sdl="$PWD/build/windows/sdl/SDL2-2.32.10/x86_64-w64-mingw32"
ttf="$PWD/build/windows/sdl/SDL2_ttf-2.24.0/x86_64-w64-mingw32"
export PATH="$PWD:$sdl/bin:$ttf/bin:$PATH"
gcc -O2 windows/loader-check.c -o build/windows/loader-check.exe
build/windows/loader-check.exe "$(cygpath -w "$PWD/wasmtime.dll")"
make schemer-compile
cygcheck ./schemer-compile.exe || true
objdump -p schemer-compile.exe | grep 'DLL Name'
make -j2 SDL_CFLAGS="-I$sdl/include/SDL2 -I$ttf/include/SDL2" SDL_LIBS="-L$sdl/lib -L$ttf/lib -lSDL2_ttf -lSDL2"
work="$PWD/build/windows"
stage="$work/stage"
rm -rf "$stage"
mkdir -p "$stage"/{app,bin,tmp,etc,licenses,usr/share/terminfo}
# Keep source and compiled WebAssembly for personal scripts. Native caches
# are fingerprinted and validated by Wasmtime; incompatible CPUs fall back
# to compiling the portable WebAssembly, as on macOS/Linux.
cp chezweb.exe chezweb-gui.exe chezweb-server.exe schemer-compile.exe irene-dixe.exe "$stage/app/"
cp chezemax.wasm chezemax.cwasm Chezweb.html "$stage/app/"
cp -R scheme compiled schemer tools femtoscheme "$stage/app/"
find "$stage/app" -type d -name bkp -prune -exec rm -rf {} +
find "$stage/app" -type f \( -name '*.o' -o -name '*.a' -o -name '*.exe' \) ! -path "$stage/app/*.exe" -delete
mkdir -p "$stage/app/build"
cp build/chezweb.js build/chezweb.wasm "$stage/app/build/"
cp windows/start.sh "$stage/app/"
# Bundle the basic shell tools used by the editor and by compile-scripts.
gcc -O2 -mwindows windows/gui-launch.c -o "$stage/bin/chezweb-gui-launch.exe"
cp "$sdl/bin/"*.dll "$ttf/bin/"*.dll "$stage/bin/"
commands='bash sh mintty cygpath cat cp mv rm mkdir mktemp dirname basename find sort awk grep sed head tail wc tr cut chmod pwd env date ls cmp touch sleep printf realpath readlink ln stat expr tar xz gzip curl unzip sha256sum'
for cmd in $commands; do
 src=$(command -v "$cmd")
 # Some shell builtins (pwd) also have a standalone executable.
 [ -f "$src" ] || src="/usr/bin/$cmd.exe"
 cp -L "$src" "$stage/bin/$cmd.exe"
done
# Cygwin DLL dependencies, including transitive ones, come from the exact
# packages installed on this builder. cygcheck recursively enumerates them.
for exe in "$stage"/{bin,app}/*.exe; do
 cygcheck "$exe" | sed 's/^[[:space:]]*//' | while IFS= read -r dependency; do
  posix=$(cygpath -u "$dependency" 2>/dev/null || true)
  case "$posix" in /usr/bin/*.dll|/bin/*.dll) cp -u "$posix" "$stage/bin/" ;; esac
 done
done
cp ./*wasmtime*.dll "$stage/bin/"
cp -RL /usr/share/terminfo/. "$stage/usr/share/terminfo/"
# curl's TLS verification uses the bundled certificate store.
if [ -d /etc/pki ]; then cp -RL /etc/pki "$stage/etc/"; fi
if [ -d /usr/ssl ]; then cp -RL /usr/ssl "$stage/usr/"; fi
printf 'none / cygdrive binary,posix=0,user 0 0\n' > "$stage/etc/fstab"
cp /usr/share/doc/Cygwin/* "$stage/licenses/" 2>/dev/null || true
find /usr/share/doc -type f \( -iname 'copying*' -o -iname 'license*' -o -iname 'copyright*' \) | while IFS= read -r file; do
 mkdir -p "$stage/licenses/doc/$(dirname "$file")"
 cp "$file" "$stage/licenses/doc/$file"
done
cp runtime/wasmtime/LICENSE "$stage/licenses/Wasmtime-LICENSE" 2>/dev/null || true
cp windows/README.md "$stage/licenses/Chezweb-Windows.txt"
# Preserve the licenses shipped with both SDL development distributions.
(cd build/windows/sdl && find . -type f \( -iname '*license*' -o -iname '*copying*' \) | while IFS= read -r file; do
 mkdir -p "$stage/licenses/SDL/$(dirname "$file")"
 cp "$file" "$stage/licenses/SDL/$file"
done)
cygcheck -cd > "$work/installed-packages.txt"
# Record the complete build source without ignored documents or caches.
gcc -O2 tests/pty-keys.c -o "$work/pty-test.exe"
git archive HEAD | gzip > "$work/Chezweb-source.tar.gz"
makensis=$(cygpath -u 'C:\Program Files (x86)\NSIS\makensis.exe')
[ -x "$makensis" ] || makensis=$(command -v makensis)
cp windows/installer.nsi "$work/"
(cd "$work" && "$makensis" installer.nsi)
(cd "$work" && sha256sum *Setup.exe > SHA256SUMS)
