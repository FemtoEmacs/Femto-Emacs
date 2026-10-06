;;;; haskell.lisp -- syntax highlighting and indentation for Haskell
;;;;
;;;; Loaded at start-up; edit and press C-x C-r (reload-scripts) to see
;;;; the change.  See DEFINE-LANGUAGE in lisp/highlight.lisp and
;;;; DEFINE-INDENTATION in lisp/indent.lisp for the options.

(in-package #:sbemacs)

(define-language "Haskell"
  :extensions '(".hs" ".lhs")
  :line-comment "--" :block-comment '("{-" . "-}")
  :word-chars "'"
  :keywords '("if" "then" "else" "case" "of" "where" "data" "deriving" "type"
              "class" "instance" "import" "do" "let" "in" "module" "newtype"))

(define-indentation "Haskell"
  :style :block :width 4 :tabs nil
  :comment "--"
  :cycle t
  :open-endings '("where" "=" "do" "of" "->" "let" "then" "else" "(" "[" "{")
  :close-words '("in"))
