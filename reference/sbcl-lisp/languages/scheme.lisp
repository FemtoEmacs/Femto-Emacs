;;;; scheme.lisp -- syntax highlighting and indentation for Scheme
;;;;
;;;; Loaded at start-up; edit and press C-x C-r (reload-scripts) to see
;;;; the change.  See DEFINE-LANGUAGE in lisp/highlight.lisp and
;;;; DEFINE-INDENTATION in lisp/indent.lisp for the options.

(in-package #:sbemacs)

(define-language "Scheme"
  :extensions '(".scm" ".ss" ".lsp")
  :line-comment ";" :block-comment '("#|" . "|#")
  :char-prefix "#\\" :word-chars *lisp-word-chars*
  :keywords '("define" "define-syntax" "lambda" "let" "let*" "letrec" "cond"
              "case" "else" "if" "when" "unless" "begin" "do" "set!" "quote"
              "and" "or"))

(define-indentation "Scheme"
  :style :lisp
  :reindent-on-newline t
  :specials '(("define" . 1) ("define-syntax" . 1) ("define-record-type" . 2)
              ("lambda" . 1) ("let" . 1) ("let*" . 1) ("letrec" . 1)
              ("letrec*" . 1) ("let-values" . 1) ("let*-values" . 1)
              ("let-syntax" . 1) ("letrec-syntax" . 1) ("syntax-rules" . 1)
              ("when" . 1) ("unless" . 1) ("do" . 2) ("case" . 1)
              ("parameterize" . 1) ("guard" . 1) ("receive" . 2)
              ("begin" . 0) ("delay" . 0) ("call-with-values" . 1)
              ("with-exception-handler" . 1)))
