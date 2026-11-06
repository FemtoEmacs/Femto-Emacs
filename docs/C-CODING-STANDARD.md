## FEMTOEMACS DESIGN PRINCIPLES

P1) FemtoEmacs is tiny footprint Emacs clone extended using Femtolisp.

P2) We will keep the design simple, with each concept implemented once, so that the code is easy to understand.

P3) FemtoEmacs will be portable to many different OS and Platforms

P4) We will maintain a TERMINAL design, there will be no XWINDOWS support or GUI.

P5) We will keep the amount of C code to a minimum.  If we can do it in SCHEME we will. Exceptions to this principle will be where performance is key or we need to do direct manipulation of the Buffers.  An example of a good exception is unlimited Undo, which should be done in C.

P6) The C code should be rebust, well formatted and best practice where possible, experienced programmers will see quality code

P7) Bug fixes and new features will be prioritised in terms of impact and benefits and in accordance with these design principles.

P8) We are not attempting to compete at the top end of Emacsen or replicate a full implementation of GNU Emacs but to provide a small, useful Emacs editor that performs quickly and can be extended through femtolisp.

P9) Where possible the key-bindings, command names and femtolisp interface names will be compatible with GNU Emacs or MicroEMACS. This will apply mostly to the C-?, C-x C-?, Esc key prefixes.  The C-c ? and C-h ? key-bindings will be user definable.  Unbound keys in the C-?, C-x C-? and Esc-? ranges will also be user definable.


## RULES WHEN COMMITTING CODE

1) Complete a GIT PULL 

2) Check that the code compiles and builds without error, if it does not report the problem and do not attempt to make further changes on a broken codebase.

3) Do your work, code, build, text, code, build test.

4) When ready to PUSH do a PULL First, this checks if the codebase has moved on since step 1.

5) Check if any merges took place - read the messages from GIT

6) Check the files you have been working on for MERGE conflicts - does it have >>>>>head etc in the middle - this indicates a failed auto-merge.

7) Fix any merge conflicts

8) build and test again

9) Now you can safely PUSH.





## CONTRIBUTER CODING STANDARD

When coding in C it is very important that a consistant coding standard is adopted and
that all contributers ensure that there code complies with this standard.

This is because there are a number of area's in the C language where
a silly mistake can lead to disaster, particularly when performing
pointer arithmetic.

The C allows you to do a lot of direct manipulation on memory through
pointers.  However this also allows you to corrupt programme memory
when you make mistakes.  Such errors can be very hard to find as they
dont reproduce consistantly.

The coding style used in Atto, Femto and FemtoEmacs is Kernighan and Ricthie style otherwise known as K&R.

If you are short of time WikiPedia contains a short description of K&R 
   https://en.wikipedia.org/wiki/Indent_style#Variant:_1TBS_.28OTBS.29

The following link contains and excellent discussion around the reasons for these choices and
the problems that are avoided by using these standards.
   https://users.ece.cmu.edu/~eno/coding/CCodingStandard.html

All the original Atto. Femto code was written in this way to enhance readability of the code.

Another very detailed discussion of coding standards was written by
Sun Microsystems a number of years back.  When I worked for Sun your
code would be rejected if it did not comply.

https://www.cis.upenn.edu/~lee/06cse480/data/cstyle.ms.pdf

All the above papers are worth a read if you are going to contribute
to the C code and may save you hours of debugging and looking for
errors.


