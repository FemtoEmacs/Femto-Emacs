;;;; c.lisp -- syntax highlighting for C
;;;;
;;;; Loaded at start-up; edit and press C-x C-r (reload-scripts) to see
;;;; the change.  See DEFINE-LANGUAGE in lisp/highlight.lisp for options.

(in-package #:sbemacs)

(define-language "C"
  :extensions '(".c" ".h")
  :line-comment "//" :block-comment '("/*" . "*/")
  :strings '("\"" "'")
  :keywords '("auto" "break" "case" "char" "const" "continue" "default" "do"
              "double" "else" "enum" "extern" "float" "for" "goto" "if" "int"
              "long" "register" "return" "short" "signed" "sizeof" "static"
              "struct" "switch" "typedef" "union" "unsigned" "void" "volatile"
              "while" "#include" "#define" "#ifdef" "#ifndef" "#if" "#else"
              "#endif"))
