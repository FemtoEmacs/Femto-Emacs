;;;; python.lisp -- syntax highlighting and indentation for Python
;;;;
;;;; Loaded at start-up; edit and press C-x C-r (reload-scripts) to see
;;;; the change.  See DEFINE-LANGUAGE in lisp/highlight.lisp and
;;;; DEFINE-INDENTATION in lisp/indent.lisp for the options.

(in-package #:sbemacs)

(define-language "Python"
  :extensions '(".py")
  :line-comment "#"
  :strings '("\"\"\"" "'''" "\"" "'")
  :keywords '("def" "if" "else" "elif" "for" "lambda" "try" "continue"
              "finally" "is" "return" "class" "exec" "in" "raise" "break"
              "except" "import" "print" "assert" "pass" "yield" "as" "global"
              "or" "with" "and" "del" "from" "not" "while" "None" "True"
              "False"))

;;; TAB again cycles through the possible levels: after a block ends
;;; only you know where the next line belongs.
(define-indentation "Python"
  :style :python :width 4 :tabs nil
  :cycle t
  :electric-keys ":" :electric-words '("else" "elif" "except" "finally"))
