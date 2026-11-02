;;;; haskell.scm -- syntax highlighting and indentation for Haskell

(define-language "Haskell"
  'extensions '(".hs" ".lhs")
  'line-comment "--" 'block-comment '("{-" . "-}")
  'word-chars "'"
  'keywords '("if" "then" "else" "case" "of" "where" "data" "deriving" "type"
              "class" "instance" "import" "do" "let" "in" "module" "newtype"))

(define-indentation "Haskell"
  'style 'block 'width 4 'tabs #f
  'comment "--"
  'cycle #t
  'open-endings '("where" "=" "do" "of" "->" "let" "then" "else" "(" "[" "{")
  'close-words '("in"))
