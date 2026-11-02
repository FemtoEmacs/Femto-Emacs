;;; bridge-test.scm -- compiled with compiled/bridge.scm (tests/bridge-test.c)
(define add (foreign-procedure "test-add" (int int) int))
(define concat (foreign-procedure "test-concat" (string string) string))
(define size (foreign-procedure "test-size" (u8*) int))
(define names (foreign-procedure "test-names" () scheme-object))
(define fail (foreign-procedure "test-fail" () void))
(define reenter (foreign-procedure "test-reenter" (int) int))

(define failures '())
(define (check name got expected)
  (unless (equal? got expected) (set! failures (cons (list name got expected) failures))))

(define (scheme-side-tests)
  (check "C adds" (add 20 22) 42)
  (check "negative numbers" (add -5 -7) -12)
  (check "Unicode both ways" (concat "café " "ação ☃") "café ação ☃")
  (check "an empty string" (concat "" "") "")
  (check "3 MB to C (the memory grows)" (size (make-bytevector 3000000 7)) 3000000)
  (check "a list from C" (names) '("um" "dois" (3 #t #f)))
  (check "C's error becomes Scheme's" (guard (e (#t (error-object-message e))) (fail) 'no-error) "test-fail failed on purpose")
  (check "nested: C calls Scheme inside a call from Scheme" (reenter 5) 105)
  (check "unknown C function" (guard (e (#t 'error)) (foreign-procedure "no-such" () void)) 'error)
  (check "wrong number of arguments" (guard (e (#t 'error)) (add 1)) 'error)
  (if (null? failures) "ok" (let ((p (open-output-string))) (write (reverse failures) p) (get-output-string p))))

(define (benchmark-calls n)          ; Scheme -> C, n calls
  (let loop ((i 0) (s 0)) (if (= i n) s (loop (+ i 1) (add s 1)))))

(bridge-hook! 1 (lambda (s n) (string-append s "/" (number->string n))))
(bridge-hook! 2 (lambda (n) (+ n 100)))
(bridge-hook! 3 scheme-side-tests)
(bridge-hook! 4 (lambda () (error "Scheme failed on purpose:" 42)))
(bridge-hook! 5 benchmark-calls)
(bridge-hook! 6 (lambda (bv) (bytevector-length bv)))
(bridge-hook! 7 (lambda () (raise 'a-symbol)))

bridge-dispatch
