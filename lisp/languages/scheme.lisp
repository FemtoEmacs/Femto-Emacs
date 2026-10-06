;;;; scheme.lisp -- syntax highlighting for Scheme
;;;;
;;;; Loaded at start-up; edit and press C-x C-r (reload-scripts) to see
;;;; the change.  See DEFINE-LANGUAGE in lisp/highlight.lisp for options.

(in-package #:sbemacs)

(define-language "Scheme"
  :extensions '(".scm" ".ss" ".lsp")
  :line-comment ";" :block-comment '("#|" . "|#")
  :char-prefix "#\\" :word-chars *lisp-word-chars*
  :keywords '("define" "define-syntax" "lambda" "let" "let*" "letrec" "cond"
              "case" "else" "if" "when" "unless" "begin" "do" "set!" "quote"
              "and" "or"))
