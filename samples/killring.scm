;;
;; Hugh Barney September 2016
;;
;; up, down, c
;;
;; (load "samples/killring.scm")
;; (kill-ring-menu)

(define kr-line 1)   
(define kr-start-line 1)
(define kr-last-line (length kill-ring))
(define kr-max-ops 400)
(define kr-debugging #t)
(define kr-stop #f)
(define kr-obuf "")
(define kr-buf "")
(define kr-key "")
(define kr-temp "")

(define first car)
(define rest cdr)

(define (kill-ring-menu)
    (kill-buffer "*kill-ring*")
    (select-buffer "*kill-ring*")
    (insert-list-as-strings kill-ring)
    (goto-line kr-line)
    (set! kr-start-line 1)
    (set! kr-last-line (length kill-ring))

)

(define (insert-list-as-strings l)
 	(cond 
           ( (null? l) #f )
       	   ( else (insert (summarize-kill (first l))) (insert "\n") (insert-list-as-strings (rest l)) )
	))

(define (summarize-kill k)
   (set! kr-temp k)
   (if (equal? (string.find kr-temp "\n") #t)
     (set! kr-temp (string.sub kr-temp 0 (string.find kr-temp kr-temp))))
   (cond
     ( (> 40 (string-length kr-temp)) kr-temp)
     ( else (string.sub kr-temp 0 40 ))))


;;(string.decode (first kill-ring))

