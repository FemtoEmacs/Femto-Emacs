;;;; common-lisp.lisp -- syntax highlighting and indentation for Common Lisp
;;;;
;;;; Loaded at start-up; edit and press C-x C-r (reload-scripts) to see
;;;; the change.  See DEFINE-LANGUAGE in lisp/highlight.lisp and
;;;; DEFINE-INDENTATION in lisp/indent.lisp for the options.

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

;;; Forms whose first N arguments are "distinguished" (indented by 4 when
;;; they start a line); the remaining arguments are a body, indented by 2.
;;; Other operators starting with "def" have a body only, "with-" and "do-"
;;; forms one distinguished argument; everything else is a function call,
;;; aligned under its first argument.
(define-indentation "Common Lisp"
  :style :lisp
  :reindent-on-newline t
  :local-function-forms '("flet" "labels" "macrolet")
  :specials '(("block" . 1) ("case" . 1) ("ccase" . 1) ("ecase" . 1)
              ("typecase" . 1) ("etypecase" . 1) ("ctypecase" . 1) ("catch" . 1)
              ("defun" . 2) ("defmacro" . 2) ("defmethod" . 2) ("defgeneric" . 2)
              ("defclass" . 2) ("defstruct" . 1) ("defpackage" . 1) ("deftype" . 2)
              ("define-condition" . 2) ("define-compiler-macro" . 2)
              ("destructuring-bind" . 2) ("multiple-value-bind" . 2)
              ("do" . 2) ("do*" . 2) ("dolist" . 1) ("dotimes" . 1)
              ("flet" . 1) ("labels" . 1) ("macrolet" . 1) ("symbol-macrolet" . 1)
              ("handler-bind" . 1) ("handler-case" . 1) ("restart-case" . 1)
              ("lambda" . 1) ("let" . 1) ("let*" . 1) ("locally" . 0)
              ("progn" . 0) ("prog1" . 1) ("prog2" . 2) ("progv" . 2)
              ("return-from" . 1) ("unless" . 1) ("when" . 1)
              ("unwind-protect" . 1) ("eval-when" . 1)
              ("print-unreadable-object" . 1)
              ("define-language" . 1) ("define-indentation" . 1)
              ("define-indent-style" . 2)
              ;; Emacs Lisp
              ("save-excursion" . 0) ("save-restriction" . 0)
              ("condition-case" . 2) ("while" . 1)))
