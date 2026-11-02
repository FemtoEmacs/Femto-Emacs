;;; scripts-femtoscheme.scm -- tests/scripts-cases.scm in femtoscheme
(define (test-bytes s) s)               ; byte strings
(define (test-text b) b)
(define (hashtable-or-get-indentation name) (get *indentation* name))
(define (current-directory) (path.cwd))
(define-macro (script-cases . cases)
  `(lambda () (list ,@(map (lambda (c) `(cons ,(car c) (trycatch ,(cadr c) (lambda (e) 'error)))) cases))))
(load "tests/scripts-cases.scm")
;; a fresh copy of every pair and string: femtoscheme writes what is shared
;; with labels (#0= ... #0#), which Chez's write does not
(define (unshared x)
  (cond ((pair? x) (cons (unshared (car x)) (unshared (cdr x))))
        ((string? x) (string-append "" x))
        ((vector? x) (list->vector (map unshared (vector->list x))))
        (else x)))
(define (script-report)
  (with-bindings ((*print-pretty* #f))
  (let ((p (open-output-string)))
    (for-each (lambda (r) (write (car r) p) (display " " p) (write (unshared (cdr r)) p) (newline p)) (*script-cases*))
    (get-output-string p))))
;; the report goes to the file $CHEZEMAX_REPORT: --eval answers at most 8 KB
(define (write-script-report)
  (let ((f (file (os.getenv "CHEZEMAX_REPORT") :write :create :truncate)))
    (io.write f (script-report))
    (io.close f)
    #t))
