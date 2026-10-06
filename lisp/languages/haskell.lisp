;;;; haskell.lisp -- syntax highlighting for Haskell
;;;;
;;;; Loaded at start-up; edit and press C-x C-r (reload-scripts) to see
;;;; the change.  See DEFINE-LANGUAGE in lisp/highlight.lisp for options.

(in-package #:sbemacs)

(define-language "Haskell"
  :extensions '(".hs" ".lhs")
  :line-comment "--" :block-comment '("{-" . "-}")
  :word-chars "'"
  :keywords '("if" "then" "else" "case" "of" "where" "data" "deriving" "type"
              "class" "instance" "import" "do" "let" "in" "module" "newtype"))
