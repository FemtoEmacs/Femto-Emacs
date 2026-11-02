;;;; femtoscheme.scm -- femtoscheme's names for what Schemer has
;;;;
;;;; So that the scripts move over with few changes (PORT-TO-SCHEMER.md,
;;;; step 4), the procedures and forms of femtoscheme they use are given
;;;; here in terms of Chez's.  Not here: femtoscheme's byte strings (AREF on
;;;; a string, STRING.SUB, STRING.FIND, LENGTH of a string) -- the scripts
;;;; change to Chez strings, and bytevectors where bytes matter -- and EVAL,
;;;; EVAL-STRING and LOAD, which need the compiler at run time.  This file
;;;; goes when femtoscheme does (step 5).

;;; Tables: femtoscheme's are hashtables compared with equal?
(define (table . keys-and-values)
  (let ((t (make-equal-hashtable)))
    (let loop ((l keys-and-values))
      (when (and (pair? l) (pair? (cdr l)))
        (hashtable-set! t (car l) (cadr l))
        (loop (cddr l))))
    t))
(define (table? x) (hashtable? x))
(define (put! t key value) (hashtable-set! t key value) t)
(define %no-entry (list 'no-entry))
(define (get t key . default)
  (let ((v (hashtable-ref t key %no-entry)))
    (cond ((not (eq? v %no-entry)) v)
          ((pair? default) (car default))
          (else (error "get: no such key" key)))))
(define (has? t key) (hashtable-contains? t key))
(define (del! t key)
  (unless (hashtable-contains? t key) (error "del!: no such key" key))
  (hashtable-delete! t key)
  t)
(define (table.count t) (hashtable-size t))
(define (table.foldl f init t)
  (let ((acc init))
    (hashtable-walk t (lambda (k v) (set! acc (f k v acc))))
    acc))
(define (table.keys t) (vector->list (hashtable-keys t)))
(define (table.values t) (vector->list (hashtable-values t)))
(define (table.pairs t) (table.foldl (lambda (k v acc) (cons (cons k v) acc)) '() t))
(define (table.foreach f t) (hashtable-walk t f))
(define (table.clone t) (hashtable-copy t #t))

;;; Text buffers: string ports
(define (buffer) (open-output-string))
(define (io.write port x)
  (cond ((string? x) (write-string x port))
        ((char? x) (write-char x port))
        ((bytevector? x) (write-string (utf8->string x) port))
        (else (display x port))))
(define (io.tostring! port)            ; the text so far; the buffer is emptied
  (let ((s (get-output-string port)))
    (%pf-set! port 2 0)
    s))
(define (io.close port) (close-port port))
;;; (file path :write :create :truncate): a file to write
(define :read ':read) (define :write ':write) (define :create ':create)
(define :truncate ':truncate) (define :append ':append)
(define (file path . modes)
  (if (memq ':write modes) (open-output-file path) (open-input-file path)))

;;; Errors: (trycatch expression handler)
(define-syntax trycatch
  (syntax-rules ()
    ((_ expression handler) (guard (e (#t (handler e))) expression))))

;;; (with-bindings ((variable value) ...) body ...): the globals hold the
;;; values while BODY runs.  *OUTPUT-STREAM* is the current output port.
(define *output-stream* #f)
(define-syntax with-bindings
  (syntax-rules (*output-stream*)
    ((_ () body ...) (let () body ...))
    ((_ ((*output-stream* port) more ...) body ...)
     (%with-port (list port) (lambda () (with-bindings (more ...) body ...))))
    ((_ ((variable value) more ...) body ...)
     (let ((saved variable) (new value))
       (dynamic-wind
        (lambda () (set! variable new))
        (lambda () (with-bindings (more ...) body ...))
        (lambda () (set! new variable) (set! variable saved)))))))

;;; Globals and procedures by name
(define (bound? name) (top-level-bound? name))
(define (function:name p) (procedure-name p))
(define (builtin? p) (foreign-procedure? p))
