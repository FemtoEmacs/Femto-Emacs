;;;; wasm.scm -- Schemer: writing a WebAssembly module, byte by byte
;;;;
;;;; A module is described by Scheme data (see compiler.scm) and turned
;;;; into the bytes of the binary format: LEB128 numbers, the type,
;;;; import, function, global, export, element and code sections, and the
;;;; instructions, including those of WasmGC (structs, arrays, i31) and of
;;;; tail calls.  Bytes are built as nested lists and flattened once.

;;; ------------------------------------------------------------------
;;; Numbers
;;; ------------------------------------------------------------------

(define (uleb n)
  "N >= 0 in unsigned LEB128."
  (let loop ((n n) (acc '()))
    (let ((b (logand n 127)) (rest (ash n -7)))
      (if (= rest 0)
          (reverse (cons b acc))
          (loop rest (cons (logior b 128) acc))))))

(define (sleb n)
  "N in signed LEB128."
  (let loop ((n n) (acc '()))
    (let* ((b (logand n 127)) (rest (ash n -7))
           (done (or (and (= rest 0) (= (logand b 64) 0))
                     (and (= rest -1) (not (= (logand b 64) 0))))))
      (if done
          (reverse (cons b acc))
          (loop rest (cons (logior b 128) acc))))))

(define (utf8-bytes s)
  (let ((bytes (string->utf8 s)))
    (let loop ((i (- (bytevector-length bytes) 1)) (out '()))
      (if (< i 0) out (loop (- i 1) (cons (bytevector-u8-ref bytes i) out))))))
(define (string-length-bytes s) (bytevector-length (string->utf8 s)))
(define (f64-bytes x)
  (let* ((sign (if (or (< x 0) (and (= x 0) (< (/ 1.0 x) 0))) 128 0))
         (x (abs x))
         (parts (cond ((not (= x x)) (cons 2047 (expt 2 51)))
                      ((= x +inf.0) (cons 2047 0))
                      ((= x 0) (cons 0 0))
                      (else (let normalize ((m x) (e 0))
                              (cond ((and (< m 1) (> e -1022)) (normalize (* m 2) (- e 1)))
                                    ((>= m 2) (normalize (/ m 2) (+ e 1)))
                                    ((< m 1) (cons 0 (exact (* m (expt 2 52)))))
                                    (else (cons (+ e 1023) (exact (* (- m 1) (expt 2 52))))))))))
         (exponent (car parts)))
    (let loop ((mantissa (cdr parts)) (n 0) (out '()))
      (if (= n 6)
          (append (reverse out) (list (+ mantissa (* 16 (modulo exponent 16))) (+ sign (quotient exponent 16))))
          (loop (quotient mantissa 256) (+ n 1) (cons (modulo mantissa 256) out))))))
(define (flatten tree)
  (let loop ((todo (list tree)) (out '()))
    (if (null? todo) (reverse out)
        (let ((x (car todo)) (rest (cdr todo)))
          (cond ((null? x) (loop rest out))
                ((pair? x) (loop (cons (car x) (cons (cdr x) rest)) out))
                (else (loop rest (cons x out))))))))

(define (wname s) (let ((b (utf8-bytes s))) (list (uleb (length b)) b)))

(define (vec items) (list (uleb (length items)) items))

(define (section id body)
  (let ((bytes (flatten body)))
    (list id (uleb (length bytes)) bytes)))

;;; ------------------------------------------------------------------
;;; Types
;;; ------------------------------------------------------------------
;;; A value type is i32, i64, f32, f64, eqref (any Scheme value: nullable
;;; eq), (ref T) or (ref null T), where T is a type index or a heap type
;;; name: eq, i31, any, func, struct, array, none, extern.

(define (heaptype t)
  (if (integer? t)
      (sleb t)
      (case t
        ((eq) #x6d) ((i31) #x6c) ((struct) #x6b) ((array) #x6a) ((any) #x6e)
        ((extern) #x6f) ((func) #x70) ((none) #x71) ((noextern) #x72) ((nofunc) #x73)
        (else (error "unknown heap type" t)))))

(define (valtype t)
  (cond ((eq? t 'i32) #x7f) ((eq? t 'i64) #x7e) ((eq? t 'f32) #x7d) ((eq? t 'f64) #x7c)
        ((eq? t 'exnref) #x69) ((eq? t 'eqref) #x6d) ((eq? t 'funcref) #x70) ((eq? t 'externref) #x6f)
        ((and (pair? t) (eq? (car t) 'ref))
         (if (eq? (cadr t) 'null)
             (list #x63 (heaptype (caddr t)))
             (list #x64 (heaptype (cadr t)))))
        (else (error "unknown value type" t))))

(define (storagetype t)
  (case t ((i8) #x78) ((i16) #x77) (else (valtype t))))

;; A type definition:
;;   (struct ((mut? type) ...))   (array (mut? type))   (func (params) (results))
;; each optionally wrapped: (sub final? (super ...) def)
(define (field-bytes f) (list (storagetype (cadr f)) (if (car f) 1 0)))

(define (comptype-bytes d)
  (case (car d)
    ((struct) (list #x5f (vec (map field-bytes (cadr d)))))
    ((array) (list #x5e (field-bytes (cadr d))))
    ((func) (list #x60 (vec (map valtype (cadr d))) (vec (map valtype (caddr d)))))
    (else (error "unknown type definition" d))))

(define (subtype-bytes d)
  (if (eq? (car d) 'sub)
      (list (if (cadr d) #x4f #x50) (vec (map uleb (caddr d))) (comptype-bytes (cadddr d)))
      (comptype-bytes d)))

;;; ------------------------------------------------------------------
;;; Instructions
;;; ------------------------------------------------------------------

(define *simple-ops*
  '((unreachable . #x00) (nop . #x01) (throw_ref . #x0a) (else . #x05) (end . #x0b) (return . #x0f) (catch_all . #x19)
    (drop . #x1a) (select . #x1b)
    (ref.is_null . #xd1) (ref.eq . #xd3) (ref.as_non_null . #xd4)
    (i32.eqz . #x45) (i32.eq . #x46) (i32.ne . #x47) (i32.lt_s . #x48) (i32.lt_u . #x49)
    (i32.gt_s . #x4a) (i32.gt_u . #x4b) (i32.le_s . #x4c) (i32.le_u . #x4d)
    (i32.ge_s . #x4e) (i32.ge_u . #x4f)
    (i64.eqz . #x50) (i64.eq . #x51) (i64.ne . #x52) (i64.lt_s . #x53) (i64.lt_u . #x54) (i64.gt_s . #x55)
    (i64.le_s . #x57) (i64.ge_s . #x59)
    (f64.eq . #x61) (f64.ne . #x62) (f64.lt . #x63) (f64.gt . #x64) (f64.le . #x65) (f64.ge . #x66)
    (i32.clz . #x67) (i32.add . #x6a) (i32.sub . #x6b) (i32.mul . #x6c) (i32.div_s . #x6d)
    (i32.div_u . #x6e) (i32.rem_s . #x6f) (i32.rem_u . #x70) (i32.and . #x71) (i32.or . #x72)
    (i32.xor . #x73) (i32.shl . #x74) (i32.shr_s . #x75) (i32.shr_u . #x76)
    (i64.add . #x7c) (i64.sub . #x7d) (i64.mul . #x7e) (i64.div_s . #x7f) (i64.rem_s . #x81)
    (i64.and . #x83) (i64.or . #x84) (i64.xor . #x85)
    (f64.abs . #x99) (f64.neg . #x9a) (f64.ceil . #x9b) (f64.floor . #x9c) (f64.trunc . #x9d)
    (f64.nearest . #x9e) (f64.sqrt . #x9f) (f64.add . #xa0) (f64.sub . #xa1) (f64.mul . #xa2)
    (f64.div . #xa3) (f64.min . #xa4) (f64.max . #xa5)
    (i32.wrap_i64 . #xa7) (i32.trunc_f64_s . #xaa) (i64.extend_i32_s . #xac)
    (i64.trunc_f64_s . #xb0)
    (f64.convert_i32_s . #xb7) (f64.convert_i64_s . #xb9)))

(define *gc-simple-ops*
  '((array.len . #x0f) (ref.i31 . #x1c) (i31.get_s . #x1d) (i31.get_u . #x1e)))

(define (blocktype bt)
  (cond ((eq? bt 'empty) #x40)
        ((integer? bt) (sleb bt))
        (else (valtype bt))))

(define (instr-bytes ins)
  "The bytes of one instruction: a symbol, or (op immediates ...)."
  (if (symbol? ins)
      (let ((s (assq ins *simple-ops*)) (g (assq ins *gc-simple-ops*)))
        (cond (s (cdr s))
              (g (list #xfb (cdr g)))
              (else (error "unknown instruction" ins))))
      (let ((op (car ins)) (a (cdr ins)))
        (case op
          ((block) (list #x02 (blocktype (car a))))
          ((loop) (list #x03 (blocktype (car a))))
          ((if) (list #x04 (blocktype (car a))))
          ;; exceptions (the first proposal, which every browser has)
          ((try) (list #x06 (blocktype (car a))))
          ((catch) (list #x07 (uleb (car a))))
          ((try_table) (list #x1f (blocktype (car a))
                              (vec (map (lambda (c) (if (eq? (car c) 'catch)
                                            (list 0 (uleb (cadr c)) (uleb (caddr c)))
                                            (list 3 (uleb (cadr c))))) (cadr a)))))
          ((throw) (list #x08 (uleb (car a))))
          ((rethrow) (list #x09 (uleb (car a))))
          ((br) (list #x0c (uleb (car a))))
          ((br_if) (list #x0d (uleb (car a))))
          ((call) (list #x10 (uleb (car a))))
          ((return_call) (list #x12 (uleb (car a))))
          ((call_ref) (list #x14 (uleb (car a))))
          ((return_call_ref) (list #x15 (uleb (car a))))
          ((local.get) (list #x20 (uleb (car a))))
          ((local.set) (list #x21 (uleb (car a))))
          ((local.tee) (list #x22 (uleb (car a))))
          ((global.get) (list #x23 (uleb (car a))))
          ((global.set) (list #x24 (uleb (car a))))
          ((i32.const) (list #x41 (sleb (car a))))
          ((i32.load8_u) (list #x2d (uleb (car a)) (uleb (cadr a))))
          ((i32.store8) (list #x3a (uleb (car a)) (uleb (cadr a))))
          ((i64.const) (list #x42 (sleb (car a))))
          ((f64.const) (list #x44 (f64-bytes (car a))))
          ((ref.null) (list #xd0 (heaptype (car a))))
          ((ref.func) (list #xd2 (uleb (car a))))
          ((br_on_null) (list #xd5 (uleb (car a))))
          ((br_on_non_null) (list #xd6 (uleb (car a))))
          ((struct.new) (list #xfb #x00 (uleb (car a))))
          ((struct.get) (list #xfb #x02 (uleb (car a)) (uleb (cadr a))))
          ((struct.set) (list #xfb #x05 (uleb (car a)) (uleb (cadr a))))
          ((array.new) (list #xfb #x06 (uleb (car a))))
          ((array.new_default) (list #xfb #x07 (uleb (car a))))
          ((array.new_fixed) (list #xfb #x08 (uleb (car a)) (uleb (cadr a))))
          ((array.get) (list #xfb #x0b (uleb (car a))))
          ((array.set) (list #xfb #x0e (uleb (car a))))
          ((array.fill) (list #xfb #x10 (uleb (car a))))
          ((array.copy) (list #xfb #x11 (uleb (car a)) (uleb (cadr a))))
          ;; (ref.test T) / (ref.test null T), likewise ref.cast
          ((ref.test) (if (eq? (car a) 'null)
                          (list #xfb #x15 (heaptype (cadr a)))
                          (list #xfb #x14 (heaptype (car a)))))
          ((ref.cast) (if (eq? (car a) 'null)
                          (list #xfb #x17 (heaptype (cadr a)))
                          (list #xfb #x16 (heaptype (car a)))))
          ;; (br_on_cast label from-null? from-ht to-null? to-ht)
          ((br_on_cast br_on_cast_fail)
           (list #xfb (if (eq? op 'br_on_cast) #x18 #x19)
                 (+ (if (list-ref a 1) 1 0) (if (list-ref a 3) 2 0))
                 (uleb (list-ref a 0)) (heaptype (list-ref a 2)) (heaptype (list-ref a 4))))
          (else (error "unknown instruction" ins))))))

(define (code-bytes instrs) (map instr-bytes instrs))

;;; ------------------------------------------------------------------
;;; The module
;;; ------------------------------------------------------------------
;;; (module types imports funcs globals exports declared)
;;;   types:   list of type definitions, all in one recursion group
;;;   imports: ((module name typeidx) ...) functions only
;;;   funcs:   ((typeidx (local-types ...) (instrs ...)) ...)
;;;   globals: ((valtype mutable? (init-instrs ...)) ...)
;;;   exports: ((name kind index) ...) kind: func or global
;;;   declared: function indices used by ref.func

(define (locals-bytes types)
  ;; runs of the same type
  (let loop ((ts types) (acc '()))
    (if (null? ts)
        (vec (reverse acc))
        (let count ((rest (cdr ts)) (n 1))
          (if (and (pair? rest) (equal? (car rest) (car ts)))
              (count (cdr rest) (+ n 1))
              (loop rest (cons (list (uleb n) (valtype (car ts))) acc)))))))

(define (function-body f)
  (let ((bytes (flatten (list (locals-bytes (cadr f)) (code-bytes (caddr f)) #x0b))))
    (list (uleb (length bytes)) bytes)))

(define *module-tags* '())   ; type indices of the module's exception tags
(define (module-bytes types imports funcs globals exports declared start . names)
  (flatten
   (list #x00 #x61 #x73 #x6d #x01 #x00 #x00 #x00
         (section 1 (list 1 #x4e (vec (map subtype-bytes types))))
         (section 2 (vec (map (lambda (im) (if (eq? (caddr im) 'memory)
                                               (list (wname (car im)) (wname (cadr im)) #x02 #x00 #x00)   ; memory, min 0
                                               (list (wname (car im)) (wname (cadr im)) #x00 (uleb (caddr im)))))
                              imports)))
         (section 3 (vec (map (lambda (f) (uleb (car f))) funcs)))
         (if (null? *module-tags*) '()
             (section 13 (vec (map (lambda (t) (list #x00 (uleb t))) *module-tags*))))
         (section 6 (vec (map (lambda (g) (list (valtype (car g)) (if (cadr g) 1 0)
                                                (code-bytes (caddr g)) #x0b))
                              globals)))
         (section 7 (vec (map (lambda (e) (list (wname (car e))
                                                (case (cadr e) ((func) #x00) ((tag) #x04) (else #x03))
                                                (uleb (caddr e))))
                              exports)))
         (if start (section 8 (uleb start)) '())
         (if (null? declared) '()
             (section 9 (list 1 3 #x00 (vec (map uleb declared)))))
         (section 10 (vec (map function-body funcs)))
         ;; the name section: ((index . "name") ...) in increasing order
         (if (or (null? names) (null? (car names))) '()
             (let ((sub (flatten (vec (map (lambda (n) (list (uleb (car n)) (wname (cdr n)))) (car names))))))
               (section 0 (list (wname "name") 1 (uleb (length sub)) sub)))))))
