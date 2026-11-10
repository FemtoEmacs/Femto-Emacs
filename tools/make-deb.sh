#!/bin/sh
# make deb: a Debian/Ubuntu package of the editor built here
# (build/deb/chezweb_VERSION_ARCH.deb), for this machine's processor.
#
#   sudo apt install ./build/deb/chezweb_0.1+20261110_amd64.deb
#
# installs it in /opt/chezweb, with the commands chezweb and chezweb-gui
# in /usr/bin and a menu entry for the window; apt installs the libraries
# it needs (ncurses, SDL2).  The package carries the WebAssembly, not the
# machine code made from it: Wasmtime makes machine code for the processor
# it runs on, so the package's postinst makes it on the user's machine
# (about half a minute), and prerm removes it.
#
# Maintainers and the GitHub workflow (.github/workflows/linux-deb.yml)
# run it; users need nothing of it.  Needs dpkg-deb and dpkg-shlibdeps.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd)

for f in chezweb chezweb-gui chezweb-server irene-dixe schemer-compile chezemax.wasm \
         schemer/compiler.wasm Chezweb.html build/chezweb.js build/chezweb.wasm \
         femtoscheme/femtoscheme.boot runtime/wasmtime/lib/libwasmtime.so; do
 [ -e "$f" ] || { echo "make-deb: $f is missing: run make (with SDL2 installed) and make browser first" >&2; exit 1; }
done
command -v dpkg-deb >/dev/null && command -v dpkg-shlibdeps >/dev/null ||
 { echo 'make-deb: needs dpkg-deb and dpkg-shlibdeps (apt install dpkg-dev)' >&2; exit 1; }

arch=$(dpkg --print-architecture)
base=$(sed -n 's/^#define VERSION[^"]*"Chezweb \([0-9.]*\).*/\1/p' src/header.h)
[ -n "$base" ] || { echo 'make-deb: no version in src/header.h' >&2; exit 1; }
# 0.1+20261110, and the commit when known (the workflow gives it)
version="$base+$(date -u +%Y%m%d)${DEB_REVISION:+.$DEB_REVISION}"

out="$root/build/deb"
stage="$out/chezweb_${version}_$arch"
rm -rf "$stage"
opt="$stage/opt/chezweb"
mkdir -p "$opt/build" "$opt/femtoscheme" "$opt/ttfy" "$opt/Chinese" "$opt/schemer" \
         "$opt/runtime/wasmtime/lib" "$opt/compiled/scripts" "$opt/browser-licenses" \
         "$opt/scheme/languages" "$opt/scheme/extensions" "$opt/scheme/modes" \
         "$stage/usr/bin" "$stage/usr/share/applications" "$stage/usr/share/doc/chezweb" \
         "$stage/DEBIAN"

# The installation, as make app lays out Chezweb.app
for f in chezweb chezweb-gui chezweb-server irene-dixe schemer-compile; do
 install -m 0755 "$f" "$opt/$f"
done
install -m 0644 chezemax.wasm Chezweb.html "$opt/"
install -m 0644 build/chezweb.js build/chezweb.wasm "$opt/build/"
install -m 0644 femtoscheme/femtoscheme.boot "$opt/femtoscheme/"
install -m 0644 ttfy/plots-guidelines.md "$opt/ttfy/"
install -m 0644 Chinese/pinyin.txt Chinese/lianxiang.txt Chinese/README.md "$opt/Chinese/"
install -m 0644 scheme/*.scm "$opt/scheme/"
install -m 0644 scheme/languages/*.scm "$opt/scheme/languages/"
install -m 0644 scheme/extensions/*.scm "$opt/scheme/extensions/"
install -m 0644 scheme/modes/*.scm "$opt/scheme/modes/"
install -m 0644 schemer/*.scm schemer/compiler.wasm "$opt/schemer/"
rm -f "$opt/schemer/native-compile.scm" "$opt/schemer/page.scm"
install -m 0644 runtime/wasmtime/lib/libwasmtime.so "$opt/runtime/wasmtime/lib/"
[ ! -f runtime/wasmtime/LICENSE ] || install -m 0644 runtime/wasmtime/LICENSE "$opt/runtime/wasmtime/"
# the program's sources, for chezweb --compile-scripts
install -m 0644 compiled/PROGRAM compiled/*.scm "$opt/compiled/"
install -m 0644 compiled/scripts/ORDER compiled/scripts/*.scm "$opt/compiled/scripts/"
install -m 0644 web/prebuilt/licenses/* "$opt/browser-licenses/"
install -m 0644 README.md "$stage/usr/share/doc/chezweb/"
install -m 0644 packaging/linux/copyright "$stage/usr/share/doc/chezweb/"
install -m 0644 packaging/linux/chezweb.desktop "$stage/usr/share/applications/"

# /usr/bin: small scripts, so that the editor sees /opt/chezweb as its folder
for c in chezweb chezweb-gui; do
 printf '#!/bin/sh\nexec /opt/chezweb/%s "$@"\n' "$c" > "$stage/usr/bin/$c"
 chmod 0755 "$stage/usr/bin/$c"
done

install -m 0755 packaging/linux/postinst packaging/linux/prerm "$stage/DEBIAN/"

# The libraries the programs need, as Debian packages (ncurses, SDL2 ...);
# libwasmtime.so is the package's own
work=$(mktemp -d "${TMPDIR:-/tmp}/chezweb-deb.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$work/debian"
printf 'Source: chezweb\n\nPackage: chezweb\nArchitecture: any\n' > "$work/debian/control"
depends=$(cd "$work" && dpkg-shlibdeps -O --ignore-missing-info -l"$opt/runtime/wasmtime/lib" \
          "$opt/chezweb" "$opt/chezweb-gui" "$opt/chezweb-server" "$opt/irene-dixe" "$opt/schemer-compile" 2>/dev/null |
          sed -n 's/^shlibs:Depends=//p')
[ -n "$depends" ] || { echo 'make-deb: dpkg-shlibdeps found no dependencies' >&2; exit 1; }

size=$(du -sk "$stage" | cut -f1)
cat > "$stage/DEBIAN/control" <<EOF
Package: chezweb
Version: $version
Architecture: $arch
Maintainer: FemtoEmacs <FemtoEmacs@users.noreply.github.com>
Installed-Size: $size
Depends: $depends
Suggests: chromium | google-chrome-stable, texlive-xetex
Section: editors
Priority: optional
Homepage: https://github.com/FemtoEmacs/Femto-Emacs
Description: Emacs-like editor for the terminal, a window and Chrome
 Chezweb is a simpler Emacs: the same basic keys, fewer features, easy to
 learn.  It edits in a terminal (chezweb), in a window (chezweb-gui) and
 in Chrome (C-c d), with Org mode, Markdown, LaTeX export, Korean,
 Chinese and polytonic Greek input, and calls Claude and Codex.  Its
 commands are Scheme, compiled to WebAssembly and run by Wasmtime.
EOF

deb="$out/chezweb_${version}_$arch.deb"
dpkg-deb --root-owner-group -Zxz --build "$stage" "$deb" >/dev/null
rm -rf "$stage"
echo "$deb"
