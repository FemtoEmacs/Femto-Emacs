;;;; languages.lisp -- the languages SBEmacs highlights out of the box
;;;;
;;;; These were the (newlanguage ...) / (keyword ...) blocks of init.lsp.
;;;; Add your own in ~/.sbemacs/init.lisp with DEFINE-LANGUAGE; a language
;;;; defined later wins for the extensions it claims.

(in-package #:sbemacs)

(defparameter +lisp-word-chars+ "-*+!?<>=/:%&$^~.")

;;; Files with no known extension: numbers and "strings" only, as before.
(setf *default-language* (%make-language :name "Text"
                                          :strings (list (octets "\""))
                                          :word-bytes (make-word-table "")))

(define-language "Scheme"
  :extensions '(".scm" ".ss" ".lsp")
  :line-comment ";" :block-comment '("#|" . "|#")
  :char-prefix "#\\" :word-chars +lisp-word-chars+
  :keywords '("define" "define-syntax" "lambda" "let" "let*" "letrec" "cond"
              "case" "else" "if" "when" "unless" "begin" "do" "set!" "quote"
              "and" "or"))

(define-language "Common Lisp"
  :extensions '(".lisp" ".cl" ".asd" ".el")
  :line-comment ";" :block-comment '("#|" . "|#")
  :char-prefix "#\\" :word-chars +lisp-word-chars+ :case-insensitive t
  :keywords '("defun" "defmacro" "defparameter" "defvar" "defconstant"
              "defgeneric" "defmethod" "defclass" "defstruct" "defpackage"
              "in-package" "define-language" "global-set-key"
              "lambda" "let" "let*" "flet" "labels" "progn" "prog1"
              "loop" "for" "do" "do*" "dolist" "dotimes" "return" "return-from"
              "block" "if" "when" "unless" "cond" "case" "ecase" "typecase"
              "and" "or" "not" "setf" "setq" "incf" "decf" "push" "pop"
              "eq" "eql" "equal" "car" "cdr" "cons" "list"
              "handler-case" "unwind-protect" "multiple-value-bind"
              "destructuring-bind"))

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

(define-language "TeX"
  :extensions '(".tex" ".sty" ".bib")
  :line-comment "%" :strings '() :escape nil
  :backslash-commands t)

(define-language "ML"
  :extensions '(".ml" ".mli")
  :line-comment "//" :block-comment '("(*" . "*)")
  :word-chars "'"
  :keywords '("let" "rec" "begin" "end" "match" "with" "if" "else" "then"
              "function" "fun" "try" "module" "print_endline" "print_newline"
              "struct" "open_out" "close_out" "input_line" "in" "const"
              "constb" "consti" "vdd" "gnd" "&:" "|:" "^:" "~:" "+:" "-:" "*:"
              "*+" "<:" "<=:" ">:" ">=:" "==:" "<+" "<=+" ">+" ">=+" "<>:"))

(define-language "Python"
  :extensions '(".py")
  :line-comment "#"
  :strings '("\"\"\"" "'''" "\"" "'")
  :keywords '("def" "if" "else" "elif" "for" "lambda" "try" "continue"
              "finally" "is" "return" "class" "exec" "in" "raise" "break"
              "except" "import" "print" "assert" "pass" "yield" "as" "global"
              "or" "with" "and" "del" "from" "not" "while" "None" "True"
              "False"))

(define-language "Haskell"
  :extensions '(".hs" ".lhs")
  :line-comment "--" :block-comment '("{-" . "-}")
  :word-chars "'"
  :keywords '("if" "then" "else" "case" "of" "where" "data" "deriving" "type"
              "class" "instance" "import" "do" "let" "in" "module" "newtype"))

(define-language "VHDL Lisp"
  :extensions '(".vlsp")
  :line-comment "--" :block-comment '("#|" . "|#")
  :word-chars "-"
  :keywords '("library" "use" "define-entity" "def-arch" "is" "out" "in"
              "process" "if" "elsif" "else" "set" "of"))

(define-language "Ruby"
  :extensions '(".rb")
  :line-comment "#" :block-comment '("=begin" . "=end")
  :strings '("\"" "'")
  :keywords '("def" "end" "if" "return" "puts" "begin" "while" "until"
              "unless" "or" "and" "not" "class" "module" "do" "elsif" "else"
              "then" "yield"))

(define-language "Prolog"
  :extensions '(".pl" ".pro" ".prolog")
  :line-comment "%" :block-comment '("/*" . "*/")
  :strings '("\"" "'" "`")
  :keywords '(":-" "-->" "is" "not" "\\+" "->" "module" "use_module"
              "dynamic" "discontiguous" "initialization"))

(define-language "Lean"
  :extensions '(".lean")
  :line-comment "--" :block-comment '("/-" . "-/")
  :word-chars "'!?."
  :keywords '("def" "theorem" "lemma" "example" "structure" "inductive"
              "class" "instance" "where" "match" "with" "fun" "let" "have"
              "show" "by" "do" "if" "then" "else" "namespace" "section" "end"
              "open" "import" "variable" "universe" "calc"))
