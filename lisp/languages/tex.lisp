;;;; tex.lisp -- syntax highlighting and indentation for TeX
;;;;
;;;; Loaded at start-up; edit and press C-x C-r (reload-scripts) to see
;;;; the change.  See DEFINE-LANGUAGE in lisp/highlight.lisp and
;;;; DEFINE-INDENTATION in lisp/indent.lisp for the options.

(in-package #:sbemacs)

(define-language "TeX"
  :extensions '(".tex" ".sty" ".bib")
  :line-comment "%" :strings '() :escape nil
  :backslash-commands t)

(define-indentation "TeX"
  :style :block :width 2 :tabs nil
  :comment "%"
  :reindent-on-newline t
  :open-anywhere '("\\begin{")
  :not-open-anywhere '("\\begin{document}" "\\end{")
  :close-words '("\\end")
  :electric-keys "}" :electric-prefixes '("\\end"))
