;; Native bridge integration and real command dispatch. Fixtures above test
;; arithmetic, macros, exception unwinding, records, ports, tables and reader.
(define *compiled-test-count* 0)
(define (assert-equal name got want)
  (set! *compiled-test-count* (+ *compiled-test-count* 1))
  (unless (equal? got want) (error name got want)))
(assert-equal 'startup *script-errors* '())
(assert-equal 'compile (schemer-eval-string "(define (native-fib n) (if (< n 2) n (+ (native-fib (- n 1)) (native-fib (- n 2))))) (native-fib 20)") 6765)
(assert-equal 'retained (native-fib 25) 75025)
(assert-equal 'nested-module (schemer-eval-string "(native-fib 30)") 832040)
(assert-equal 'macro-values (schemer-eval-string "(define-syntax twice (syntax-rules () ((_ x) (+ x x)))) (call-with-values (lambda () (values (twice 3) 7)) +)") 13)
(assert-equal 'R7RS-length (schemer-eval-string "(list (length '(1 2 3)) (string-length \"café\"))") '(3 4))
;; A real legacy command body compiles, with LENGTH's byte semantics adapted.
(assert-equal 'command-adapter
  (begin (define (native-length-command) (length "café"))
         (set! *schemer-source-index* (or *schemer-source-index* (table)))
         (put! *schemer-source-index* 'native-length-command '(define (native-length-command) (length "café")))
         (call-command 'native-length-command)) 5)
(assert-equal 'was-compiled (get *schemer-command-compiled* 'native-length-command #f) #t)
;; Native callbacks can return Unicode strings and raise catchable errors.
(define (native-unicode) "Olá, café")
(assert-equal 'unicode (schemer-eval-string "(native-unicode)") "Olá, café")
(define (native-failure) (error "bridge failure"))
(assert-equal 'callback-error (schemer-eval-string "(guard (e (#t 'caught)) (native-failure))") 'caught)
;; A failed operation must execute once, never retry in the interpreter.
(define attempts 0)
(define (native-touch) (set! attempts (+ attempts 1)) #t)
(trycatch (schemer-eval-string "(native-touch) (error \"stop\")") (lambda (e) #f))
(assert-equal 'no-retry attempts 1)
(assert-equal 'legacy-state (schemer-eval-string "(define native-data (table)) (put! native-data 'x 17) (get native-data 'x)") 17)
;; File ports preserve Unicode and embedded NUL bytes, using a disposable path.
(define port-test-path (string-append (or (os.getenv "CHEZEMAX_TEST_DIR") "/tmp") "/native-port-test.txt"))
(assert-equal 'file-text
  (schemer-eval-string
   (concat "(let ((path " (value->string port-test-path) ")) "
     "(call-with-output-file path (lambda (p) (write-string (string #\\a (integer->char 0) #\\é) p))) "
     "(let ((s (call-with-input-file path (lambda (p) (read-string 3 p))))) "
     "(delete-file path) (list (string-length s) (char->integer (string-ref s 1)) (string-ref s 2))))"))
  '(3 0 #\é))
;; Actual Help-menu wrapper definitions must keep native procedure arguments.
;; Mock only window access and providers: no terminal or live service is used.
(let ((window call-in-window-of) (name get-buffer-name)
      (codex ask-codex) (claude ask-claude))
  (dynamic-wind
   (lambda ()
     (set! *schemer-source-index* #f)
     (set! get-buffer-name (lambda () "*test-source*"))
     (set! call-in-window-of (lambda (buffer fn) (fn)))
     (set! ask-codex (lambda () 'mock-codex))
     (set! ask-claude (lambda () 'mock-claude)))
   (lambda ()
     (assert-equal 'help-menu-codex (call-command 'menu-chatgpt) 'mock-codex)
     (assert-equal 'help-menu-claude (call-command 'menu-claude) 'mock-claude)
     (assert-equal 'expression-window-callback
       (schemer-eval-string "(call-in-window-of \"*test-source*\" (lambda () 'native-callback))") 'native-callback))
   (lambda ()
     (set! call-in-window-of window) (set! get-buffer-name name)
     (set! ask-codex codex) (set! ask-claude claude))))
(assert-equal 'comment-native-language-records
  (and (schemer-command-reason (schemer-command-definition 'comment-dwim)) #t) #t)
;; The exact definition + separate (time ...) interaction uses compiled code.
(assert-equal 'timed-value (schemer-eval-string "(time (native-fib 40))") 102334155)
(concat *compiled-test-count* " native compiled integration tests passed")
