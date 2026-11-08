(define (fib n)
  (if (< n 2) n 
      (+ (fib (- n 1)) (fib (- n 2))))) 


(time (fib 39))                 ; Fibonacci of 39

(define (fact n)
  (if (< n 2) 1                 ; Trivial case
      (* (fact (- n 1)) n)))
