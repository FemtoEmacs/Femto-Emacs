# Optional browser build: Chrome JSPI, same C core and compiled Scheme.
EMCC ?= emcc
WEB_CORE = $(filter-out src/compiled.c src/compile-scripts.c,$(CORE))
WEB_FEMTO = $(addprefix femtoscheme/,flisp.c builtins.c string.c equalhash.c table.c iostream.c)
WEB_LLT = $(addprefix femtoscheme/llt/,bitvector.c hashing.c socket.c timefuncs.c ptrhash.c utf8.c ios.c dirpath.c htable.c bitvector-ops.c int2str.c dump.c random.c lltinit.c)
WEB_CFLAGS = -fwasm-exceptions -sSUPPORT_LONGJMP=wasm -O2 -std=gnu11 -Wno-everything -DSBEMACS_GUI -DNDEBUG -Isrc -Ifemtoscheme -Ifemtoscheme/llt
WEB_EXPORTS = _main,_malloc,_free,_web_set_scrap,_web_ccall,_web_module_buffer,_web_module_size,_web_editor_request,_web_layer_set,_web_layer_on
.PHONY: browser browser-rebuild check-web-toolchain check-browser-assets
# Users install the bundled, platform-independent browser build. The SDK is
# used only when a maintainer explicitly requests browser-rebuild.
WEB_BUNDLE_INPUTS := $(shell awk '{print $$2}' web/prebuilt/SHA256SUMS 2>/dev/null)
check-browser-assets:
	sh tools/browser-assets.sh check
browser: check-browser-assets Chezweb.html chezweb-server
build/browser-assets.stamp: web/prebuilt/SHA256SUMS tools/browser-assets.sh $(WEB_BUNDLE_INPUTS)
	sh tools/browser-assets.sh install
build/chezweb.js build/chezweb.wasm: build/browser-assets.stamp
	@test -f "$@" || sh tools/browser-assets.sh install
Chezweb.html: web/shell.html build/chezweb.js build/chezweb.wasm
	cp web/shell.html $@

# Maintainers rebuild and record the browser bundle before publishing changed
# editor sources. Ordinary make/browser never executes a browser compiler.
check-web-toolchain:
	EMCC="$(EMCC)" sh tools/check-emcc.sh
browser-rebuild: check-web-toolchain chezemax.wasm
	mkdir -p build/browser-dev
	$(EMCC) $(WEB_CFLAGS) -Dmain=app_main -c src/app.c -o build/browser-dev/web-app.o
	$(EMCC) $(WEB_CFLAGS) -sJSPI=1 -sJSPI_EXPORTS=main,web_ccall,web_editor_request -sALLOW_MEMORY_GROWTH=1 -sSTACK_SIZE=4194304 -sENVIRONMENT=web -sEXIT_RUNTIME=0 -sEXPORTED_FUNCTIONS=$(WEB_EXPORTS) -sEXPORTED_RUNTIME_METHODS=UTF8ToString,stringToUTF8,lengthBytesUTF8,stringToNewUTF8,FS \
	  -Wl,--wrap=getfilename -Wl,--wrap=getfilename_default -Wl,--wrap=line_edit -Wl,--wrap=call_lisp_event $(WEB_CORE) web/screen.c web/text-layer.c web/host.c web/main.c build/browser-dev/web-app.o $(WEB_FEMTO) $(WEB_LLT) \
	  --pre-js web/scheme-host.js --pre-js web/runtime.js --pre-js web/files.js --pre-js web/shell.js --pre-js web/grammarly.js --pre-js web/page.js \
	  --embed-file femtoscheme/femtoscheme.boot@/femtoscheme/femtoscheme.boot \
	  --embed-file schemer/compiler.wasm@/schemer/compiler.wasm --embed-file chezemax.wasm@/chezemax.wasm --embed-file scheme@/scheme --exclude-file '*/bkp/*' -o build/browser-dev/chezweb.js
	sh tools/browser-assets.sh record build/browser-dev
	sh tools/browser-assets.sh install
	cp web/shell.html Chezweb.html

chezweb-server: tools/web-server.c
	$(CC) -O2 -std=gnu11 -Wall -Wextra $< -o $@

# A new file, never a copy over the old one: macOS kills a program whose
# file was overwritten in place (its signature no longer matches).
chezweb: chezemax chezweb-server
	rm -f chezweb
	cp chezemax chezweb
chezweb-gui: chezemax-gui
	rm -f chezweb-gui
	cp chezemax-gui chezweb-gui

.PHONY: check-browser run
# Development only: npm's playwright package and an installed Google Chrome.
check-browser: browser chezweb
	node tests/chezweb-server.cjs
	node tests/chezweb-web.cjs
	node tests/chezweb-files.cjs
	node tests/chezweb-shell.cjs
	node tests/chezweb-multiple-folders.cjs
	node tests/chezweb-grammarly.cjs
	node tests/chezweb-settings.cjs
	node tests/chezweb-tab-pick.cjs
	node tests/chezweb-browser-only.cjs
	sh tests/run-chezweb-program.sh
	sh tests/chezweb-native-shell.sh
	node tests/chezweb-native.cjs
run: chezweb
	./chezweb
