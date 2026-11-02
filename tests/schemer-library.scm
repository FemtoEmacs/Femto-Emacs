;;; schemer-library.scm -- make check-library: the procedures Schemer's
;;; prelude gained for the scripts (Chez's, SRFI 1's and 13's), guard, and
;;; globals by name.  Prints "PASS n" or the failures.
(define failures 0)
(define checks 0)
(define (check name got expected)
  (set! checks (+ checks 1))
  (unless (equal? got expected)
    (set! failures (+ failures 1))
    (display "FAIL ") (display name) (display ": got ") (write got)
    (display ", expected ") (write expected) (newline)))

;; guard
(check "guard catches" (guard (e (#t (list 'caught e))) (raise 'boom)) '(caught boom))
(check "guard clauses" (guard (e ((string? e) 'str) ((symbol? e) 'sym)) (raise 'x)) 'sym)
(check "guard re-raises" (guard (e ((symbol? e) 'outer)) (guard (e ((string? e) 'inner)) (raise 'x))) 'outer)
(check "guard error objects" (guard (e (#t (error-object-message e))) (error "msg" 1 2)) "msg")
(check "guard values" (call-with-values (lambda () (guard (e (#t 0)) (values 1 2))) list) '(1 2))
(check "raise-continuable" (with-exception-handler (lambda (c) 10) (lambda () (+ 1 (raise-continuable 'c)))) 11)
(check "an escape through a guard" (guard (e (#t (list 'outer e))) (call/cc (lambda (k) (guard (e2 (#t 'wrong)) (k 5)))) (raise 'later)) '(outer later))
(check "guard =>" (guard (e ((assq 'a e) => cdr) ((assq 'b e))) (raise (list (cons 'a 42)))) 42)
(check "guard and dynamic-wind"
       (let ((log '())) (guard (e (#t (reverse log)))
                          (dynamic-wind (lambda () (set! log (cons 'in log))) (lambda () (raise 'x)) (lambda () (set! log (cons 'out log))))))
       '(in out))
(check "a raise in a handler" (guard (e (#t (guard (e2 (#t (list e e2))) (raise 'second)))) (raise 'first)) '(first second))

;; lists
(check "every" (list (every odd? '(1 3 5)) (every odd? '(1 2)) (every odd? '()) (every + '(1 2) '(3 4))) '(#t #f #t 6))
(check "any" (list (any even? '(1 2 3)) (any even? '(1 3)) (any (lambda (x) (and (> x 1) x)) '(1 5))) '(#t #f 5))
(check "find" (list (find even? '(1 2 3 4)) (find even? '(1 3)) (find-tail even? '(1 2 3))) '(2 #f (2 3)))
(check "list-index" (list (list-index even? '(1 3 4)) (list-index even? '(1))) '(2 #f))
(check "filter-map" (filter-map (lambda (x) (and (odd? x) (* x x))) '(1 2 3)) '(1 9))
(check "fold" (list (fold cons '() '(1 2 3)) (fold + 0 '(1 2) '(10 20))) '((3 2 1) 33))
(check "reduce" (list (reduce + 0 '(1 2 3)) (reduce + 0 '())) '(6 0))
(check "remove, delete" (list (remove odd? '(1 2 3)) (delete 2 '(1 2 3 2)) (remq 'a '(a b a))) '((2) (1 3) (b)))
(check "partition" (call-with-values (lambda () (partition odd? '(1 2 3 4))) list) '((1 3) (2 4)))
(check "delete-duplicates" (list (delete-duplicates '(1 2 1 3 2)) (delete-duplicates (append (iota 20) (iota 20))))
       (list '(1 2 3) (iota 20)))
(check "last" (last '(1 2 3)) 3)
(check "assp, memp" (list (assp even? '((1 . a) (2 . b))) (memp even? '(1 2 3))) '((2 . b) (2 3)))
(check "sort, Chez's order" (sort < '(3 1 2)) '(1 2 3))
(check "sort, the other order" (sort '("b" "c" "a") string<?) '("a" "b" "c"))
(check "sort is stable" (sort (lambda (a b) (< (car a) (car b))) '((1 . a) (0 . b) (1 . c) (0 . d))) '((0 . b) (0 . d) (1 . a) (1 . c)))
(check "list-sort, vector-sort" (list (list-sort < '(2 1)) (vector-sort < #(3 2 1))) '((1 2) #(1 2 3)))
(check "vector-sort!" (let ((v (vector 3 1 2))) (vector-sort! < v) v) #(1 2 3))
(check "void" (eq? (void) (if #f #f)) #t)

;; bits
(check "bitwise" (list (bitwise-and 12 10) (bitwise-ior 12 10) (bitwise-xor 12 10) (bitwise-and) (logand 255 -1) (bitwise-not 0))
       '(8 14 6 -1 255 -1))
(check "bitwise, negative" (list (bitwise-and -8 13) (bitwise-ior -8 3)) '(8 -5))
(check "bitwise, big" (bitwise-and (expt 2 40) (+ (expt 2 40) 5)) (expt 2 40))
(check "shift" (list (arithmetic-shift 1 10) (arithmetic-shift 1024 -3) (arithmetic-shift -9 -1) (ash 3 40)) (list 1024 128 -5 (* 3 (expt 2 40))))
(check "random" (let ((r (random 10))) (and (exact-integer? r) (>= r 0) (< r 10))) #t)

;; strings
(check "prefix, suffix" (list (string-prefix? "ab" "abc") (string-prefix? "b" "abc") (string-suffix? "bc" "abc") (string-suffix? "abcd" "abc"))
       '(#t #f #t #f))
(check "string-search-forward" (list (string-search-forward "lo" "hello" 0) (string-search-forward "x" "hello" 0) (string-contains "a café" "fé"))
       '(3 #f 4))
(check "string-index" (list (string-index "a,b" #\,) (string-index "ab" #\,) (string-index-right "a,b,c" #\,)) '(1 #f 3))
(check "trim" (list (string-trim "  a  ") (string-trim-right "  a  ") (string-trim-both " \t a \n") (string-trim-both "xxaxx" #\x))
       '("a  " "  a" "a" "a"))
(check "string-join" (list (string-join '("a" "b" "c") ", ") (string-join '("a" "b")) (string-join '())) '("a, b, c" "a b" ""))
(check "string-split" (list (string-split "a b  c") (string-split "a,b;c" ",;") (string-split "" ",")) '(("a" "b" "" "c") ("a" "b" "c") ("")))
(check "string-split, unicode" (string-split "olá mundo") '("olá" "mundo"))
(check "string-count, reverse" (list (string-count "banana" #\a) (string-reverse "abc")) '(3 "cba"))

;; write: escapes as Chez writes them
(check "write escapes" (call-with-output-string (lambda (p) (write (string #\a #\tab #\b (integer->char 13) (integer->char 1) #\newline #\" #\\) p)))
       "\"a\\tb\\r\\x1;\\n\\\"\\\\\"")
(check "read what write wrote" (read (open-input-string (call-with-output-string (lambda (p) (write (string #\tab (integer->char 1)) p)))))
       (string #\tab (integer->char 1)))

;; bytevectors
(check "bytevector->u8-list" (list (bytevector->u8-list (bytevector 1 2)) (u8-list->bytevector '(3 4))) (list '(1 2) (bytevector 3 4)))
(check "bytevector-fill!, bytevector=?" (let ((b (make-bytevector 2 0))) (bytevector-fill! b 7) (list (bytevector=? b (bytevector 7 7)) (bytevector=? b (bytevector 7))))
       '(#t #f))

;; globals by name
(define counter 1)
(define (twice x) (* 2 x))
(check "top-level-value" (list (top-level-value 'counter) ((top-level-value 'twice) 4)) '(1 8))
(set-top-level-value! 'counter 5)
(check "set-top-level-value!" (list counter (top-level-value 'counter)) '(5 5))
(check "top-level-bound?" (list (top-level-bound? 'twice) (top-level-bound? 'no-such-thing)) '(#t #f))
(define-top-level-value 'made-later 42)
(check "define-top-level-value" (list (top-level-bound? 'made-later) (top-level-value 'made-later)) '(#t 42))
(check "a procedure is not replaced" (guard (e (#t 'refused)) (set-top-level-value! 'twice 0)) 'refused)
(check "procedure-name" (list (procedure-name twice) (procedure-name (lambda (x) x))) '(twice #f))
(check "twice is still called directly" (twice 21) 42)

(if (= failures 0)
    (begin (display "PASS ") (display checks) (display " checks of Schemer's library") (newline))
    (begin (display failures) (display " of ") (display checks) (display " checks failed") (newline)))
