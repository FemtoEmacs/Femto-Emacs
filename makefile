#
# makefile
#

CC      = cc
CFLAGS  = -O -Wall -g
LLTDIR 	= ./femtolisp/llt
LD      = cc
LDFLAGS =
LIBS    = -lm -lncursesw
LISPLIBS = femtolisp/libflisp.a femtolisp/llt/libllt.a
CP      = cp
MV      = mv
RM      = rm

E       =
O       = .o

OBJ     = complete$(O) command$(O) data$(O) display$(O) gap$(O) \
             key$(O) search$(O) buffer$(O) replace$(O) utils$(O) window$(O) funcmap$(O) undo$(O)\
             main$(O) femtolisp/interface2editor$(O) \
             femtolisp/flcall$(O)

femtoEmacs$(E) : $(OBJ)
	cd femtolisp && make -f Makefile 
	$(LD) $(LDFLAGS) $(OBJ)  $(LISPLIBS) $(LIBS) -o femto$(E)

interface2editor$(E) : public.h $(OBJ)
	$(CC) $(CFLAGS)  -I$(LLTDIR) -c femtolisp/interface2editor.c

flcall$(E) : $(OBJ)
	$(CC) $(CFLAGS)  -I./femtolisp/llt  -c femtolisp/flcall.c

complete$(O): complete.c header.h public.h
	$(CC) $(CFLAGS)  -I$(LLTDIR) -c complete.c

command$(O): command.c header.h public.h
	$(CC) $(CFLAGS)  -I$(LLTDIR) -c command.c

data$(O): data.c header.h public.h
	$(CC) $(CFLAGS)  -I$(LLTDIR) -c data.c

display$(O): display.c header.h public.h
	$(CC) $(CFLAGS)   -I$(LLTDIR) -c display.c

gap$(O): gap.c header.h public.h
	$(CC) $(CFLAGS)  -I$(LLTDIR) -c gap.c

key$(O): key.c header.h public.h
	$(CC) $(CFLAGS)  -I$(LLTDIR) -c key.c

search$(O): search.c header.h public.h
	$(CC) $(CFLAGS)  -I$(LLTDIR) -c search.c

replace$(O): replace.c header.h public.h
	$(CC) $(CFLAGS)  -I$(LLTDIR) -c replace.c

window$(O): window.c header.h public.h
	$(CC) $(CFLAGS)  -I$(LLTDIR) -c window.c

buffer$(O): buffer.c header.h public.h
	$(CC) $(CFLAGS)  -I$(LLTDIR) -c buffer.c

utils$(O): utils.c header.h public.h
	$(CC) $(CFLAGS)  -I$(LLTDIR) -c utils.c

funcmap$(O): funcmap.c header.h public.h
	$(CC) $(CFLAGS)  -I$(LLTDIR) -c funcmap.c

undo$(O): undo.c header.h public.h
	$(CC) $(CFLAGS)  -I$(LLTDIR) -c undo.c

Main$(O): main.c header.h public.h
	$(CC) $(CFLAGS)  -I$(LLTDIR) -c main.c

clean:
	-$(RM) -f $(OBJ) femto$(E) *.c~ *.h~
	cd femtolisp && make clean
	cd femtolisp/llt && make clean

install:
	-$(MV) femto$(E) $(HOME)/bin

