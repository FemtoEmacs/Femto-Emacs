# Femto-Emacs
Tiny emacs clone that can be configured with femtolisp 

## ncurses
femtoemacs requires the libncurses library. This library allows one to treat
a text terminal as an editor window. You must download, build and install 
ncurses.  Here is where to get it:                                                    
                                                                            
http://ftp.gnu.org/gnu/ncurses/                                             
                                                                            
If you DON'T CARE about diacritics, you can compile ncurses as shown below:                                          

> 
> ~$ cd ncurses-6.0 
> ~/ncurses-6.0$ ./configure                                                                 
> ~/ncurses-6.0$ make                                                                        
> ~/ncurses-6.0$ sudo make install                                                           
                                                                            
In English, some people add marks or glyphs to certain letters. For instance,                                    
instead of writing "facade", they write "façade". On the same token, they write                                     
"café" in lieu de "cafe". If you need or like diacritics, you must compile                                        
the libncurses library thus:                                                

> ~$ cd ncurses-6.0/                                                                            
> ~/ncurses-6.0$ ./configure --enable-widec                                                  
> ~/ncurses-6.0$ make                                                                        
> ~/ncurses-6.0$ sudo make install  

## MAC OS-X
The developers of femtoemacs assume that you have placed libncursesw.a here:

/usr/local/lib/libncursesw.a 
            
Therefore, enter the folder where you unpacked the ncursesw-6.0 distribution
archive, and copy the libncursesw.a file to /usr/local/lib/ as shown below.

> ~/$ cd ncurses-6.0
> ~/ncurses-6.0$ cd lib
> ~/ncurses-6.0/lib$ sudo cp libncursesw.a /usr/local/lib/

After installing libncursesw, enter the folder Femto-Emacs/femto/ and build
the editor for Macistosh:

> ~/$ cd ~/Femto-Emacs/femto/
> ~/Femto-Emacs/femto$ make -f Makefile.macosx

You can test the editor in loco:

~/Femto-Emacs/femto$ ./femto test.scm

Of course, you may want to use femto anywhere in the directory tree.
Here is how to achieve this goal:

> ~/Femto-Emacs/femto$ sudo cp femto /usr/local/bin/
> ~/Femto-Emacs/femto$ sudo cp femto.boot /usr/local/bin/
> ~/Femto-Emacs/femto$ cp init.lsp ~/
> ~/Femto-Emacs/femto$ cp aliases.scm ~/


## Linux

Do not use apt-get to install ncurses, because the repositories are old.
Instead, download a recent source distribution and build it thus:

> ~/$ cd ncurses-6.0
> ~/ncurses-6.0$ ./configure --enable-widec                                                  
> ~/ncurses-6.0$ make                                                                        
> ~/ncurses-6.0$ sudo make install

After installing ncursesw, you can make the editor:

> ~/$ cd ~/Femto-Emacs/femto/
> ~/Femto-Emacs/femto$ make

Test the editor in loco:

~/Femto-Emacs/femto$ ./femto test.scm

Then, copy femto to /usr/local/bin in order to make it globally available:

> ~/Femto-Emacs/femto$ sudo cp femto /usr/local/bin/
> ~/Femto-Emacs/femto$ sudo cp femto.boot /usr/local/bin/

You will need the lisp configuration files in your home directory:

> ~/Femto-Emacs/femto$ cp init.lsp ~/
> ~/Femto-Emacs/femto$ cp aliases.scm ~/

Hopefully, you will be able to use femto anywhere in your computer.
You will notice that it will pop up much faster than emacs.

## Short term goals

1 -- Binaries for Windows. Since most windows users don't know how to
     compile applications from source, we need to provide binaries.
     If you want to contribute with mingw binaries, please let us know.

2 -- Documentation. We intend to provide good documentation for people
     who want to extend the editor or adapt femtolisp for this new role
     of scripting language.
     
  
