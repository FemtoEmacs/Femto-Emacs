;;
;; Basic kill-ring menu
;; Hugh Barney September 2016
;;
;; In order to enable kill ring, copy this file to your home folder
;; when invoked write a 1 line summary of each region in the kill-ring
;; and enabled the user to copy a selected block back to the clipboard
;;
;; (load "samples/killring.scm")
;; (kill-ring-menu)
;;

(define kr-line 1)   
(define kr-start-line 1)
(define kr-last-line (length kill-ring))
(define kr-max-ops 2000)
(define kr-debugging #t)
(define kr-stop #f)
(define kr-obuf "")
(define kr-key "")
(define kr-temp "")
(define first car)
(define rest cdr)

(define (kill-ring-menu)
    (set! kr-stop #f)
    (set! kr-max-ops 2000)
    (set! kr-obuf (get-buffer-name))
    (kill-buffer "*kill-ring*")
    (select-buffer "*kill-ring*")
    (insert-list-as-strings kill-ring)
    (goto-line kr-line)
    (set! kr-start-line 1)
    (set! kr-last-line (length kill-ring))
    ;; (goto-line kr-start-line)
    (delete-other-windows)
    (kr-show-options)
    (do ((i 1 (1+ i)))
        ((or (> i kr-max-ops) kr-stop))        
        (kr-loop-payload))
    (update-display))

(define (kr-loop-payload)
    (set! kr-key (get-key))
    (if (equal? kr-key "")
	 (kr-handle-bound-key)
         (kr-handle-single-key kr-key)))

;; handle a bound key (up or down only)
(define (kr-handle-bound-key)
    (set! kr-key (get-key-binding))
    (if (equal? kr-key "previous-line") (kr-move-line -1))
    (if (equal? kr-key "next-line") (kr-move-line 1))
    (goto-line kr-line)
    (kr-show-options))

;; handle a single key c or x
(define (kr-handle-single-key k)
   (cond   ( (equal? k "x")
             (select-buffer kr-obuf)
             (delete-other-windows)
             (set! kr-stop #t))
           ( (equal? k "c")
	     (when (>= (length kill-ring) 0)
                   (set-clipboard (list-ref kill-ring (- kr-line 1)) ))
             (message (string-append "item " kr-line " copied to clipboard"))
             (update-display))))

;;
;; increment line by n (could +1 or -1)
;; check that kr-line is between kr-start-line and kr-last-line
;; and adjust the value if required
;;
(define (kr-move-line n)
	(set! kr-line (max kr-start-line (min (+ kr-line n) kr-last-line))))

;;
;; iterate over the kill-ring convert it to a summary and then
;; insert the string into the kill ring menu buffer
;;

(define (insert-list-as-strings l)
 	(cond 
           ( (null? l) #f )
       	   ( else (insert (summarize-kill (first l))) (insert "\n") (insert-list-as-strings (rest l)) )
	))

;; inserts the whole of the kill ring into a buffer
(define (insert-kill-ring)
  (insert-kr kill-ring))

(define (insert-kr l)
 	(cond 
           ( (null? l) #f )
       	   ( else
               (insert (first l))
               (insert "\n#########################\n")
               (insert-kr (rest l)))
	))

;; produce a 1 line summary of the killed region
(define (summarize-kill k)
   (set! kr-temp k)
   (if (string.find kr-temp "\n")
     (set! kr-temp (string.sub kr-temp 0 (string.find kr-temp "\n"))))
   (cond
     ( (> 40 (string-length kr-temp)) kr-temp)
     ( else (string.sub kr-temp 0 40 ))))

(define (kr-show-options)
    (message (string-append "kill item " kr-line " : select (up), (down), (c=copy to clipboard), (x=exit)"))
    (update-display))



