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
OBJECTS += schemer/native-host.o
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
	$(CC) $(LDFLAGS) $(OBJECTS) src/term.o src/app.o $(RUNTIME) $(CURSES_LIBS) $(PDF_LIBS) $(WASMTIME_LIBS) -lm -o $@
chezemax-gui: $(OBJECTS) src/gui.o src/app-gui.o runtime schemer-compile
	$(CC) $(LDFLAGS) $(OBJECTS) src/gui.o src/app-gui.o $(RUNTIME) $(SDL_LIBS) $(PDF_LIBS) $(WASMTIME_LIBS) -lm -o $@
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
check: check-platform check-browser-assets-test check-web-toolchain-test chezemax check-compiled check-bridge check-library check-scripts
	$(MAKE) -C femtoscheme test
	./chezemax --eval '(+ 20 22)' | grep -x 42
	./chezemax --eval '(get-version-string)' | grep femtoscheme
	CHEZEMAX_SCHEME=femtoscheme CHEZEMAX_NO_INIT=1 ./chezemax --eval '(load "tests/run-tests.scm")'
	! ./chezemax --eval '(error "expected test error")'
	sh tests/run-editor.sh
	sh tests/run-read-mode.sh
	sh tests/run-compile-scripts.sh
clean:
	rm -f src/*.o schemer/*.o tests/native-host-test tests/fileprompt-test tests/filename-completion-test chezemax chezemax-gui irene-dixe tests/search-test chezemax.wasm chezemax.cwasm schemer/compiler.cwasm tests/bridge-test
	$(MAKE) -C femtoscheme clean

.PHONY: app
app: chezweb-gui irene-dixe chezemax.wasm chezemax.cwasm browser
	rm -rf Chezweb.app/Contents/MacOS/scheme
	mkdir -p Chezweb.app/Contents/MacOS/femtoscheme Chezweb.app/Contents/MacOS/ttfy \
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

.PHONY: check-ui
check-ui: chezemax chezweb browser
	sh tests/run-spawn.sh
	sh tests/run-browser-launch.sh
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
