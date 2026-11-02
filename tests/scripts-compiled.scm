;;; scripts-compiled.scm -- tests/scripts-cases.scm compiled (run-scripts.sh):
(define (test-bytes s) (string->utf8 s)) ; bytevectors
(define (test-text b) (utf8->string b))
(define (hashtable-or-get-indentation name) (hashtable-ref *indentation* name #f))
;;; C-c 9 inserts the report after the text the cases leave in the buffer
(define-syntax script-cases
  (syntax-rules ()
    ((_ (name expression) ...)
     (lambda () (list (cons name (guard (e (#t 'error)) expression)) ...)))))
(define (script-report results)
  (let ((p (open-output-string)))
    (for-each (lambda (r) (write (car r) p) (display " " p) (write (cdr r) p) (newline p)) results)
    (get-output-string p)))
;; the report goes to the file $CHEZEMAX_REPORT
(compiled-key! "C-c 9"
  (lambda ()
    (let ((report (script-report (*script-cases*))))
      (call-with-output-file (getenv "CHEZEMAX_REPORT") (lambda (p) (write-string report p))))))
