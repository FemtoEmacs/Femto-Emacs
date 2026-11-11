# Chezweb for Windows

This branch replaces the older SBEmacs installer with Chezweb. Its old tip
is retained as a merge parent and locally as archive/windows-before-chezweb.

Download Chezweb-Windows-x86_64-Setup.exe from a successful **Windows installer**
Actions run. Run it as your ordinary user; it installs under
%LOCALAPPDATA%\Programs\Chezweb and adds a Start-menu entry and uninstaller.
Install current Google Chrome, launch Chezweb, then press C-c d for its browser
editor. The terminal window remains open for shell commands and AI assistance.

This package bundles the Cygwin POSIX runtime, mintty, ncurses, the Scheme
compiler, the native Windows Wasmtime DLL, SDL and portable browser WebAssembly.
Users do not install Cygwin, WSL, a C compiler, Node or a browser compiler.
The package provides terminal, native SDL GUI and browser interfaces.
Choose Chezweb or Chezweb GUI in the Start menu. Claude/Codex are optional separate installations. PDF rendering
currently requires macOS. Windows ARM64 is not a native build target here.

Settings and personal scripts stay in %USERPROFILE%\.chezemax. Uninstallation
preserves that folder and documents. Close Chezweb before updating/uninstalling.
Cygwin shell tools use paths such as `/c/Users/nia/Documents`. The Windows command interpreter uses paths such as `C:\Users\nia\Documents`.
The included shell tools support ordinary ls, cd and pwd commands.

Maintainers: the GitHub workflow installs build dependencies, runs
windows/build-installer.sh, tests a silently installed copy in a folder with
spaces, and uploads the installer, checksums, build log and corresponding source.
Cygwin component sources accompany the binary artifact to satisfy redistribution
requirements: https://cygwin.com/licensing.html. Do not publish a binary without
its matching source artifact. This installer is unsigned; Windows may display
an unknown-publisher warning.

## Org and the embedded terminal

Open a file ending in `.org` to use the shared Org mode, including folding,
tables, source blocks, and LaTeX export. Generating a PDF requires a separate
TeX installation.

In the terminal editor or SDL window, `M-x term` starts the Windows command
interpreter configured in `ComSpec` (normally `cmd.exe`). This requires Windows
10 version 1809 or later. ConPTY connects the shell to the same libvterm
renderer used on macOS and Linux. Use `C-c C-c` to interrupt the shell,
`C-c C-j` for copy mode, and `C-c C-k` to resume sending keys to the shell.
