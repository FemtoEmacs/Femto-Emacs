#!/bin/bash
# Native Windows DLLs: no X server is required.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/windows/sdl
fetch() {
 local name=$1 url=$2 hash=$3
 curl -fL "$url" -o "build/windows/sdl/$name"
 printf '%s  %s\n' "$hash" "build/windows/sdl/$name" | sha256sum -c -
 tar -xf "build/windows/sdl/$name" -C build/windows/sdl
}
fetch SDL2.tar.gz https://github.com/libsdl-org/SDL/releases/download/release-2.32.10/SDL2-devel-2.32.10-mingw.tar.gz 83a5d74012311edc3c0d40ea6faecbe57ad692aa033fa5dc273cc937e3938ff2
fetch TTF.tar.gz https://github.com/libsdl-org/SDL_ttf/releases/download/release-2.24.0/SDL2_ttf-devel-2.24.0-mingw.tar.gz 3a09e0a967ad53eca3ff2701de4d0df3369c0368739a1088a78d9d74908ef2c3

# Cygwin maps POSIX execute permission to the Windows DLL-loader ACL.
find build/windows/sdl -type f -iname '*.dll' -exec chmod +x {} +
