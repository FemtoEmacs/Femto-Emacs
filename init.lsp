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

;; start with an empty user defined keymap
;; this is a list of pairs in the form 
;;   key-name function
(define keymap ())

;; extend the keymap by creating a new pair
;; and cons-ing it onto the keymap list
(define (global-set-key ky fn)
  (set! keymap (cons (cons ky fn) keymap)))

;; for convenience
(define first car)
(define rest cdr)

;; the user keymap interpretter, match the key, call the function
(define (exec_key k map)
  (cond
    ( (eqv? () map)
       (message "key not bound"))
    ( (string=? k (first (first map)))
       ((rest (first map))))
    ( else
       (exec_key k (rest map)))))

;; called by the C code
(define (keyboard key)
  (exec_key key keymap))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; some user functions
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


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


;; C-c a
(define (html-p)
  (insert "<p> </p>")
  (backward-char 5))

;; C-c b
(define (html-h1)
  (beginning-of-line) 
  (insert "<h1> </h1>")
  (beginning-of-line)
  (forward-char 4))

;; C-c c
(define (html-pp)
  (end-of-line)
  (insert "<p>-")
  (insert (get-clipboard))
  (insert "-</p>"))

;; C-c z
(define (insert-day)
  (insert (what-day (read-string (cut-region)))))

;; C-t
(define (indent-two)
  (insert "  "))

;; C-o
(define (deindent-two)
  (backwards-delete-char 2))

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

;; bind later C-x C-b
(define (invoke-buffer-menu)
  (if (not (top-level-bound? 'bufm-stop)) (load (home "bufmenu.scm")))
  (buffer-menu))

;; bind later C-c i
(define (invoke-insert-kill-ring)
  (if (not (top-level-bound? 'kill-ring-menu)) (load (home "killring.scm")))
  (insert-kill-ring))

;; bind later C-c k
(define (invoke-kill-ring-menu)
  (if (not (top-level-bound? 'kill-ring-menu)) (load (home "killring.scm")))
  (kill-ring-menu))

;; bind later C-x C-d
(define (invoke-dired)
  (if (not (top-level-bound? 'dired)) (load (home "dired.scm")))
  (dired))

;;;;;;; C-x C-g
(define grep-search-string "")
(define grep-filespec "*.c *.h")
(define grep-command-prefix "grep -ni ")
(define grep-buffer "*grep*")
(define grep-line 0)
(define grep-file-to-load "")
(define grep-line-to-goto 0)

(define (grep-command)
  (kill-buffer grep-buffer)
  (set! grep-line 0)
  (set! grep-file-to-load "")
  (set! grep-line-to-goto 0)
  (set! grep-search-string (prompt "grep search for : " ""))
  (set! grep-filespec (prompt "search in files : " grep-filespec))
  (shell-command (string-append grep-command-prefix "\"" grep-search-string "\" " grep-filespec))
  (select-buffer "*output*")
  (rename-buffer "*grep*")
  (update-display))

(define (next-grep)
  (select-buffer "*grep*")
  (set! grep-line (+ 1 grep-line))
  (goto-line grep-line)
  (beginning-of-line)
  (set-mark)
  (search-forward ":")
  (backward-char 1)
  (copy-region)
  (set! grep-file-to-load (get-clipboard))
  (forward-char 1)
  (set-mark)
  (search-forward ":")
  (backward-char 1)
  (copy-region)
  (set! grep-line-to-goto (string->number (get-clipboard)))
  (find-file grep-file-to-load)
  (goto-line grep-line-to-goto))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Our user definable key-bindings, the actual key names must have been defined
;; in key.c. In the future we will add the ability to create new key names for
;; binding. 
;;
;; A list of available keys can be found using
;;   Esc-x list-bindings
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(global-set-key "C-x C-b" invoke-buffer-menu)
(global-set-key "C-x C-d" invoke-dired)
(global-set-key "C-x C-u" upcase-region)
(global-set-key "C-x C-l" downcase-region)
(global-set-key "C-x C-g" grep-command)
(global-set-key "C-x !" next-grep)

(global-set-key "C-c a" html-p)
(global-set-key "C-c b" html-h1)
(global-set-key "C-c c" html-pp)
(global-set-key "C-c i" invoke-insert-kill-ring)
(global-set-key "C-c k" invoke-kill-ring-menu)
(global-set-key "C-c z" insert-day)

(global-set-key "C-o" deindent-two)
(global-set-key "C-t" indent-two)

;;
;; Initialise the kill-ring to empty
;;
(define kill-ring ())

;;
;; append to the kill-ring on every kill
;; NOTE: commented out now that we have unlimited undo
;; 
;;(define (kill-hook bufn)
;;        (set! kill-ring (cons (get-clipboard) kill-ring)))


(define (show-startup-message)
  (if (string=? "*scratch*" (get-buffer-name))
    (begin 
      (insert "\n\n\n")
      (insert "                  _______  _______ .___  ___. .___________.  ______          \n")
      (insert "                 |   ____||   ____||   \\/   | |           | /  __  \\         \n")
      (insert "                 |  |__   |  |__   |  \\  /  | `---|  |----`|  |  |  |        \n")
      (insert "                 |   __|  |   __|  |  |\\/|  |     |  |     |  |  |  |        \n")
      (insert "                 |  |     |  |____ |  |  |  |     |  |     |  `--'  |        \n")
      (insert "                 |__|     |_______||__|  |__|     |__|      \\______/         \n")
      (insert "                                                                             \n")
      (insert "                  _______ .___  ___.      ___       ______     _______.      \n")
      (insert "                 |   ____||   \\/   |     /   \\     /      |   /       |      \n")
      (insert "                 |  |__   |  \\  /  |    /  ^  \\   |  ,----'  |   (----`      \n")
      (insert "                 |   __|  |  |\\/|  |   /  /_\\  \\  |  |        \\   \\          \n")
      (insert "                 |  |____ |  |  |  |  /  _____  \\ |  `----.----)   |         \n")
      (insert "                 |_______||__|  |__| /__/     \\__\\ \\______|_______/          \n\n")
      (insert "                 ")
      (insert (get-version-string))
      (insert "\n\n\n"))))



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Programming Language keywords for syntax highlighting
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

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

;; define syntax hi-lighting for C code
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

(newlanguage ".vlsp" "--" "#|" "|#" )
(keyword "library")
(keyword "use")
(keyword "define-entity")
(keyword "def-arch")
(keyword "is")
(keyword "out")
(keyword "in")
(keyword "process")
(keyword "if")
(keyword "elsif")
(keyword "else")
(keyword "set")
(keyword "of")

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
