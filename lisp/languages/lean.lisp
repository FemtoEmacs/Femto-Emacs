;;;; lean.lisp -- syntax highlighting for Lean
;;;;
;;;; Loaded at start-up; edit and press C-x C-r (reload-scripts) to see
;;;; the change.  See DEFINE-LANGUAGE in lisp/highlight.lisp for options.

(in-package #:sbemacs)

(define-language "Lean"
  :extensions '(".lean")
  :line-comment "--" :block-comment '("/-" . "-/")
  :word-chars "'!?."
  :keywords '("def" "theorem" "lemma" "example" "structure" "inductive"
              "class" "instance" "where" "match" "with" "fun" "let" "have"
              "show" "by" "do" "if" "then" "else" "namespace" "section" "end"
              "open" "import" "variable" "universe" "calc"))
