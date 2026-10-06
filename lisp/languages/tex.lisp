;;;; tex.lisp -- syntax highlighting for TeX
;;;;
;;;; Loaded at start-up; edit and press C-x C-r (reload-scripts) to see
;;;; the change.  See DEFINE-LANGUAGE in lisp/highlight.lisp for options.

(in-package #:sbemacs)

(define-language "TeX"
  :extensions '(".tex" ".sty" ".bib")
  :line-comment "%" :strings '() :escape nil
  :backslash-commands t)
