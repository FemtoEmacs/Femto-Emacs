;;;; common-lisp.lisp -- syntax highlighting for Common Lisp
;;;;
;;;; Loaded at start-up; edit and press C-x C-r (reload-scripts) to see
;;;; the change.  See DEFINE-LANGUAGE in lisp/highlight.lisp for options.

(in-package #:sbemacs)

(define-language "Common Lisp"
  :extensions '(".lisp" ".cl" ".asd" ".el")
  :line-comment ";" :block-comment '("#|" . "|#")
  :char-prefix "#\\" :word-chars *lisp-word-chars* :case-insensitive t
  :keywords '("defun" "defmacro" "defparameter" "defvar" "defconstant"
              "defgeneric" "defmethod" "defclass" "defstruct" "defpackage"
              "in-package" "define-language" "global-set-key"
              "lambda" "let" "let*" "flet" "labels" "progn" "prog1"
              "loop" "for" "do" "do*" "dolist" "dotimes" "return" "return-from"
              "block" "if" "when" "unless" "cond" "case" "ecase" "typecase"
              "and" "or" "not" "setf" "setq" "incf" "decf" "push" "pop"
              "eq" "eql" "equal" "car" "cdr" "cons" "list"
              "handler-case" "unwind-protect" "multiple-value-bind"
              "destructuring-bind"))
