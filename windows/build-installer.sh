#!/bin/sh
# build-installer.sh -- make SBEmacs-<version>-Windows-x86_64-Setup.exe
#
# Nobody installing SBEmacs runs this: GitHub runs it on a Windows machine
# of its own at every push to the windows branch
# (.github/workflows/build-windows-installer.yml) and publishes the result.
# A developer can also run it, from the top of the sources, either
#
#   on Linux (Debian or Ubuntu):
#     sudo apt-get install gcc-mingw-w64-x86-64 wine nsis msitools unzip curl
#     sh windows/build-installer.sh
#
#   or on Windows, in the MSYS2 MINGW64 shell, with NSIS installed:
#     pacman -S mingw-w64-x86_64-gcc unzip
#     sh windows/build-installer.sh
#
# The result is in build/windows/: one .exe that a Windows user
# double-clicks, then clicks Next, Next, Finish.  It needs no SBCL, no
# PowerShell, no MSYS2 and no administrator: SBEmacs goes to the user's
# own programs folder, %LOCALAPPDATA%\Programs\SBEmacs.
#
# How, from first principles.  sbemacs.exe is an SBCL image saved with
# save-lisp-and-die; the image carries the SBCL runtime, so the user does
# not need SBCL.  But only a Windows SBCL saves a Windows image.  So:
#
#   1. the C core is compiled into libsbemacs-gui.dll with MinGW-w64,
#      against the official SDL2 and SDL2_ttf MinGW packages;
#   2. the official Windows SBCL (run under Wine on Linux) loads build.lisp
#      and saves sbemacs.exe (a window program: no console opens with it);
#   3. NSIS packs sbemacs.exe, the DLLs, the Lisp scripts, a font and the
#      manual into the setup program.
#
# Every download is pinned by its SHA-256, so the build is the same
# wherever it runs.  Downloads are kept in build/windows/downloads.

set -eu

case $(uname -s) in
    MINGW*|MSYS*) ON_WINDOWS=1 ;;
    *)            ON_WINDOWS=0 ;;
esac

TOP=$(cd "$(dirname "$0")/.." && pwd)
WORK=${WORK:-$TOP/build/windows}
DL=$WORK/downloads
if [ $ON_WINDOWS = 1 ]; then
    CC=${CC_WIN:-gcc}
    # NSIS installs itself here, without touching the PATH
    PATH="$PATH:/c/Program Files (x86)/NSIS:/c/Program Files/NSIS"
    NEEDED="unzip"
else
    CC=${CC_WIN:-x86_64-w64-mingw32-gcc}
    NEEDED="wine msiextract unzip"
fi

SDL2_VERSION=2.32.10
SDL2_TTF_VERSION=2.24.0
SBCL_VERSION=2.6.9
DEJAVU_VERSION=2.37

SDL2_TGZ=SDL2-devel-$SDL2_VERSION-mingw.tar.gz
SDL2_URL=https://github.com/libsdl-org/SDL/releases/download/release-$SDL2_VERSION/$SDL2_TGZ
SDL2_SHA=83a5d74012311edc3c0d40ea6faecbe57ad692aa033fa5dc273cc937e3938ff2

TTF_TGZ=SDL2_ttf-devel-$SDL2_TTF_VERSION-mingw.tar.gz
TTF_URL=https://github.com/libsdl-org/SDL_ttf/releases/download/release-$SDL2_TTF_VERSION/$TTF_TGZ
TTF_SHA=3a09e0a967ad53eca3ff2701de4d0df3369c0368739a1088a78d9d74908ef2c3

# The official SBCL MSI (also on sbcl.org), from the GitHub mirror
SBCL_MSI=sbcl-$SBCL_VERSION-x86-64-windows-binary.msi
SBCL_URL=https://github.com/roswell/sbcl_bin/releases/download/$SBCL_VERSION/$SBCL_MSI
SBCL_SHA=e0628213190db735004b54aeaf367864da9940e33337f9f20ae6dbe5c26de66d

DEJAVU_ZIP=dejavu-fonts-ttf-$DEJAVU_VERSION.zip
DEJAVU_URL=https://github.com/dejavu-fonts/dejavu-fonts/releases/download/version_2_37/$DEJAVU_ZIP
DEJAVU_SHA=7576310b219e04159d35ff61dd4a4ec4cdba4f35c00e002a136f00e96a908b0a

say() { printf '\n== %s\n' "$*"; }
die() { printf 'build-installer: %s\n' "$*" >&2; exit 1; }

for tool in "$CC" makensis $NEEDED curl sha256sum; do
    command -v "$tool" >/dev/null 2>&1 || die "$tool is missing (see the top of this script)"
done

# fetch FILE URL SHA256: download once, then always check the checksum
fetch() {
    if [ ! -f "$DL/$1" ]; then
        echo "downloading $2"
        curl -fsSL --retry 3 -o "$DL/$1.part" "$2" || die "could not download $2"
        mv "$DL/$1.part" "$DL/$1"
    fi
    echo "$3  $DL/$1" | sha256sum -c --quiet - || die "$1: wrong checksum (delete it and retry)"
}

VERSION=$(sed -n 's/^#define VERSION[^"]*"SBEmacs \([0-9.]*\).*/\1/p' "$TOP/src/header.h")
[ -n "$VERSION" ] || die "no version in src/header.h"

mkdir -p "$DL"
say "Downloads"
fetch "$SDL2_TGZ" "$SDL2_URL" "$SDL2_SHA"
fetch "$TTF_TGZ" "$TTF_URL" "$TTF_SHA"
fetch "$SBCL_MSI" "$SBCL_URL" "$SBCL_SHA"
fetch "$DEJAVU_ZIP" "$DEJAVU_URL" "$DEJAVU_SHA"

say "Unpacking"
rm -rf "$WORK/deps" "$WORK/obj" "$WORK/stage"
mkdir -p "$WORK/deps" "$WORK/obj" "$WORK/stage"
tar xzf "$DL/$SDL2_TGZ" -C "$WORK/deps"
tar xzf "$DL/$TTF_TGZ" -C "$WORK/deps"
unzip -q "$DL/$DEJAVU_ZIP" -d "$WORK/deps"
mkdir -p "$WORK/deps/sbcl"
if [ $ON_WINDOWS = 1 ]; then
    # an "administrative install" only unpacks the MSI; nothing is installed
    powershell -NoProfile -Command "\$p = Start-Process msiexec.exe -Wait -PassThru -ArgumentList '/a','$(cygpath -w "$DL/$SBCL_MSI")','/qn','TARGETDIR=$(cygpath -w "$WORK/deps/sbcl")'; exit \$p.ExitCode" \
        || die "msiexec could not unpack $SBCL_MSI"
else
    (cd "$WORK/deps/sbcl" && msiextract "$DL/$SBCL_MSI" >/dev/null)
fi
SBCL_EXE=$(find "$WORK/deps/sbcl" -name sbcl.exe | head -1)
[ -n "$SBCL_EXE" ] || die "no sbcl.exe in $SBCL_MSI"
SBCL_DIR=$(dirname "$SBCL_EXE")

SDL2=$WORK/deps/SDL2-$SDL2_VERSION/x86_64-w64-mingw32
TTF=$WORK/deps/SDL2_ttf-$SDL2_TTF_VERSION/x86_64-w64-mingw32

say "Compiling the C core (MinGW-w64)"
CFLAGS="-O2 -Wall"
for c in "$TOP"/src/*.c; do
    name=$(basename "$c" .c)
    case $name in
        term) continue ;;                  # the terminal: not in a window program
        gui)  extra="-I$SDL2/include -I$SDL2/include/SDL2 -I$TTF/include -I$TTF/include/SDL2" ;;
        *)    extra="" ;;
    esac
    # shellcheck disable=SC2086
    "$CC" $CFLAGS $extra -c "$c" -o "$WORK/obj/$name.o"
done
"$CC" -shared -static-libgcc -o "$WORK/stage/libsbemacs-gui.dll" "$WORK"/obj/*.o \
      -L"$SDL2/lib" -L"$TTF/lib" -lSDL2_ttf -lSDL2

say "Staging"
S=$WORK/stage
cp "$SDL2/bin/SDL2.dll" "$TTF/bin/SDL2_ttf.dll" "$S/"
cp "$TOP/build.lisp" "$S/"
cp -R "$TOP/lisp" "$S/lisp"
mkdir -p "$S/fonts" "$S/docs" "$S/samples"
# used only when Windows has none of the fonts in *gui-font-candidates*
# (Cascadia Mono and Consolas come with Windows 10 and 11)
cp "$WORK/deps/dejavu-fonts-ttf-$DEJAVU_VERSION/ttf/DejaVuSansMono.ttf" "$S/fonts/"
cp "$WORK/deps/dejavu-fonts-ttf-$DEJAVU_VERSION/LICENSE" "$S/fonts/DejaVu-LICENSE.txt"
cp "$TOP/docs/sbemacs.pdf" "$S/docs/"
cp "$TOP/samples/init.lisp" "$TOP/samples/fib.lisp" "$S/samples/"
cp "$TOP/README.md" "$TOP/CHANGE.LOG.md" "$S/"

say "Saving sbemacs.exe with SBCL $SBCL_VERSION"
if [ $ON_WINDOWS = 1 ]; then
    WINDIR_SBCL=$(cygpath -w "$SBCL_DIR")
    (cd "$S" && SBEMACS_WINDOW_APP=1 SBCL_HOME="$WINDIR_SBCL" \
        "$SBCL_EXE" --core "$WINDIR_SBCL\\sbcl.core" --noinform --non-interactive \
                    --no-sysinit --no-userinit --load build.lisp)
else
    export WINEPREFIX="$WORK/wine" WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml="
    # Wine sees the Linux root as drive Z:
    (cd "$S" && SBEMACS_WINDOW_APP=1 SBCL_HOME="Z:$SBCL_DIR" \
        wine "$SBCL_EXE" --core "Z:$SBCL_DIR/sbcl.core" --noinform --non-interactive \
             --no-sysinit --no-userinit --load build.lisp)
fi
[ -f "$S/sbemacs.exe" ] || die "SBCL did not save sbemacs.exe"
rm -rf "$S/build" "$S/build.lisp"

say "Making the setup program (NSIS)"
if [ $ON_WINDOWS = 1 ]; then
    # Windows paths, left alone by MSYS2's path conversion
    MSYS2_ARG_CONV_EXCL='*' makensis -V2 -DTARGET=x86-unicode \
        -DVERSION="$VERSION" -DSTAGE="$(cygpath -w "$S")" \
        -DOUTDIR="$(cygpath -w "$WORK")" "$(cygpath -w "$TOP/windows/sbemacs.nsi")"
else
    makensis -V2 -DVERSION="$VERSION" -DSTAGE="$S" -DOUTDIR="$WORK" "$TOP/windows/sbemacs.nsi"
fi
SETUP=$WORK/SBEmacs-$VERSION-Windows-x86_64-Setup.exe
[ -f "$SETUP" ] || die "makensis made nothing"
say "Done: $SETUP ($(du -h "$SETUP" | cut -f1))"
