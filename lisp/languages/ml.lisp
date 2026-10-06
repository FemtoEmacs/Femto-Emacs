;;;; ml.lisp -- syntax highlighting for ML
;;;;
;;;; Loaded at start-up; edit and press C-x C-r (reload-scripts) to see
;;;; the change.  See DEFINE-LANGUAGE in lisp/highlight.lisp for options.

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
