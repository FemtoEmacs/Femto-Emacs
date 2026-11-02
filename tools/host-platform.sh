#!/bin/sh
# Normalize the host and compiler architecture for Wasmtime's C SDK.
set -eu
system=${1:-$(uname -s)}
if [ "$#" -ge 2 ]; then machine=$2; else
 # A compiler's target is more reliable than uname under Rosetta or -arch.
 target=$(${CC:-cc} -dumpmachine 2>/dev/null || true)
 case $target in
  x86_64*|amd64*) machine=x86_64 ;;
  aarch64*|arm64*) machine=aarch64 ;;
  i?86*) machine=i386 ;;
  *) machine=$(uname -m) ;;
 esac
fi
case $system in
 Darwin) os=macos ;;
 Linux) os=linux ;;
 MINGW*|MSYS*|CYGWIN*) os=windows ;;
 *) echo "Unsupported operating system: $system" >&2;exit 1 ;;
esac
case $machine in
 arm64|aarch64) arch=aarch64 ;;
 x86_64|amd64) arch=x86_64 ;;
 *) echo "Unsupported architecture: $machine. Chezemax requires a 64-bit x86_64 or ARM64 compiler." >&2;exit 1 ;;
esac
printf '%s-%s\n' "$arch" "$os"
