;; Compatibility with SICP
(load "aliases.scm")

;; Shortcut definitions
(define (keyboard key clipboard) 
   (cond ( (equal? key "C-c a") 
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
           (insert clipboard)
           (insert "-</p>"))
         (else (insert key)) ))

(newlanguage ".scm")
(keyword "define")
(keyword "cond")
(keyword "else")


