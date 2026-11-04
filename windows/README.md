# Chezweb for Windows

This branch replaces the older SBEmacs installer with Chezweb. Its old tip
is retained as a merge parent and locally as archive/windows-before-chezweb.

Download Chezweb-Windows-x86_64-Setup.exe from a successful **Windows installer**
Actions run. Run it as your ordinary user; it installs under
%LOCALAPPDATA%\Programs\Chezweb and adds a Start-menu entry and uninstaller.
Install current Google Chrome, launch Chezweb, then press C-c d for its browser
editor. The terminal window remains open for shell commands and AI assistance.

This package bundles the Cygwin POSIX runtime, mintty, ncurses, the Scheme
compiler, the native Windows Wasmtime DLL and portable browser WebAssembly.
Users do not install Cygwin, WSL, a C compiler, Node or a browser compiler.
The initial package provides terminal and browser interfaces; SDL is not
included. Claude/Codex are optional separate installations. PDF rendering
currently requires macOS. Windows ARM64 is not a native build target here.

Settings and personal scripts stay in %USERPROFILE%\.chezemax. Uninstallation
preserves that folder and documents. Close Chezweb before updating/uninstalling.
Paths inside the terminal use Cygwin notation, e.g. /c/Users/nia/Documents.

Maintainers: the GitHub workflow installs build dependencies, runs
windows/build-installer.sh, tests a silently installed copy in a folder with
spaces, and uploads the installer, checksums, build log and corresponding source.
Cygwin component sources accompany the binary artifact to satisfy redistribution
requirements: https://cygwin.com/licensing.html. Do not publish a binary without
its matching source artifact. This installer is unsigned; Windows may display
an unknown-publisher warning.
