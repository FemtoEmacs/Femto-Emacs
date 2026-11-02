;;;; scheme.scm -- syntax highlighting and indentation for Scheme
;;;;
;;;; Also the language of Chezemax's own scripts (scheme/*.scm).

(define-language "Scheme"
  'extensions '(".scm" ".ss" ".lsp" ".sld")
  'line-comment ";" 'block-comment '("#|" . "|#")
  'char-prefix "#\\" 'word-chars *lisp-word-chars*
  'keywords '("define" "define-syntax" "define-macro" "define-record-type"
              "lambda" "let" "let*" "letrec" "letrec*" "let-values" "cond"
              "case" "else" "if" "when" "unless" "begin" "do" "set!" "quote"
              "and" "or" "guard" "dynamic-wind" "syntax-rules" "parameterize"
              "defcommand" "global-set-key" "define-language" "define-indentation"))

(define-indentation "Scheme"
  'style 'lisp
  'reindent-on-newline #t
  'specials '(("define" . 1) ("define-syntax" . 1) ("define-record-type" . 2)
              ("define-macro" . 1) ("defcommand" . 1)
              ("lambda" . 1) ("let" . 1) ("let*" . 1) ("letrec" . 1)
              ("letrec*" . 1) ("let-values" . 1) ("let*-values" . 1)
              ("let-syntax" . 1) ("letrec-syntax" . 1) ("syntax-rules" . 1)
              ("when" . 1) ("unless" . 1) ("do" . 2) ("case" . 1)
              ("parameterize" . 1) ("guard" . 1) ("receive" . 2)
              ("begin" . 0) ("delay" . 0) ("call-with-values" . 1)
              ("with-exception-handler" . 1) ("dynamic-wind" . 0)
              ("define-language" . 1) ("define-indentation" . 1)))
