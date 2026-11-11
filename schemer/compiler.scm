;;;; compiler.scm -- Schemer: Scheme compiled to WebAssembly (WasmGC)
;;;;
;;;; (compile-program forms) gives the bytes of a WebAssembly module whose
;;;; export main runs FORMS.  Scheme values are WebAssembly GC references:
;;;;
;;;;   small integers   i31ref (31 bits)
;;;;   integers         struct $Int {i64}, beyond 31 bits (beyond 64: flonums)
;;;;   flonums          struct $Flo {f64}
;;;;   pairs            struct $Pair {car, cdr}
;;;;   characters       struct $Char {i32}
;;;;   strings          struct $Str {array of code points}
;;;;   symbols          struct $Sym {name}, interned
;;;;   vectors          array of values
;;;;   procedures       struct $Clo_n {arity, code, environment}
;;;;   #t #f () ...     struct $Imm, one each
;;;;
;;;; Each lambda is a WebAssembly function taking its closure and its
;;;; arguments; calls in tail position are tail calls (return_call); calls
;;;; to procedures known at compile time are direct calls; arithmetic on
;;;; small integers is written inline.  The browser's garbage collector
;;;; manages the memory.  The library is prelude.scm, compiled with the
;;;; program (only what the program uses).

(define *max-args* 8)
(define *uses-memory* #f)   ; the program reads or writes the host's memory ("host" "memory")

;;; ------------------------------------------------------------------
;;; Types
;;; ------------------------------------------------------------------

(define *types* '())   ; reversed
(define *ntypes* 0)
(define (add-type! d)
  (set! *types* (cons d *types*))
  (set! *ntypes* (+ *ntypes* 1))
  (- *ntypes* 1))

(define T-PAIR #f) (define T-FLO #f) (define T-CHAR #f) (define T-CODES #f)
(define T-STR #f) (define T-SYM #f) (define T-VEC #f) (define T-BOX #f)
(define T-IMM #f) (define T-INT #f) (define T-REC #f) (define T-CLO #f) (define T-FV #f) (define T-CLOV #f)
(define *fn-types* #f)    ; vector: F_n
(define *clo-types* #f)   ; vector: Clo_n
(define *sigs* '())       ; ((params . results) . typeidx)

(define (init-types!)
  (set! *types* '()) (set! *ntypes* 0) (set! *sigs* '())
  (set! T-PAIR (add-type! '(struct ((#t eqref) (#t eqref)))))
  (set! T-FLO (add-type! '(struct ((#f f64)))))
  (set! T-CHAR (add-type! '(struct ((#f i32)))))
  (set! T-CODES (add-type! '(array (#t i32))))
  (set! T-STR (add-type! (list 'struct (list (list #t (list 'ref T-CODES))))))
  (set! T-SYM (add-type! (list 'struct (list (list #f (list 'ref T-STR))))))
  (set! T-VEC (add-type! '(array (#t eqref))))
  (set! T-BOX (add-type! '(struct ((#t eqref)))))
  (set! T-IMM (add-type! '(struct ((#f i32) (#f i32)))))
  (set! T-INT (add-type! '(struct ((#f i64)))))
  (set! T-REC (add-type! (list 'struct (list '(#f eqref) (list #f (list 'ref T-VEC))))))   ; record: type, fields
  (set! T-CLO (add-type! '(sub #f () (struct ((#f i32))))))
  (set! *fn-types* (make-vector (+ *max-args* 1) #f))
  (set! *clo-types* (make-vector (+ *max-args* 1) #f))
  (let loop ((n 0))
    (when (<= n *max-args*)
      ;; F_n refers to Clo_n, which is the next index
      (let ((f (add-type! (list 'func (cons (list 'ref 'null (+ *ntypes* 1)) (make-list n 'eqref))
                                '(eqref)))))
        (vector-set! *fn-types* n f)
        (vector-set! *clo-types* n
                     (add-type! (list 'sub #t (list T-CLO)
                                      (list 'struct (list '(#f i32) (list #f (list 'ref f))
                                                          (list #f (list 'ref 'null T-VEC))))))))
      (loop (+ n 1))))
  (set! T-FV (add-type! (list 'func (list (list 'ref 'null (+ *ntypes* 1)) 'eqref) '(eqref))))
  (set! T-CLOV (add-type! (list 'sub #t (list T-CLO)
                                (list 'struct (list '(#f i32) (list #f (list 'ref T-FV))
                                                    (list #f (list 'ref 'null T-VEC))))))))

(define (sig params results)
  (let ((key (cons params results)))
    (let ((s (assoc key *sigs*)))
      (if s (cdr s)
          (let ((i (add-type! (list 'func params results))))
            (set! *sigs* (cons (cons key i) *sigs*))
            i)))))

;;; ------------------------------------------------------------------
;;; Functions and globals
;;; ------------------------------------------------------------------

(define *imports*
  ;; name, params, results
  '(("write_char" (i32) ()) ("write_flonum" (f64) ()) ("abort" (eqref) ())
    ("now" () (f64)) ("math" (i32 f64) (f64)) ("math2" (i32 f64 f64) (f64))
    ("flonum_char" (f64 i32) (i32))
    ;; decimals: the characters one by one, then the flonum
    ("number_char" (i32) ()) ("number_end" () (f64))
    ;; hash tables (prelude.scm)
    ("table" (i32 eqref eqref eqref) (eqref))
    ;; files: 0 read (a string, or 0), 1 write, 2 exists? (1 or 0), 3 delete
    ("file" (i32 eqref eqref) (eqref))
    ;; every million calls and loop turns, so that the host may stop a long run
    ("poll" () ())
    ;; (editor-call text) -> text: a procedure of the editor (*editor-procedures*)
    ("editor" (eqref) (eqref))))
(define F-WRITE-CHAR 0) (define F-WRITE-FLONUM 1) (define F-ABORT 2)
(define F-NOW 3) (define F-MATH 4) (define F-MATH2 5) (define F-FLONUM-CHAR 6)
(define F-NUMBER-CHAR 7) (define F-NUMBER-END 8) (define F-TABLE 9) (define F-FILE 10) (define F-POLL 11) (define F-EDITOR 12)
(define *nimports* 13)

(define *funcs* '())       ; reversed: #(typeidx locals body)
(define *nfuncs* 0)
(define *declared* '())    ; functions used by ref.func

(define (new-func! typeidx)
  (set! *funcs* (cons (vector typeidx '() '(unreachable)) *funcs*))
  (set! *nfuncs* (+ *nfuncs* 1))
  (+ *nimports* (- *nfuncs* 1)))

(define (set-func! idx locals body)
  (let ((f (list-ref *funcs* (- *nfuncs* 1 (- idx *nimports*)))))
    (vector-set! f 1 locals)
    (vector-set! f 2 body)))

(define *globals* '())     ; reversed: (valtype mutable? init)
(define *nglobals* 0)
(define (new-global! type mutable init)
  (set! *globals* (cons (list type mutable init) *globals*))
  (set! *nglobals* (+ *nglobals* 1))
  (- *nglobals* 1))

(define G-FALSE #f) (define G-TRUE #f) (define G-NIL #f) (define G-UNSPEC #f) (define G-EOF #f)
(define (imm-global! tag)
  (new-global! 'eqref #f (list (list 'i32.const tag) '(i32.const 0) (list 'struct.new T-IMM))))

(define *global-vars* '())   ; (sym . globalidx) of the program's variables
(define (global-of sym)
  (let ((g (assq sym *global-vars*)))
    (if g (cdr g)
        (let ((i (new-global! 'eqref #t '((ref.null eq)))))
          (set! *global-vars* (cons (cons sym i) *global-vars*))
          i))))

;;; Constants: symbols, strings and quoted data, made once at start-up
(define *symbol-globals* '())   ; (name-string . global)
(define *const-globals* '())    ; (datum . global), compared with equal? for strings
(define *init-code* '())        ; reversed list of instruction lists

(define (symbol-global sym)
  (let* ((name (symbol->string sym)) (s (assoc name *symbol-globals*)))
    (if s (cdr s)
        (let ((g (new-global! 'eqref #t '((ref.null eq)))))
          (set! *symbol-globals* (cons (cons name g) *symbol-globals*))
          (set! *init-code*
                (cons (append (list (list 'ref.null (vector-ref *clo-types* 1)))
                              (string-code name)
                              (list (list 'struct.new T-SYM)
                                    (list 'call (known-func '%intern!))
                                    (list 'global.set g)))
                      *init-code*))
          g))))

(define (string-code s)
  "Instructions making a new string with the text of S: (ref $Str)."
  (let* ((codes (map char->integer (string->list s))) (n (length codes)))
    (if (<= n 5000)
        (append (map (lambda (c) (list 'i32.const c)) codes)
                (list (list 'array.new_fixed T-CODES n) (list 'struct.new T-STR)))
        ;; long text: a new array, filled a code at a time
        (let ((tmp (new-init-local! (list 'ref 'null T-CODES))))
          (append (list '(i32.const 0) (list 'i32.const n) (list 'array.new T-CODES) (list 'local.set tmp))
                  (let loop ((i 0) (cs codes) (acc '()))
                    (if (null? cs) (reverse acc)
                        (loop (+ i 1) (cdr cs)
                              (append (reverse (list (list 'local.get tmp) (list 'i32.const i)
                                                     (list 'i32.const (car cs)) (list 'array.set T-CODES)))
                                      acc))))
                  (list (list 'local.get tmp) '(ref.as_non_null) (list 'struct.new T-STR)))))))

(define *init-locals* '())
(define (new-init-local! type)
  (set! *init-locals* (append *init-locals* (list type)))
  (- (length *init-locals*) 1))

(define (const-code x)
  "Instructions pushing the constant X."
  (cond ((and (integer? x) (exact? x) (>= x -1073741824) (< x 1073741824))
         (list (list 'i32.const x) 'ref.i31))
        ((and (integer? x) (exact? x)) (list (list 'i64.const x) (list 'struct.new T-INT)))
        ((number? x) (list (list 'f64.const (exact->inexact x)) (list 'struct.new T-FLO)))
        ((eq? x #t) (list (list 'global.get G-TRUE)))
        ((eq? x #f) (list (list 'global.get G-FALSE)))
        ((null? x) (list (list 'global.get G-NIL)))
        ((char? x) (list (list 'i32.const (char->integer x)) (list 'call (helper '$char))))
        ((symbol? x) (list (list 'global.get (symbol-global x))))
        ((or (string? x) (pair? x) (vector? x))
         (let ((c (assoc x *const-globals*)))
           (if c (list (list 'global.get (cdr c)))
               (let* ((build (datum-code x))
                      (g (new-global! 'eqref #t '((ref.null eq)))))
                 (set! *const-globals* (cons (cons x g) *const-globals*))
                 (set! *init-code* (cons (append build (list (list 'global.set g))) *init-code*))
                 (list (list 'global.get g))))))
        (else (error "Schemer: cannot compile the constant" x))))

(define (datum-code x)
  (cond ((string? x) (string-code x))
        ((pair? x) (append (datum-code (car x)) (datum-code (cdr x)) (list (list 'struct.new T-PAIR))))
        ((vector? x) (let ((items (vector->list x)))
                       (append (apply append (map datum-code items))
                               (list (list 'array.new_fixed T-VEC (length items))))))
        (else (const-code x))))

;;; ------------------------------------------------------------------
;;; Procedures known at compile time
;;; ------------------------------------------------------------------
;;; A top-level (define (f ...) ...) never assigned elsewhere, and a local
;;; procedure bound by let or letrec and never assigned, are called
;;; directly (call $f), not through their closure.

(define *known-globals* '())   ; (sym funcidx arity)
(define (known-func sym)
  (let ((k (assq sym *known-globals*)))
    (if k (cadr k) (error "Schemer: the library lacks" sym))))

(define (fixed-lambda? e)
  (and (pair? e) (eq? (car e) 'lambda) (not (caddr e)) (<= (length (cadr e)) *max-args*)))

;;; known local procedures: var -> (funcidx . arity)
(define *known-locals* '())
(define (known-local v) (let ((k (assq v *known-locals*))) (and k (cdr k))))

;;; ------------------------------------------------------------------
;;; Free variables
;;; ------------------------------------------------------------------

(define (adjoin v set) (if (memq v set) set (cons v set)))

(define (free-vars e bound acc)
  (case (car e)
    ((const gref) acc)
    ((lref) (if (memq (cadr e) bound) acc (adjoin (cadr e) acc)))
    ((lset) (free-vars (caddr e) bound (if (memq (cadr e) bound) acc (adjoin (cadr e) acc))))
    ((gset gdef) (free-vars (caddr e) bound acc))
    ((if) (free-vars (cadddr e) bound (free-vars (caddr e) bound (free-vars (cadr e) bound acc))))
    ((seq) (fold-free (cdr e) bound acc))
    ((call) (fold-free (cdr e) bound acc))
    ((prim) (fold-free (cddr e) bound acc))
    ((lambda) (free-vars (cadddr e) (append (cadr e) (if (caddr e) (list (caddr e)) '()) bound) acc))
    ((let) (free-vars (caddr e) (append (map car (cadr e)) bound)
                      (fold-free (map cadr (cadr e)) bound acc)))
    ((letrec) (let ((b2 (append (map car (cadr e)) bound)))
                (free-vars (caddr e) b2 (fold-free (map cadr (cadr e)) b2 acc))))
    (else (error "Schemer: unknown form" e))))

(define (fold-free es bound acc)
  (if (null? es) acc (fold-free (cdr es) bound (free-vars (car es) bound acc))))

;;; ------------------------------------------------------------------
;;; Function context
;;; ------------------------------------------------------------------
;;; #(nparams extra-locals locations env-local)
;;; location of a var: (local i boxed?) or (env i boxed?)

(define (make-fctx nparams) (vector nparams '() '() #f #f #f))
;;; slot 3: the local holding the environment; slot 4: the function's own
;;; index (fixed arity only); slot 5: #t when a self tail call became a loop
(define (fctx-new-local! f type)
  (vector-set! f 1 (append (vector-ref f 1) (list type)))
  (+ (vector-ref f 0) (length (vector-ref f 1)) -1))
(define (fctx-bind! f v loc) (vector-set! f 2 (cons (cons v loc) (vector-ref f 2))))
(define (fctx-loc f v)
  (let ((l (assq v (vector-ref f 2))))
    (if l (cdr l) (error "Schemer: internal: variable without a place" (var-name v)))))

(define (raw-get f v)
  "The value stored for V: the value itself, or its box."
  (let ((loc (fctx-loc f v)))
    (if (eq? (car loc) 'local)
        (list (list 'local.get (cadr loc)))
        (list (list 'local.get (vector-ref f 3)) (list 'i32.const (cadr loc)) (list 'array.get T-VEC)))))

(define (var-get f v)
  (let ((loc (fctx-loc f v)))
    (append (raw-get f v)
            (if (caddr loc) (list (list 'ref.cast 'null T-BOX) (list 'struct.get T-BOX 0)) '()))))

;;; ------------------------------------------------------------------
;;; Expressions
;;; ------------------------------------------------------------------

(define UNSPEC-CODE #f)

(define (gen e f tail)
  "Instructions computing E (one value) in the function context F."
  (case (car e)
    ((const) (const-code (cadr e)))
    ((lref) (var-get f (cadr e)))
    ((gref) (list (list 'global.get (global-of (cadr e)))))
    ((lset) (append (raw-get f (cadr e)) (list (list 'ref.cast 'null T-BOX))
                    (gen (caddr e) f #f) (list (list 'struct.set T-BOX 0))
                    (unspec)))
    ((gset gdef) (append (gen-global-value e f) (list (list 'global.set (global-of (cadr e))))
                         (unspec)))
    ((if) (append (gen-test (cadr e) f)
                  (list '(if eqref)) (gen (caddr e) f tail)
                  (list 'else) (gen (cadddr e) f tail) (list 'end)))
    ((seq) (let loop ((es (cdr e)) (acc '()))
             (if (null? (cdr es))
                 (append acc (gen (car es) f tail))
                 (loop (cdr es) (append acc (gen (car es) f #f) (list 'drop))))))
    ((lambda) (gen-lambda e f #f))
    ((let) (gen-let e f tail))
    ((letrec) (gen-letrec e f tail))
    ((call) (gen-call e f tail))
    ((prim) (gen-prim (cadr e) (cddr e) f tail))
    (else (error "Schemer: unknown form" e))))

(define (unspec) (list (list 'global.get G-UNSPEC)))

(define (gen-global-value e f)
  ;; a known top-level procedure is made with its own function
  (let ((k (and (eq? (car e) 'gdef) (assq (cadr e) *known-globals*))))
    (if k
        (gen-lambda (caddr e) f (cadr k))
        (gen (caddr e) f #f))))

(define (bool-of-i32)
  (list '(if eqref) (list 'global.get G-TRUE) 'else (list 'global.get G-FALSE) 'end))

(define (gen-test e f)
  "Instructions computing E as an i32: 0 when E is #f."
  (if (and (eq? (car e) 'prim) (test-prim? (cadr e)))
      (gen-prim-test (cadr e) (cddr e) f)
      (append (gen e f #f) (list (list 'global.get G-FALSE) 'ref.eq 'i32.eqz))))

;;; let: each variable in a local (boxed when assigned)
(define (gen-let e f tail)
  (let loop ((bs (cadr e)) (code '()))
    (if (null? bs)
        (append code (gen (caddr e) f tail))
        (let* ((v (caar bs)) (init (cadar bs))
               (boxed (var-assigned? v))
               (i (fctx-new-local! f 'eqref)))
          (when (and (not boxed) (fixed-lambda? init))
            (set! *known-locals* (cons (cons v (cons (lambda-func! init) (length (cadr init)))) *known-locals*)))
          (let ((c (append (gen init f #f)
                           (if boxed (list (list 'struct.new T-BOX)) '())
                           (list (list 'local.set i)))))
            (fctx-bind! f v (list 'local i boxed))
            (loop (cdr bs) (append code c)))))))

;;; letrec: procedures made first and tied to each other; anything else boxed
(define (gen-letrec e f tail)
  (let* ((bs (cadr e)) (vars (map car bs)) (inits (map cadr bs)))
    (if (and (every fixed-lambda? inits) (not (any var-assigned? vars)))
        (let ((locals (map (lambda (v) (fctx-new-local! f 'eqref)) vars)))
          (for-each (lambda (v i init)
                      (fctx-bind! f v (list 'local i #f))
                      (set! *known-locals* (cons (cons v (cons (lambda-func! init) (length (cadr init))))
                                                 *known-locals*)))
                    vars locals inits)
          (let* ((make (apply append
                              (map (lambda (init i)
                                     (append (gen-lambda init f #f vars) (list (list 'local.set i))))
                                   inits locals)))
                 ;; fill the environment slots that hold the group's own procedures
                 (tie (apply append
                             (map (lambda (init i)
                                    (let* ((fv (lambda-free init)) (n (length (cadr init)))
                                           (ct (vector-ref *clo-types* n)))
                                      (let loop ((k 0) (fvs fv) (acc '()))
                                        (cond ((null? fvs) acc)
                                              ((memq (car fvs) vars)
                                               (loop (+ k 1) (cdr fvs)
                                                     (append acc
                                                             (list (list 'local.get i) (list 'ref.cast 'null ct)
                                                                   (list 'struct.get ct 2) (list 'i32.const k))
                                                             (raw-get f (car fvs))
                                                             (list (list 'array.set T-VEC)))))
                                              (else (loop (+ k 1) (cdr fvs) acc))))))
                                  inits locals))))
            (append make tie (gen (caddr e) f tail))))
        ;; general case: boxes
        (let ((locals (map (lambda (v) (fctx-new-local! f 'eqref)) vars)))
          (for-each (lambda (v i) (fctx-bind! f v (list 'local i #t))) vars locals)
          (append (apply append (map (lambda (i) (append (unspec) (list (list 'struct.new T-BOX) (list 'local.set i))))
                                     locals))
                  (apply append (map (lambda (i init)
                                       (append (list (list 'local.get i) (list 'ref.cast 'null T-BOX))
                                               (gen init f #f) (list (list 'struct.set T-BOX 0))))
                                     locals inits))
                  (gen (caddr e) f tail))))))

(define (every p l) (or (null? l) (and (p (car l)) (every p (cdr l)))))
(define (any p l) (and (pair? l) (or (p (car l)) (any p (cdr l)))))

;;; ------------------------------------------------------------------
;;; Lambda
;;; ------------------------------------------------------------------
;;; Each lambda node gets its function index once (lambda-func!); its
;;; free variables are computed once (lambda-free).

(define *lambda-info* '())   ; (node funcidx free)
(define (lambda-info node)
  (let ((i (assq node *lambda-info*)))
    (or i (let ((new (list node #f #f)))
            (set! *lambda-info* (cons new *lambda-info*))
            new))))
(define (lambda-variadic? node) (or (caddr node) (> (length (cadr node)) *max-args*)))
(define (lambda-type node)
  (if (lambda-variadic? node) T-FV (vector-ref *fn-types* (length (cadr node)))))
(define (lambda-clo-type node)
  (if (lambda-variadic? node) T-CLOV (vector-ref *clo-types* (length (cadr node)))))
(define (lambda-func! node)
  (let ((i (lambda-info node)))
    (or (cadr i)
        (let ((idx (new-func! (lambda-type node))))
          (set-car! (cdr i) idx)
          (set! *declared* (cons idx *declared*))
          idx))))
(define (lambda-free node)
  (let ((i (lambda-info node)))
    (or (caddr i)
        (let ((fv (reverse (free-vars node '() '()))))
          (set-car! (cddr i) fv)
          fv))))

(define (gen-lambda node f idx . group)
  "Compile NODE into its function; instructions making its closure.
GROUP: variables of a letrec group, whose slots are filled later."
  (let* ((idx (or idx (lambda-func! node)))
         (_ (let ((i (lambda-info node))) (set-car! (cdr i) idx)))
         ;; A singleton letrec already receives its own closure as local 0.
         ;; Capturing that closure in its environment creates an unnecessary
         ;; cycle (closure -> environment -> closure). Wasmtime's DRC cannot
         ;; reclaim such a cycle or any text/bytevectors it captures.
         (self (and (pair? group) (pair? (car group)) (null? (cdar group)) (caar group)))
         (free (if self (filter (lambda (v) (not (eq? v self))) (lambda-free node))
                   (lambda-free node)))
         (req (cadr node)) (rest (caddr node))
         (variadic (lambda-variadic? node))
         (ct (lambda-clo-type node))
         (arity (if variadic (- -1 (length req)) (length req)))
         (g (make-fctx (if variadic 2 (+ 1 (length req)))))
         (env-prologue '())
         (prologue '()))
    (unless variadic (vector-set! g 4 idx))
    (when self
      ;; Keep letrec's environment-slot numbering consistent with the reduced
      ;; capture list, and resolve first-class self references through local 0.
      (set-car! (cddr (lambda-info node)) free)
      (fctx-bind! g self (list 'local 0 #f)))
    ;; the environment
    (when (pair? free)
      (let ((envl (fctx-new-local! g (list 'ref 'null T-VEC))))
        (vector-set! g 3 envl)
        (set! env-prologue (list (list 'local.get 0) (list 'struct.get ct 2) (list 'local.set envl)))
        (let loop ((k 0) (fv free))
          (when (pair? fv)
            (fctx-bind! g (car fv) (list 'env k (caddr (fctx-loc f (car fv)))))
            (loop (+ k 1) (cdr fv))))))
    ;; the parameters
    (if variadic
        (let ((lst 1))
          (for-each (lambda (v)
                      (let ((i (fctx-new-local! g 'eqref)))
                        (set! prologue
                              (append prologue
                                      (list (list 'local.get lst) (list 'ref.cast 'null T-PAIR) (list 'struct.get T-PAIR 0))
                                      (if (var-assigned? v) (list (list 'struct.new T-BOX)) '())
                                      (list (list 'local.set i)
                                            (list 'local.get lst) (list 'ref.cast 'null T-PAIR) (list 'struct.get T-PAIR 1)
                                            (list 'local.set lst))))
                        (fctx-bind! g v (list 'local i (var-assigned? v)))))
                    req)
          (if rest
              (if (var-assigned? rest)
                  (let ((i (fctx-new-local! g 'eqref)))
                    (set! prologue (append prologue (list (list 'local.get lst) (list 'struct.new T-BOX) (list 'local.set i))))
                    (fctx-bind! g rest (list 'local i #t)))
                  (fctx-bind! g rest (list 'local lst #f)))
              ;; more than *max-args* parameters and no rest: nothing may be left
              (set! prologue (append prologue (list (list 'local.get lst) (list 'global.get G-NIL) 'ref.eq 'i32.eqz
                                                    '(if empty) '(i32.const 4) (list 'local.get 0)
                                                    (list 'call (helper '$type-error)) 'end)))))
        (let loop ((k 1) (vs req))
          (when (pair? vs)
            (let ((v (car vs)))
              (if (var-assigned? v)
                  (let ((i (fctx-new-local! g 'eqref)))
                    (set! prologue (append prologue (list (list 'local.get k) (list 'struct.new T-BOX) (list 'local.set i))))
                    (fctx-bind! g v (list 'local i #t)))
                  (fctx-bind! g v (list 'local k #f))))
            (loop (+ k 1) (cdr vs)))))
    (let ((body (gen (cadddr node) g #t)))
      (set-func! idx (vector-ref g 1)
                 (if (vector-ref g 5)
                     ;; self tail calls jump back to the start
                     (append env-prologue (list '(loop eqref))
                             (resolve-self-jumps (append prologue body)) (list 'end))
                     (append env-prologue prologue body))))
    ;; the closure
    (append (list (list 'i32.const arity) (list 'ref.func idx))
            (if (null? free)
                (list (list 'ref.null T-VEC))
                (append (apply append
                               (map (lambda (v)
                                      (if (and (pair? group) (memq v (car group)))
                                          (list '(ref.null eq))
                                          (raw-get f v)))
                                    free))
                        (list (list 'array.new_fixed T-VEC (length free)))))
            (list (list 'struct.new ct)))))

;;; Each tail call (a loop turns by tail calls) burns one unit of fuel;
;;; with none left, $poll asks the host, which may stop the program.  A
;;; recursion that never ends fills the stack and stops by itself.
(define (fuel-check)
  (list (list 'global.get G-FUEL) '(i32.const 1) 'i32.sub (list 'global.set G-FUEL)
        (list 'global.get G-FUEL) 'i32.eqz '(if empty) (list 'call (helper '$poll)) 'end))

;;; A self tail call is (br-self); its depth is known once the body is made.
(define (resolve-self-jumps code)
  (let loop ((cs code) (depth 0) (acc '()))
    (if (null? cs) (reverse acc)
        (let ((c (car cs)))
          (cond ((eq? c 'br-self) (loop (cdr cs) depth (cons (list 'br depth) acc)))
                ((eq? c 'end) (loop (cdr cs) (- depth 1) (cons c acc)))
                ((and (pair? c) (memq (car c) '(block loop if))) (loop (cdr cs) (+ depth 1) (cons c acc)))
                (else (loop (cdr cs) depth (cons c acc))))))))

(define (gen-self-jump args f)
  "A tail call of the function being made, to itself: new arguments, then a jump."
  (vector-set! f 5 #t)
  (append (fuel-check)
          (apply append (map (lambda (a) (gen a f #f)) args))
          (let loop ((k (length args)) (acc '()))
            (if (= k 0) (reverse acc) (loop (- k 1) (cons (list 'local.set k) acc))))
          (list 'br-self)))

;;; ------------------------------------------------------------------
;;; Calls
;;; ------------------------------------------------------------------

(define (gen-call e f tail)
  (let* ((fn (cadr e)) (args (cddr e)) (n (length args)))
    (cond
     ;; ((lambda (x ...) body) arg ...) is a let
     ((and (eq? (car fn) 'lambda) (not (caddr fn)) (= (length (cadr fn)) n))
      (gen-let (list 'let (map list (cadr fn) args) (cadddr fn)) f tail))
     ;; a known top-level procedure
     ((and (eq? (car fn) 'gref) (assq (cadr fn) *known-globals*)
           (= (caddr (assq (cadr fn) *known-globals*)) n))
      (let ((k (assq (cadr fn) *known-globals*)))
       (if (and tail (eqv? (vector-ref f 4) (cadr k)))
        (gen-self-jump args f)
        (append (if tail (fuel-check) '())
                (list (list 'ref.null (vector-ref *clo-types* n)))
                (apply append (map (lambda (a) (gen a f #f)) args))
                (list (list (if tail 'return_call 'call) (cadr k)))))))
     ;; a known top-level procedure with a rest list: all arguments in a list
     ((and (eq? (car fn) 'gref) (assq (cadr fn) *known-globals*)
           (< (caddr (assq (cadr fn) *known-globals*)) 0)
           (>= n (- -1 (caddr (assq (cadr fn) *known-globals*)))))
      (append (if tail (fuel-check) '())
              (list (list 'ref.null T-CLOV))
              (apply append (map (lambda (a) (gen a f #f)) args))
              (list (list 'global.get G-NIL))
              (map (lambda (a) (list 'struct.new T-PAIR)) args)
              (list (list (if tail 'return_call 'call) (cadr (assq (cadr fn) *known-globals*))))))
     ;; a known local procedure
     ((and (eq? (car fn) 'lref) (known-local (cadr fn)) (= (cdr (known-local (cadr fn))) n))
      (if (and tail (eqv? (vector-ref f 4) (car (known-local (cadr fn)))))
       (gen-self-jump args f)
       (append (if tail (fuel-check) '())
              (var-get f (cadr fn)) (list (list 'ref.cast 'null (vector-ref *clo-types* n)))
              (apply append (map (lambda (a) (gen a f #f)) args))
              (list (list (if tail 'return_call 'call) (car (known-local (cadr fn))))))))
     (else (gen-unknown-call fn args f tail)))))

(define (gen-unknown-call fn args f tail)
  (if tail
      (append (fuel-check) (gen-unknown-call2 fn args f tail))
      (gen-unknown-call2 fn args f tail)))
(define (gen-unknown-call2 fn args f tail)
  (let* ((n (length args))
         (ft (fctx-new-local! f 'eqref))
         (ats (map (lambda (a) (fctx-new-local! f 'eqref)) args))
         (eval (append (gen fn f #f) (list (list 'local.set ft))
                       (apply append (map (lambda (a t) (append (gen a f #f) (list (list 'local.set t))))
                                          args ats))))
         (arglist (let loop ((ts (reverse ats)) (code (list (list 'global.get G-NIL))))
                    (if (null? ts) code
                        (loop (cdr ts) (append (list (list 'local.get (car ts))) code
                                               (list (list 'struct.new T-PAIR)))))))
         (slow (append (list (list 'local.get ft)) arglist
                       (list (list (if tail 'return_call 'call) (helper '$apply))))))
    (if (> n *max-args*)
        (append eval slow)
        (let* ((ct (vector-ref *clo-types* n)) (ftype (vector-ref *fn-types* n))
               (cl (fctx-new-local! f (list 'ref 'null ct))))
          (append eval
                  (list '(block eqref)
                        (list 'block (list 'ref ct))
                        (list 'local.get ft)
                        (list 'br_on_cast 0 #t 'eq #f ct)
                        'drop)
                  slow
                  (if tail '() (list '(br 1)))
                  (list 'end (list 'local.set cl) (list 'local.get cl))
                  (map (lambda (t) (list 'local.get t)) ats)
                  (list (list 'local.get cl) (list 'struct.get ct 1)
                        (list (if tail 'return_call_ref 'call_ref) ftype)
                        'end))))))

;;; ------------------------------------------------------------------
;;; Primitives
;;; ------------------------------------------------------------------

(define (test-prim? op)
  (memq op '(< > <= >= = null? pair? eq? not zero? boolean? symbol? string? char? vector?
             procedure? fixnum? flonum? %int? %eqv? %record?)))

(define (fixnum-const e)
  (and (eq? (car e) 'const) (integer? (cadr e)) (exact? (cadr e))
       (>= (cadr e) -1073741824) (< (cadr e) 1073741824) (cadr e)))

(define (untag-i31 code) (append code (list (list 'ref.cast 'null 'i31) 'i31.get_s)))

;;; A comparison of two numbers: i32.  Small integers inline.
(define (gen-compare op a b f)
  (let* ((ta (fctx-new-local! f 'eqref)) (tb (fctx-new-local! f 'eqref))
         (ka (fixnum-const a)) (kb (fixnum-const b))
         (i32op (case op ((<) 'i32.lt_s) ((>) 'i32.gt_s) ((<=) 'i32.le_s) ((>=) 'i32.ge_s) ((=) 'i32.eq)))
         (slow (case op
                 ((<) (list (list 'local.get ta) (list 'local.get tb) (list 'call (helper '$num-lt))))
                 ((>) (list (list 'local.get tb) (list 'local.get ta) (list 'call (helper '$num-lt))))
                 ((<=) (list (list 'local.get tb) (list 'local.get ta) (list 'call (helper '$num-lt)) 'i32.eqz))
                 ((>=) (list (list 'local.get ta) (list 'local.get tb) (list 'call (helper '$num-lt)) 'i32.eqz))
                 ((=) (list (list 'local.get ta) (list 'local.get tb) (list 'call (helper '$num-eq)))))))
    (append (gen a f #f) (list (list 'local.set ta))
            (gen b f #f) (list (list 'local.set tb))
            (cond (kb (list (list 'local.get ta) (list 'ref.test 'i31)))
                  (ka (list (list 'local.get tb) (list 'ref.test 'i31)))
                  (else (list (list 'local.get ta) (list 'ref.test 'i31) (list 'local.get tb) (list 'ref.test 'i31) 'i32.and)))
            (list '(if i32))
            (if ka (list (list 'i32.const ka)) (untag-i31 (list (list 'local.get ta))))
            (if kb (list (list 'i32.const kb)) (untag-i31 (list (list 'local.get tb))))
            (list i32op 'else)
            slow
            (list 'end))))

;;; + - * on two numbers.  Small integers inline, with overflow checked.
(define (gen-arith op a b f)
  (let* ((ta (fctx-new-local! f 'eqref)) (tb (fctx-new-local! f 'eqref))
         (r (fctx-new-local! f (if (eq? op '*) 'i64 'i32)))
         (ka (fixnum-const a)) (kb (fixnum-const b))
         (helper-name (case op ((+) '$num-add) ((-) '$num-sub) ((*) '$num-mul)))
         (slow (list (list 'local.get ta) (list 'local.get tb) (list 'call (helper helper-name)))))
    (append (gen a f #f) (list (list 'local.set ta))
            (gen b f #f) (list (list 'local.set tb))
            (cond (kb (list (list 'local.get ta) (list 'ref.test 'i31)))
                  (ka (list (list 'local.get tb) (list 'ref.test 'i31)))
                  (else (list (list 'local.get ta) (list 'ref.test 'i31) (list 'local.get tb) (list 'ref.test 'i31) 'i32.and)))
            (list '(if eqref))
            (if (eq? op '*)
                (append (if ka (list (list 'i64.const ka)) (append (untag-i31 (list (list 'local.get ta))) (list 'i64.extend_i32_s)))
                        (if kb (list (list 'i64.const kb)) (append (untag-i31 (list (list 'local.get tb))) (list 'i64.extend_i32_s)))
                        (list 'i64.mul (list 'local.tee r)
                              '(i64.const 1073741824) 'i64.add '(i64.const 2147483648) 'i64.lt_u))
                (append (if ka (list (list 'i32.const ka)) (untag-i31 (list (list 'local.get ta))))
                        (if kb (list (list 'i32.const kb)) (untag-i31 (list (list 'local.get tb))))
                        (list (if (eq? op '+) 'i32.add 'i32.sub) (list 'local.tee r)
                              '(i32.const 1073741824) 'i32.add '(i32.const 31) 'i32.shr_u 'i32.eqz)))
            (list '(if eqref) (list 'local.get r))
            (if (eq? op '*) (list 'i32.wrap_i64) '())
            (list 'ref.i31 'else)
            slow
            (list 'end 'else)
            slow
            (list 'end))))

(define (gen-fold op args f identity)
  (cond ((null? args) (const-code identity))
        ((null? (cdr args))
         (if (eq? op '-) (gen-arith '- '(const 0) (car args) f) (gen (car args) f #f)))
        (else (let loop ((acc (car args)) (rest (cdr args)))
                ;; left fold, as a nested expression
                (if (null? rest)
                    (gen acc f #f)
                    (loop (list 'prim (list '%arith2 op) acc (car rest)) (cdr rest)))))))

(define (gen-prim-test op args f)
  "Instructions computing the test OP on ARGS as an i32."
  (define (arg i) (gen (list-ref args i) f #f))
  (define (is type) (append (arg 0) (list (list 'ref.test type))))
  (case op
    ((< > <= >= =) (gen-compare op (car args) (cadr args) f))
    ((null?) (append (arg 0) (list (list 'global.get G-NIL) 'ref.eq)))
    ((not) (append (arg 0) (list (list 'global.get G-FALSE) 'ref.eq)))
    ((eq?) (append (arg 0) (arg 1) (list 'ref.eq)))
    ((%eqv?) (append (arg 0) (arg 1) (list (list 'call (helper '$eqv)))))
    ((pair?) (is T-PAIR))
    ((symbol?) (is T-SYM))
    ((string?) (is T-STR))
    ((char?) (is T-CHAR))
    ((vector?) (is T-VEC))
    ((procedure?) (is T-CLO))
    ((fixnum?) (is 'i31))
    ((flonum?) (is T-FLO))
    ((%int?) (is T-INT))
    ((%record?) (is T-REC))
    ((boolean?) (let ((t (fctx-new-local! f 'eqref)))
                  (append (arg 0) (list (list 'local.tee t) (list 'global.get G-TRUE) 'ref.eq
                                        (list 'local.get t) (list 'global.get G-FALSE) 'ref.eq 'i32.or))))
    ((zero?) (gen-compare '= (car args) '(const 0) f))
    (else (error "Schemer: internal: not a test" op))))

(define (gen-prim op args f tail)
  (define (arg i) (gen (list-ref args i) f #f))
  (define (fix i) (untag-i31 (arg i)))
  (cond
   ((test-prim? op) (append (gen-prim-test op args f) (bool-of-i32)))
   ((pair? op) (gen-arith (cadr op) (car args) (cadr args) f))   ; (%arith2 op)
   (else
    (case op
      ((+) (gen-fold '+ args f 0))
      ((*) (gen-fold '* args f 1))
      ((-) (gen-fold '- args f 0))
      ((quotient remainder modulo) (gen-division op args f))
      ((cons) (append (arg 0) (arg 1) (list (list 'struct.new T-PAIR))))
      ((car) (append (arg 0) (list (list 'ref.cast 'null T-PAIR) (list 'struct.get T-PAIR 0))))
      ((cdr) (append (arg 0) (list (list 'ref.cast 'null T-PAIR) (list 'struct.get T-PAIR 1))))
      ((set-car!) (append (arg 0) (list (list 'ref.cast 'null T-PAIR)) (arg 1) (list (list 'struct.set T-PAIR 0)) (unspec)))
      ((set-cdr!) (append (arg 0) (list (list 'ref.cast 'null T-PAIR)) (arg 1) (list (list 'struct.set T-PAIR 1)) (unspec)))
      ((vector-ref) (append (arg 0) (list (list 'ref.cast 'null T-VEC)) (fix 1) (list (list 'array.get T-VEC))))
      ((vector-set!) (append (arg 0) (list (list 'ref.cast 'null T-VEC)) (fix 1) (arg 2) (list (list 'array.set T-VEC)) (unspec)))
      ((vector-length) (append (arg 0) (list (list 'ref.cast 'null T-VEC) 'array.len 'ref.i31)))
      ((%make-vector) (append (arg 1) (fix 0) (list (list 'array.new T-VEC))))
      ((string-length) (append (arg 0) (list (list 'ref.cast 'null T-STR) (list 'struct.get T-STR 0) 'array.len 'ref.i31)))
      ((string-ref) (append (arg 0) (list (list 'ref.cast 'null T-STR) (list 'struct.get T-STR 0)) (fix 1)
                            (list (list 'array.get T-CODES) (list 'call (helper '$char)))))
      ((string-set!) (append (arg 0) (list (list 'ref.cast 'null T-STR) (list 'struct.get T-STR 0)) (fix 1)
                             (arg 2) (list (list 'ref.cast 'null T-CHAR) (list 'struct.get T-CHAR 0) (list 'array.set T-CODES))
                             (unspec)))
      ((%make-string) (append (arg 1) (list (list 'ref.cast 'null T-CHAR) (list 'struct.get T-CHAR 0)) (fix 0)
                              (list (list 'array.new T-CODES) (list 'struct.new T-STR))))
      ((char->integer) (append (arg 0) (list (list 'ref.cast 'null T-CHAR) (list 'struct.get T-CHAR 0) 'ref.i31)))
      ((integer->char) (append (fix 0) (list (list 'call (helper '$char)))))
      ((%make-record) (append (arg 0) (arg 1) (list (list 'ref.cast T-VEC) (list 'struct.new T-REC))))
      ((%record-tag) (append (arg 0) (list (list 'ref.cast 'null T-REC) (list 'struct.get T-REC 0))))
      ((%record-fields) (append (arg 0) (list (list 'ref.cast 'null T-REC) (list 'struct.get T-REC 1))))
      ;; escapes, with WebAssembly exceptions: (%catch thunk tag) runs THUNK;
      ;; (%throw tag value) leaves the %catch of TAG with VALUE;
      ;; (%protect thunk after) runs AFTER however THUNK is left
      ((%catch) (append (arg 0) (arg 1) (list (list 'call (helper '$catch)))))
      ((%throw) (append (arg 0) (arg 1) (list (list 'throw (escape-tag))) (unspec)))
      ((%protect) (append (arg 0) (arg 1) (list (list 'call (helper '$protect)))))
      ((%number-char) (append (arg 0) (list (list 'ref.cast 'null T-CHAR) (list 'struct.get T-CHAR 0) (list 'call F-NUMBER-CHAR)) (unspec)))
      ((%editor) (append (arg 0) (list (list 'call F-EDITOR))))
      ;; the bytes of a memory the host gives (the editor's): (%mem-u8 address)
      ;; bits of two fixnums: the result is a fixnum too
      ((%fxand) (append (fix 0) (fix 1) (list 'i32.and 'ref.i31)))
      ((%fxior) (append (fix 0) (fix 1) (list 'i32.or 'ref.i31)))
      ((%fxxor) (append (fix 0) (fix 1) (list 'i32.xor 'ref.i31)))
      ((%fxsra) (append (fix 0) (fix 1) (list 'i32.shr_s 'ref.i31)))
      ((%mem-u8) (set! *uses-memory* #t) (append (fix 0) (list (list 'i32.load8_u 0 0) 'ref.i31)))
      ((%mem-u8-set!) (set! *uses-memory* #t) (append (fix 0) (fix 1) (list (list 'i32.store8 0 0)) (unspec)))
      ((%file) (append (fix 0) (arg 1) (arg 2) (list (list 'call F-FILE))))
      ((%table) (append (fix 0) (arg 1) (arg 2) (arg 3) (list (list 'call F-TABLE))))
      ((%number-end) (list (list 'call F-NUMBER-END) (list 'struct.new T-FLO)))
      ((%string-copy!)   ; (dst at src start count)
       (append (arg 0) (list (list 'ref.cast 'null T-STR) (list 'struct.get T-STR 0)) (fix 1)
               (arg 2) (list (list 'ref.cast 'null T-STR) (list 'struct.get T-STR 0)) (fix 3) (fix 4)
               (list (list 'array.copy T-CODES T-CODES)) (unspec)))
      ((%vector-copy!)   ; (dst at src start count)
       (append (arg 0) (list (list 'ref.cast 'null T-VEC)) (fix 1) (arg 2) (list (list 'ref.cast 'null T-VEC)) (fix 3) (fix 4)
               (list (list 'array.copy T-VEC T-VEC)) (unspec)))
      ((%symbol-name) (append (arg 0) (list (list 'ref.cast 'null T-SYM) (list 'struct.get T-SYM 0))))
      ((%make-symbol) (append (arg 0) (list (list 'ref.cast T-STR) (list 'struct.new T-SYM))))
      ((%write-char) (append (arg 0) (list (list 'ref.cast 'null T-CHAR) (list 'struct.get T-CHAR 0)
                                           (list 'call F-WRITE-CHAR)) (unspec)))
      ((%write-flonum) (append (arg 0) (list (list 'call (helper '$to-f64)) (list 'call F-WRITE-FLONUM)) (unspec)))
      ((%flonum-char) (append (arg 0) (list (list 'call (helper '$to-f64))) (fix 1)
                              (list (list 'call F-FLONUM-CHAR) 'ref.i31)))
      ((%abort) (append (arg 0) (list (list 'call F-ABORT)) (unspec)))
      ((%now) (list (list 'call F-NOW) (list 'struct.new T-FLO)))
      ((%math) (append (fix 0) (arg 1) (list (list 'call (helper '$to-f64)) (list 'call F-MATH) (list 'struct.new T-FLO))))
      ((%math2) (append (fix 0) (arg 1) (list (list 'call (helper '$to-f64))) (arg 2) (list (list 'call (helper '$to-f64))
                        (list 'call F-MATH2) (list 'struct.new T-FLO))))
      ((%apply) (append (if tail (fuel-check) '()) (arg 0) (arg 1) (list (list (if tail 'return_call 'call) (helper '$apply)))))
      ((%num-add) (append (arg 0) (arg 1) (list (list 'call (helper '$num-add)))))
      ((%num-sub) (append (arg 0) (arg 1) (list (list 'call (helper '$num-sub)))))
      ((%num-mul) (append (arg 0) (arg 1) (list (list 'call (helper '$num-mul)))))
      ((%num-div) (append (arg 0) (arg 1) (list (list 'call (helper '$num-div)))))
      ((%num-lt) (append (arg 0) (arg 1) (list (list 'call (helper '$num-lt))) (bool-of-i32)))
      ((%num-eq) (append (arg 0) (arg 1) (list (list 'call (helper '$num-eq))) (bool-of-i32)))
      ((%to-flonum) (append (arg 0) (list (list 'call (helper '$to-f64)) (list 'struct.new T-FLO))))
      ((%flonum-floor) (append (arg 0) (list (list 'call (helper '$to-f64)) 'f64.floor (list 'struct.new T-FLO))))
      ((%flonum-sqrt) (append (arg 0) (list (list 'call (helper '$to-f64)) 'f64.sqrt (list 'struct.new T-FLO))))
      ((%flonum->fixnum) (append (arg 0) (list (list 'call (helper '$to-f64)) 'i64.trunc_f64_s (list 'call (helper '$from-i64)))))
      ((%unspecified) (unspec))
      ((%eof) (list (list 'global.get G-EOF)))
      (else (error "Schemer: internal: unknown primitive" op))))))

;;; quotient, remainder, modulo of small integers (others: an error)
;;; quotient, remainder, modulo: small integers inline, others by $int-div
(define (gen-division op args f)
  (let ((ta (fctx-new-local! f 'eqref)) (tb (fctx-new-local! f 'eqref))
        (a (fctx-new-local! f 'i32)) (b (fctx-new-local! f 'i32)) (r (fctx-new-local! f 'i32))
        (opcode (case op ((quotient) 0) ((remainder) 1) ((modulo) 2))))
    (append (gen (car args) f #f) (list (list 'local.set ta))
            (gen (cadr args) f #f) (list (list 'local.set tb))
            (list (list 'local.get ta) (list 'ref.test 'i31) (list 'local.get tb) (list 'ref.test 'i31) 'i32.and
                  '(if eqref))
            (untag-i31 (list (list 'local.get ta))) (list (list 'local.set a))
            (untag-i31 (list (list 'local.get tb)))
            (list (list 'local.tee b) 'i32.eqz '(if empty) '(i32.const 3) (list 'local.get ta)
                  (list 'call (helper '$type-error)) 'end)
            (case op
              ((quotient) (list (list 'local.get a) (list 'local.get b) 'i32.div_s
                                'i64.extend_i32_s (list 'call (helper '$from-i64))))
              ((remainder) (list (list 'local.get a) (list 'local.get b) 'i32.rem_s 'ref.i31))
              ((modulo) (list (list 'local.get a) (list 'local.get b) 'i32.rem_s (list 'local.set r)
                              (list 'local.get r) '(i32.const 0) 'i32.ne
                              (list 'local.get r) (list 'local.get b) 'i32.xor '(i32.const 0) 'i32.lt_s 'i32.and
                              '(if i32) (list 'local.get r) (list 'local.get b) 'i32.add 'else (list 'local.get r) 'end
                              'ref.i31)))
            (list 'else (list 'i32.const opcode) (list 'local.get ta) (list 'local.get tb)
                  (list 'call (helper '$int-div)) 'end))))
