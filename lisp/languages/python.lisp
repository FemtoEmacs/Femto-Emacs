;;;; python.lisp -- syntax highlighting for Python
;;;;
;;;; Loaded at start-up; edit and press C-x C-r (reload-scripts) to see
;;;; the change.  See DEFINE-LANGUAGE in lisp/highlight.lisp for options.

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
