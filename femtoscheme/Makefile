# femtoscheme: a Scheme (R7RS-small subset) derived from femtolisp.
# Native build for macOS (clang) and Linux (gcc or clang). The WebAssembly
# build used by Browsered is in wasm/build.sh.
CC ?= cc

SRCS = flisp.c builtins.c string.c equalhash.c table.c iostream.c
OBJS = $(SRCS:%.c=%.o)
DOBJS = $(SRCS:%.c=%.do)
EXENAME = femtoscheme
LIBTARGET = libfemtoscheme
LLTDIR = llt
LLT = $(LLTDIR)/libllt.a

FLAGS = -Wall -Wno-strict-aliasing -I$(LLTDIR) $(CFLAGS) -DUSE_COMPUTED_GOTO
LIBFILES = $(LLT)
LIBS = $(LIBFILES) -lm

DEBUGFLAGS = -g -DDEBUG $(FLAGS)
SHIPFLAGS = -O2 -DNDEBUG $(FLAGS)

default: release test

test:
	cd tests && ../$(EXENAME) unittest.scm && ../$(EXENAME) r7rs-test.scm

%.o: %.c
	$(CC) $(SHIPFLAGS) -c $< -o $@
%.do: %.c
	$(CC) $(DEBUGFLAGS) -c $< -o $@

flisp.o:  flisp.c cvalues.c operators.c types.c flisp.h print.c read.c equal.c
flisp.do: flisp.c cvalues.c operators.c types.c flisp.h print.c read.c equal.c
flmain.o: flmain.c flisp.h
flmain.do: flmain.c flisp.h

$(LLT):
	cd $(LLTDIR) && $(MAKE) CC="$(CC)"

$(LIBTARGET).da: $(DOBJS)
	rm -rf $@
	ar rs $@ $(DOBJS)

$(LIBTARGET).a: $(OBJS)
	rm -rf $@
	ar rs $@ $(OBJS)

debug: $(DOBJS) $(LIBFILES) $(LIBTARGET).da flmain.do
	$(CC) $(DEBUGFLAGS) $(DOBJS) flmain.do -o $(EXENAME) $(LIBS) $(LIBTARGET).da
	$(MAKE) test

release: $(OBJS) $(LIBFILES) $(LIBTARGET).a flmain.o
	$(CC) $(SHIPFLAGS) $(OBJS) flmain.o -o $(EXENAME) $(LIBS) $(LIBTARGET).a

clean:
	rm -f *.o *.do $(EXENAME) $(LIBTARGET).a $(LIBTARGET).da
	cd $(LLTDIR) && $(MAKE) clean
