;;;; bridge.scm -- compiled Scheme and the C core talk through memory
;;;;
;;;; Chezemax's scripts run compiled by Schemer, in Wasmtime; the editor's
;;;; buffers, windows and screen are in C (src/).  The two call each other
;;;; through a mailbox at the start of a memory they share:
;;;;
;;;;   Scheme calls C   (foreign-procedure "fe-insert" (string) void), as in
;;;;                    Chez: the arguments go in the mailbox, (%editor N)
;;;;                    calls C function N (src/bridge.c), the result comes
;;;;                    back in the mailbox.
;;;;   C calls Scheme   the program's value is BRIDGE-DISPATCH: C puts the
;;;;                    arguments of a hook in the mailbox and calls it with
;;;;                    the hook's number; the result comes back the same way.
;;;;
;;;; In the mailbox: a count (4 bytes), then the values, each a tag byte and
;;;; its contents (numbers are 4 bytes, little-endian, signed):
;;;;   0 #f   1 #t   2 integer   3 string (length, UTF-8 bytes)
;;;;   4 bytevector (length, bytes)   5 list (count, values)   6 nothing
;;;; A call answers 0, the result in the mailbox, or 1, an error message.
;;;; Each side copies its arguments out before doing anything else, so calls
;;;; may nest (a C function that runs a hook that calls C again).

(define *bridge-size* 0)                 ; the memory's size, as C last said

;;; Numbers: the small integers (fixnums, 31 bits) never leave fixnum
;;; arithmetic here; anything beyond 2^30 would be a slow bignum.
(define (%bridge-u32! at n)
  (if (< n 0)
      (let ((m (- -1 n)))                ; the bytes of n are 255 minus those of -1-n
        (%mem-u8-set! at (- 255 (remainder m 256)))
        (%mem-u8-set! (+ at 1) (- 255 (remainder (quotient m 256) 256)))
        (%mem-u8-set! (+ at 2) (- 255 (remainder (quotient m 65536) 256)))
        (%mem-u8-set! (+ at 3) (- 255 (quotient m 16777216))))
      (begin
        (%mem-u8-set! at (remainder n 256))
        (%mem-u8-set! (+ at 1) (remainder (quotient n 256) 256))
        (%mem-u8-set! (+ at 2) (remainder (quotient n 65536) 256))
        (%mem-u8-set! (+ at 3) (quotient n 16777216)))))

(define (%bridge-u32 at)
  (let ((b3 (%mem-u8 (+ at 3)))
        (low (+ (%mem-u8 at) (* 256 (%mem-u8 (+ at 1))) (* 65536 (%mem-u8 (+ at 2))))))
    (cond ((= b3 0) low)
          ((= b3 255) (- low 16777216))
          ((< b3 128) (+ low (* 16777216 b3)))
          (else (- (+ low (* 16777216 b3)) 4294967296)))))

;;; Writing: the count first, then each value at *BRIDGE-AT*.  Strings are
;;; written character by character as UTF-8, straight into the memory:
;;; going through a bytevector or a list costs far more (variadic calls).
(define *bridge-at* 4)

(define (%bridge-room! n)          ; N more bytes at *BRIDGE-AT*
  (let ((need (+ *bridge-at* n)))
    (when (> need *bridge-size*)
      (let ((b0 (%mem-u8 0)) (b1 (%mem-u8 1)) (b2 (%mem-u8 2)) (b3 (%mem-u8 3)))
        (%bridge-u32! 0 (+ need 65536))
        (set! *bridge-size* (%editor -1))
        (%mem-u8-set! 0 b0) (%mem-u8-set! 1 b1) (%mem-u8-set! 2 b2) (%mem-u8-set! 3 b3)
        (when (< *bridge-size* need) (error "The C bridge has no room for" need))))))

(define (%bridge-begin! count)
  (%bridge-u32! 0 count)
  (set! *bridge-at* 4))

(define (%bridge-tag! t)
  (%bridge-room! 1)
  (%mem-u8-set! *bridge-at* t)
  (set! *bridge-at* (+ *bridge-at* 1)))

(define (%bridge-int! n)
  (%bridge-room! 4)
  (%bridge-u32! *bridge-at* n)
  (set! *bridge-at* (+ *bridge-at* 4)))

(define (%utf8-length s)
  (let ((n (string-length s)))
    (let loop ((i 0) (bytes 0))
      (if (= i n) bytes
          (let ((c (char->integer (string-ref s i))))
            (loop (+ i 1) (+ bytes (cond ((< c #x80) 1) ((< c #x800) 2) ((< c #x10000) 3) (else 4)))))))))

(define (%bridge-string! s)
  (let ((n (string-length s)) (bytes (%utf8-length s)))
    (%bridge-tag! 3)
    (%bridge-int! bytes)
    (%bridge-room! bytes)
    (let loop ((i 0) (at *bridge-at*))
      (if (= i n)
          (set! *bridge-at* at)
          (let ((c (char->integer (string-ref s i))))
            (cond ((< c #x80) (%mem-u8-set! at c) (loop (+ i 1) (+ at 1)))
                  ((< c #x800)
                   (%mem-u8-set! at (+ #xc0 (quotient c 64)))
                   (%mem-u8-set! (+ at 1) (+ #x80 (remainder c 64)))
                   (loop (+ i 1) (+ at 2)))
                  ((< c #x10000)
                   (%mem-u8-set! at (+ #xe0 (quotient c 4096)))
                   (%mem-u8-set! (+ at 1) (+ #x80 (remainder (quotient c 64) 64)))
                   (%mem-u8-set! (+ at 2) (+ #x80 (remainder c 64)))
                   (loop (+ i 1) (+ at 3)))
                  (else
                   (%mem-u8-set! at (+ #xf0 (quotient c 262144)))
                   (%mem-u8-set! (+ at 1) (+ #x80 (remainder (quotient c 4096) 64)))
                   (%mem-u8-set! (+ at 2) (+ #x80 (remainder (quotient c 64) 64)))
                   (%mem-u8-set! (+ at 3) (+ #x80 (remainder c 64)))
                   (loop (+ i 1) (+ at 4)))))))))

(define (%bridge-bytes! bv)
  (let ((n (bytevector-length bv)))
    (%bridge-tag! 4)
    (%bridge-int! n)
    (%bridge-room! n)
    (let loop ((i 0) (at *bridge-at*))
      (if (= i n)
          (set! *bridge-at* at)
          (begin (%mem-u8-set! at (bytevector-u8-ref bv i)) (loop (+ i 1) (+ at 1)))))))

(define (%bridge-arg! v)
  (cond ((eq? v #f) (%bridge-tag! 0))
        ((eq? v #t) (%bridge-tag! 1))
        ((fixnum? v) (%bridge-tag! 2) (%bridge-int! v))
        ((and (exact-integer? v) (<= -2147483648 v 2147483647)) (%bridge-tag! 2) (%bridge-int! v))
        ((string? v) (%bridge-string! v))
        ((symbol? v) (%bridge-string! (symbol->string v)))
        ((bytevector? v) (%bridge-bytes! v))
        ((or (null? v) (pair? v))
         (%bridge-tag! 5)
         (%bridge-int! (length v))
         (let loop ((l v)) (when (pair? l) (%bridge-arg! (car l)) (loop (cdr l)))))
        ((char? v) (%bridge-tag! 2) (%bridge-int! (char->integer v)))
        (else (%bridge-tag! 6))))

(define (%bridge-put-all values)   ; for the less frequent paths
  (%bridge-begin! (length values))
  (let loop ((l values)) (when (pair? l) (%bridge-arg! (car l)) (loop (cdr l)))))

;;; Reading
(define (%bridge-read-string at)  ; (string . next): count the characters, then fill
  (let* ((n (%bridge-u32 at)) (start (+ at 4)) (end (+ start n)))
    (let ((chars (let loop ((i start) (k 0))
                   (if (= i end) k (loop (+ i 1) (if (= (quotient (%mem-u8 i) 64) 2) k (+ k 1)))))))
      (let ((s (%make-string chars #\space)))
        (let loop ((i start) (k 0))
          (if (= i end)
              (cons s end)
              (let ((b0 (%mem-u8 i)))
                (cond ((< b0 #x80) (string-set! s k (integer->char b0)) (loop (+ i 1) (+ k 1)))
                      ;; a piece of a character cut at the start: not counted
                      ((< b0 #xc0) (loop (+ i 1) k))
                      ;; a character cut at the end
                      ((> (+ i (cond ((< b0 #xe0) 2) ((< b0 #xf0) 3) (else 4))) end)
                       (string-set! s k #\xFFFD) (loop end (+ k 1)))
                      ((< b0 #xe0)
                       (string-set! s k (integer->char (+ (* 64 (- b0 #xc0)) (- (%mem-u8 (+ i 1)) #x80))))
                       (loop (+ i 2) (+ k 1)))
                      ((< b0 #xf0)
                       (string-set! s k (integer->char (+ (* 4096 (- b0 #xe0)) (* 64 (- (%mem-u8 (+ i 1)) #x80))
                                                          (- (%mem-u8 (+ i 2)) #x80))))
                       (loop (+ i 3) (+ k 1)))
                      (else
                       (string-set! s k (integer->char (+ (* 262144 (- b0 #xf0)) (* 4096 (- (%mem-u8 (+ i 1)) #x80))
                                                          (* 64 (- (%mem-u8 (+ i 2)) #x80)) (- (%mem-u8 (+ i 3)) #x80))))
                       (loop (+ i 4) (+ k 1)))))))))))

(define (%bridge-read-bytes at)
  (let* ((n (%bridge-u32 at)) (bv (make-bytevector n 0)))
    (let loop ((i 0))
      (when (< i n)
        (bytevector-u8-set! bv i (%mem-u8 (+ at 4 i)))
        (loop (+ i 1))))
    (cons bv (+ at 4 n))))

;;; The value at AT: (value . where the next one starts)
(define (%bridge-read at)
  (case (%mem-u8 at)
    ((0) (cons #f (+ at 1)))
    ((1) (cons #t (+ at 1)))
    ((2) (cons (%bridge-u32 (+ at 1)) (+ at 5)))
    ((3) (%bridge-read-string (+ at 1)))
    ((4) (%bridge-read-bytes (+ at 1)))
    ((5) (let loop ((k (%bridge-u32 (+ at 1))) (at (+ at 5)) (acc '()))
           (if (= k 0) (cons (reverse acc) at)
               (let ((r (%bridge-read at))) (loop (- k 1) (cdr r) (cons (car r) acc))))))
    (else (cons (if #f #f) (+ at 1)))))

(define (%bridge-get-all)
  (let loop ((k (%bridge-u32 0)) (at 4) (acc '()))
    (if (= k 0) (reverse acc)
        (let ((r (%bridge-read at))) (loop (- k 1) (cdr r) (cons (car r) acc))))))

;;; Calling C: the arguments are written; C function ID answers
(define (%bridge-finish id)
  (if (= (%editor id) 0)
      (if (> (%bridge-u32 0) 0) (car (%bridge-read 4)) (if #f #f))
      (error (if (and (> (%bridge-u32 0) 0) (= (%mem-u8 4) 3)) (car (%bridge-read 4)) "C function failed"))))

(define (%bridge-call id args) (%bridge-put-all args) (%bridge-finish id))

(define (%bridge-lookup name)
  (let ((id (%bridge-call 0 (list name))))
    (when (<= id 0) (error "No C function of that name:" name))
    id))

;;; The procedures that call C, for (foreign-procedure? p)
(define *foreign-procedures* '())
(define (%foreign! p) (set! *foreign-procedures* (cons p *foreign-procedures*)) p)
(define (foreign-procedure? p) (and (memq p *foreign-procedures*) #t))

;;; As in Chez: (foreign-procedure "name" (argument-type ...) result-type).
;;; The procedure has exactly as many arguments as there are types: a
;;; procedure of fixed arity is called far faster than one with a rest list.
(define-syntax foreign-procedure
  (syntax-rules ()
    ((_ name (t ...) r) (%foreign-procedure name (t ...) () r))))
(define-syntax %foreign-procedure
  (syntax-rules ()
    ((_ name () (x ...) r)
     (let ((id (%bridge-lookup name)) (n (length '(x ...))))
       (%foreign!
        (lambda (x ...)
          (%bridge-begin! n)
          (%bridge-arg! x) ...
          (%bridge-finish id)))))
    ((_ name (t0 t1 ...) (x ...) r) (%foreign-procedure name (t1 ...) (x ... y) r))))

;;; Calls from C: hook number -> procedure
(define *bridge-hooks* (make-vector 64 #f))
(define (bridge-hook! n proc) (vector-set! *bridge-hooks* n proc))

(define (%bridge-error-text e)
  (if (error-object? e)
      (let ((irritants (error-object-irritants e)))
        (if (null? irritants)
            (error-object-message e)
            (let ((p (open-output-string)))
              (display (error-object-message e) p)
              (for-each (lambda (x) (display " " p) (write x p)) irritants)
              (get-output-string p))))
      (let ((p (open-output-string))) (display "raised: " p) (write e p) (get-output-string p))))

;;; Errors in a hook become its answer, not an unwinding into C.  This is
;;; guard without call/cc, call-with-values and apply, which cost far more
;;; than a hook: one handler, installed once at the bottom of the handlers,
;;; throws to the tag of the hook running now ((%catch thunk tag) returns
;;; the thunk's value or what (%throw tag v) threw).
(define *bridge-tag* #f)
(define (%bridge-handler c) (%throw *bridge-tag* (cons #f c)))
(set! %handlers (list %bridge-handler))

(define (%bridge-try thunk)        ; (#t . value) or (#f . what was raised)
  (let ((saved-tag *bridge-tag*) (saved-handlers %handlers) (tag (cons 'bridge-try '())))
    (set! *bridge-tag* tag)
    (let ((r (%catch (lambda () (cons #t (thunk))) tag)))
      (set! *bridge-tag* saved-tag)
      (set! %handlers saved-handlers)
      r)))

(define (%bridge-apply proc args)
  (let ((n (length args)))
    (cond ((= n 0) (proc))
          ((= n 1) (proc (car args)))
          ((= n 2) (proc (car args) (cadr args)))
          ((= n 3) (proc (car args) (cadr args) (caddr args)))
          ((= n 4) (proc (car args) (cadr args) (caddr args) (cadddr args)))
          ((= n 5) (proc (car args) (cadr args) (caddr args) (cadddr args) (car (cddddr args))))
          (else (apply proc args)))))

;;; The program's value: C calls it with a hook's number
;;; DEPTH: how many hooks run already.  At 0 nothing of the program is
;;; running, so what a call left half done is put back: a trap (a car of a
;;; number, say) stops the program where it is, with no handler run.
(define (%bridge-fresh!)
  (set! *bridge-tag* #f)
  (set! %handlers (list %bridge-handler))
  (set! %guard-hit #f)
  (set! %out #f))
(define (bridge-dispatch n depth unused)
  (when (eqv? depth 0) (%bridge-fresh!))
  (let ((proc (and (>= n 0) (< n (vector-length *bridge-hooks*)) (vector-ref *bridge-hooks* n))))
    (if (not proc)
        (begin (%bridge-put-all (list "No Scheme procedure for this hook")) 1)
        (let* ((args (%bridge-get-all))
               (r (%bridge-try (lambda () (%bridge-apply proc args)))))
          (if (car r)
              (begin (%bridge-begin! 1) (%bridge-arg! (cdr r)) 0)
              (begin (%bridge-put-all (list (%bridge-error-text (cdr r)))) 1))))))
