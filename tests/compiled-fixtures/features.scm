;;; Macros, records, escapes, exceptions, parameters, values, ports.
(define (show . xs) (for-each display xs) (newline))

;; syntax-rules
(define-syntax swap!
  (syntax-rules () ((_ a b) (let ((tmp a)) (set! a b) (set! b tmp)))))
(define tmp 1) (define other 2)
(swap! tmp other)
(show "swap! (hygiene): " tmp " " other)
(define-syntax my-or
  (syntax-rules () ((_) #f) ((_ e) e) ((_ e r ...) (let ((t e)) (if t t (my-or r ...))))))
(define t 5)
(show "my-or: " (my-or #f t))
(define-syntax while
  (syntax-rules () ((_ c body ...) (let lp () (when c body ... (lp))))))
(define i 0) (while (< i 3) (set! i (+ i 1)))
(show "while: " i)
(define-syntax my-let*
  (syntax-rules () ((_ () body ...) (let () body ...))
                   ((_ ((x v) rest ...) body ...) (let ((x v)) (my-let* (rest ...) body ...)))))
(show "my-let*: " (my-let* ((a 1) (b (+ a 1))) (* a b)))
(define-syntax ten (syntax-rules () ((_) 10)))
(show "nested ellipses: "
      (let-syntax ((pairs (syntax-rules () ((_ (a b ...) ...) '((a . (b ...)) ...)))))
        (pairs (1 2 3) (4) (5 6))))
(define (f) (define-syntax twice (syntax-rules () ((_ e) (begin e e)))) (define n 0) (twice (set! n (+ n 1))) n)
(show "internal define-syntax: " (f) " " (ten))
(define-syntax my-if (syntax-rules (then else) ((_ c then a else b) (if c a b))))
(show "literals: " (my-if #f then 'no else 'yes))
(define-syntax vec-mac (syntax-rules () ((_ #(a ...)) (list a ...))))
(show "vector pattern: " (vec-mac #(1 2 3)))

;; records
(define-record-type point (make-point x y) point? (x point-x set-point-x!) (y point-y))
(define p (make-point 3 4))
(set-point-x! p 10)
(show "record: " (point-x p) " " (point-y p) " " (point? p) " " (point? 5) " " (vector? p))

;; values
(call-with-values (lambda () (values 1 2 3)) (lambda (a b c) (show "values: " (+ a b c))))
(let-values (((q r) (floor/ 17 5)) ((x) (values 'x))) (show "let-values: " q " " r " " x))
(define-values (u v . w) (values 1 2 3 4))
(show "define-values: " u " " v " " w)
(receive (a . rest) (values 1 2 3) (show "receive: " a " " rest))

;; case-lambda
(define area (case-lambda ((r) (* 3 r r)) ((w h) (* w h)) ((a b . more) (length more))))
(show "case-lambda: " (area 2) " " (area 2 5) " " (area 1 2 3 4))

;; escapes
(show "call/cc: " (call/cc (lambda (k) (+ 1 (k 42)))))
(define (find-first pred l) (call/cc (lambda (return) (for-each (lambda (x) (if (pred x) (return x))) l) #f)))
(show "early return: " (find-first even? '(1 3 4 5 6)))
(define trace '())
(define (note x) (set! trace (cons x trace)))
(call/cc (lambda (k) (dynamic-wind (lambda () (note 'in)) (lambda () (k 'out)) (lambda () (note 'after)))))
(show "dynamic-wind: " (reverse trace))

;; exceptions
(show "guard error: " (guard (e ((error-object? e) (list (error-object-message e) (error-object-irritants e))))
                       (error "bad thing" 1 2)))
(show "guard raise: " (guard (e ((symbol? e) (list 'caught e)) ((string? e) 'string)) (raise 'oops)))
(show "guard =>: " (guard (e ((assq 'a e) => cdr) ((assq 'b e))) (raise (list (cons 'a 42)))))
(show "raise-continuable: " (with-exception-handler (lambda (c) 10) (lambda () (+ 1 (raise-continuable 'c)))))
(show "nested guard: " (guard (e (#t (list 'outer e))) (guard (e ((number? e) 'number)) (raise 'sym))))
(show "car error caught: " (guard (e (#t 'caught)) (+ 1 "a")))

;; parameters
(define radix (make-parameter 10))
(define (get) (radix))
(show "parameterize: " (parameterize ((radix 2)) (get)) " " (get))
(define conv (make-parameter 5 (lambda (x) (* x 2))))
(show "converter: " (conv) " " (parameterize ((conv 7)) (conv)))

;; string ports
(define out (open-output-string))
(write 'sym out) (display " " out) (write "str" out) (display 1.5 out)
(show "string port: " (get-output-string out))
(define in (open-input-string "abc\ndef"))
(show "read-line: " (read-line in) " " (read-char in) " " (read-line in) " " (eof-object? (read-line in)))

;; misc
(show "case =>: " (case 5 ((1 2) 'low) (else => (lambda (x) (* x x)))))
(show "cond-expand: " (cond-expand (schemer 'schemer) (else 'other)))
(show "assoc string: " (assoc "b" '(("a" . 1) ("b" . 2))))
(show "string->symbol: " (eq? (string->symbol "abc") 'abc))
(show "char cache: " (eq? (string-ref "abc" 0) #\a))
