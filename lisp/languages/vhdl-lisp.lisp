;;;; vhdl-lisp.lisp -- syntax highlighting for VHDL Lisp
;;;;
;;;; Loaded at start-up; edit and press C-x C-r (reload-scripts) to see
;;;; the change.  See DEFINE-LANGUAGE in lisp/highlight.lisp for options.

(in-package #:sbemacs)

(define-language "VHDL Lisp"
  :extensions '(".vlsp")
  :line-comment "--" :block-comment '("#|" . "|#")
  :word-chars "-"
  :keywords '("library" "use" "define-entity" "def-arch" "is" "out" "in"
              "process" "if" "elsif" "else" "set" "of"))
