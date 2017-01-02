[![Join the chat at https://gitter.im/FemtoLisp/flisp](https://badges.gitter.im/FemtoLisp/flisp.svg)](https://gitter.im/FemtoLisp/flisp)

# Femto-Emacs
Tiny emacs clone that can be configured with femtolisp

## ncurses femtoemacs requires the `ncurses` library. This library
allows one to treat a text terminal as an editor window. You must
download, build and install ncurses. You can obtain it
[here](http://ftp.gnu.org/gnu/ncurses/).


In English, some people add marks or glyphs to certain letters. For
instance, instead of writing "facade", they write "façade". On the
same token, they write "café" in lieu de "cafe". If you need or like
diacritics, you must compile the libncurses library thus:


```shell
% cd ncurses-6.0/
% ./configure --enable-widec
% make
% sudo make install
```

## MAC OS-X
The developers of femtoemacs assume that you have placed
`libncursesw.a` here:

`/usr/local/lib/libncursesw.a`

Therefore, enter the folder where you unpacked the ncursesw-6.0
distribution archive, and copy the `libncursesw.a` file to
`/usr/local/lib/` as shown below.

```
% cd ncurses-6.0
% cd lib
% sudo cp libncursesw.a /usr/local/lib/
```

After installing `libncursesw`, enter the folder `Femto-Emacs/femto/`
and build the editor for Macistosh:

```
% cd ~/Femto-Emacs/
% make -f Makefile.macosx
% sudo make -f Makefile.macosx install
```

You can test the editor in loco:

```
% femto test.scm
```

You can remove Femto-Emacs from your system with the following command:

```
% sudo sh uninstall.sh
```




## Linux

Do not use `apt-get` to install ncurses, because the repositories are
old. Instead, download a recent source distribution and build it thus:

```
% cd ncurses-6.0
% ./configure --enable-widec
% make
% sudo make install
```

After installing `ncursesw`, you can make the editor:

```
% cd ~/Femto-Emacs/
% make
% sudo make install 
```

Test the editor in loco:

```
% femto test.scm
```

You can remove Femto-Emacs from your system with the following command:

```
% sudo sh uninstall.sh
```


Hopefully, you will be able to use femto anywhere in your computer.
You will notice that it will pop up much faster than emacs.

## Short term goals

Binaries for Windows. Since most Windows users don't know how to
compile applications from source, we need to provide binaries. If you
want to contribute with mingw binaries, please let us know.

Documentation. We intend to provide good documentation for people who
want to extend the editor or adapt femtolisp for this new role of
scripting language.


## Lisp Interaction Mode

There are two way to interact with Femto Lisp from inside FemtoEmacs.

At a command prompt: Enter <kbd>C-o</kbd> and type a lisp command
followed by <kbd>return</kbd>. The result is inserted into the current
*buffer* at the cursor location

Inside the actual buffer: Place the cursor on the openning or closing
bracket `(` or `)`. This will define a block. Now enter
<kbd>ESC-]</kbd>. The code will be copied to the *FemtoLisp*
interpreter and the result inserted into the *buffer*. This is very
useful for trying out bits of lisp code when developing Emacs
extensions.


## Integration of Femto with Femtolisp to be become FemtoEmacs

**Femtolisp** required three modifications, in order to work as a
script language for `femto`. In the file `flcall.c` you will be find
the functions `callLisp` and `initLisp`, that are used for calling a
*Lisp* function from *C* and initializing *Lisp*, respectively. In
file `interface2editor.c` you will find all functions directly related
to the editor.

It is also necessary to generate a *boot* and a *compiler* without a
*Read Eval Print Loop*. This is done in file `mkeditorboot.lsp`, that
has three lines:

```scheme
(load "femtosystem.lsp")            ;; system without Read Eval Print Loop
(load "compiler.lsp")               ;; compiler exactly like femtolisp compiler
(make-system-image "femto.boot")    ;; generate femto.boot
```

The only difference between `femto.boot` and `flisp.boot` is in
function `__start`, that does nothing in the editor, besides
initializing the global environment.

```scheme
(define (__start argv)
  (__init_globals))
```

In **femtolisp**, this funcion is defined in `system.lsp`, and
implements the *Read Eval Print Loop*:

```scheme
(define (__start argv)
  (__init_globals)
   (if (pair? (cdr argv))
       (begin
	     (set! *argv* (cdr argv))
         (set! *interactive* #f)
         (__script (cadr argv)))
       (begin
	     (set! *argv* argv)
         (set! *interactive* #t)
         (princ *banner*)
         (repl)))
  (exit 0))
```

The `__start` function is called in `flcall.c`:

```c
(void)fl_applyn(1, symbol_value(symbol("__start")),
	            argv_list(argc, argv));
```
