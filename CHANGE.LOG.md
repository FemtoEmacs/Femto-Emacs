#Femto Emacs Change Log

## Femto 1.10 6 Nov 2016
* fixed UTF8 char handling in undo for INSERT, BACKSPACE, DEL, INSERT_AT
* fixed DEL, INSERT_AT now working properly at all.
* python support for syntax highlighting

## Femto 1.9 27 Oct 2016
* added discard-undo-history command and lisp interface

## Femto 1.8.1 27 Oct 2016
* removed _(x) macro from header.h
* changed C-o to Esc-; for repl(), frees up Control-O for other editor commands.
* cleaned up call_lisp code in flcall.c
* cleaned up main code that calls init_lisp(), pass size of heap in KB into init_lisp().
* removed double wrapping of lisp commands with the (let ((b buffer)) expression
* changed repl() so that output more than 60 chars is sent to a *lisp_output* buffer that pops up
* changed killbuffer so it does not ask to kill a special buffer (even if modified)
* renamed temp to response_buf and ensured we only use it for getting response at the command line

## Femto 1.8 26 Oct 2016
* Added unlimited undo (supports Insert, Backspace, Yank, Kill-Region, Delete), see docs/undo.txt for details
* Added special buffer mode for buffers that have names starting with * (Thanks to chigoncalves)

## Femto 1.7 9 Oct 2016
* Potential fix for segmentation fault when calling (environment) within FemtoEmacs

## Femto 1.6 8 Oct 2016
* Added apropos Esc-a
* Execute-command Esc-x (with command completion)
* Added list-bindings command
* Sorted key binding list
* Fixed bug with copying first time in a buffer

## Femto 1.5.X dd/mm/yy
* Interim history to be added from got logs

## Femto 1.5 20 June 2016
* Added automatic matching of parenthesis {}() and []
* Fixed bug where a new file created when file not found did not have a buffer created

## Femto 1.4 13 June 2016
* Initialised buffer name to empty string
* Added basic colour scheme

## Femto v1.3 12 June 2016
* Fixed defect with paste command introduced in v1.1
* Added messages on copy and cut to show how many bytes

## Femto v1.2 3 June 2016
* Added UTF8 support

## Femto v1.1 31 May 2016
* Added list-buffers C-x C-b
* fixed problem of opening up multiple output windows
* refactored paste.  Paste now calls insert-string with contents of scrap

## Femto v1.0 29 May 2016
* Added filename completion (use TAB to complete)
* Added shell-command (C-x @), output is read into a buffer
