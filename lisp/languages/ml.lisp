;;;; ml.lisp -- syntax highlighting and indentation for ML
;;;;
;;;; Loaded at start-up; edit and press C-x C-r (reload-scripts) to see
;;;; the change.  See DEFINE-LANGUAGE in lisp/highlight.lisp and
;;;; DEFINE-INDENTATION in lisp/indent.lisp for the options.

(in-package #:sbemacs)

(define-language "ML"
  :extensions '(".ml" ".mli")
  :line-comment "//" :block-comment '("(*" . "*)")
  :word-chars "'"
  :keywords '("let" "rec" "begin" "end" "match" "with" "if" "else" "then"
              "function" "fun" "try" "module" "print_endline" "print_newline"
              "struct" "open_out" "close_out" "input_line" "in" "const"
              "constb" "consti" "vdd" "gnd" "&:" "|:" "^:" "~:" "+:" "-:" "*:"
              "*+" "<:" "<=:" ">:" ">=:" "==:" "<+" "<=+" ">+" ">=+" "<>:"))

(define-indentation "ML"
  :style :block :width 2 :tabs nil
  :cycle t
  :open-endings '("=" "->" "in" "then" "else" "begin" "do" "struct" "sig"
                  "with" "(" "object")
  :close-words '("end" "done" "in")
  :electric-keys "den" :electric-words '("end" "done" "in"))
