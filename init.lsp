;; Compatibility with SICP
(load (home "aliases.scm"))

;;
;;  what does this do ?
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


;; Shortcut definitions
(define (keyboard key) 
   (cond
      ( (equal? key "C-c z")
        (insert (what-day (read-string (cutregion))) ))
      ( (equal? key "C-c a") 
        (insert "<p> </p>")
        (backward 5))
      ( (equal? key "C-c b")
        (beginning-of-line) 
        (insert "<h1> </h2>")
        (beginning-of-line)
        (forward 4))
      ( (equal? key "C-c c")
        (end-of-line)
        (insert "<p>-")
        (insert (clipboard))
        (insert "-</p>"))
      ( (equal? key "C-c m")
	(buffer-menu))
      (else (insert key)) ))


;; this is just a start
(define (buffer-menu)
  (message "please use (load samples/bufmenu.scm), press key to continue")
  (update-display)
  (get-key))

(newlanguage ".scm" ";" "#|" "|#")
(keyword "define")
(keyword "cond")
(keyword "else")

(newlanguage ".lsp" ";" "#|" "|#")
(keyword "define")
(keyword "cond")
(keyword "else")

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
