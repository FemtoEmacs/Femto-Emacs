;;;; prolog.lisp -- syntax highlighting and indentation for Prolog
;;;;
;;;; Loaded at start-up; edit and press C-x C-r (reload-scripts) to see
;;;; the change.  See DEFINE-LANGUAGE in lisp/highlight.lisp and
;;;; DEFINE-INDENTATION in lisp/indent.lisp for the options.

(in-package #:sbemacs)

(define-language "Prolog"
  :extensions '(".pl" ".pro" ".prolog")
  :line-comment "%" :block-comment '("/*" . "*/")
  :strings '("\"" "'" "`")
  :keywords '(":-" "-->" "is" "not" "\\+" "->" "module" "use_module"
              "dynamic" "discontiguous" "initialization"))

(define-indentation "Prolog"
  :style :prolog :width 4 :tabs nil
  :reindent-on-newline t
  :line-comments '("%") :block-comments '(("/*" . "*/"))
  :strings "\"'`")
