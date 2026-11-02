; -*- scheme -*-
; Stage 1 of the bootstrap: load the sources and write the boot image.

(load "system.scm")
(load "compiler.scm")
(load "r7rs.scm")
(make-system-image "femtoscheme.boot")
