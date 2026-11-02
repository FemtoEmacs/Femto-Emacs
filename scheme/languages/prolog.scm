;;;; prolog.scm -- syntax highlighting and indentation for Prolog

(define-language "Prolog"
  'extensions '(".pl" ".pro" ".prolog")
  'line-comment "%" 'block-comment '("/*" . "*/")
  'strings '("\"" "'" "`")
  'keywords '(":-" "-->" "is" "not" "\\+" "->" "module" "use_module"
              "dynamic" "discontiguous" "initialization"))

(define-indentation "Prolog"
  'style 'prolog 'width 4 'tabs #f
  'reindent-on-newline #t
  'line-comments '("%") 'block-comments '(("/*" . "*/"))
  'strings "\"'`")
