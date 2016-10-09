#Femto Emacs Change Log

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
