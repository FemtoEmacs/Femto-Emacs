;; Compiler-generated recursive helper environments must not retain themselves.
(define (gc-check name got expected)
  (unless (equal? got expected) (error "GC closure regression" name got expected)))
(gc-check 'non-tail
  (letrec ((sum (lambda (n) (if (= n 0) 0 (+ n (sum (- n 1))))))) (sum 20))
  210)
(gc-check 'first-class-self
  (letrec ((self (lambda (n) (if (= n 0) self ((if #t self self) (- n 1))))))
    (eq? self (self 3))) #t)
(gc-check 'nested-self
  (letrec ((self (lambda (n) (if (= n 0) self ((lambda () (self (- n 1))))))))
    (eq? self (self 3))) #t)
(gc-check 'captures
  (let ((x 13) (y 17))
    (letrec ((self (lambda (n) (if (= n 0) (+ x y) (+ x (self (- n 1)))))))
      (self 2))) 56)
(gc-check 'escaping-self
  (let ((f (let ((x 17))
             (letrec ((self (lambda (n) (if (= n 0) x (+ 1 (self (- n 1))))))) self))))
    (f 4)) 21)
(gc-check 'mutable-capture
  (let ((x 0))
    (letrec ((self (lambda (n) (if (= n 0) x (begin (set! x (+ x 1)) (self (- n 1)))))))
      (self 5))) 5)
(gc-check 'mutual-recursion
  (letrec ((even (lambda (n) (if (= n 0) #t (odd (- n 1)))))
           (odd (lambda (n) (if (= n 0) #f (even (- n 1))))))
    (list (even 10) (odd 10))) '(#t #f))
;; make-bytevector uses vector/list helpers. Before the fix, their recursive
;; closures retained each vector and exhausted the native GC heap at ~44k calls.
(lambda (a b c) (bytevector-length (make-bytevector 24000 0)))
