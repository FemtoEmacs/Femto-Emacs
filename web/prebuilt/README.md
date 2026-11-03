# Portable browser build

These JavaScript and WebAssembly files run unchanged on macOS and Linux.
Ordinary `make` verifies and installs them into `build/`; no browser SDK,
Node.js or Python is invoked on users' computers.

The bundle was built from this checkout with Emscripten 6.0.13, using JSPI
and WebAssembly exceptions. Its embedded Scheme editor and compiler are
portable WebAssembly, not Wasmtime's architecture-specific machine caches.
Runtime-library notices are in `licenses/`.

Maintainers run `make browser-rebuild` after changing editor inputs, then
commit both assets and SHA256SUMS with their source changes. The manifest
covers authoritative source/generator inputs and both assets. Native build
outputs and generated bridge output are deliberately excluded so parallel
native compilation cannot race verification.
