# C-owned editor with embedded femtoscheme; optional native GUI.
.DEFAULT_GOAL := all
CC ?= cc
CFLAGS ?= -O2 -Wall -std=gnu11
CPPFLAGS += -Isrc -Ifemtoscheme -Ifemtoscheme/llt
UNAME_S := $(shell uname -s)
PKG_CONFIG ?= pkg-config
HOST_TARGET = $(shell CC="$(CC)" sh tools/host-platform.sh)
ifeq ($(UNAME_S),Darwin)
CURSES_CFLAGS ?=
CURSES_LIBS ?= -lncurses
PDF_LIBS = -framework CoreGraphics -framework ImageIO -framework CoreFoundation
else
CURSES_CFLAGS ?= $(shell $(PKG_CONFIG) --cflags ncursesw 2>/dev/null)
CURSES_LIBS ?= $(shell $(PKG_CONFIG) --libs ncursesw 2>/dev/null || echo -lncursesw)
endif
SDL_CFLAGS := $(shell $(PKG_CONFIG) --cflags sdl2 SDL2_ttf 2>/dev/null)
SDL_LIBS := $(filter-out -lSDL2main,$(shell $(PKG_CONFIG) --libs sdl2 SDL2_ttf 2>/dev/null))
# All C sources live in src/. term.c and gui.c are the two screen backends;
# app.c is compiled twice (terminal and GUI).
# irene-dixe.c is a program of its own (the C-c p plot window).
CORE = $(filter-out src/term.c src/gui.c src/app.c src/irene-dixe.c,$(wildcard src/*.c))
OBJECTS = $(CORE:.c=.o)
WASMTIME_ROOT ?= runtime/wasmtime
CPPFLAGS += -I$(WASMTIME_ROOT)/include
WASMTIME_LIBS = -L$(WASMTIME_ROOT)/lib -lwasmtime -Wl,-rpath,'$$ORIGIN/runtime/wasmtime/lib'
ifeq ($(UNAME_S),Darwin)
WASMTIME_LIBS = -L$(WASMTIME_ROOT)/lib -lwasmtime -Wl,-rpath,@loader_path/runtime/wasmtime/lib
endif
# The Windows installer bundles Cygwin for the editor's POSIX services.
ifneq ($(filter CYGWIN%,$(UNAME_S)),)
WASMTIME_LIBS = -L$(WASMTIME_ROOT)/lib -lwasmtime
GUI_LDFLAGS = -mwindows
endif
OBJECTS += schemer/native-host.o
# libvterm (libvterm/, bundled source): the terminal emulator of M-x term
CPPFLAGS += -Ilibvterm/include
VTERM_OBJECTS = $(patsubst %.c,%.o,$(wildcard libvterm/src/*.c))
OBJECTS += $(VTERM_OBJECTS)
$(VTERM_OBJECTS): libvterm/include/vterm.h libvterm/src/vterm_internal.h
src/terminal.o src/terminal-windows.o: src/terminal-windows.h
# forkpty: in libutil on Linux and the BSDs, in libSystem on macOS
ifneq ($(filter Darwin CYGWIN%,$(UNAME_S)),)
PTY_LIBS =
else
PTY_LIBS = -lutil
endif
RUNTIME = femtoscheme/libfemtoscheme.a femtoscheme/llt/libllt.a
.PHONY: all runtime check check-compiled check-library check-scripts check-compile-scripts fetch-wasmtime clean
fetch-wasmtime:
	CC="$(CC)" WASMTIME_ROOT="$(WASMTIME_ROOT)" sh tools/fetch-wasmtime.sh
$(WASMTIME_ROOT)/include/wasmtime.h:
	CC="$(CC)" WASMTIME_ROOT="$(WASMTIME_ROOT)" sh tools/fetch-wasmtime.sh
src/compiled.o schemer/native-host.o: $(WASMTIME_ROOT)/include/wasmtime.h
all: check-build schemer-compile schemer/compiler.cwasm chezemax chezemax.wasm chezemax.cwasm $(if $(SDL_LIBS),chezemax-gui irene-dixe)

.PHONY: check-build check-platform show-config
check-build:
	CC="$(CC)" CPPFLAGS="$(CPPFLAGS)" CFLAGS="$(CFLAGS)" LDFLAGS="$(LDFLAGS)" CURSES_CFLAGS="$(CURSES_CFLAGS)" CURSES_LIBS="$(CURSES_LIBS)" sh tools/check-build.sh
show-config:
	@echo "Platform: $(HOST_TARGET)"
	@echo "Compiler: $(CC)"
	@echo "Terminal libraries: $(CURSES_LIBS)"
	@echo "SDL interface: $(if $(SDL_LIBS),enabled,not installed; terminal only)"
check-platform:
	sh tests/platform.sh
# The check runs once even with make -j; no architecture-specific -f file.
$(OBJECTS) src/term.o src/app.o src/gui.o src/app-gui.o: | check-build
src/term.o: src/term.c src/screen.h
	$(CC) $(CPPFLAGS) $(CFLAGS) $(CURSES_CFLAGS) -c $< -o $@

# The compiled Scheme program (PORT-TO-SCHEMER.md): compiled/*.scm and the
# scripts, in this order, compiled by Schemer (about two minutes).  The C
# core loads it at start-up, and it runs the editor: femtoscheme runs no
# script unless CHEZEMAX_SCHEME=femtoscheme.  compiled/scripts/ORDER lists
# the scripts in the order scheme/init.scm loaded them.
# compiled/PROGRAM lists the files (tools/program-files.awk expands it);
# chezemax --compile-scripts compiles the same, with your code in
# ~/.chezemax/users, into ~/.chezemax (src/compile-scripts.c).
COMPILED := $(shell awk -f tools/program-files.awk compiled/PROGRAM)
chezemax.wasm: $(COMPILED) compiled/PROGRAM compiled/scripts/ORDER schemer-compile schemer/compiler.wasm schemer/compiler.cwasm
	sh tools/build-program.sh $@ $(COMPILED)
# its machine code, made once: the editor starts without translating it
chezemax.cwasm: chezemax.wasm schemer-compile
	./schemer-compile --machine-code chezemax.wasm $@
# the compiler's machine code: without it, every compilation would begin
# by translating the compiler (some 17 s) before compiling (about one)
schemer/compiler.cwasm: schemer/compiler.wasm schemer-compile
	./schemer-compile --machine-code schemer/compiler.wasm $@
# Both sides of the bridge to the C core's functions are generated from
# src/native.c (awk only)
src/bridge-functions.c: src/native.c tools/gen-bridge.awk
	awk -f tools/gen-bridge.awk src/native.c > $@
compiled/editor-functions.scm: src/native.c tools/gen-bridge-scheme.awk
	awk -f tools/gen-bridge-scheme.awk src/native.c > $@
src/bridge.o src/bridge-functions.o src/compiled-program.o: src/bridge.h schemer/native-host.h
runtime:
	$(MAKE) -C femtoscheme release CC="$(CC)"
chezemax: $(OBJECTS) src/term.o src/app.o runtime schemer-compile
	$(CC) $(LDFLAGS) $(OBJECTS) src/term.o src/app.o $(RUNTIME) $(CURSES_LIBS) $(PDF_LIBS) $(WASMTIME_LIBS) $(PTY_LIBS) -lm -o $@
chezemax-gui: $(OBJECTS) src/gui.o src/app-gui.o runtime schemer-compile
	$(CC) $(LDFLAGS) $(GUI_LDFLAGS) $(OBJECTS) src/gui.o src/app-gui.o $(RUNTIME) $(SDL_LIBS) $(PDF_LIBS) $(WASMTIME_LIBS) $(PTY_LIBS) -lm -o $@
irene-dixe: src/irene-dixe.c
	$(CC) $(CFLAGS) $(SDL_CFLAGS) $< $(LDFLAGS) $(SDL_LIBS) -lm -o $@
src/gui.o: src/gui.c src/screen.h
	$(CC) $(CPPFLAGS) $(CFLAGS) $(SDL_CFLAGS) -c $< -o $@
src/app-gui.o: src/app.c
	$(CC) $(CPPFLAGS) $(CFLAGS) -DSBEMACS_GUI -c $< -o $@
src/assistant.o src/pdf-pages.o: src/pdf-pages.h
$(CORE:.c=.o) src/term.o src/gui.o src/app.o src/app-gui.o: src/header.h src/public.h
schemer/native-host.o: schemer/native-host.c schemer/native-host.h
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@
src/compiled.o: schemer/native-host.h
%.o: %.c
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@
tests/native-host-test: tests/native-host-test.c schemer/native-host.o
	$(CC) $(CPPFLAGS) $(CFLAGS) $< schemer/native-host.o $(WASMTIME_LIBS) -Wl,-rpath,$(abspath $(WASMTIME_ROOT))/lib -lm -o $@
check-compiled: chezemax tests/native-host-test
	sh tests/run-compiled.sh
tests/bridge-test: tests/bridge-test.c src/bridge.o schemer/native-host.o
	$(CC) $(CPPFLAGS) $(CFLAGS) $< src/bridge.o schemer/native-host.o $(WASMTIME_LIBS) -Wl,-rpath,$(abspath $(WASMTIME_ROOT))/lib -lm -o $@
check-bridge: chezemax tests/bridge-test schemer-compile
	sh tests/run-bridge.sh
check-library: schemer-compile tests/native-host-test
	sh tests/run-library.sh
# the scripts compiled so far against femtoscheme's (step 4)
check-scripts: chezemax schemer-compile
	sh tests/run-scripts.sh
# chezemax --compile-scripts and M-x compile-scripts (a few minutes each)
check-compile-scripts: chezemax chezemax.wasm schemer/compiler.cwasm
	sh tests/run-compile-scripts.sh
check: check-history check-gc-allocation check-platform check-browser-assets-test check-web-toolchain-test chezemax check-compiled check-bridge check-library check-scripts
	$(MAKE) -C femtoscheme test
	./chezemax --eval '(+ 20 22)' | grep -x 42
	./chezemax --eval '(get-version-string)' | grep femtoscheme
	CHEZEMAX_SCHEME=femtoscheme CHEZEMAX_NO_INIT=1 ./chezemax --eval '(load "tests/run-tests.scm")'
	! ./chezemax --eval '(error "expected test error")'
	sh tests/run-editor.sh
	sh tests/run-read-mode.sh
	sh tests/run-compile-scripts.sh
clean:
	rm -f src/*.o schemer/*.o tests/native-host-test tests/gc-allocation-test tests/fileprompt-test tests/filename-completion-test chezemax chezemax-gui irene-dixe tests/search-test chezemax.wasm chezemax.cwasm schemer/compiler.cwasm tests/bridge-test
	$(MAKE) -C femtoscheme clean

.PHONY: app
app: chezweb-gui irene-dixe chezemax.wasm chezemax.cwasm browser
	rm -rf Chezweb.app/Contents/MacOS/scheme
	mkdir -p Chezweb.app/Contents/MacOS/femtoscheme Chezweb.app/Contents/MacOS/ttfy \
	    Chezweb.app/Contents/MacOS/Chinese \
	    Chezweb.app/Contents/MacOS/scheme/languages Chezweb.app/Contents/MacOS/scheme/extensions \
	    Chezweb.app/Contents/MacOS/scheme/modes
	cp packaging/Info.plist Chezweb.app/Contents/Info.plist
	cp chezweb-gui Chezweb.app/Contents/MacOS/chezweb-gui.new
	mv -f Chezweb.app/Contents/MacOS/chezweb-gui.new Chezweb.app/Contents/MacOS/chezweb-gui
	cp irene-dixe Chezweb.app/Contents/MacOS/irene-dixe.new
	mv -f Chezweb.app/Contents/MacOS/irene-dixe.new Chezweb.app/Contents/MacOS/irene-dixe
	cp scheme/*.scm Chezweb.app/Contents/MacOS/scheme/
	cp scheme/languages/*.scm Chezweb.app/Contents/MacOS/scheme/languages/
	cp scheme/extensions/*.scm Chezweb.app/Contents/MacOS/scheme/extensions/
	cp scheme/modes/*.scm Chezweb.app/Contents/MacOS/scheme/modes/
	cp ttfy/plots-guidelines.md Chezweb.app/Contents/MacOS/ttfy/
	cp Chinese/pinyin.txt Chinese/lianxiang.txt Chinese/README.md Chezweb.app/Contents/MacOS/Chinese/
	cp femtoscheme/femtoscheme.boot Chezweb.app/Contents/MacOS/femtoscheme/
	rm -f Chezweb.app/Contents/MacOS/femtoscheme/femtoscheme \
	    Chezweb.app/Contents/MacOS/schemer/native-compile.scm \
	    Chezweb.app/Contents/MacOS/schemer/page.scm
	cp schemer-compile Chezweb.app/Contents/MacOS/schemer-compile
	cp chezemax.wasm chezemax.cwasm Chezweb.app/Contents/MacOS/
	mkdir -p Chezweb.app/Contents/MacOS/runtime/wasmtime/lib Chezweb.app/Contents/MacOS/schemer
	cp $(WASMTIME_ROOT)/lib/libwasmtime.dylib Chezweb.app/Contents/MacOS/runtime/wasmtime/lib/
	cp schemer/*.scm schemer/compiler.wasm schemer/compiler.cwasm Chezweb.app/Contents/MacOS/schemer/
	# the program's sources, for chezemax --compile-scripts
	rm -rf Chezweb.app/Contents/MacOS/compiled
	mkdir -p Chezweb.app/Contents/MacOS/compiled/scripts
	cp compiled/PROGRAM compiled/*.scm Chezweb.app/Contents/MacOS/compiled/
	cp compiled/scripts/ORDER compiled/scripts/*.scm Chezweb.app/Contents/MacOS/compiled/scripts/
	cp $(WASMTIME_ROOT)/LICENSE Chezweb.app/Contents/MacOS/runtime/wasmtime/
	mkdir -p Chezweb.app/Contents/MacOS/build
	cp chezweb-server Chezweb.html Chezweb.app/Contents/MacOS/
	cp build/chezweb.js build/chezweb.wasm Chezweb.app/Contents/MacOS/build/
	mkdir -p Chezweb.app/Contents/Resources/browser-licenses
	cp web/prebuilt/licenses/* Chezweb.app/Contents/Resources/browser-licenses/

# A Debian/Ubuntu package of what was built here (tools/make-deb.sh):
# build/deb/chezweb_VERSION_ARCH.deb.  For maintainers and the workflow
# .github/workflows/linux-deb.yml; it needs dpkg-dev and SDL2.
.PHONY: deb
deb: chezweb chezweb-gui irene-dixe chezweb-server schemer-compile chezemax.wasm chezemax.cwasm browser
	sh tools/make-deb.sh

.PHONY: check-ui
check-ui: chezemax chezweb browser
	sh tests/terminal-hover.sh
	sh tests/run-spawn.sh
	sh tests/run-browser-launch.sh
	sh tests/run-kill-ring-menu.sh
	sh tests/run-command-help.sh
	sh tests/run-compile-notification.sh
	sh tests/run-script-installer.sh
	$(CC) $(CPPFLAGS) $(CFLAGS) tests/filename-completion.c src/complete.c src/fileprompt.c -o tests/filename-completion-test
	./tests/filename-completion-test
	$(CC) $(CFLAGS) tests/fileprompt.c src/fileprompt.c -o tests/fileprompt-test
	./tests/fileprompt-test
	$(CC) $(CFLAGS) tests/search.c src/search.c -o tests/search-test
	./tests/search-test
	sh tests/provider-protocol.sh
	sh tests/ttfy-protocol.sh

# The compiler is compiled Scheme hosted by Wasmtime, independent of femtoscheme.
schemer-compile: schemer/compiler-driver.c schemer/native-host.o schemer/native-host.h
	$(CC) $(CPPFLAGS) $(CFLAGS) schemer/compiler-driver.c schemer/native-host.o $(WASMTIME_LIBS) -lm -o $@
.PHONY: rebuild-compiler check-selfhost
rebuild-compiler: schemer-compile
	sh schemer/build-compiler.sh
check-selfhost: schemer-compile tests/native-host-test
	sh tests/selfhost-compiler.sh

include web/makefile.inc

# Both interfaces are available after the same make on macOS and Linux.
# The browser bundle is portable WebAssembly, shipped with the source.
all: chezweb $(if $(SDL_LIBS),chezweb-gui) browser

.PHONY: check-web-toolchain-test
check-web-toolchain-test:
	sh tests/emcc-toolchain.sh

.PHONY: check-browser-assets-test
check-browser-assets-test:
	sh tests/browser-assets.sh

.PHONY: check-read-mode
check-read-mode: chezemax chezemax.wasm chezemax.cwasm
	sh tests/run-read-mode.sh

.PHONY: check-gc-allocation
check-gc-allocation: schemer-compile tests/gc-allocation-test
	sh tests/run-gc-allocation.sh
tests/gc-allocation-test: tests/gc-allocation.c schemer/native-host.o
	$(CC) $(CPPFLAGS) $(CFLAGS) $< schemer/native-host.o $(WASMTIME_LIBS) -Wl,-rpath,$(abspath $(WASMTIME_ROOT))/lib -lm -o $@

# Optional research tooling: never dependencies of ordinary make/check.
.PHONY: lean-checker check-lean check-lean-native
lean-checker:
	$(MAKE) -C Lean
check-lean:
	$(MAKE) -C Lean check audit
check-lean-native: chezemax chezemax.wasm chezemax.cwasm
	$(MAKE) -C Lean native-check

# The native stress driver is included by the tester translation unit.
src/chez-tester.o: src/chez-edit-tester.h src/chez-search-tester.h

.PHONY: check-history check-lean-edit
check-history: chezemax schemer-compile
	sh tests/history-limits.sh
check-lean-edit: chezemax chezemax.wasm chezemax.cwasm
	$(MAKE) -C Lean edit-check

.PHONY: check-lean-search
check-lean-search: chezemax chezemax.wasm chezemax.cwasm
	$(MAKE) -C Lean search-check

# Native browser persistence helpers are included by the bridge.
src/browser-launch.o: src/browser-save.h

# Vertical motion without word wrapping must land on UTF-8 boundaries.
ifeq ($(UNAME_S),Darwin)
NAV_TEST_LDFLAGS = -Wl,-dead_strip
else
NAV_TEST_LDFLAGS = -Wl,--gc-sections
endif
# PE linkers retain public routines; LTO removes unused test-only dependencies.
NAV_TEST_CFLAGS = -ffunction-sections -fdata-sections
ifneq ($(filter CYGWIN%,$(UNAME_S)),)
NAV_TEST_CFLAGS += -flto -fwhole-program
NAV_TEST_LDFLAGS += -Wl,--exclude-all-symbols
endif
.PHONY: check-navigation
check-navigation:
	@set -eu; work=$$(mktemp -d "$${TMPDIR:-/tmp}/chezweb-navigation.XXXXXX"); \
	  trap 'rm -rf "$$work"' EXIT HUP INT TERM; \
	  $(CC) $(CFLAGS) $(NAV_TEST_CFLAGS) -Isrc tests/unwrapped-navigation.c tests/no-terminal.c src/display.c src/width.c src/narrow.c src/fold.c $(NAV_TEST_LDFLAGS) -o "$$work/check"; \
	  "$$work/check"
check: check-navigation

.PHONY: check-utf8-input
check-utf8-input:
	@set -eu; work=$$(mktemp -d "$${TMPDIR:-/tmp}/chezweb-utf8-input.XXXXXX"); \
	  trap 'rm -rf "$$work"' EXIT HUP INT TERM; \
	  $(CC) $(CFLAGS) $(NAV_TEST_CFLAGS) -Isrc -Deditor_mouse_event=input_test_mouse -DkeyboardDefinition=input_test_undefined -c src/key.c -o "$$work/key.o"; \
	  $(CC) $(CFLAGS) $(NAV_TEST_CFLAGS) -Isrc tests/utf8-input.c tests/no-terminal.c "$$work/key.o" src/command.c src/gap.c src/display.c src/width.c src/buffer.c src/narrow.c src/fold.c $(NAV_TEST_LDFLAGS) -o "$$work/check"; \
	  "$$work/check"
check: check-utf8-input

.PHONY: check-utf8-typing
check-utf8-typing: chezemax chezemax.wasm chezemax.cwasm
	sh tests/utf8-typing.sh
check: check-utf8-typing

.PHONY: check-chinese-input
check-chinese-input: chezemax chezemax.wasm chezemax.cwasm
	sh tests/chinese-input.sh
check: check-chinese-input

.PHONY: check-korean-input
check-korean-input: chezemax chezemax.wasm chezemax.cwasm
	sh tests/korean-input.sh
check: check-korean-input

.PHONY: check-latex-export
check-latex-export: chezemax chezemax.wasm chezemax.cwasm
	sh tests/latex-export.sh
check: check-latex-export

.PHONY: check-terminal
check-terminal: chezemax chezemax.wasm chezemax.cwasm
	sh tests/terminal.sh
check: check-terminal

.PHONY: check-ghost-window
check-ghost-window: chezemax chezemax.wasm chezemax.cwasm
	sh tests/ghost-window.sh
check: check-ghost-window

.PHONY: check-polytonic
check-polytonic: chezemax chezemax.wasm chezemax.cwasm
	sh tests/polytonic.sh
check: check-polytonic

.PHONY: check-char-width
check-char-width: chezemax chezemax.wasm chezemax.cwasm
	sh tests/char-width.sh
check: check-char-width

.PHONY: check-backdoor-guard
check-backdoor-guard: chezemax chezemax.wasm chezemax.cwasm
	sh tests/backdoor-guard.sh
check: check-backdoor-guard
.PHONY: check-backdoor-config
check-backdoor-config: chezemax chezemax.wasm chezemax.cwasm
	sh tests/backdoor-config.sh
check: check-backdoor-config
.PHONY: check-yank-window
check-yank-window: chezemax chezemax.wasm chezemax.cwasm
	sh tests/yank-window.sh
check: check-yank-window
.PHONY: check-org-mode
check-org-mode: chezemax chezemax.wasm chezemax.cwasm
	sh tests/org-mode.sh
check: check-org-mode
.PHONY: check-org-goto
check-org-goto: chezemax chezemax.wasm chezemax.cwasm
	sh tests/org-goto.sh
check: check-org-goto
.PHONY: check-org-fold
check-org-fold: chezemax chezemax.wasm chezemax.cwasm
	sh tests/org-fold.sh
check: check-org-fold

.PHONY: check-markdown-blank-newline
check-markdown-blank-newline: chezemax chezemax.wasm chezemax.cwasm
	sh tests/markdown-blank-newline.sh
check: check-markdown-blank-newline

.PHONY: check-bracketed-paste
check-bracketed-paste: chezemax chezemax.wasm chezemax.cwasm
	sh tests/bracketed-paste.sh
check: check-bracketed-paste

.PHONY: check-paste-decoder
check-paste-decoder:
	@set -eu; work=$$(mktemp -d "$${TMPDIR:-/tmp}/chezweb-paste-decoder.XXXXXX"); \
	  trap 'rm -rf "$$work"' EXIT HUP INT TERM; \
	  $(CC) $(CFLAGS) $(NAV_TEST_CFLAGS) -DTERMINAL_PASTE_LIMIT=32 -Isrc tests/bracketed-paste.c tests/no-terminal.c src/command.c $(NAV_TEST_LDFLAGS) -o "$$work/check"; \
	  "$$work/check"
check: check-paste-decoder
