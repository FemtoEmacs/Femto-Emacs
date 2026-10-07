#
# SBEmacs makefile
#
#   make            build the editor libraries and the sbemacs executable
#   make install    install into $(PREFIX) (default /usr/local)
#   make test       run the non-interactive Lisp test suite
#
# Requirements: a C compiler, ncurses (wide-char build) and SBCL; for the
# GUI also SDL2 and SDL2_ttf.
#

PREFIX  ?= /usr/local
SBCL    ?= sbcl
CC      ?= cc
CFLAGS  ?= -O2 -g
CFLAGS  += -Wall -fPIC
LDFLAGS ?=

UNAME_S := $(shell uname -s 2>/dev/null || echo Windows)
PKG_CONFIG ?= pkg-config

# the GUI library is built when SDL2 and SDL2_ttf are installed
SDL_CFLAGS ?= $(shell $(PKG_CONFIG) --cflags sdl2 SDL2_ttf 2>/dev/null)
SDL_LIBS   ?= $(shell $(PKG_CONFIG) --libs sdl2 SDL2_ttf 2>/dev/null)

ifeq ($(UNAME_S),Darwin)
  LIBEXT       = dylib
  SHARED       = -dynamiclib
  NCURSES_LIBS ?= -lncurses
else ifneq (,$(findstring MINGW,$(UNAME_S))$(findstring MSYS,$(UNAME_S))$(findstring Windows,$(UNAME_S)))
  # MSYS2 MINGW64 shell; ncurses is linked statically into the DLL
  EXE          = .exe
  LIBEXT       = dll
  SHARED       = -shared -static-libgcc
  CFLAGS      := $(filter-out -fPIC,$(CFLAGS))
  NCURSES_CFLAGS ?= -DNCURSES_STATIC $(shell pkg-config --cflags ncursesw 2>/dev/null)
  NCURSES_LIBS ?= -Wl,-Bstatic $(shell pkg-config --static --libs ncursesw 2>/dev/null || echo -lncursesw) -Wl,-Bdynamic
  # a DLL has no main(): drop SDL's WinMain wrapper
  SDL_LIBS    := $(filter-out -lSDL2main -lmingw32 -mwindows,$(SDL_LIBS))
else
  LIBEXT       = so
  # -Bsymbolic: the core's internal calls must never be resolved to
  # same-named symbols exported by the SBCL runtime
  SHARED       = -shared -Wl,-Bsymbolic
  NCURSES_CFLAGS ?= $(shell pkg-config --cflags ncursesw 2>/dev/null)
  NCURSES_LIBS ?= $(shell pkg-config --libs ncursesw 2>/dev/null || echo -lncursesw)
endif

ARCH     := $(shell uname -m 2>/dev/null || echo x86_64)
OS_NAME  := $(if $(EXE),windows,$(if $(filter Darwin,$(UNAME_S)),macos,linux))
DISTNAME ?= sbemacs-$(OS_NAME)-$(ARCH)

# Two libraries with the same editor core and the same fe_* API: one draws
# in a terminal with ncurses, the other in a window with SDL2.  The
# sbemacs executable loads one of them at start-up (--gui for the window).
TERM_LIB = libsbemacs-term.$(LIBEXT)
GUI_LIB  = libsbemacs-gui.$(LIBEXT)
LIBS     = $(TERM_LIB) $(if $(SDL_LIBS),$(GUI_LIB))

CORE_SRCS = $(filter-out src/term.c src/gui.c,$(wildcard src/*.c))
CORE_OBJS = $(CORE_SRCS:.c=.o)

all: $(LIBS) sbemacs$(EXE)
	@$(if $(SDL_LIBS),,echo "note: SDL2/SDL2_ttf not found, built the terminal version only")

$(TERM_LIB): $(CORE_OBJS) src/term.o
	$(CC) $(SHARED) $(LDFLAGS) -o $@ $(CORE_OBJS) src/term.o $(NCURSES_LIBS)

$(GUI_LIB): $(CORE_OBJS) src/gui.o
	$(CC) $(SHARED) $(LDFLAGS) -o $@ $(CORE_OBJS) src/gui.o $(SDL_LIBS)

src/term.o: src/term.c src/screen.h
	$(CC) $(CFLAGS) $(NCURSES_CFLAGS) -c $< -o $@

src/gui.o: src/gui.c src/screen.h
	$(CC) $(CFLAGS) $(SDL_CFLAGS) -c $< -o $@

src/%.o: src/%.c src/header.h src/public.h src/screen.h
	$(CC) $(CFLAGS) -c $< -o $@

# The executable is a saved SBCL image holding the Lisp engine plus a
# compiled copy of the scripts.  Editing a script does NOT need a rebuild:
# changed scripts are loaded at start-up (see lisp/loader.lisp).
sbemacs$(EXE): $(TERM_LIB) build.lisp $(wildcard lisp/*.lisp lisp/*/*.lisp)
	$(SBCL) --noinform --non-interactive --no-sysinit --no-userinit \
	        --load build.lisp

test: $(TERM_LIB)
	$(SBCL) --noinform --non-interactive --no-sysinit --no-userinit \
	        --load tests/run-tests.lisp

# a self-contained directory for a release archive
dist: all
	rm -rf dist/$(DISTNAME)
	mkdir -p dist/$(DISTNAME)
	cp sbemacs$(EXE) $(LIBS) README.md CHANGE.LOG.md dist/$(DISTNAME)/
	cp -R lisp samples dist/$(DISTNAME)/

install: all
	install -d $(DESTDIR)$(PREFIX)/bin $(DESTDIR)$(PREFIX)/lib/sbemacs
	install -m 755 sbemacs $(DESTDIR)$(PREFIX)/lib/sbemacs/sbemacs
	install -m 644 $(LIBS) $(DESTDIR)$(PREFIX)/lib/sbemacs/
	cp -R lisp $(DESTDIR)$(PREFIX)/lib/sbemacs/
	ln -sf ../lib/sbemacs/sbemacs $(DESTDIR)$(PREFIX)/bin/sbemacs
	ln -sf ../lib/sbemacs/sbemacs $(DESTDIR)$(PREFIX)/bin/sbemacs-gui

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/bin/sbemacs $(DESTDIR)$(PREFIX)/bin/sbemacs-gui
	rm -rf $(DESTDIR)$(PREFIX)/lib/sbemacs

clean:
	rm -rf src/*.o libsbemacs*.* sbemacs sbemacs.exe build dist

# The Windows setup program, made on Linux (see the script)
windows-installer:
	sh windows/build-installer.sh

.PHONY: all test dist install uninstall clean windows-installer
