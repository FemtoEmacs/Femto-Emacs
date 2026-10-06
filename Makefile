#
# SBEmacs makefile
#
#   make            build the editor core library and the sbemacs launcher
#   make install    install into $(PREFIX) (default /usr/local)
#   make test       run the non-interactive Lisp test suite
#
# Requirements: a C compiler, ncurses (wide-char build) and SBCL.
#

PREFIX  ?= /usr/local
SBCL    ?= sbcl
CC      ?= cc
CFLAGS  ?= -O2 -g
CFLAGS  += -Wall -fPIC
LDFLAGS ?=

UNAME_S := $(shell uname -s 2>/dev/null || echo Windows)

ifeq ($(UNAME_S),Darwin)
  LIBEXT       = dylib
  SHARED       = -dynamiclib
  NCURSES_LIBS ?= -lncurses
else ifneq (,$(findstring MINGW,$(UNAME_S))$(findstring MSYS,$(UNAME_S))$(findstring Windows,$(UNAME_S)))
  # MSYS2 MINGW64 shell; ncurses is linked statically into the DLL
  EXE          = .exe
  LIBEXT       = dll
  SHARED       = -shared -static-libgcc
  CFLAGS      := $(filter-out -fPIC,$(CFLAGS)) -DNCURSES_STATIC \
                 $(shell pkg-config --cflags ncursesw 2>/dev/null)
  NCURSES_LIBS ?= -Wl,-Bstatic $(shell pkg-config --static --libs ncursesw 2>/dev/null || echo -lncursesw) -Wl,-Bdynamic
else
  LIBEXT       = so
  # -Bsymbolic: the core's internal calls must never be resolved to
  # same-named symbols exported by the SBCL runtime
  SHARED       = -shared -Wl,-Bsymbolic
  CFLAGS      += $(shell pkg-config --cflags ncursesw 2>/dev/null)
  NCURSES_LIBS ?= $(shell pkg-config --libs ncursesw 2>/dev/null || echo -lncursesw)
endif

ARCH     := $(shell uname -m 2>/dev/null || echo x86_64)
OS_NAME  := $(if $(EXE),windows,$(if $(filter Darwin,$(UNAME_S)),macos,linux))
DISTNAME ?= sbemacs-$(OS_NAME)-$(ARCH)

LIB  = libsbemacs.$(LIBEXT)
SRCS = $(wildcard src/*.c)
OBJS = $(SRCS:.c=.o)

all: $(LIB) sbemacs$(EXE)

$(LIB): $(OBJS)
	$(CC) $(SHARED) $(LDFLAGS) -o $@ $(OBJS) $(NCURSES_LIBS)

src/%.o: src/%.c src/header.h src/public.h
	$(CC) $(CFLAGS) -c $< -o $@

# The executable is a saved SBCL image holding the Lisp engine plus a
# compiled copy of the scripts.  Editing a script does NOT need a rebuild:
# changed scripts are loaded at start-up (see lisp/loader.lisp).
sbemacs$(EXE): $(LIB) build.lisp $(wildcard lisp/*.lisp lisp/*/*.lisp)
	$(SBCL) --noinform --non-interactive --no-sysinit --no-userinit \
	        --load build.lisp

test: $(LIB)
	$(SBCL) --noinform --non-interactive --no-sysinit --no-userinit \
	        --load tests/run-tests.lisp

# a self-contained directory for a release archive
dist: all
	rm -rf dist/$(DISTNAME)
	mkdir -p dist/$(DISTNAME)
	cp sbemacs$(EXE) $(LIB) README.md CHANGE.LOG.md dist/$(DISTNAME)/
	cp -R lisp samples dist/$(DISTNAME)/

install: all
	install -d $(DESTDIR)$(PREFIX)/bin $(DESTDIR)$(PREFIX)/lib/sbemacs
	install -m 755 sbemacs $(DESTDIR)$(PREFIX)/lib/sbemacs/sbemacs
	install -m 644 $(LIB) $(DESTDIR)$(PREFIX)/lib/sbemacs/$(LIB)
	cp -R lisp $(DESTDIR)$(PREFIX)/lib/sbemacs/
	ln -sf ../lib/sbemacs/sbemacs $(DESTDIR)$(PREFIX)/bin/sbemacs

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/bin/sbemacs
	rm -rf $(DESTDIR)$(PREFIX)/lib/sbemacs

clean:
	rm -rf src/*.o $(LIB) sbemacs sbemacs.exe build dist

.PHONY: all test dist install uninstall clean
