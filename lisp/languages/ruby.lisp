;;;; ruby.lisp -- syntax highlighting for Ruby
;;;;
;;;; Loaded at start-up; edit and press C-x C-r (reload-scripts) to see
;;;; the change.  See DEFINE-LANGUAGE in lisp/highlight.lisp for options.

(in-package #:sbemacs)

(define-language "Ruby"
  :extensions '(".rb")
  :line-comment "#" :block-comment '("=begin" . "=end")
  :strings '("\"" "'")
  :keywords '("def" "end" "if" "return" "puts" "begin" "while" "until"
              "unless" "or" "and" "not" "class" "module" "do" "elsif" "else"
              "then" "yield"))
