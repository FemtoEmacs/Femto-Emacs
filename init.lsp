;; FemtoEmacs init.lsp, should be placed in the users HOME directory together with "r5rs.scm"
;; For now other examples of extensions from the samples directory should be placed
;; in the HOME directory. For example killring.scm and buffmenu.scm
;;
;;

;; Compatibility with SICP
(define (home f)
   (string (os.getenv "HOME") "/" f))

(load (home "r5rs.scm"))

;;
;; comment the line below to disable unlimited undo mode
;;
;; activate unlimited undo for non-special buffers
;; not advisable on systems with low memory footprint as the undo history
;; needs to be stored in memory for each buffer that is modified.
;;
(add-mode-global "undo")

;;
;; The function read-string is necessary for reading a Lisp list from a string. 
;; When Lisp retrieves a text such as "(2016 8 31)" the text comes out as a string. 
;; On the other hand, (read-string "(2016 8 31)" ) reads a list from this string in the 
;; same way as it would read a list from a file.
;;
(define (read-string str)
    (let ( (port (open-input-string str)))
      (begin0 (read port)
	      (close-input-port port)) ))


;;
;; returns weekday as a string
;;
(define (weekday n)
    (cond ( (equal? n 0) "Sunday")
	  ( (equal? n 1) "Monday")
	  ( (equal? n 2) "Tuesday")
	  ( (equal? n 3) "Wednesday")
	  ( (equal? n 4) "Thursday")
	  ( (equal? n 5) "Friday")
	  ( (equal? n 6) "Saturday")
	  (else "unknown")))

;;
;; returns the day for the specific date
;; (what-day '(2016 9 3))
(define (what-day ymd)
    (let* ( (y (car ymd))
            (m (cadr ymd))
            (d (caddr ymd))
            (ax (quotient (- 14 m) 12))
	    (mm (+ m (* 12 ax) -2))
	    (yy (- y ax))
	    (c (- (quotient yy 100)))
	    (ly (quotient yy 4)) )
      (weekday (mod (+ yy
		    (quotient (- (* 13 mm) 1) 5)
		    ly
                    c
		    (quotient yy 400) d) 7)) ))

;; call kill-region and return it as a string
(define (cut-region)
  (kill-region)
  (get-clipboard))

;; bound to C-x C-u
(define (upcase-region)
   (kill-region)
   (set-clipboard (string.map char.upcase (get-clipboard)))
   (yank)
   (clear-message-line))

;; bound to C-x C-l
(define (downcase-region)
   (kill-region)
   (set-clipboard (string.map char.downcase (get-clipboard)))
   (yank)
   (clear-message-line))

;; Shortcut definitions
(define (keyboard key) 
   (cond
      ( (equal? key "C-c z")
        (insert (what-day (read-string (cut-region))) ))
      ( (equal? key "C-c a") 
        (insert "<p> </p>")
        (backward-char 5))
      ( (equal? key "C-t")
	(insert "  "))
      ( (equal? key "C-o")
        (backwards-delete-char 2))
      ( (equal? key "C-c b")
        (beginning-of-line) 
        (insert "<h1> </h2>")
        (beginning-of-line)
        (forward-char 4))

      ( (equal? key "C-c c")
        (end-of-line)
        (insert "<p>-")
        (insert (get-clipboard))
        (insert "-</p>"))

      ( (equal? key "C-c i")
        (if (not (top-level-bound? 'kill-ring-menu))
          (load (home "killring.scm")))
          (insert-kill-ring))

      ( (equal? key "C-c k")
        (if (not (top-level-bound? 'kill-ring-menu))
          (load (home "killring.scm")))
          (kill-ring-menu))

      ( (equal? key "C-x C-d")
        (if (not (top-level-bound? 'dired))
          (load (home "dired.scm")))
          (dired))

      ( (equal? key "C-c m")
        (if (not (top-level-bound? 'bufm-stop))
          (load (home "bufmenu.scm")))
          (buffer-menu))

      ( (equal? key "C-x C-u")
          (upcase-region))

      ( (equal? key "C-x C-l")
          (downcase-region))

      (else (insert key)) ))

;;
;; Initialise the kill-ring to empty
;;
(define kill-ring ())

;;
;; append to the kill-ring on every kill
;; 
(define (kill-hook bufn)
        (set! kill-ring (cons (get-clipboard) kill-ring)))

;; define syntax highlighting for scheme files
(newlanguage ".scm" ";" "#|" "|#")
(keyword "define")
(keyword "cond")
(keyword "else")

;; define syntax hughlihgting for lisp files
(newlanguage ".lsp" ";" "#|" "|#")
(keyword "define")
(keyword "cond")
(keyword "else")
(keyword "keyword") ;; To help debug init.lsp

(newlanguage ".lisp" ";" "#|" "|#")
(keyword "defun")
(keyword "defmacro")
(keyword "defparameter")
(keyword "defvar")
(keyword "let")
(keyword "let*")
(keyword "loop")
(keyword "for")
(keyword "do")
(keyword "dolist")
(keyword "eq")
(keyword "equal")
(keyword "eql")
(keyword "and")
(keyword "or")
(keyword "car")
(keyword "cdr")
(keyword "cond")
(keyword "if")

;; define syntax hughlighting for C code
(newlanguage ".c" "//" "/*" "*/")
(keyword "auto")
(keyword "break")
(keyword "case")
(keyword "char")
(keyword "const")
(keyword "continue")
(keyword "default")
(keyword "do")
(keyword "double")
(keyword "else")
(keyword "enum")
(keyword "extern")
(keyword "float")
(keyword "for")
(keyword "goto")
(keyword "if")
(keyword "int")
(keyword "long")
(keyword "register")
(keyword "return")
(keyword "short")
(keyword "signed")
(keyword "sizeof")
(keyword "static")
(keyword "struct")
(keyword "switch")
(keyword "typedef")
(keyword "union")
(keyword "unsigned")
(keyword "void")
(keyword "volatile")
(keyword "while")
(keyword "#include")
(keyword "#define")


(newlanguage ".tex" "%" "{" "}")
(keyword "\\begin")
(keyword "\\end")
(keyword "\\em")
(keyword "\\usepackage")
(keyword "\\chapter")
(keyword "\\section")
(keyword "\\paragraph")
(keyword "\\documentclass")
(keyword "\\label")
(keyword "\\ref")

(newlanguage ".ml" "//" "(*" "*)")
(keyword "let")
(keyword "rec")
(keyword "begin")
(keyword "end")
(keyword "match")
(keyword "with")
(keyword "if")
(keyword "else")
(keyword "then")
(keyword "function")
(keyword "fun")
(keyword "try")
(keyword "with")
(keyword "module")
(keyword "print_endline")
(keyword "print_newline")
(keyword "struct")
(keyword "open_out")
(keyword "close_out")
(keyword "input_line")
(keyword "in")
(keyword "const")
(keyword "constb")
(keyword "consti")
(keyword "vdd")
(keyword "gnd")
(keyword "&:")
(keyword "|:")
(keyword "^:")
(keyword "~:")
(keyword "+:")
(keyword "-:")
(keyword "*:")
(keyword "*+")
(keyword "<:") 
(keyword "<=:")
(keyword ">:")
(keyword ">=:")
(keyword "==:")
(keyword "<+")
(keyword "<=+")
(keyword ">+")
(keyword ">=+")
(keyword "<>:")
 

(newlanguage ".py" "#" "\"\"\"" "\"\"\"")
(keyword "def")
(keyword "if")
(keyword "else")
(keyword "elif")
(keyword "for")
(keyword "lambda")
(keyword "try")
(keyword "continue")
(keyword "finally")
(keyword "is")
(keyword "finally")
(keyword "return")
(keyword "class")
(keyword "exec")
(keyword "in")
(keyword "raise")
(keyword "break")
(keyword "except")
(keyword "import")
(keyword "print")
(keyword "assert")
(keyword "pass")
(keyword "yield")
(keyword "as")
(keyword "global")
(keyword "or")
(keyword "with")
(keyword "and")
(keyword "del")
(keyword "from")
(keyword "not")
(keyword "while")

(newlanguage ".hs" "--" "{-" "-}")
(keyword "if")
(keyword "then")
(keyword "else")
(keyword "case")
(keyword "of")
(keyword "where")
(keyword "data")
(keyword "deriving")
(keyword "type")
(keyword "class")
(keyword "instance")
(keyword "import")
(keyword "do")

(newlanguage ".rb" "#" "=begin" "=end")
(keyword "def")
(keyword "end")
(keyword "if")
(keyword "return")
(keyword "puts")
(keyword "begin")
(keyword "while")
(keyword "until")
(keyword "unless")
(keyword "or")
(keyword "and")
(keyword "not")
