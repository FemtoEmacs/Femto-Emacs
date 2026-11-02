;;;; c.lisp -- syntax highlighting and indentation for C
;;;;
;;;; Loaded at start-up; edit and press C-x C-r (reload-scripts) to see
;;;; the change.  See DEFINE-LANGUAGE in lisp/highlight.lisp and
;;;; DEFINE-INDENTATION in lisp/indent.lisp for the options.

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

(define-indentation "C"
  :style :c :width 4
  :preprocessor t :case-labels t
  :reindent-on-newline t
  :electric-keys "{}:#" :electric-prefixes '("{" "}" "#")
  :electric-words '("case" "default"))
