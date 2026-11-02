;;;; vhdl-lisp.scm -- syntax highlighting and indentation for VHDL Lisp

(define-language "VHDL Lisp"
  'extensions '(".vlsp")
  'line-comment "--" 'block-comment '("#|" . "|#")
  'word-chars "-"
  'keywords '("library" "use" "define-entity" "def-arch" "is" "out" "in"
              "process" "if" "elsif" "else" "set" "of"))

(define-indentation "VHDL Lisp"
  'style 'lisp
  'reindent-on-newline #t
  'specials '(("define-entity" . 1) ("def-arch" . 2) ("process" . 1)))
