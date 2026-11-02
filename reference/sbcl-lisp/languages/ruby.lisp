;;;; ruby.lisp -- syntax highlighting and indentation for Ruby
;;;;
;;;; Loaded at start-up; edit and press C-x C-r (reload-scripts) to see
;;;; the change.  See DEFINE-LANGUAGE in lisp/highlight.lisp and
;;;; DEFINE-INDENTATION in lisp/indent.lisp for the options.

(in-package #:sbemacs)

(define-language "Ruby"
  :extensions '(".rb")
  :line-comment "#" :block-comment '("=begin" . "=end")
  :strings '("\"" "'")
  :keywords '("def" "end" "if" "return" "puts" "begin" "while" "until"
              "unless" "or" "and" "not" "class" "module" "do" "elsif" "else"
              "then" "yield"))

(define-indentation "Ruby"
  :style :block :width 2 :tabs nil
  :comment "#"
  :reindent-on-newline t
  :open-words '("def" "class" "module" "if" "unless" "while" "until" "case"
                "begin" "for")
  :mid-words '("else" "elsif" "when" "rescue" "ensure")
  :close-words '("end")
  :close-chars "}"
  :open-endings '("do" "{" "|")
  :electric-keys "defn}" :electric-prefixes '("}")
  :electric-words '("end" "else" "elsif" "when" "rescue" "ensure"))
