;;;; prolog.lisp -- syntax highlighting for Prolog
;;;;
;;;; Loaded at start-up; edit and press C-x C-r (reload-scripts) to see
;;;; the change.  See DEFINE-LANGUAGE in lisp/highlight.lisp for options.

(in-package #:sbemacs)

(define-language "Prolog"
  :extensions '(".pl" ".pro" ".prolog")
  :line-comment "%" :block-comment '("/*" . "*/")
  :strings '("\"" "'" "`")
  :keywords '(":-" "-->" "is" "not" "\\+" "->" "module" "use_module"
              "dynamic" "discontiguous" "initialization"))
