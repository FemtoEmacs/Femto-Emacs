(define-syntax my-unless (syntax-rules () ((_ c e ...) (if c #f (begin e ...)))))
(display (let ((if list)) (my-unless #f 'ok))) (newline)            ; user's if does not capture
(define-syntax define-getter (syntax-rules () ((_ name val) (define (name) val))))
(define-getter get-five 5) (display (get-five)) (newline)
(define-syntax def-macro-maker
  (syntax-rules () ((_ name v) (define-syntax name (syntax-rules () ((_) v))))))
(def-macro-maker seven 7) (display (seven)) (newline)
(define-syntax my-cond (syntax-rules (else) ((_ (else e)) e) ((_ (c e) rest ...) (if c e (my-cond rest ...)))))
(display (my-cond (#f 1) (else 2))) (newline)
(define (g x) (let-syntax ((add-x (syntax-rules () ((_ y) (+ x y))))) (let ((x 100)) (add-x 1))))
(display (g 10)) (newline)    ; 11: the macro's x is g's x
(define-syntax for
  (syntax-rules (in) ((_ x in l body ...) (for-each (lambda (x) body ...) l))))
(for y in '(1 2 3) (display y)) (newline)
(define-syntax inc! (syntax-rules () ((_ v) (set! v (+ v 1))) ((_ v n) (set! v (+ v n)))))
(define cnt 0) (inc! cnt) (inc! cnt 10) (display cnt) (newline)
(define-syntax ell (syntax-rules () ((_ (a b ...) ...) (list (list a (+ b ...)) ...))))
(display (ell (1 2 3) (4 5))) (newline)
(define-syntax tail-pat (syntax-rules () ((_ a ... z) '(z a ...))))
(display (tail-pat 1 2 3 4)) (newline)
(define-syntax dot (syntax-rules () ((_ a . b) '(a b))))
(display (dot 1 2 3)) (newline)
(define-syntax lit (syntax-rules () ((_ x) (quote (x ...)))))
