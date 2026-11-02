;;;; link.scm -- Schemer: the run-time helpers, and the whole program
;;;;
;;;; (compile-program forms prelude-forms) -> the module's bytes.
;;;; The helpers are written here in WebAssembly instructions: generic
;;;; arithmetic (the slow path of + - * /, beyond small integers), eqv?,
;;;; apply and the type error.

(define *helpers* '())   ; (name . funcidx)

(define *helper-sigs*
  '(($to-f64 (eqref) (f64))
    ($num-add (eqref eqref) (eqref)) ($num-sub (eqref eqref) (eqref))
    ($num-mul (eqref eqref) (eqref)) ($num-div (eqref eqref) (eqref))
    ($num-lt (eqref eqref) (i32)) ($num-eq (eqref eqref) (i32))
    ($eqv (eqref eqref) (i32)) ($apply (eqref eqref) (eqref))
    ($type-error (i32 eqref) ())
    ($from-i64 (i64) (eqref)) ($to-i64 (eqref) (i64)) ($exact? (eqref) (i32))
    ($int-div (i32 eqref eqref) (eqref)) ($char (i32) (eqref))
    ($catch (eqref eqref) (eqref)) ($protect (eqref eqref) (eqref)) ($poll () ())))
(define G-FUEL #f)
(define *fuel* 1000000)

;;; The exception of escapes: (tag value); exported, for the host
(define *escape-tag* #f)
(define (escape-tag)
  (or *escape-tag*
      (begin (set! *module-tags* (list (sig '(eqref eqref) '())))
             (set! *escape-tag* 0)
             0)))

;;; Characters below 256 are made once, in a table filled as they are met
(define G-CHARS #f)

(define (helper name)
  (let ((h (assq name *helpers*)))
    (if h (cdr h)
        (let* ((s (cdr (assq name *helper-sigs*)))
               (idx (new-func! (sig (car s) (cadr s)))))
          (set! *helpers* (cons (cons name idx) *helpers*))
          idx))))

(define (i31-of i) (list (list 'local.get i) (list 'ref.cast 'null 'i31) 'i31.get_s))
(define (both-i31)
  (list '(local.get 0) '(ref.test i31) '(local.get 1) '(ref.test i31) 'i32.and))
(define (type-error code arg)
  (list (list 'i32.const code) (list 'local.get arg) (list 'call (helper '$type-error))))

;;; + - * on any two numbers: exact (31 or 64 bits) while the result fits
;;; 64 bits, else flonums.
(define (exact-both) (list '(local.get 0) (list 'call (helper '$exact?)) '(local.get 1) (list 'call (helper '$exact?)) 'i32.and))
(define (as-i64 i) (list (list 'local.get i) (list 'call (helper '$to-i64))))
(define (flonum-op opf64)
  (list '(local.get 0) (list 'call (helper '$to-f64)) '(local.get 1) (list 'call (helper '$to-f64))
        opf64 (list 'struct.new T-FLO)))

(define (arith-helper op64 opf64)
  ;; locals: 2 a, 3 b, 4 result (i64)
  (list '(i64 i64 i64)
        (append (exact-both)
                (list '(if eqref))
                (as-i64 0) (list '(local.set 2)) (as-i64 1) (list '(local.set 3))
                (case op64
                  ((i64.add)  ; overflow when a and b have one sign and the sum the other
                   (list '(local.get 2) '(local.get 3) 'i64.add '(local.set 4)
                         '(local.get 2) '(local.get 4) 'i64.xor '(local.get 3) '(local.get 4) 'i64.xor 'i64.and
                         '(i64.const 0) 'i64.lt_s))
                  ((i64.sub)
                   (list '(local.get 2) '(local.get 3) 'i64.sub '(local.set 4)
                         '(local.get 2) '(local.get 3) 'i64.xor '(local.get 2) '(local.get 4) 'i64.xor 'i64.and
                         '(i64.const 0) 'i64.lt_s))
                  ((i64.mul)  ; overflow when the product divided by a is not b
                   (list '(local.get 2) '(local.get 3) 'i64.mul '(local.set 4)
                         '(local.get 2) 'i64.eqz '(if i32) '(i32.const 0) 'else
                         '(local.get 2) '(i64.const -1) 'i64.eq '(if i32)
                         '(local.get 3) (list 'i64.const (- -9223372036854775807 1)) 'i64.eq 'else
                         '(local.get 4) '(local.get 2) 'i64.div_s '(local.get 3) 'i64.ne 'end 'end)))
                (list '(if eqref))
                (flonum-op opf64)
                (list 'else '(local.get 4) (list 'call (helper '$from-i64)) 'end
                      'else)
                (flonum-op opf64)
                (list 'end))))

(define (helper-body name)
  "(locals body) of the helper NAME."
  (case name
    (($poll) (list '() (list (list 'i32.const *fuel*) (list 'global.set G-FUEL) (list 'call F-POLL))))
    (($catch)   ; finalized exception handling: caught tag and value
     (list '(eqref eqref)
           (list '(block eqref) (list 'block (sig '() '(eqref eqref)))
                 (list 'try_table 'eqref (list (list 'catch (escape-tag) 0)))
                 '(local.get 0) (list 'global.get G-NIL) (list 'call (helper '$apply))
                 'end '(br 1) 'end '(local.set 3) '(local.set 2)
                 '(local.get 2) '(local.get 1) 'ref.eq
                 '(if eqref) '(local.get 3) 'else '(local.get 2) '(local.get 3)
                 (list 'throw (escape-tag)) 'end 'end)))
    (($protect)   ; value local 2; exception reference local 3
     (list '(eqref exnref)
           (list '(block eqref) '(block exnref)
                 '(try_table eqref ((catch_all_ref 0)))
                 '(local.get 0) (list 'global.get G-NIL) (list 'call (helper '$apply)) '(local.set 2)
                 '(local.get 1) (list 'global.get G-NIL) (list 'call (helper '$apply)) 'drop
                 '(local.get 2) 'end '(br 1) 'end '(local.set 3)
                 '(local.get 1) (list 'global.get G-NIL) (list 'call (helper '$apply)) 'drop
                 '(local.get 3) 'throw_ref 'end)))
    (($char)
     (set! G-CHARS (new-global! (list 'ref T-VEC) #f (list '(i32.const 256) (list 'array.new_default T-VEC))))
     (list '(eqref)
           (list '(local.get 0) '(i32.const 256) 'i32.lt_u '(if eqref)
                 (list 'global.get G-CHARS) '(local.get 0) (list 'array.get T-VEC) '(local.tee 1)
                 'ref.is_null '(if empty)
                 (list 'global.get G-CHARS) '(local.get 0) '(local.get 0) (list 'struct.new T-CHAR) '(local.tee 1)
                 (list 'array.set T-VEC)
                 'end '(local.get 1)
                 'else '(local.get 0) (list 'struct.new T-CHAR) 'end)))
    (($to-f64)
     (list '()
           (append (list '(local.get 0) '(ref.test i31) '(if f64))
                   (i31-of 0)
                   (list 'f64.convert_i32_s 'else
                         '(local.get 0) (list 'ref.test T-FLO) '(if f64)
                         '(local.get 0) (list 'ref.cast 'null T-FLO) (list 'struct.get T-FLO 0)
                         'else '(local.get 0) (list 'ref.test T-INT) '(if f64)
                         '(local.get 0) (list 'ref.cast 'null T-INT) (list 'struct.get T-INT 0) 'f64.convert_i64_s
                         'else)
                   (type-error 1 0)
                   (list '(f64.const 0.0) 'end 'end 'end))))
    (($from-i64)
     (list '()
           (list '(local.get 0) '(i64.const 1073741824) 'i64.add '(i64.const 2147483648) 'i64.lt_u
                 '(if eqref) '(local.get 0) 'i32.wrap_i64 'ref.i31
                 'else '(local.get 0) (list 'struct.new T-INT) 'end)))
    (($exact?)
     (list '() (list '(local.get 0) '(ref.test i31) '(local.get 0) (list 'ref.test T-INT) 'i32.or)))
    (($to-i64)
     (list '()
           (append (list '(local.get 0) '(ref.test i31) '(if i64))
                   (i31-of 0)
                   (list 'i64.extend_i32_s 'else
                         '(local.get 0) (list 'ref.test T-INT) '(if i64)
                         '(local.get 0) (list 'ref.cast 'null T-INT) (list 'struct.get T-INT 0) 'else)
                   (type-error 2 0)
                   (list '(i64.const 0) 'end 'end))))
    (($int-div)
     ;; (op a b): 0 quotient, 1 remainder, 2 modulo; locals: 3 a, 4 b, 5 r
     (list '(i64 i64 i64)
           (append (list '(local.get 1) (list 'call (helper '$to-i64)) '(local.set 3)
                         '(local.get 2) (list 'call (helper '$to-i64)) '(local.tee 4) 'i64.eqz '(if empty))
                   (list '(i32.const 3) '(local.get 1) (list 'call (helper '$type-error)))
                   (list 'end
                         '(local.get 0) 'i32.eqz '(if i64) '(local.get 3) '(local.get 4) 'i64.div_s 'else
                         '(local.get 3) '(local.get 4) 'i64.rem_s '(local.set 5)
                         '(local.get 0) '(i32.const 2) 'i32.eq
                         '(local.get 5) '(i64.const 0) 'i64.ne 'i32.and
                         '(local.get 5) '(local.get 4) 'i64.xor '(i64.const 0) 'i64.lt_s 'i32.and
                         '(if i64) '(local.get 5) '(local.get 4) 'i64.add 'else '(local.get 5) 'end
                         'end
                         (list 'call (helper '$from-i64))))))
    (($num-add) (arith-helper 'i64.add 'f64.add))
    (($num-sub) (arith-helper 'i64.sub 'f64.sub))
    (($num-mul) (arith-helper 'i64.mul 'f64.mul))
    (($num-div)
     ;; locals: 2 a, 3 b (i64)
     (list '(i64 i64)
           (append (exact-both)
                   (list '(if eqref))
                   (as-i64 0) (list '(local.set 2)) (as-i64 1)
                   (list '(local.tee 3) 'i64.eqz '(if empty))
                   (type-error 3 0)
                   (list 'end '(local.get 2) '(local.get 3) 'i64.rem_s 'i64.eqz
                         '(local.get 3) '(i64.const -1) 'i64.ne 'i32.and
                         '(if eqref) '(local.get 2) '(local.get 3) 'i64.div_s (list 'call (helper '$from-i64))
                         'else)
                   (flonum-op 'f64.div)
                   (list 'end 'else)
                   (flonum-op 'f64.div)
                   (list 'end))))
    (($num-lt $num-eq)
     (list '()
           (append (exact-both) (list '(if i32))
                   (as-i64 0) (as-i64 1)
                   (list (if (eq? name '$num-lt) 'i64.lt_s 'i64.eq) 'else
                         '(local.get 0) (list 'call (helper '$to-f64)) '(local.get 1) (list 'call (helper '$to-f64))
                         (if (eq? name '$num-lt) 'f64.lt 'f64.eq) 'end))))
    (($eqv)
     (list '()
           (list '(local.get 0) '(local.get 1) 'ref.eq '(if i32) '(i32.const 1) 'else
                 '(local.get 0) (list 'ref.test T-FLO) '(local.get 1) (list 'ref.test T-FLO) 'i32.and
                 '(if i32)
                 '(local.get 0) (list 'ref.cast 'null T-FLO) (list 'struct.get T-FLO 0)
                 '(local.get 1) (list 'ref.cast 'null T-FLO) (list 'struct.get T-FLO 0) 'f64.eq
                 'else
                 '(local.get 0) (list 'ref.test T-CHAR) '(local.get 1) (list 'ref.test T-CHAR) 'i32.and
                 '(if i32)
                 '(local.get 0) (list 'ref.cast 'null T-CHAR) (list 'struct.get T-CHAR 0)
                 '(local.get 1) (list 'ref.cast 'null T-CHAR) (list 'struct.get T-CHAR 0) 'i32.eq
                 'else
                 '(local.get 0) (list 'ref.test T-INT) '(local.get 1) (list 'ref.test T-INT) 'i32.and
                 '(if i32)
                 '(local.get 0) (list 'ref.cast 'null T-INT) (list 'struct.get T-INT 0)
                 '(local.get 1) (list 'ref.cast 'null T-INT) (list 'struct.get T-INT 0) 'i64.eq
                 'else '(i32.const 0) 'end 'end 'end 'end)))
    (($type-error)
     (list '()
           (list (list 'ref.null (vector-ref *clo-types* 2)) '(local.get 0) 'ref.i31 '(local.get 1)
                 (list 'call (known-func '%type-error)) 'drop 'unreachable)))
    (($apply)
     ;; locals: 2 closure, 3 arity, 4 length, 5 list walker
     (list (list (list 'ref 'null T-CLO) 'i32 'i32 'eqref)
           (append
            (list '(local.get 0) (list 'ref.test T-CLO) 'i32.eqz '(if empty))
            (type-error 5 0)
            (list 'end
                  '(local.get 0) (list 'ref.cast 'null T-CLO) '(local.tee 2) (list 'struct.get T-CLO 0) '(local.set 3)
                  ;; the length of the list
                  '(i32.const 0) '(local.set 4) '(local.get 1) '(local.set 5)
                  '(block empty) '(loop empty)
                  '(local.get 5) (list 'ref.test T-PAIR) 'i32.eqz '(br_if 1)
                  '(local.get 4) '(i32.const 1) 'i32.add '(local.set 4)
                  '(local.get 5) (list 'ref.cast 'null T-PAIR) (list 'struct.get T-PAIR 1) '(local.set 5)
                  '(br 0) 'end 'end
                  ;; a variadic procedure takes the list
                  '(local.get 3) '(i32.const 0) 'i32.lt_s '(if empty)
                  '(local.get 4) '(i32.const -1) '(local.get 3) 'i32.sub 'i32.lt_s '(if empty))
            (type-error 6 0)
            (list 'end
                  '(local.get 0) (list 'ref.cast 'null T-CLOV) '(local.get 1)
                  '(local.get 0) (list 'ref.cast 'null T-CLOV) (list 'struct.get T-CLOV 1)
                  (list 'return_call_ref T-FV) 'end
                  '(local.get 4) '(local.get 3) 'i32.ne '(if empty))
            (type-error 6 0)
            (list 'end '(local.get 1) '(local.set 5))
            (apply append
                   (map (lambda (n)
                          (let ((ct (vector-ref *clo-types* n)))
                            (append (list '(local.get 3) (list 'i32.const n) 'i32.eq '(if empty)
                                          '(local.get 0) (list 'ref.cast 'null ct))
                                    (apply append
                                           (map (lambda (k)
                                                  (list '(local.get 5) (list 'ref.cast 'null T-PAIR) (list 'struct.get T-PAIR 0)
                                                        '(local.get 5) (list 'ref.cast 'null T-PAIR) (list 'struct.get T-PAIR 1)
                                                        '(local.set 5)))
                                                (iota n)))
                                    (list '(local.get 0) (list 'ref.cast 'null ct) (list 'struct.get ct 1)
                                          (list 'return_call_ref (vector-ref *fn-types* n)) 'end))))
                        (iota (+ *max-args* 1))))
            (list 'unreachable))))
    (else (error "Schemer: internal: unknown helper" name))))

;;; ------------------------------------------------------------------
;;; Which parts of the library a program needs
;;; ------------------------------------------------------------------

(define (global-refs e acc)
  (case (car e)
    ((const lref) acc)
    ((gref) (adjoin (cadr e) acc))
    ((gset gdef) (global-refs (caddr e) (adjoin (cadr e) acc)))
    ((lset) (global-refs (caddr e) acc))
    ((if) (global-refs (cadddr e) (global-refs (caddr e) (global-refs (cadr e) acc))))
    ((seq call) (fold-refs (cdr e) acc))
    ((prim) (fold-refs (cddr e) acc))
    ((lambda) (global-refs (cadddr e) acc))
    ((let letrec) (global-refs (caddr e) (fold-refs (map cadr (cadr e)) acc)))
    (else acc)))
(define (fold-refs es acc) (if (null? es) acc (fold-refs (cdr es) (global-refs (car es) acc))))

(define *library-roots* '(%intern! %type-error %print))

(define (needed-library lib user)
  "The definitions of LIB (gdef forms) that USER's forms reach."
  (let loop ((todo (append *library-roots* (fold-refs user '()))) (seen '()))
    (if (null? todo)
        (filter (lambda (d) (memq (cadr d) seen)) lib)
        (let ((s (car todo)))
          (if (memq s seen)
              (loop (cdr todo) seen)
              (let ((defs (filter (lambda (d) (and (eq? (car d) 'gdef) (eq? (cadr d) s))) lib)))
                (loop (append (fold-refs defs '()) (cdr todo)) (cons s seen))))))))

;;; ------------------------------------------------------------------
;;; The program
;;; ------------------------------------------------------------------

(define (count-defs sym forms)
  (let loop ((fs forms) (n 0))
    (if (null? fs) n (loop (cdr fs) (if (and (eq? (caar fs) 'gdef) (eq? (cadar fs) sym)) (+ n 1) n)))))

(define (assigned-globals forms)
  ;; globals set with set! anywhere
  (let walk ((es forms) (acc '()))
    (if (null? es) acc
        (walk (cdr es) (gsets (car es) acc)))))
(define (gsets e acc)
  (case (car e)
    ((gset) (gsets (caddr e) (adjoin (cadr e) acc)))
    ((gdef lset) (gsets (caddr e) acc))
    ((if) (gsets (cadddr e) (gsets (caddr e) (gsets (cadr e) acc))))
    ((seq call) (let loop ((l (cdr e)) (a acc)) (if (null? l) a (loop (cdr l) (gsets (car l) a)))))
    ((prim) (let loop ((l (cddr e)) (a acc)) (if (null? l) a (loop (cdr l) (gsets (car l) a)))))
    ((lambda) (gsets (cadddr e) acc))
    ((let letrec) (let loop ((l (map cadr (cadr e))) (a (gsets (caddr e) acc)))
                    (if (null? l) a (loop (cdr l) (gsets (car l) a)))))
    (else acc)))

(define (reset-compiler!)
  (set! *funcs* '()) (set! *nfuncs* 0) (set! *declared* '())
  (set! *globals* '()) (set! *nglobals* 0) (set! *global-vars* '())
  (set! *symbol-globals* '()) (set! *const-globals* '()) (set! *init-code* '()) (set! *init-locals* '())
  (set! *known-globals* '()) (set! *known-locals* '()) (set! *lambda-info* '()) (set! *helpers* '())
  (set! G-CHARS #f) (set! *escape-tag* #f) (set! *module-tags* '()) (set! *uses-memory* #f)
  (init-types!)
  (escape-tag)
  (set! G-FUEL (new-global! 'i32 #t (list (list 'i32.const *fuel*))))
  (set! G-FALSE (imm-global! 0)) (set! G-TRUE (imm-global! 1)) (set! G-NIL (imm-global! 2))
  (set! G-UNSPEC (imm-global! 3)) (set! G-EOF (imm-global! 4))
  ;; the table of symbols, empty at start
  (let ((g (new-global! 'eqref #t (list (list 'global.get G-NIL)))))
    (set! *global-vars* (list (cons '%symbols g)))))

;;; In an editor (Browsered sets *editor-procedures*), a variable that
;;; neither the program nor the library defines is a procedure of the
;;; editor: (insert "x") asks the editor to run its insert.
(define *editor-procedures* #f)
(define (editor-procedures user lib)
  (if (not *editor-procedures*) '()
      (let* ((defined (let loop ((fs (append lib user)) (acc '(%symbols)))
                        (if (null? fs) acc
                            (loop (cdr fs) (if (eq? (caar fs) 'gdef) (cons (cadar fs) acc) acc)))))
             (free (filter (lambda (s) (not (memq s defined))) (fold-refs user '()))))
        (expand-toplevel
         (map (lambda (s) (list 'define (cons s 'args) (list '%editor-apply (list 'quote s) 'args))) free)))))

;;; The registry of the program's globals, for top-level-value,
;;; set-top-level-value!, bound? and procedure names (the prelude's
;;; %registry): when the program uses it, it starts by registering each of
;;; its global variables, (%register-global! 'name getter setter).  Only
;;; variables get a setter: a procedure set! would no longer be called
;;; directly.
(define (with-registry user lib)
  (if (not (assq '%registry (map (lambda (d) (cons (cadr d) d))
                                 (filter (lambda (d) (eq? (car d) 'gdef)) (needed-library lib user)))))
      user
      (let loop ((fs user) (seen '()) (acc '()) (assigned (assigned-globals user)))
        (cond ((null? fs) (append (reverse acc) user))
              ((and (eq? (caar fs) 'gdef) (not (memq (cadar fs) seen)))
               (let* ((name (cadar fs)) (v (make-var 'value))
                      (procedure? (and (pair? (caddar fs)) (eq? (car (caddar fs)) 'lambda)
                                       (= (count-defs name user) 1) (not (memq name assigned))))
                      (form (list 'call (list 'gref '%register-global!) (list 'const name)
                                  (list 'lambda '() #f (list 'gref name))
                                  (if procedure?
                                      (list 'const #f)
                                      (list 'lambda (list v) #f (list 'gset name (list 'lref v)))))))
                 (loop (cdr fs) (cons name seen) (cons form acc) assigned)))
              (else (loop (cdr fs) seen acc assigned))))))

;;; The library expanded once: a compiler kept by its host (the editor's
;;; M-: and C-x C-e, compiler-main.scm) compiles one request after another,
;;; and expanding the library took some 0.4 s of each.
(define *expanded-library* #f)          ; (library-forms . expanded)
(define (expanded-library library-forms)
  (if (and *expanded-library* (eq? (car *expanded-library*) library-forms))
      (cdr *expanded-library*)
      (let ((x (expand-toplevel library-forms)))
        (set! *expanded-library* (cons library-forms x))
        x)))

(define (compile-program user-forms library-forms)
  "The bytes of the module running USER-FORMS with what they need of the library."
  (reset-compiler!)
  (set! *macros* '()) (set! *aliases* (table)) (reset-libraries!)
  (let* ((user0 (map browsered-rewrite-ir (expand-toplevel user-forms)))
         ;; the library is expanded without the program's macros
         (lib0 (begin (set! *macros* '()) (reset-libraries!) (expanded-library library-forms)))
         (user (with-registry (append (editor-procedures user0 lib0) user0) lib0))
         (lib (needed-library lib0 user))
         (forms (append lib user))
         (assigned (assigned-globals forms))
         (defined (let loop ((fs forms) (acc '(%symbols)))
                    (if (null? fs) acc
                        (loop (cdr fs) (if (eq? (caar fs) 'gdef) (cons (cadar fs) acc) acc)))))
         (unbound (filter (lambda (s) (not (memq s defined))) (fold-refs forms '())))
         (import-types (map (lambda (im) (sig (cadr im) (caddr im))) *imports*)))
    (when (pair? unbound)
      (error "Schemer: unbound variables:" unbound))
    ;; the known top-level procedures
    (for-each (lambda (d)
                ;; arity: n, or -1-n for n required arguments and a rest list
                (when (and (eq? (car d) 'gdef) (pair? (caddr d)) (eq? (car (caddr d)) 'lambda)
                           (not (memq (cadr d) assigned)) (= (count-defs (cadr d) forms) 1))
                  (set! *known-globals*
                        (cons (list (cadr d) (lambda-func! (caddr d))
                                    (if (lambda-variadic? (caddr d))
                                        (- -1 (length (cadr (caddr d))))
                                        (length (cadr (caddr d)))))
                              *known-globals*))))
              forms)
    (let* ((init (new-func! (sig '() '())))
           (main (new-func! (sig '() '(eqref))))
           (f (make-fctx 0))
           (nlib (length lib))
           (body (let loop ((fs forms) (i 0) (acc '()))
                   (cond ((null? fs) (if (null? user) (append acc (unspec)) acc))
                         ((null? (cdr fs)) (append acc (gen (car fs) f #f)))
                         (else (loop (cdr fs) (+ i 1) (append acc (gen (car fs) f #f) (list 'drop))))))))
      (set-func! main (vector-ref f 1) (append (list (list 'call init)) body))
      ;; exported printers
      (let ((wr (new-func! (sig '(eqref) '()))) (dp (new-func! (sig '(eqref) '())))
            (c0 (new-func! (sig '(eqref) '(eqref))))
            (c3 (new-func! (sig '(eqref eqref eqref eqref) '(eqref))))
            (cn (new-func! (sig '(eqref eqref) '(eqref))))
            (eq (new-func! (sig '(eqref eqref) '(i32))))
            (sn (new-func! (sig '(i32) '(eqref)))) (ss (new-func! (sig '(eqref i32 i32) '())))
            (sl (new-func! (sig '(eqref) '(i32)))) (sr (new-func! (sig '(eqref i32) '(i32)))))
        (set-func! eq '() (list '(local.get 0) '(local.get 1) 'ref.eq))
        (set-func! cn '() (list '(local.get 0) '(local.get 1) (list 'struct.new T-PAIR)))
        ;; strings for the host (files)
        (set-func! sn '() (list '(i32.const 32) '(local.get 0) (list 'array.new T-CODES) (list 'struct.new T-STR)))
        (set-func! ss '() (list '(local.get 0) (list 'ref.cast 'null T-STR) (list 'struct.get T-STR 0)
                                '(local.get 1) '(local.get 2) (list 'array.set T-CODES)))
        (set-func! sl '() (list '(local.get 0) (list 'ref.cast 'null T-STR) (list 'struct.get T-STR 0) 'array.len))
        (set-func! sr '() (list '(local.get 0) (list 'ref.cast 'null T-STR) (list 'struct.get T-STR 0)
                                '(local.get 1) (list 'array.get T-CODES)))
        ;; call0: the host calls a procedure of no arguments (escapes)
        (set-func! c0 '() (list '(local.get 0) (list 'global.get G-NIL) (list 'call (helper '$apply))))
        ;; call3: the host calls a procedure of three arguments (the editor's hot paths)
        (set-func! c3 '() (list '(local.get 0) '(local.get 1) '(local.get 2) '(local.get 3) (list 'global.get G-NIL)
                                (list 'struct.new T-PAIR) (list 'struct.new T-PAIR) (list 'struct.new T-PAIR)
                                (list 'call (helper '$apply))))
        (set-func! wr '() (list (list 'ref.null (vector-ref *clo-types* 2)) '(local.get 0) (list 'global.get G-TRUE)
                                (list 'call (known-func '%print)) 'drop))
        (set-func! dp '() (list (list 'ref.null (vector-ref *clo-types* 2)) '(local.get 0) (list 'global.get G-FALSE)
                                (list 'call (known-func '%print)) 'drop))
        ;; helpers (they may add one another)
        (let fill ((done '()))
          (let ((todo (filter (lambda (h) (not (memq (car h) done))) *helpers*)))
            (when (pair? todo)
              (for-each (lambda (h) (let ((b (helper-body (car h)))) (set-func! (cdr h) (car b) (cadr b)))) todo)
              (fill (append (map car todo) done)))))
        ;; start-up: symbols and constants (in the order they were made)
        (set-func! init *init-locals* (apply append (reverse *init-code*)))
        (module-bytes (reverse *types*)
                      (append (map (lambda (im t) (list "host" (car im) t)) *imports* import-types)
                              (if *uses-memory* (list (list "host" "memory" 'memory)) '()))
                      (map (lambda (fn) (list (vector-ref fn 0) (vector-ref fn 1) (vector-ref fn 2)))
                           (reverse *funcs*))
                      (reverse *globals*)
                      (list (list "main" 'func main) (list "write" 'func wr) (list "display" 'func dp)
                            (list "native_ref_equal" 'func eq) (list "call0" 'func c0) (list "call3" 'func c3) (list "cons" 'func cn)
                            (list "escape" 'tag (escape-tag))
                            (list "string_new" 'func sn) (list "string_set" 'func ss)
                            (list "string_length" 'func sl) (list "string_ref" 'func sr))
                      (reverse *declared*)
                      #f
                      (function-names))))))

;;; Names of the functions, for profilers and debuggers
(define (function-names)
  (let* ((named (append (let loop ((ims *imports*) (i 0) (acc '()))
                          (if (null? ims) acc (loop (cdr ims) (+ i 1) (cons (cons i (car (car ims))) acc))))
                        (map (lambda (k) (cons (cadr k) (symbol->string (car k)))) *known-globals*)
                        (map (lambda (k) (cons (cadr k) (symbol->string (var-name (car k))))) *known-locals*)
                        (map (lambda (h) (cons (cdr h) (symbol->string (car h)))) *helpers*)))
         (sorted (sort-by-car named)))
    ;; one name per index
    (let loop ((l sorted) (acc '()))
      (cond ((null? l) (reverse acc))
            ((and (pair? acc) (= (caar acc) (caar l))) (loop (cdr l) acc))
            (else (loop (cdr l) (cons (car l) acc)))))))
(define (sort-by-car l)
  (if (or (null? l) (null? (cdr l))) l
      (let ((p (caar l)))
        (append (sort-by-car (filter (lambda (x) (< (car x) p)) (cdr l)))
                (list (car l))
                (sort-by-car (filter (lambda (x) (>= (car x) p)) (cdr l)))))))
