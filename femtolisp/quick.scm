
(define (quick xs)
   (if  (or (null? xs) (null? (cdr xs))) xs
       (append (quick (filter (curry > (car xs)) (cdr xs)))
               (list (car xs))
               (quick (filter (curry <= (car xs)) (cdr xs))) ) ))

