;;;; expand.scm -- Schemer: from Scheme to the core language
;;;;
;;;; The derived forms (let, let*, letrec, named let, cond, case, and, or,
;;;; when, unless, do, quasiquote, internal define, time) become the
;;;; core forms below, and every variable is resolved: a local variable
;;;; becomes a record of its own, a free one is global.
;;;;
;;;;   (const v)  (lref var)  (gref sym)  (lset var e)  (gset sym e)
;;;;   (gdef sym e)  (if t c a)  (seq e ...)  (lambda req rest body)
;;;;   (let ((var e) ...) body)  (letrec ((var e) ...) body)
;;;;   (call f arg ...)  (prim op arg ...)

;;; A local variable: #(name id assigned? captured?)
(define *var-counter* 0)
(define (make-var name)
  (set! *var-counter* (+ *var-counter* 1))
  (vector name *var-counter* #f #f))
(define (var-name v) (vector-ref v 0))
(define (var-assigned? v) (vector-ref v 2))
(define (var-assigned! v) (vector-set! v 2 #t))

;;; The primitives the compiler writes inline (compiler.scm); with their
;;; number of arguments, or #f for any.  Used as values, they are the
;;; procedures of the same name in prelude.scm.
(define *primitives*
  '((+ . #f) (- . #f) (* . #f) (< . 2) (> . 2) (<= . 2) (>= . 2) (= . 2)
    (quotient . 2) (remainder . 2) (modulo . 2) (zero? . 1)
    (cons . 2) (car . 1) (cdr . 1) (set-car! . 2) (set-cdr! . 2)
    (null? . 1) (pair? . 1) (eq? . 2) (not . 1) (boolean? . 1) (symbol? . 1)
    (string? . 1) (char? . 1) (vector? . 1) (procedure? . 1) (fixnum? . 1) (flonum? . 1) (%int? . 1)
    (vector-ref . 2) (vector-set! . 3) (vector-length . 1) (%make-vector . 2)
    (string-length . 1) (string-ref . 2) (string-set! . 3) (%make-string . 2)
    (char->integer . 1) (integer->char . 1)
    (%symbol-name . 1) (%make-symbol . 1)
    (%write-char . 1) (%write-flonum . 1) (%flonum-char . 2) (%string-copy! . 5) (%vector-copy! . 5) (%abort . 1) (%now . 0) (%math . 2) (%math2 . 3)
    (%apply . 2) (%num-add . 2) (%num-sub . 2) (%num-mul . 2) (%num-div . 2)
    (%num-lt . 2) (%num-eq . 2) (%to-flonum . 1) (%flonum-floor . 1) (%flonum->fixnum . 1)
    (%flonum-sqrt . 1) (%eqv? . 2) (%unspecified . 0) (%eof . 0)
    (%make-record . 2) (%record? . 1) (%record-tag . 1) (%record-fields . 1)
    (%catch . 2) (%throw . 2) (%protect . 2) (%number-char . 1) (%number-end . 0) (%table . 4) (%file . 3) (%editor . 1)
    (%mem-u8 . 1) (%mem-u8-set! . 2)
    (%fxand . 2) (%fxior . 2) (%fxxor . 2) (%fxsra . 2)))

(define (primitive? sym env)
  (and (symbol? sym) (not (lookup sym env)) (eq? (global-target sym env) (global-name sym))
       (assq (global-name sym) *primitives*)))

(define (cxr? sym)
  ;; c[ad]+r, up to four letters
  (let ((s (symbol->string sym)))
    (and (> (string-length s) 2) (< (string-length s) 7)
         (char=? (string-ref s 0) #\c)
         (char=? (string-ref s (- (string-length s) 1)) #\r)
         (let loop ((i 1))
           (or (= i (- (string-length s) 1))
               (and (memv (string-ref s i) '(#\a #\d)) (loop (+ i 1))))))))

(define (syntax-error msg form) (error (string-append "Schemer: " msg) form))

;;; ------------------------------------------------------------------
;;; Expressions
;;; ------------------------------------------------------------------

(define (sch-expand x env)
  (cond ((symbol? x)
         (let ((b (lookup x env)))
           (cond ((macro-binding? b) (syntax-error "a macro used as a variable" (strip x)))
                 (b (list 'lref b))
                 (else (list 'gref (global-target x env))))))
        ((pair? x) (expand-pair x env))
        ((null? x) (syntax-error "empty combination ()" x))
        (else (list 'const x))))

(define (expand-pair x env)
  (let* ((head (car x)) (args (cdr x))
         (b (and (symbol? head) (lookup head env))))
    (cond
     ((macro-binding? b) (sch-expand (apply-macro (cdr b) x) env))
     ((and (symbol? head) (not b))
        (case (global-name head)
          ((quote) (list 'const (strip (car args))))
          ((quasiquote) (sch-expand (quasi (car args) 1) env))
          ((if) (list 'if (sch-expand (car args) env) (sch-expand (cadr args) env)
                      (if (pair? (cddr args)) (sch-expand (caddr args) env) '(prim %unspecified))))
          ((define define-values define-record-type define-record define-syntax)
           (syntax-error "a definition is allowed only at the top or at the start of a body" (strip x)))
          ((set!) (let ((v (lookup (car args) env)))
                    (cond ((macro-binding? v) (syntax-error "set! of a macro" (strip x)))
                          (v (var-assigned! v) (list 'lset v (sch-expand (cadr args) env)))
                          (else (list 'gset (global-target (car args) env) (sch-expand (cadr args) env))))))
          ((let-syntax letrec-syntax) (expand-let-syntax (car args) (cdr args) env))
          ;; (record-type-descriptor NAME) of a record definition: its type,
          ;; even when NAME was also given to its constructor (Chez)
          ((record-type-descriptor record-constructor-descriptor)
           (let ((type (record-type-variable (car args))))
             (if (eq? (global-name head) 'record-type-descriptor)
                 (sch-expand type env)
                 (sch-expand (list '%rtd-rcd type) env))))
          ((let-values) (sch-expand (expand-let-values (car args) (cdr args)) env))
          ((let*-values) (sch-expand (expand-let*-values (car args) (cdr args)) env))
          ((receive) (sch-expand (list 'call-with-values (list 'lambda '() (cadr args))
                                       (cons 'lambda (cons (car args) (cddr args))))
                                 env))
          ((case-lambda) (sch-expand (expand-case-lambda args) env))
          ((parameterize) (sch-expand (list '%parameterize (cons 'list (map car (car args)))
                                            (cons 'list (map cadr (car args)))
                                            (cons 'lambda (cons '() (cdr args))))
                                      env))
          ((guard) (sch-expand (expand-guard (car args) (cdr args)) env))
          ((cond-expand) (sch-expand (cons 'begin (cond-expand-forms args)) env))
          ((assert) (sch-expand (list 'if (car args) #t (list 'error "assertion failed:" (list 'quote (strip (car args)))))
                                env))
          ((delay-force) (sch-expand (list '%make-lazy-promise (list 'lambda '() (car args))) env))
          ((lambda) (expand-lambda (car args) (cdr args) env))
          ((begin) (if (null? args) '(prim %unspecified)
                       (cons 'seq (map (lambda (e) (sch-expand e env)) args))))
          ((let) (if (and (pair? args) (symbol? (car args)))
                     (expand-named-let (car args) (cadr args) (cddr args) env)
                     (expand-let (car args) (cdr args) env)))
          ((let*) (sch-expand (if (or (null? (car args)) (null? (cdar args)))
                              (cons 'let args)
                              (list 'let (list (caar args)) (cons 'let* (cons (cdar args) (cdr args)))))
                          env))
          ((letrec letrec*) (expand-letrec (car args) (cdr args) env))
          ((cond) (sch-expand (expand-cond args) env))
          ((case) (sch-expand (expand-case args) env))
          ((and) (sch-expand (cond ((null? args) #t)
                               ((null? (cdr args)) (car args))
                               (else (list 'if (car args) (cons 'and (cdr args)) #f)))
                         env))
          ((or) (sch-expand (cond ((null? args) #f)
                              ((null? (cdr args)) (car args))
                              (else (let ((t (gensym-name "or")))
                                      (list 'let (list (list t (car args)))
                                            (list 'if t t (cons 'or (cdr args)))))))
                        env))
          ((when) (sch-expand (list 'if (car args) (cons 'begin (cdr args))) env))
          ((unless) (sch-expand (list 'if (car args) '(begin) (cons 'begin (cdr args))) env))
          ((do) (sch-expand (expand-do args) env))
          ((time) (sch-expand (list '%time-it (list 'lambda '() (car args))) env))
          ((delay) (sch-expand (list '%make-promise (list 'lambda '() (car args))) env))
          (else (expand-application head args env))))
     (else (expand-application head args env)))))

(define *gensym-counter* 0)
(define (gensym-name base)
  (set! *gensym-counter* (+ *gensym-counter* 1))
  (string->symbol (string-append " " base (number->string *gensym-counter*))))

(define (expand-application head args env)
  (cond ((and (primitive? head env)
              (let ((n (cdr (assq (global-name head) *primitives*)))) (or (not n) (= n (length args)))))
         (cons 'prim (cons (global-name head) (map (lambda (e) (sch-expand e env)) args))))
        ((and (symbol? head) (not (lookup head env)) (cxr? (global-name head)) (= (length args) 1))
         ;; cadr -> (car (cdr x))
         (let* ((s (symbol->string (global-name head))) (n (string-length s)))
           (let loop ((i (- n 2)) (e (sch-expand (car args) env)))
             (if (= i 0) e
                 (loop (- i 1) (list 'prim (if (char=? (string-ref s i) #\a) 'car 'cdr) e))))))
        (else (cons 'call (cons (sch-expand head env) (map (lambda (e) (sch-expand e env)) args))))))

;;; (lambda (a b . c) body ...)
(define (expand-lambda params body env)
  (let loop ((p params) (req '()))
    (cond ((null? p) (make-lambda (reverse req) #f body env))
          ((symbol? p) (make-lambda (reverse req) p body env))
          (else (loop (cdr p) (cons (car p) req))))))

(define (make-lambda req rest body env)
  (let* ((rvars (map make-var req))
         (restvar (and rest (make-var rest)))
         (env2 (append (map cons req rvars)
                       (if rest (list (cons rest restvar)) '())
                       env)))
    (list 'lambda rvars restvar (expand-body body env2))))

;;; A body: internal definitions first (letrec*), then expressions
(define (expand-body body env)
  (let* ((s (scan-definitions body env)) (defs (car s)) (forms (cadr s)) (env (caddr s)))
    (if (null? defs)
        (expand-sequence forms env)
        (expand-letrec defs forms env))))

(define (expand-sequence forms env)
  (cond ((null? forms) '(prim %unspecified))
        ((null? (cdr forms)) (sch-expand (car forms) env))
        (else (cons 'seq (map (lambda (e) (sch-expand e env)) forms)))))

;;; (define (f . args) body) -> (f (lambda args body)); curried too
(define (normalize-define d)
  (let ((target (cadr d)))
    (if (pair? target)
        (normalize-define (list 'define (car target) (cons 'lambda (cons (cdr target) (cddr d)))))
        (list target (if (pair? (cddr d)) (caddr d) '(begin))))))

(define (expand-let bindings body env)
  (let* ((names (map car bindings))
         (vars (map make-var names))
         (inits (map (lambda (b) (sch-expand (cadr b) env)) bindings))
         (env2 (append (map cons names vars) env)))
    (list 'let (map list vars inits) (expand-body body env2))))

(define (expand-letrec bindings body env)
  (let* ((names (map car bindings))
         (vars (map make-var names))
         (env2 (append (map cons names vars) env))
         (inits (map (lambda (b) (sch-expand (cadr b) env2)) bindings)))
    (list 'letrec (map list vars inits) (expand-body body env2))))

(define (expand-named-let name bindings body env)
  ;; the loop applied to the initial values
  (sch-expand (cons (list 'letrec (list (list name (cons 'lambda (cons (map car bindings) body)))) name)
                (map cadr bindings))
          env))

(define (expand-cond clauses)
  (if (null? clauses) '(begin)
      (let ((c (car clauses)) (rest (cdr clauses)))
        (cond ((kw? (car c) 'else) (cons 'begin (cdr c)))
              ((and (pair? (cdr c)) (kw? (cadr c) '=>))
               (let ((t (gensym-name "cond")))
                 (list 'let (list (list t (car c)))
                       (list 'if t (list (caddr c) t) (expand-cond rest)))))
              ((null? (cdr c))
               (list 'or (car c) (expand-cond rest)))
              (else (list 'if (car c) (cons 'begin (cdr c)) (expand-cond rest)))))))

(define (expand-case args)
  ;; symbols, booleans, () and small integers compare with eq?; others with eqv?
  (define (test t k)
    (list (if (or (symbol? k) (boolean? k) (null? k)
                  (and (integer? k) (exact? k) (< (abs k) 1000000000)))
              'eq? '%eqv?)
          t (list 'quote k)))
  (define (body t c)   ; (k ...) => proc, or the expressions
    (if (and (pair? (cdr c)) (kw? (cadr c) '=>))
        (list (caddr c) t)
        (cons 'begin (cdr c))))
  (let ((t (gensym-name "case")))
    (list 'let (list (list t (car args)))
          (let loop ((clauses (cdr args)))
            (if (null? clauses) '(begin)
                (let ((c (car clauses)))
                  (if (kw? (car c) 'else)
                      (body t c)
                      (list 'if (cons 'or (map (lambda (k) (test t k)) (car c)))
                            (body t c)
                            (loop (cdr clauses))))))))))

;;; (do ((var init step) ...) (test res ...) body ...)
(define (expand-do args)
  (let ((loop (gensym-name "do")) (specs (car args)) (test (cadr args)) (body (cddr args)))
    (list 'let loop (map (lambda (s) (list (car s) (cadr s))) specs)
          (list 'if (car test)
                (cons 'begin (cdr test))
                (cons 'begin (append body
                                     (list (cons loop (map (lambda (s) (if (pair? (cddr s)) (caddr s) (car s)))
                                                           specs)))))))))

(define (quasi x depth)
  (cond ((not (pair? x)) (if (vector? x)
                             (list 'list->vector (quasi (vector->list x) depth))
                             (list 'quote x)))
        ((kw? (car x) 'unquote)
         (if (= depth 1) (cadr x) (list 'list ''unquote (quasi (cadr x) (- depth 1)))))
        ((kw? (car x) 'quasiquote)
         (list 'list ''quasiquote (quasi (cadr x) (+ depth 1))))
        ((and (pair? (car x)) (kw? (caar x) 'unquote-splicing) (= depth 1))
         (list 'append (cadar x) (quasi (cdr x) depth)))
        (else (list 'cons (quasi (car x) depth) (quasi (cdr x) depth)))))

;;; ------------------------------------------------------------------
;;; Macros: syntax-rules, hygienic by renaming
;;; ------------------------------------------------------------------
;;; A symbol a template brings in is renamed to an alias, fresh at each
;;; use of the macro.  An alias bound by the expansion (a let or lambda
;;; variable) is a variable of its own; a free alias means what its
;;; symbol means where the macro was defined.  So a macro's temporaries
;;; cannot capture the user's variables, and a user's variable cannot
;;; capture the macro's free names.
;;;
;;; An environment maps a symbol to a variable (a vector, make-var) or to
;;; (macro . #(literals ellipsis rules env)).

(define *macros* '())            ; global: (symbol . #(literals ellipsis rules env))
(define *aliases* (table))       ; alias -> (symbol . environment of the macro)
(define *alias-counter* 0)

(define (make-alias sym env)
  (set! *alias-counter* (+ *alias-counter* 1))
  (let ((a (string->symbol (string-append (symbol->string sym) "\x2032;" (number->string *alias-counter*)))))
    (put! *aliases* a (cons sym env))
    a))
(define (alias-info s) (and (symbol? s) (get *aliases* s #f)))

;;; The symbol an alias stands for (a symbol stands for itself)
(define (global-name s) (let ((i (alias-info s))) (if i (global-name (car i)) s)))

;;; Quoted data lose their aliases
(define (strip x)
  (cond ((symbol? x) (global-name x))
        ((pair? x) (cons (strip (car x)) (strip (cdr x))))
        ((vector? x) (list->vector (map strip (vector->list x))))
        (else x)))

;;; The binding of SYM in ENV: a variable, (macro . m), or #f (global)
(define (lookup sym env)
  (let ((b (assq sym env)))
    (if b (cdr b)
        (let ((i (alias-info sym)))
          (if i (lookup (car i) (cdr i))
              (let ((m (assq (map-apply (env-map env) sym) *macros*)))
                (and m (cons 'macro (cdr m)))))))))

;;; ------------------------------------------------------------------
;;; Libraries and modules: which global a top-level name means
;;; ------------------------------------------------------------------
;;; A library's definitions are globals of their own, LIBRARY::NAME; a
;;; name a library or a program imports means the global of the library
;;; that exports it.  A map is a procedure: name -> global, or #f for the
;;; name itself (the library's, prelude.scm's).  The map of the library or
;;; program being expanded is *gmap*; a macro's environment keeps the map
;;; of the library that defined it, so its templates mean its globals.

(define *gmap* #f)
(define (map-apply m sym) (or (and m (m sym)) sym))
(define (env-map env) (let ((e (assq '%gmap% env))) (if e (cdr e) *gmap*)))
(define (global-target s env)
  "The global variable that the free symbol S means."
  (let loop ((s s) (m (env-map env)))
    (let ((i (alias-info s)))
      (if i
          (loop (car i) (let ((e (assq '%gmap% (cdr i)))) (if e (cdr e) m)))
          (map-apply m s)))))
(define (toplevel-env) (if *gmap* (list (cons '%gmap% *gmap*)) '()))

(define (macro-binding? b) (and (pair? b) (eq? (car b) 'macro)))

;;; SYM, unbound in ENV, is the keyword KEY (else, =>, define ...)
(define (keyword? sym env key)
  (and (symbol? sym) (not (lookup sym env)) (eq? (global-name sym) key)))
(define (kw? sym key) (and (symbol? sym) (eq? (global-name sym) key)))

;;; (syntax-rules (literal ...) (pattern template) ...), or with an
;;; ellipsis of its own: (syntax-rules ellipsis (literal ...) rule ...)
(define (make-syntax-rules spec env)
  (if (not (and (pair? spec) (kw? (car spec) 'syntax-rules)))
      ;; any other transformer: a procedure of the form, run at expansion
      ;; time by the meta-evaluator (syntax-case, below)
      (vector *procedural-macro* (meta-eval spec '()) #f env)
      (let* ((custom (symbol? (cadr spec)))
             (ellipsis (if custom (cadr spec) '...))
             (literals (if custom (caddr spec) (cadr spec)))
             (rules (if custom (cdddr spec) (cddr spec))))
        (vector literals ellipsis rules env))))

(define *seq-tag* (list 'seq))   ; marks the values of a pattern variable under an ellipsis
(define (seq? x) (and (pair? x) (eq? (car x) *seq-tag*)))

(define (apply-macro m form)
  (if (eq? (vector-ref m 0) *procedural-macro*)
      (apply-procedural-macro m form)
      (apply-syntax-rules m form)))
(define (apply-syntax-rules m form)
  (let ((literals (vector-ref m 0)) (ell (vector-ref m 1)) (env (vector-ref m 3)))
    (let loop ((rules (vector-ref m 2)))
      (if (null? rules)
          (syntax-error "no syntax-rules pattern matches" (strip form))
          (let ((b (sr-match (cdar (car rules)) (cdr form) literals ell (list (cons *seq-tag* #t)))))
            (if b
                (sr-expand (cadr (car rules)) b ell env (list '()))
                (loop (cdr rules))))))))

(define (proper-length l) (let loop ((l l) (n 0)) (if (pair? l) (loop (cdr l) (+ n 1)) n)))

;;; Bindings of the pattern variables, or #f
(define (sr-match pat form lits ell b)
  (cond ((not b) #f)
        ((symbol? pat)
         (cond ((memq pat lits) (and (symbol? form) (eq? (global-name form) (global-name pat)) b))
               ((eq? (global-name pat) '_) b)
               (else (cons (cons pat form) b))))
        ((and (pair? pat) (pair? (cdr pat)) (eq? (cadr pat) ell))
         (let* ((tail (cddr pat))
                (n (- (proper-length form) (proper-length tail))))
           (and (>= n 0)
                (let collect ((f form) (k n) (items '()))
                  (if (> k 0)
                      (collect (cdr f) (- k 1) (cons (car f) items))
                      (let ((ms (map (lambda (x) (sr-match (car pat) x lits ell (list (cons *seq-tag* #t))))
                                     (reverse items))))
                        (and (not (memq #f ms))
                             (sr-match tail f lits ell
                                       (append (map (lambda (v)
                                                      (cons v (cons *seq-tag*
                                                                    (map (lambda (m) (cdr (assq v m))) ms))))
                                                    (pattern-vars (car pat) lits ell))
                                               b)))))))))
        ((pair? pat)
         (and (pair? form)
              (sr-match (cdr pat) (cdr form) lits ell (sr-match (car pat) (car form) lits ell b))))
        ((null? pat) (and (null? form) b))
        ((vector? pat) (and (vector? form) (sr-match (vector->list pat) (vector->list form) lits ell b)))
        (else (and (equal? pat form) b))))

(define (pattern-vars pat lits ell)
  (cond ((symbol? pat) (if (or (memq pat lits) (eq? pat ell) (eq? (global-name pat) '_)) '() (list pat)))
        ((pair? pat) (append (pattern-vars (car pat) lits ell) (pattern-vars (cdr pat) lits ell)))
        ((vector? pat) (pattern-vars (vector->list pat) lits ell))
        (else '())))

;;; The template with the bindings; RENAMED: a box of (symbol . alias)
(define (sr-expand t b ell env renamed)
  (cond ((symbol? t)
         (let ((v (assq t b)))
           (cond ((and v (seq? (cdr v))) (syntax-error "pattern variable used without ellipsis" t))
                 (v (cdr v))
                 (else (let ((r (assq t (car renamed))))
                         (if r (cdr r)
                             (let ((a (make-alias t env)))
                               (set-car! renamed (cons (cons t a) (car renamed)))
                               a)))))))
        ((and (pair? t) (eq? (car t) ell) (pair? (cdr t)))   ; (... template): no ellipsis inside
         (sr-expand (cadr t) b (list 'no-ellipsis) env renamed))
        ((and (pair? t) (pair? (cdr t)) (eq? (cadr t) ell))
         (let* ((sub (car t))
                (rest (let skip ((r (cddr t)) (extra 0))   ; t ... ... flattens
                        (if (and (pair? r) (eq? (car r) ell)) (skip (cdr r) (+ extra 1)) (cons extra r))))
                (vars (filter (lambda (v) (let ((x (assq v b))) (and x (seq? (cdr x)))))
                              (template-symbols sub)))
                (items (if (null? vars)
                           (syntax-error "no pattern variable under the ellipsis" (strip t))
                           ;; sub ... ... : each element is itself (sub ...), spliced
                           (let ((inner (let more ((k (car rest)) (t sub)) (if (= k 0) t (more (- k 1) (list t ell))))))
                             (let each ((seqs (map (lambda (v) (cddr (assq v b))) vars)) (acc '()))
                               (if (memq '() seqs)
                                   (reverse acc)
                                   (each (map cdr seqs)
                                         (cons (sr-expand inner (append (map (lambda (v s) (cons v (car s))) vars seqs) b)
                                                          ell env renamed)
                                               acc)))))))
                (items (let flat ((k (car rest)) (items items))
                         (if (= k 0) items (flat (- k 1) (apply append items))))))
           (append items (sr-expand (cdr rest) b ell env renamed))))
        ((pair? t) (cons (sr-expand (car t) b ell env renamed) (sr-expand (cdr t) b ell env renamed)))
        ((vector? t) (list->vector (sr-expand (vector->list t) b ell env renamed)))
        (else t)))

(define (template-symbols t)
  (cond ((symbol? t) (list t))
        ((pair? t) (append (template-symbols (car t)) (template-symbols (cdr t))))
        ((vector? t) (template-symbols (vector->list t)))
        (else '())))

;;; (let-syntax ((name transformer) ...) body ...); letrec-syntax too
(define (expand-let-syntax bindings body env)
  (let* ((ms (map (lambda (b) (make-syntax-rules (cadr b) env)) bindings))
         (env2 (append (map (lambda (b m) (cons (car b) (cons 'macro m))) bindings ms) env)))
    (for-each (lambda (m) (vector-set! m 3 env2)) ms)
    (expand-body body env2)))

;;; ------------------------------------------------------------------
;;; syntax-case: procedural macros, as R6RS and Chez Scheme have them
;;; ------------------------------------------------------------------
;;; A transformer that is not syntax-rules is an expression giving a
;;; procedure of the form, as (lambda (x) (syntax-case x () ...)).  It runs
;;; while the program is expanded, so the expander evaluates it itself:
;;; the meta-evaluator below, a small Scheme interpreter (the compiler may
;;; itself be compiled, without an eval).  Its globals are *meta-globals*,
;;; the standard procedures and the syntax procedures, and what
;;; (meta define ...) adds.
;;;
;;; Syntax objects are the forms themselves: identifiers are symbols, and
;;; the hygiene is syntax-rules': a symbol a template brings in becomes an
;;; alias (make-alias) that means what it meant where the macro was defined.
;;; Pattern variables are those of syntax-rules (sr-match, sr-expand).

(define *procedural-macro* (list 'procedural-macro))
(define *syntax-renamed* (list '()))   ; this expansion's renamed symbols (sr-expand)
(define *syntax-env* '())              ; the environment of the macro being applied

(define (apply-procedural-macro m form)
  (let ((renamed *syntax-renamed*) (env *syntax-env*))
    (set! *syntax-renamed* (list '()))
    (set! *syntax-env* (vector-ref m 3))
    (let ((out ((vector-ref m 1) form)))
      (set! *syntax-renamed* renamed)
      (set! *syntax-env* env)
      out)))

;;; The meta-evaluator.  ENV: an alist of (symbol . cell); a cell is
;;; #(value v) for a variable, #(pattern b) for a pattern variable.
(define (meta-cell kind v) (vector kind v))
(define (meta-lookup sym env)
  (let ((c (assq sym env)))
    (cond (c (let ((cell (cdr c)))
               (if (eq? (vector-ref cell 0) 'pattern)
                   (syntax-error "a pattern variable outside a syntax template" (strip sym))
                   (vector-ref cell 1))))
          ((assq (global-name sym) *meta-globals*) => cdr)
          (else (syntax-error "unbound variable in a transformer" (strip sym))))))
(define (meta-set! sym v env)
  (let ((c (assq sym env)))
    (cond (c (vector-set! (cdr c) 1 v))
          ((assq (global-name sym) *meta-globals*) => (lambda (g) (set-cdr! g v)))
          (else (syntax-error "set! of an unbound variable in a transformer" (strip sym))))))

(define (meta-bind formals args env)
  (cond ((null? formals)
         (if (null? args) env (syntax-error "too many arguments to a transformer procedure" (strip args))))
        ((symbol? formals) (cons (cons formals (meta-cell 'value args)) env))
        ((null? args) (syntax-error "too few arguments to a transformer procedure" (strip formals)))
        (else (meta-bind (cdr formals) (cdr args) (cons (cons (car formals) (meta-cell 'value (car args))) env)))))

(define (meta-body forms env)
  "Internal definitions first (letrec*), then the expressions."
  (let loop ((fs forms) (env env) (defs '()))
    (if (and (pair? fs) (pair? (car fs)) (symbol? (caar fs)) (not (assq (caar fs) env))
             (kw? (caar fs) 'define))
        (let ((d (normalize-define (car fs))))
          (loop (cdr fs) (cons (cons (car d) (meta-cell 'value #f)) env) (cons d defs)))
        (begin
          (for-each (lambda (d) (meta-set! (car d) (meta-eval (cadr d) env) env)) (reverse defs))
          (let seq ((fs fs) (v #f))
            (if (null? fs) v (seq (cdr fs) (meta-eval (car fs) env))))))))

(define (meta-special? x env)
  (and (pair? x) (symbol? (car x)) (not (assq (car x) env))))

(define (meta-eval x env)
  (cond
   ((symbol? x) (meta-lookup x env))
   ((not (pair? x)) x)
   ((meta-special? x env)
    (let ((head (global-name (car x))) (args (cdr x)))
      (case head
        ((quote) (strip (car args)))
        ((quasiquote) (meta-eval (quasi (car args) 1) env))
        ((if) (if (meta-eval (car args) env)
                  (meta-eval (cadr args) env)
                  (if (pair? (cddr args)) (meta-eval (caddr args) env) #f)))
        ((set!) (meta-set! (car args) (meta-eval (cadr args) env) env))
        ((lambda) (let ((formals (car args)) (body (cdr args)))
                    (lambda vals (meta-body body (meta-bind formals vals env)))))
        ((begin) (meta-body args env))
        ((let) (if (and (pair? args) (symbol? (car args)))
                   ;; named let
                   (let* ((name (car args)) (bs (cadr args))
                          (env2 (cons (cons name (meta-cell 'value #f)) env))
                          (proc (meta-eval (cons 'lambda (cons (map car bs) (cddr args))) env2)))
                     (meta-set! name proc env2)
                     (apply proc (map (lambda (b) (meta-eval (cadr b) env)) bs)))
                   (meta-body (cdr args)
                              (append (map (lambda (b) (cons (car b) (meta-cell 'value (meta-eval (cadr b) env))))
                                           (car args))
                                      env))))
        ((let*) (let loop ((bs (car args)) (env env))
                  (if (null? bs) (meta-body (cdr args) env)
                      (loop (cdr bs) (cons (cons (caar bs) (meta-cell 'value (meta-eval (cadar bs) env))) env)))))
        ((letrec letrec*)
         (let ((env2 (append (map (lambda (b) (cons (car b) (meta-cell 'value #f))) (car args)) env)))
           (for-each (lambda (b) (meta-set! (car b) (meta-eval (cadr b) env2) env2)) (car args))
           (meta-body (cdr args) env2)))
        ((and) (let loop ((es args) (v #t))
                 (cond ((null? es) v) ((meta-eval (car es) env) => (lambda (v) (loop (cdr es) v))) (else #f))))
        ((or) (let loop ((es args))
                (if (null? es) #f (or (meta-eval (car es) env) (loop (cdr es))))))
        ((when) (if (meta-eval (car args) env) (meta-body (cdr args) env) #f))
        ((unless) (if (meta-eval (car args) env) #f (meta-body (cdr args) env)))
        ((cond) (let loop ((cs args))
                  (cond ((null? cs) #f)
                        ((kw? (caar cs) 'else) (meta-body (cdar cs) env))
                        (else (let ((v (meta-eval (caar cs) env)))
                                (cond ((not v) (loop (cdr cs)))
                                      ((null? (cdar cs)) v)
                                      ((kw? (cadar cs) '=>) ((meta-eval (caddar cs) env) v))
                                      (else (meta-body (cdar cs) env))))))))
        ((case) (let ((v (meta-eval (car args) env)))
                  (let loop ((cs (cdr args)))
                    (cond ((null? cs) #f)
                          ((or (kw? (caar cs) 'else) (memv v (strip (caar cs)))) (meta-body (cdar cs) env))
                          (else (loop (cdr cs)))))))
        ((do) (let* ((specs (car args)) (test (cadr args)) (body (cddr args))
                     (env2 (append (map (lambda (s) (cons (car s) (meta-cell 'value (meta-eval (cadr s) env)))) specs) env)))
                (let loop ()
                  (if (meta-eval (car test) env2)
                      (meta-body (cdr test) env2)
                      (begin
                        (meta-body body env2)
                        (let ((news (map (lambda (s) (if (pair? (cddr s)) (meta-eval (caddr s) env2) (meta-lookup (car s) env2)))
                                         specs)))
                          (for-each (lambda (s v) (meta-set! (car s) v env2)) specs news))
                        (loop))))))
        ((define) (syntax-error "a definition is allowed only at the start of a body" (strip x)))
        ((syntax-case) (meta-syntax-case (meta-eval (car args) env) (cadr args) (cddr args) env))
        ((syntax) (meta-syntax (car args) env))
        ((quasisyntax) (meta-quasisyntax (car args) env))
        ((with-syntax) (meta-with-syntax (car args) (cdr args) env))
        (else
         (let ((m (lookup (car x) '())))
           (if (macro-binding? m)
               (meta-eval (apply-macro (cdr m) x) env)     ; a macro used in a transformer
               (meta-apply x env)))))))
   (else (meta-apply x env))))

(define (meta-apply x env)
  (let ((f (meta-eval (car x) env)) (vals (map (lambda (a) (meta-eval a env)) (cdr x))))
    (if (procedure? f) (apply f vals) (syntax-error "not a procedure, in a transformer" (strip (car x))))))

;;; (syntax-case e (literal ...) (pattern [fender] output) ...)
(define (meta-syntax-case v literals clauses env)
  (let loop ((cs clauses))
    (if (null? cs)
        (syntax-error "invalid syntax" (strip v))
        (let* ((c (car cs))
               (b (sr-match (car c) v literals '... (list (cons *seq-tag* #t)))))
          (if (not b)
              (loop (cdr cs))
              (let ((env2 (meta-pattern-env b env)))
                (if (and (pair? (cddr c)) (not (meta-eval (cadr c) env2)))
                    (loop (cdr cs))
                    (meta-eval (if (pair? (cddr c)) (caddr c) (cadr c)) env2))))))))
(define (meta-pattern-env b env)
  (append (map (lambda (pv) (cons (car pv) (meta-cell 'pattern (cdr pv))))
               (filter (lambda (pv) (not (eq? (car pv) *seq-tag*))) b))
          env))
(define (meta-pattern-bindings env)
  "The pattern variables in ENV, as sr-expand wants them."
  (let loop ((env env) (b '()))
    (cond ((null? env) (cons (cons *seq-tag* #t) (reverse b)))
          ((and (vector? (cdar env)) (eq? (vector-ref (cdar env) 0) 'pattern) (not (assq (caar env) b)))
           (loop (cdr env) (cons (cons (caar env) (vector-ref (cdar env) 1)) b)))
          (else (loop (cdr env) b)))))

;;; (syntax template): pattern variables replaced, other symbols renamed
(define (meta-syntax t env)
  (sr-expand t (meta-pattern-bindings env) '... *syntax-env* *syntax-renamed*))

;;; (quasisyntax template): as syntax, with (unsyntax e) and
;;; (unsyntax-splicing e) computed; each becomes a pattern variable
(define (meta-quasisyntax t env)
  (let* ((extra '())
         (hole (lambda (v seq?)
                 (let ((name (gensym-name "unsyntax")))
                   (set! extra (cons (cons name (if seq? (cons *seq-tag* v) v)) extra))
                   name)))
         (t2 (let walk ((t t))
               (cond ((and (pair? t) (kw? (car t) 'unsyntax) (pair? (cdr t)))
                      (hole (meta-eval (cadr t) env) #f))
                     ((and (pair? t) (pair? (car t)) (kw? (caar t) 'unsyntax-splicing))
                      (let ((name (hole (meta-eval (cadar t) env) #t)))
                        (cons name (cons '... (walk (cdr t))))))
                     ((pair? t) (cons (walk (car t)) (walk (cdr t))))
                     ((vector? t) (list->vector (walk (vector->list t))))
                     (else t)))))
    (sr-expand t2 (append extra (meta-pattern-bindings env)) '... *syntax-env* *syntax-renamed*)))

;;; (with-syntax ((pattern e) ...) body ...)
(define (meta-with-syntax bindings body env)
  (let loop ((bs bindings) (env2 env))
    (if (null? bs)
        (meta-body body env2)
        (let ((b (sr-match (caar bs) (meta-eval (cadar bs) env) '() '... (list (cons *seq-tag* #t)))))
          (if b (loop (cdr bs) (meta-pattern-env b env2))
              (syntax-error "with-syntax: no match" (strip (caar bs))))))))

;;; The syntax procedures
(define (identifier? x) (symbol? x))
(define (bound-identifier=? a b) (eq? a b))
(define (identifier-meaning s)
  (let ((b (lookup s '())))
    (or b (global-target s '()))))
(define (free-identifier=? a b)
  (let ((ma (identifier-meaning a)) (mb (identifier-meaning b)))
    (or (eq? ma mb) (and (pair? ma) (pair? mb) (eq? (cdr ma) (cdr mb))))))
(define (syntax->datum x) (strip x))
(define (datum->syntax id datum)
  "DATUM's symbols as if ID's context had written them."
  (let ((info (alias-info id)) (made '()))
    (if (not info) datum
        (let walk ((d datum))
          (cond ((symbol? d) (let ((m (assq d made)))
                               (if m (cdr m)
                                   (let ((a (make-alias d (cdr info))))
                                     (set! made (cons (cons d a) made))
                                     a))))
                ((pair? d) (cons (walk (car d)) (walk (cdr d))))
                ((vector? d) (list->vector (walk (vector->list d))))
                (else d))))))
(define (generate-temporaries l) (map (lambda (x) (gensym-name "t")) (strip l)))
(define (syntax-violation who msg form . sub)
  (syntax-error (string-append (if who (string-append (if (symbol? who) (symbol->string who) who) ": ") "") msg)
                (strip form)))

(define *meta-globals*
  (list (cons 'car car) (cons 'cdr cdr) (cons 'cons cons) (cons 'list list) (cons 'append append)
        (cons 'reverse reverse) (cons 'length length) (cons 'map map) (cons 'for-each for-each)
        (cons 'apply apply) (cons 'list-ref list-ref) (cons 'list-tail list-tail) (cons 'last-pair last-pair)
        (cons 'caar caar) (cons 'cadr cadr) (cons 'cdar cdar) (cons 'cddr cddr) (cons 'caddr caddr)
        (cons 'cdddr cdddr) (cons 'cadddr cadddr) (cons 'pair? pair?) (cons 'null? null?) (cons 'list? list?)
        (cons 'symbol? symbol?) (cons 'string? string?) (cons 'number? number?) (cons 'integer? integer?)
        (cons 'vector? vector?) (cons 'char? char?) (cons 'boolean? boolean?) (cons 'procedure? procedure?)
        (cons 'eq? eq?) (cons 'eqv? eqv?) (cons 'equal? equal?) (cons 'not not)
        (cons 'memq memq) (cons 'memv memv) (cons 'member member) (cons 'assq assq) (cons 'assv assv) (cons 'assoc assoc)
        (cons 'filter filter) (cons 'vector vector) (cons 'vector-ref vector-ref) (cons 'vector-length vector-length)
        (cons 'vector->list vector->list) (cons 'list->vector list->vector) (cons 'make-vector make-vector)
        (cons '+ +) (cons '- -) (cons '* *) (cons '/ /) (cons '< <) (cons '> >) (cons '<= <=) (cons '>= >=) (cons '= =)
        (cons 'zero? zero?) (cons 'even? even?) (cons 'odd? odd?) (cons 'quotient quotient) (cons 'remainder remainder)
        (cons 'modulo modulo) (cons 'abs abs) (cons 'min min) (cons 'max max) (cons 'expt expt)
        (cons 'number->string number->string) (cons 'string->number string->number)
        (cons 'symbol->string symbol->string) (cons 'string->symbol string->symbol)
        (cons 'string-append string-append) (cons 'substring substring) (cons 'string-length string-length)
        (cons 'string=? string=?) (cons 'string-ref string-ref) (cons 'string string) (cons 'list->string list->string)
        (cons 'string->list string->list) (cons 'char=? char=?)
        (cons 'error syntax-error) (cons 'display display) (cons 'newline newline) (cons 'write write)
        (cons 'identifier? identifier?) (cons 'bound-identifier=? bound-identifier=?)
        (cons 'free-identifier=? free-identifier=?) (cons 'syntax->datum syntax->datum)
        (cons 'datum->syntax datum->syntax) (cons 'generate-temporaries generate-temporaries)
        (cons 'syntax-violation syntax-violation)))

;;; (meta define ...) at the top: a definition for transformers only
(define (meta-define! d)
  (let ((d (normalize-define d)))
    (set! *meta-globals* (cons (cons (global-name (car d)) #f) *meta-globals*))
    (set-cdr! (assq (global-name (car d)) *meta-globals*) (meta-eval (cadr d) '()))))


;;; ------------------------------------------------------------------
;;; Definitions: define, define-values, define-record-type, define-syntax
;;; ------------------------------------------------------------------
;;; A definition becomes a list of (name expression) pairs.

(define (definition-head form env)
  "The kind of definition FORM is, or #f."
  (and (pair? form) (symbol? (car form)) (not (lookup (car form) env))
       (memq (global-name (car form)) '(define define-values define-record-type define-record define-syntax begin cond-expand
                                        define-library library module import include meta))
       (let ((k (global-name (car form)))) (if (eq? k 'define-record) 'define-record-type k))))

(define (expand-define-values formals expr)
  (let* ((names (let loop ((f formals) (acc '()))
                  (cond ((pair? f) (loop (cdr f) (cons (car f) acc)))
                        ((symbol? f) (reverse (cons f acc)))
                        (else (reverse acc)))))
         (temps (map (lambda (n) (gensym-name "v")) names))
         (tformals (let loop ((f formals) (ts temps))
                     (cond ((pair? f) (cons (car ts) (loop (cdr f) (cdr ts))))
                           ((symbol? f) (car ts))
                           (else '())))))
    (append (map (lambda (n) (list n #f)) names)
            (list (list (gensym-name "dv")
                        (list 'call-with-values (list 'lambda '() expr)
                              (list 'lambda tformals
                                    (cons 'begin (map (lambda (n t) (list 'set! n t)) names temps)))))))))

;;; Record definitions, as R7RS, R6RS and Chez Scheme have them.  All make
;;; record-type descriptors (prelude.scm); the R7RS form keeps its own
;;; direct constructor and accessors (fast, no inheritance).
(define (expand-define-record-type spec)
  (cond ((kw? (car spec) 'define-record) (expand-chez-define-record spec))
        ((and (>= (length spec) 4) (or (symbol? (cadddr spec)) (not (cadddr spec))))
         (expand-r7rs-define-record-type spec))
        (else (expand-r6rs-define-record-type spec))))

(define (symbol-append . parts)
  (string->symbol (apply string-append (map (lambda (p) (if (symbol? p) (symbol->string (strip p)) p)) parts))))
(define (field-spec-list fields)
  "(f (mutable f) (immutable f)) -> ((mutable f) ...), as make-record-type-descriptor wants."
  (cons 'list (map (lambda (f) (list 'quote (if (pair? f) (list (strip (car f)) (strip (car (last-pair f)))) (list 'mutable (strip f)))))
                   fields)))

;;; The record types defined so far: their type is also kept in a hidden
;;; variable, since the type's name may be given to its constructor too.
(define *record-names* '())
(define (record-type-variable name)
  (if (and (symbol? name) (memq (global-name name) *record-names*))
      (symbol-append "%record-type:" (global-name name))
      name))
(define (record-type-bindings name expr ctor pred)
  "(hidden expr) and, unless the name is the constructor's or predicate's, (name hidden)."
  (set! *record-names* (cons (global-name name) *record-names*))
  (let ((hidden (record-type-variable name)))
    (cons (list hidden expr)
          (if (memq (global-name name) (map global-name (list ctor pred))) '() (list (list name hidden))))))

;;; R6RS: (define-record-type name-or-(name ctor pred) clause ...)
;;; clauses: (fields f (mutable f [acc mod]) (immutable f [acc])) (parent p)
;;; (protocol e) (sealed #t) (opaque #t) (nongenerative [uid]) (parent-rtd rtd rcd)
(define (expand-r6rs-define-record-type spec)
  (let* ((ns (cadr spec))
         (name (if (pair? ns) (car ns) ns))
         (ctor (if (pair? ns) (cadr ns) (symbol-append "make-" name)))
         (pred (if (pair? ns) (caddr ns) (symbol-append name "?")))
         (clause (lambda (k) (let loop ((cs (cddr spec)))
                               (cond ((null? cs) #f) ((kw? (caar cs) k) (car cs)) (else (loop (cdr cs)))))))
         (fields (let ((c (clause 'fields))) (if c (cdr c) '())))
         (norm (map (lambda (f) (cond ((symbol? f) (list 'immutable f))
                                      ((kw? (car f) 'mutable) f)
                                      ((kw? (car f) 'immutable) f)
                                      (else (syntax-error "a record field" f))))
                    fields))
         (parent (clause 'parent)) (prtd (clause 'parent-rtd))
         (protocol (clause 'protocol)) (sealed (clause 'sealed)) (opaque (clause 'opaque))
         (ng (clause 'nongenerative))
         (uid (and ng (list 'quote (if (pair? (cdr ng)) (strip (cadr ng)) (strip (gensym-name (symbol->string (strip name))))))))
         (rcd (gensym-name "rcd"))
         (T (begin (set! *record-names* (cons (global-name name) *record-names*)) (record-type-variable name))))
    (append
     (record-type-bindings name
                           (list 'make-record-type-descriptor (list 'quote (strip name))
                                 (cond (parent (record-type-variable (cadr parent))) (prtd (cadr prtd)) (else #f))
                                 (or uid #f) (and sealed (cadr sealed)) (and opaque (cadr opaque))
                                 (field-spec-list norm))
                           ctor pred)
     (list (list rcd (list '%set-rtd-rcd! T
                           (list 'make-record-constructor-descriptor T (if prtd (caddr prtd) #f)
                                 (if protocol (cadr protocol) #f))))
           (list ctor (list 'record-constructor rcd))
           (list pred (list 'record-predicate T)))
     (let loop ((fs norm) (k 0) (out '()))
       (if (null? fs) (reverse out)
           (let* ((f (car fs)) (fname (cadr f))
                  (acc (if (pair? (cddr f)) (caddr f) (symbol-append name "-" fname)))
                  (mod (and (kw? (car f) 'mutable)
                            (if (and (pair? (cddr f)) (pair? (cdddr f))) (cadddr f) (symbol-append name "-" fname "-set!"))))
                  (out (cons (list acc (list 'record-accessor T k)) out)))
             (loop (cdr fs) (+ k 1) (if mod (cons (list mod (list 'record-mutator T k)) out) out))))))))

;;; Chez: (define-record name [parent] (field ...) [((field init) ...)] [(option ...)])
;;; field: f, (mutable f), (immutable f); options: (prefix "p") (constructor c) (predicate p)
;;; The constructor takes the parent's fields, then the type's own fields
;;; without an initial value; those with one are computed in order, in the
;;; scope of the fields before them.
(define (expand-chez-define-record spec)
  (let* ((name (cadr spec))
         (rest (cddr spec))
         (parent (and (symbol? (car rest)) (car rest)))
         (rest (if parent (cdr rest) rest))
         (fields (car rest))
         (rest (cdr rest))
         (option? (lambda (l) (and (pair? l) (pair? (car l)) (memq (global-name (caar l)) '(prefix constructor predicate)))))
         (defaults (if (and (pair? rest) (not (option? (car rest)))) (car rest) '()))
         (options (let ((r (if (and (pair? rest) (not (option? (car rest)))) (cdr rest) rest))) (if (pair? r) (car r) '())))
         (option (lambda (k) (let ((o (assq k (map (lambda (o) (cons (global-name (car o)) (cdr o))) options))))
                               (and o (cadr o)))))
         (prefix (or (option 'prefix) (string-append (symbol->string (strip name)) "-")))
         (ctor (or (option 'constructor) (symbol-append "make-" name)))
         (pred (or (option 'predicate) (symbol-append name "?")))
         (fname (lambda (f) (if (pair? f) (car (last-pair f)) f)))
         (mutable? (lambda (f) (not (and (pair? f) (kw? (car f) 'immutable)))))
         (all (append fields (map car defaults)))
         (args (map fname fields))
         (pvals (gensym-name "parent")) (as (gensym-name "args"))
         (P (and parent (record-type-variable parent)))
         (T (begin (set! *record-names* (cons (global-name name) *record-names*)) (record-type-variable name))))
    (append
     (record-type-bindings name
                           (list 'make-record-type-descriptor (list 'quote (strip name)) (or P #f) #f #f #f
                                 (field-spec-list (map (lambda (f) (if (mutable? f) (list 'mutable (fname f)) (list 'immutable (fname f))))
                                                       all)))
                           ctor pred)
     (list (list ctor (list 'lambda as
                            (list '%chez-construct T (length args) as
                                  (list 'lambda (cons pvals args)
                                        (list 'let* (map (lambda (d) (list (car d) (cadr d))) defaults)
                                              (list '%make-record T
                                                    (list 'list->vector
                                                          (list 'append pvals (cons 'list (map fname all))))))))))
           (list pred (list 'record-predicate T)))
     (let loop ((fs all) (k 0) (out '()))
       (if (null? fs) (reverse out)
           (let* ((f (car fs)) (n (fname f))
                  (out (cons (list (symbol-append prefix n) (list 'record-accessor T k)) out)))
             (loop (cdr fs) (+ k 1)
                   (if (mutable? f) (cons (list (symbol-append "set-" prefix n "!") (list 'record-mutator T k)) out) out))))))))

;;; R7RS: (define-record-type name (constructor field ...) predicate (field accessor [modifier]) ...)
(define (expand-r7rs-define-record-type spec)
  (let* ((tname (if (pair? (cadr spec)) (car (cadr spec)) (cadr spec)))
         (ctor (caddr spec)) (pred (cadddr spec)) (fspecs (cdr (cdddr spec)))
         (fields (map (lambda (f) (if (pair? f) (car f) f)) fspecs))
         (index (lambda (f) (let loop ((fs fields) (i 0))
                              (cond ((null? fs) (syntax-error "not a field of the record type" f))
                                    ((eq? (car fs) f) i)
                                    (else (loop (cdr fs) (+ i 1)))))))
         (obj (gensym-name "obj")) (val (gensym-name "val"))
         (check (lambda (who) (list 'if (list '%record-of? obj tname) #f (list '%record-error obj (list 'quote who))))))
    (append
     (list (list tname (list 'make-record-type-descriptor (list 'quote (strip tname)) #f #f #f #f
                             (field-spec-list (map (lambda (f) (list 'mutable f)) fields)))))
     (if (and ctor (not (eq? ctor #t)))
         (let ((cname (if (pair? ctor) (car ctor) ctor))
               (cfields (if (pair? ctor) (cdr ctor) fields)))
           (list (list cname
                       (list 'lambda cfields
                             (list '%make-record tname
                                   (cons 'vector (map (lambda (f) (if (memq f cfields) f #f)) fields)))))))
         '())
     (if pred (list (list pred (list 'lambda (list obj) (list '%record-of? obj tname)))) '())
     (apply append
            (map (lambda (f)
                   (if (not (pair? f)) '()
                       (let ((i (index (car f))))
                         (append
                          (if (pair? (cdr f))
                              (list (list (cadr f)
                                          (list 'lambda (list obj) (check (cadr f))
                                                (list 'vector-ref (list '%record-fields obj) i))))
                              '())
                          (if (and (pair? (cdr f)) (pair? (cddr f)))
                              (list (list (caddr f)
                                          (list 'lambda (list obj val) (check (caddr f))
                                                (list 'vector-set! (list '%record-fields obj) i val))))
                              '())))))
                 fspecs)))))

;;; The definitions at the start of FORMS (macros used there expanded):
;;; (bindings rest-forms env), ENV extended by internal define-syntax.
;;; Expressions between definitions become bindings of unused variables.
(define (scan-definitions forms env)
  (let loop ((fs forms) (defs '()) (pending '()) (env env))
    (if (null? fs)
        (list (reverse defs) (reverse pending) env)
        (let* ((f (car fs)) (kind (definition-head f env)))
          (cond ((and (pair? f) (symbol? (car f)) (macro-binding? (lookup (car f) env)))
                 (loop (cons (apply-macro (cdr (lookup (car f) env)) f) (cdr fs)) defs pending env))
                ((eq? kind 'begin) (loop (append (cdr f) (cdr fs)) defs pending env))
                ((eq? kind 'cond-expand) (loop (append (cond-expand-forms (cdr f)) (cdr fs)) defs pending env))
                ((not kind) (loop (cdr fs) defs (cons f pending) env))
                (else
                 ;; a definition after expressions: they become bindings too
                 (let ((defs (append (map (lambda (e) (list (gensym-name "e") e)) (reverse pending)) defs)))
                   (case kind
                     ((define) (loop (cdr fs) (cons (normalize-define f) defs) '() env))
                     ((define-values) (loop (cdr fs) (append (reverse (expand-define-values (cadr f) (caddr f))) defs) '() env))
                     ((define-record-type) (loop (cdr fs) (append (reverse (expand-define-record-type f)) defs) '() env))
                     ((define-syntax)
                      (let ((m (make-syntax-rules (caddr f) #f)))
                        (let ((env2 (cons (cons (cadr f) (cons 'macro m)) env)))
                          (vector-set! m 3 env2)
                          (loop (cdr fs) defs '() env2))))))))))))

;;; ------------------------------------------------------------------
;;; A program: top-level forms
;;; ------------------------------------------------------------------

(define (expand-toplevel forms)
  "The core forms of the top-level FORMS: (gdef sym e) or expressions."
  (let loop ((fs forms) (acc '()))
    (if (null? fs) (reverse acc)
        (let* ((f (car fs)) (kind (definition-head f '())))
          (cond ((and (pair? f) (symbol? (car f)) (macro-binding? (lookup (car f) '())))
                 (loop (cons (apply-macro (cdr (lookup (car f) '())) f) (cdr fs)) acc))
                ((eq? kind 'begin) (loop (append (cdr f) (cdr fs)) acc))
                ((eq? kind 'cond-expand) (loop (append (cond-expand-forms (cdr f)) (cdr fs)) acc))
                ((eq? kind 'define-syntax)
                 (define-global! (global-name (cadr f)))
                 (set! *macros* (cons (cons (global-target (cadr f) '()) (make-syntax-rules (caddr f) (toplevel-env)))
                                      *macros*))
                 (loop (cdr fs) acc))
                ((memq kind '(define-library library module))
                 (loop (cdr fs) (append (reverse (expand-library f kind)) acc)))
                ((eq? kind 'import) (add-imports! (cdr f)) (loop (cdr fs) acc))
                ((eq? kind 'meta) (meta-define! (cdr f)) (loop (cdr fs) acc))
                ((eq? kind 'include) (loop (append (include-forms (cdr f)) (cdr fs)) acc))
                (kind
                 (let ((ds (case kind
                             ((define) (list (normalize-define f)))
                             ((define-values) (expand-define-values (cadr f) (caddr f)))
                             (else (expand-define-record-type f)))))
                   (for-each (lambda (d) (define-global! (global-name (car d)))) ds)
                   (loop (cdr fs)
                         (append (reverse (map (lambda (d) (list 'gdef (global-target (car d) '()) (sch-expand (cadr d) '())))
                                               ds))
                                 acc))))
                (else (loop (cdr fs) (cons (sch-expand f '()) acc))))))))

;;; ------------------------------------------------------------------
;;; Libraries: R7RS define-library, R6RS and Chez library, Chez module
;;; ------------------------------------------------------------------

(define *libraries* '())      ; (key . ((exported-name . global) ...))
(define *scope* #f)           ; the library or program being expanded: #(prefix defined imports)
(define (scope-defined s) (vector-ref s 1))
(define (new-scope prefix)
  (let ((scope (vector prefix '() '())))
    (set! *gmap* (scope-map scope))
    (set! *scope* scope)
    scope))
(define (scope-map scope)
  (lambda (sym)
    (cond ((memq sym (vector-ref scope 1)) (scope-global scope sym))
          (else (let loop ((ims (vector-ref scope 2)))
                  (if (null? ims) #f
                      (or ((car ims) sym) (loop (cdr ims)))))))))
(define (scope-global scope sym)
  (if (vector-ref scope 0) (string->symbol (string-append (vector-ref scope 0) "::" (symbol->string sym))) sym))
(define (define-global! sym)
  "SYM is defined at the top of the library or program being expanded."
  (when (and *scope* (not (memq sym (vector-ref *scope* 1))))
    (vector-set! *scope* 1 (cons sym (vector-ref *scope* 1)))))
(define (reset-libraries!)
  (set! *libraries* '()) (set! *scope* #f) (set! *gmap* #f) (set! *record-names* '())
  (new-scope #f))

(define (library-key name)
  (cond ((symbol? name) (list 'module (strip name)))
        (else (let loop ((n (strip name)) (out '()))   ; R6RS versions (1 0) are dropped
                (if (or (null? n) (pair? (car n))) (reverse out) (loop (cdr n) (cons (car n) out)))))))
(define (library-prefix key)
  "(my lib) -> \"(my lib)\""
  (let loop ((k key) (out "("))
    (if (null? k) (string-append out ")")
        (loop (cdr k) (string-append out (if (string=? out "(") "" " ")
                                     (let ((x (car k))) (if (symbol? x) (symbol->string x) (number->string x))))))))
(define (builtin-library? key)
  (and (pair? key) (memq (car key) '(scheme srfi rnrs chezscheme schemer))))

;;; An import set: a map of the names it gives
(define (import-set-map set)
  (let ((head (and (pair? set) (symbol? (car set)) (global-name (car set)))))
    (cond ((and (memq head '(only except prefix rename)) (pair? (cdr set)) (pair? (cadr set)))
           (let ((base (import-set-map (cadr set))) (args (map strip (cddr set))))
             (case head
               ((only) (lambda (s) (and (memq s args) (base s))))
               ((except) (lambda (s) (and (not (memq s args)) (base s))))
               ((prefix) (let ((p (symbol->string (car args))))
                           (lambda (s) (let ((n (symbol->string s)))
                                         (and (> (string-length n) (string-length p))
                                              (string=? (substring n 0 (string-length p)) p)
                                              (base (string->symbol (substring n (string-length p) (string-length n)))))))))
               (else (lambda (s) (let ((r (let find ((rs args)) (cond ((null? rs) #f) ((eq? (cadr (car rs)) s) (car rs)) (else (find (cdr rs)))))))
                                   (cond (r (base (car r)))
                                         ((assq s args) #f)   ; renamed away
                                         (else (base s)))))))))
          ((and (memq head '(for library)) (pair? (cdr set))) (import-set-map (cadr set)))
          (else
           (let* ((key (library-key set)) (lib (assoc key *libraries*)))
             (cond (lib (let ((exports (cdr lib))) (lambda (s) (let ((e (assq s exports))) (and e (cdr e))))))
                   ((builtin-library? key) (lambda (s) s))
                   (else (syntax-error "unknown library" set))))))))
(define (import-set-library set)
  "The key of the library an import set takes names from."
  (let ((head (and (pair? set) (symbol? (car set)) (global-name (car set)))))
    (if (and (memq head '(only except prefix rename for library)) (pair? (cdr set)) (pair? (cadr set)))
        (import-set-library (cadr set))
        (library-key set))))
(define (add-imports! sets)
  ;; the built-in libraries give every other name: they are asked last
  (let* ((builtin? (lambda (set) (and (not (assoc (import-set-library set) *libraries*))
                                      (builtin-library? (import-set-library set)))))
         (own (map import-set-map (filter (lambda (set) (not (builtin? set))) sets)))
         (builtin (map import-set-map (filter builtin? sets)))
         (old (vector-ref *scope* 2))
         (old-own (filter (lambda (m) (not (memq m *builtin-maps*))) old))
         (old-builtin (filter (lambda (m) (memq m *builtin-maps*)) old)))
    (set! *builtin-maps* (append builtin *builtin-maps*))
    (vector-set! *scope* 2 (append old-own own old-builtin builtin))))
(define *builtin-maps* '())

;;; (include "file" ...): the forms of the files
(define (include-forms files)
  (apply append (map (lambda (f)
                       (let ((p (open-input-file f)))
                         (let loop ((acc '()))
                           (let ((x (read p)))
                             (if (eof-object? x) (begin (close-input-port p) (reverse acc)) (loop (cons x acc)))))))
                     files)))

;;; (define-library name decl ...), (library name (export ...) (import ...) form ...),
;;; (module [name] (export ...) form ...): the core forms of its definitions;
;;; its exports are kept in *libraries*.  An anonymous module's exports
;;; are imported where it stands.
(define (expand-library f kind)
  (let* ((anonymous (and (eq? kind 'module) (not (symbol? (cadr f)))))
         (key (if anonymous (list 'module (gensym-name "module")) (library-key (cadr f))))
         (decls (cond ((eq? kind 'define-library) (cddr f))
                      (anonymous (cons (cons 'export (cadr f)) (cddr f)))
                      ((eq? kind 'module) (cons (cons 'export (caddr f)) (cdddr f)))
                      (else (cons (caddr f) (cons (cadddr f) (list (cons 'begin (cddddr f))))))))
         (decl? (lambda (d k) (and (pair? d) (kw? (car d) k))))
         ;; export specs: name, (rename a b) as R7RS, (rename (a b) ...) as R6RS
         (exports (apply append
                         (map (lambda (e)
                                (if (and (pair? e) (kw? (car e) 'rename) (pair? (cdr e)) (pair? (cadr e)))
                                    (map (lambda (r) (list 'rename (car r) (cadr r))) (cdr e))
                                    (list e)))
                              (apply append (map cdr (filter (lambda (d) (decl? d 'export)) decls))))))
         (decls (append (filter (lambda (d) (decl? d 'import)) decls)   ; imports first
                        (filter (lambda (d) (not (decl? d 'import))) decls)))
         (body (apply append
                      (map (lambda (d)
                             (cond ((decl? d 'begin) (cdr d))
                                   ((decl? d 'include) (include-forms (cdr d)))
                                   ((decl? d 'import) (list d))
                                   ((decl? d 'export) '())
                                   ((eq? kind 'define-library) (syntax-error "a library declaration" (strip d)))
                                   (else (list d))))
                           decls)))
         (outer-scope *scope*) (outer-map *gmap*)
         (scope (new-scope (library-prefix key)))
         ;; the library's own definitions are known before its body is expanded
         (_ (for-each (lambda (n) (define-global! n)) (defined-names body)))
         (core (expand-toplevel body))
         (exported (map (lambda (e)
                          (let ((internal (if (pair? e) (strip (cadr e)) (strip e)))
                                (external (if (pair? e) (strip (caddr e)) (strip e))))
                            (cons external (map-apply *gmap* internal))))
                        exports)))
    (set! *scope* outer-scope) (set! *gmap* outer-map)
    (set! *libraries* (cons (cons key exported) *libraries*))
    (when anonymous (add-imports! (list key)))
    core))

(define (defined-names forms)
  "The names FORMS define at their top (begin and records included)."
  (apply append
         (map (lambda (f)
                (if (not (and (pair? f) (symbol? (car f)))) '()
                    (case (global-name (car f))
                      ((begin) (defined-names (cdr f)))
                      ((define) (list (global-name (car (normalize-define f)))))
                      ((define-syntax) (list (global-name (cadr f))))
                      ((define-values) (map (lambda (d) (global-name (car d))) (expand-define-values (cadr f) (caddr f))))
                      ((define-record-type define-record) (map (lambda (d) (global-name (car d))) (expand-define-record-type f)))
                      (else '()))))
              forms)))

;;; ------------------------------------------------------------------
;;; More derived forms
;;; ------------------------------------------------------------------

;;; (let-values (((a b . c) expr) ...) body): the values in temporaries first
(define (expand-let-values bindings body)
  (let* ((renames '())
         (rename (lambda (formals)
                   (let loop ((f formals))
                     (cond ((pair? f) (let ((t (gensym-name "lv")))
                                        (set! renames (cons (list (car f) t) renames))
                                        (cons t (loop (cdr f)))))
                           ((symbol? f) (let ((t (gensym-name "lv")))
                                          (set! renames (cons (list f t) renames))
                                          t))
                           (else '())))))
         (tformals (map (lambda (b) (rename (car b))) bindings)))
    (let loop ((bs bindings) (ts tformals))
      (if (null? bs)
          (cons 'let (cons (reverse renames) body))
          (list 'call-with-values (list 'lambda '() (cadar bs))
                (list 'lambda (car ts) (loop (cdr bs) (cdr ts))))))))

(define (expand-let*-values bindings body)
  (if (null? bindings)
      (cons 'let (cons '() body))
      (list 'call-with-values (list 'lambda '() (cadar bindings))
            (list 'lambda (caar bindings) (expand-let*-values (cdr bindings) body)))))

;;; (case-lambda (formals body ...) ...)
(define (expand-case-lambda clauses)
  (let ((args (gensym-name "args")) (n (gensym-name "n")))
    (list 'lambda args
          (list 'let (list (list n (list 'length args)))
                (cons 'cond
                      (append (map (lambda (c)
                                     (list (list (if (list? (car c)) '= '>=) n (proper-length (car c)))
                                           (list 'apply (cons 'lambda c) args)))
                                   clauses)
                              (list (list 'else (list 'error "case-lambda: no clause takes this many arguments:" n)))))))))

;;; (guard (var clause ...) body ...): (%guard thunk handler) of the
;;; prelude; the handler re-raises when no clause applies
(define (expand-guard spec body)
  (let ((clauses (cdr spec)))
    (list '%guard
          (cons 'lambda (cons '() body))
          (list 'lambda (list (car spec))
                (cons 'cond
                      (if (and (pair? clauses) (kw? (car (car (last-pair clauses))) 'else))
                          clauses
                          (append clauses
                                  (list (list 'else (list 'raise-continuable (car spec)))))))))))

;;; (cond-expand (requirement form ...) ...): the forms of the first clause met
(define *features* '(r7rs full-unicode schemer wasm))
(define (feature? req)
  (cond ((symbol? req) (or (kw? req 'else) (memq (global-name req) *features*)))
        ((kw? (car req) 'and) (let loop ((l (cdr req))) (or (null? l) (and (feature? (car l)) (loop (cdr l))))))
        ((kw? (car req) 'or) (let loop ((l (cdr req))) (and (pair? l) (or (feature? (car l)) (loop (cdr l))))))
        ((kw? (car req) 'not) (not (feature? (cadr req))))
        ((kw? (car req) 'library) (or (memq (global-name (car (cadr req))) '(scheme))
                                      (and (assoc (library-key (cadr req)) *libraries*) #t)))
        (else #f)))
(define (cond-expand-forms clauses)
  (cond ((null? clauses) '())
        ((feature? (caar clauses)) (cdar clauses))
        (else (cond-expand-forms (cdr clauses)))))
