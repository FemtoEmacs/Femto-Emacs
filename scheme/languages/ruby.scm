;;;; ruby.scm -- syntax highlighting and indentation for Ruby

(define-language "Ruby"
  'extensions '(".rb")
  'line-comment "#" 'block-comment '("=begin" . "=end")
  'strings '("\"" "'")
  'keywords '("def" "end" "if" "return" "puts" "begin" "while" "until"
              "unless" "or" "and" "not" "class" "module" "do" "elsif" "else"
              "then" "yield"))

(define-indentation "Ruby"
  'style 'block 'width 2 'tabs #f
  'comment "#"
  'reindent-on-newline #t
  'open-words '("def" "class" "module" "if" "unless" "while" "until" "case"
                "begin" "for")
  'mid-words '("else" "elsif" "when" "rescue" "ensure")
  'close-words '("end")
  'close-chars "}"
  'open-endings '("do" "{" "|")
  'electric-keys "defn}" 'electric-prefixes '("}")
  'electric-words '("end" "else" "elsif" "when" "rescue" "ensure"))
