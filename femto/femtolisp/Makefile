CC ?= gcc

NAME = flisp
SRCS = $(NAME).c builtins.c string.c equalhash.c table.c iostream.c
OBJS = $(SRCS:%.c=%.o)
DOBJS = $(SRCS:%.c=%.do)
EXENAME = $(NAME)
LIBTARGET = lib$(NAME)
LLTDIR = llt
LLT = $(LLTDIR)/libllt.a

CONFIG = 

FLAGS = -falign-functions -Wall -Wno-strict-aliasing -I$(LLTDIR) $(CFLAGS) -DUSE_COMPUTED_GOTO $(CONFIG)
LIBFILES = $(LLT)
LIBS = $(LIBFILES) -lm

DEBUGFLAGS = -g -DDEBUG $(FLAGS)
SHIPFLAGS = -O2 -DNDEBUG $(FLAGS)

default: release test

test:
	cd tests && ../flisp unittest.lsp

%.o: %.c
	$(CC) -I./llt $(SHIPFLAGS) -c $< -o $@
%.do: %.c
	$(CC) -I./llt $(DEBUGFLAGS) -c $< -o $@

flisp.o:  flisp.c cvalues.c types.c flisp.h print.c read.c equal.c
flisp.do: flisp.c cvalues.c types.c flisp.h print.c read.c equal.c
flmain.o: flmain.c flisp.h
flmain.do: flmain.c flisp.h

$(LLT):
	cd $(LLTDIR) && make -f Makefile

$(LIBTARGET).da: $(DOBJS)
	rm -rf $@
	ar rs $@ $(DOBJS)

$(LIBTARGET).a: $(OBJS)
	rm -rf $@
	ar rs $@ $(OBJS)

debug: $(DOBJS) $(LIBFILES) $(LIBTARGET).da flmain.do
	$(CC) $(DEBUGFLAGS) $(DOBJS) flmain.do -o $(EXENAME) $(LIBS) $(LIBTARGET).da
	make test

release: $(OBJS) $(LIBFILES) $(LIBTARGET).a interface.o flmain.o
	$(CC) $(SHIPFLAGS) $(OBJS) flmain.o interface.o \
             -o $(EXENAME) $(LIBS) $(LIBTARGET).a

clean:
	rm -f *.o
	rm -f *.do
	rm -f $(EXENAME)
	rm -f $(LIBTARGET).a llt/libllt.a
	rm -f $(LIBTARGET).da llt/libllt.da
