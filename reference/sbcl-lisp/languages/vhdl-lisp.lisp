;;;; vhdl-lisp.lisp -- syntax highlighting and indentation for VHDL Lisp
;;;;
;;;; Loaded at start-up; edit and press C-x C-r (reload-scripts) to see
;;;; the change.  See DEFINE-LANGUAGE in lisp/highlight.lisp and
;;;; DEFINE-INDENTATION in lisp/indent.lisp for the options.

(in-package #:sbemacs)

(define-language "VHDL Lisp"
  :extensions '(".vlsp")
  :line-comment "--" :block-comment '("#|" . "|#")
  :word-chars "-"
  :keywords '("library" "use" "define-entity" "def-arch" "is" "out" "in"
              "process" "if" "elsif" "else" "set" "of"))

(define-indentation "VHDL Lisp"
  :style :lisp
  :reindent-on-newline t
  :specials '(("define-entity" . 1) ("def-arch" . 2) ("process" . 1)))
