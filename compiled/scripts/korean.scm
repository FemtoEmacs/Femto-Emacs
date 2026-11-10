;;;; korean.scm -- Korean typed on the standard 2-set keyboard (M-x korean-input)
;;;;
;;;; While it is on (the mode line shows 한), the letters type Hangul as on
;;;; a Korean keyboard (두벌식, KS X 5002):
;;;;
;;;;   r ㄱ  s ㄴ  e ㄷ  f ㄹ  a ㅁ  q ㅂ  t ㅅ  d ㅇ  w ㅈ  c ㅊ  z ㅋ  x ㅌ  v ㅍ  g ㅎ
;;;;   R ㄲ  E ㄸ  Q ㅃ  T ㅆ  W ㅉ
;;;;   k ㅏ  o ㅐ  i ㅑ  j ㅓ  p ㅔ  u ㅕ  h ㅗ  y ㅛ  n ㅜ  b ㅠ  m ㅡ  l ㅣ
;;;;   O ㅒ  P ㅖ        (other capitals type their small letter's jamo)
;;;;
;;;; The syllable being composed is in the text, before the cursor, and
;;;; changes with each key: gksrmf types 한글, dkssud 안녕.  A vowel after
;;;; a final consonant takes it into the next syllable (rk f k: 갈, then 가라),
;;;; and of a double final only the second (ekfr k: 닭, then 달가).
;;;; Compound vowels (ㅘ ㅙ ㅚ ㅝ ㅞ ㅟ ㅢ) and finals (ㄳ ㄵ ㄶ ㄺ ㄻ ㄼ ㄽ
;;;; ㄾ ㄿ ㅀ ㅄ) are typed as their parts.  DEL takes back the last jamo of
;;;; the syllable; any other key, or moving the cursor, ends it.
;;;;
;;;; The syllables are computed (Unicode's U+AC00 + (19 initials x 21
;;;; vowels x 28 finals)), so there are no tables to read.  Turned off, it
;;;; costs nothing: the key handler is put back, and nothing else looks at
;;;; *korean*.

(define *korean* #f)
(define *korean-previous-handler* #f)

;; Jamo are kept as their compatibility code points (U+3131 ...), the
;; characters a lone jamo is shown with.  The initials and the finals, in
;; Unicode's order for the syllables:
(define *korean-initials*
  '#(#x3131 #x3132 #x3134 #x3137 #x3138 #x3139 #x3141 #x3142 #x3143 #x3145
     #x3146 #x3147 #x3148 #x3149 #x314A #x314B #x314C #x314D #x314E))
(define *korean-finals*                 ; index 0: no final
  '#(0 #x3131 #x3132 #x3133 #x3134 #x3135 #x3136 #x3137 #x3139 #x313A #x313B
     #x313C #x313D #x313E #x313F #x3140 #x3141 #x3142 #x3144 #x3145 #x3146
     #x3147 #x3148 #x314A #x314B #x314C #x314D #x314E))
;; the 21 vowels are U+314F + their index (ㅏ 0 ... ㅣ 20)

(define *korean-keys*                   ; key -> consonant (compatibility code)
  '((#\r . #x3131) (#\R . #x3132) (#\s . #x3134) (#\e . #x3137) (#\E . #x3138)
    (#\f . #x3139) (#\a . #x3141) (#\q . #x3142) (#\Q . #x3143) (#\t . #x3145)
    (#\T . #x3146) (#\d . #x3147) (#\w . #x3148) (#\W . #x3149) (#\c . #x314A)
    (#\z . #x314B) (#\x . #x314C) (#\v . #x314D) (#\g . #x314E)))
(define *korean-vowel-keys*             ; key -> vowel index
  '((#\k . 0) (#\o . 1) (#\i . 2) (#\O . 3) (#\j . 4) (#\p . 5) (#\u . 6)
    (#\P . 7) (#\h . 8) (#\y . 12) (#\n . 13) (#\b . 17) (#\m . 18) (#\l . 20)))

(define *korean-compound-vowels*        ; (first second . compound), indices
  '((8 0 . 9) (8 1 . 10) (8 20 . 11) (13 4 . 14) (13 5 . 15) (13 20 . 16) (18 20 . 19)))
(define *korean-compound-finals*        ; (first second . compound), code points
  '((#x3131 #x3145 . #x3133) (#x3134 #x3148 . #x3135) (#x3134 #x314E . #x3136)
    (#x3139 #x3131 . #x313A) (#x3139 #x3141 . #x313B) (#x3139 #x3142 . #x313C)
    (#x3139 #x3145 . #x313D) (#x3139 #x314C . #x313E) (#x3139 #x314D . #x313F)
    (#x3139 #x314E . #x3140) (#x3142 #x3145 . #x3144)))

(define (korean-index vec x)
  (let loop ((i 0))
    (cond ((= i (vector-length vec)) #f)
          ((= (vector-ref vec i) x) i)
          (else (loop (+ i 1))))))

(define (korean-pair table a b)
  (let loop ((t table))
    (cond ((null? t) #f)
          ((and (= (car (car t)) a) (= (cadr (car t)) b)) (cddr (car t)))
          (else (loop (cdr t))))))

(define (korean-split table c)
  "The parts (first . second) of the compound C, or #f."
  (let loop ((t table))
    (cond ((null? t) #f)
          ((= (cddr (car t)) c) (cons (car (car t)) (cadr (car t))))
          (else (loop (cdr t))))))

;; A syllable being composed: #(initial vowel final), each #f when absent
;; (initial and final as code points, the vowel as its index).
(define (korean-char s)
  "The character the syllable S shows as."
  (let ((i (vector-ref s 0)) (v (vector-ref s 1)) (f (vector-ref s 2)))
    (integer->char
     (cond ((and i v) (+ #xAC00 (* 588 (korean-index *korean-initials* i)) (* 28 v)
                         (if f (korean-index *korean-finals* f) 0)))
           (v (+ #x314F v))
           (else i)))))

(define *korean-history* '())    ; the syllable's states, latest first
(define *korean-at* #f)          ; where it starts, or #f
(define *korean-buffer* #f)

(define (korean-reset) (set! *korean-history* '()) (set! *korean-at* #f))

(define (korean-composing?)
  "Is a syllable being composed, and still just before the cursor?"
  (and *korean-at* (pair? *korean-history*)
       (equal? *korean-buffer* (get-buffer-name))
       (= (point) (+ *korean-at* 3))            ; every jamo and syllable: 3 bytes
       (let ((c (char->integer (korean-char (car *korean-history*)))))
         (and (= (fe-char-at *korean-at*) (+ #xE0 (quotient c 4096)))
              (= (fe-char-at (+ *korean-at* 1)) (+ #x80 (remainder (quotient c 64) 64)))
              (= (fe-char-at (+ *korean-at* 2)) (+ #x80 (remainder c 64)))))))

(define (korean-show s)
  "Make S the syllable before the cursor."
  (set! *korean-history* (cons s *korean-history*))
  (replace-region *korean-at* (point) (string (korean-char s))))

(define (korean-start s)
  "Begin a new syllable S at the cursor (the one before it is finished)."
  (set! *korean-history* '())
  (set! *korean-at* (point))
  (set! *korean-buffer* (get-buffer-name))
  (korean-show s))

(define (korean-consonant c)
  (let ((s (and (korean-composing?) (car *korean-history*))))
    (cond ((not s) (korean-start (vector c #f #f)))
          ((and (vector-ref s 0) (vector-ref s 1) (not (vector-ref s 2))
                (korean-index *korean-finals* c))                ; ㄸ ㅃ ㅉ are no finals
           (korean-show (vector (vector-ref s 0) (vector-ref s 1) c)))
          ((and (vector-ref s 2) (korean-pair *korean-compound-finals* (vector-ref s 2) c))
           => (lambda (f) (korean-show (vector (vector-ref s 0) (vector-ref s 1) f))))
          (else (korean-start (vector c #f #f))))))

(define (korean-vowel v)
  (let ((s (and (korean-composing?) (car *korean-history*))))
    (cond ((not s) (korean-start (vector #f v #f)))
          ((not (vector-ref s 1)) (korean-show (vector (vector-ref s 0) v #f)))
          ((vector-ref s 2)
           ;; the final goes into the next syllable (of a double final, its second part)
           (let* ((f (vector-ref s 2)) (parts (korean-split *korean-compound-finals* f)))
             (korean-show (vector (vector-ref s 0) (vector-ref s 1) (and parts (car parts))))
             (korean-start (vector (if parts (cdr parts) f) #f #f))
             (korean-show (vector (if parts (cdr parts) f) v #f))))
          ((korean-pair *korean-compound-vowels* (vector-ref s 1) v)
           => (lambda (w) (korean-show (vector (vector-ref s 0) w #f))))
          (else (korean-start (vector #f v #f))))))

(define (korean-back)
  "DEL: the syllable without its last jamo."
  (set! *korean-history* (cdr *korean-history*))
  (if (null? *korean-history*)
      (begin (replace-region *korean-at* (point) "") (korean-reset))
      (replace-region *korean-at* (point) (string (korean-char (car *korean-history*))))))

(define (korean-key-handler kind key)
  "The key handler while the input is on (core.scm's *modal-key-handler*)."
  (or (and *korean*
           (cond ((and (eq? kind 'char) (= (string-length key) 1))
                  (let* ((ch (string-ref key 0))
                         (c (or (assv ch *korean-keys*) (assv (char-downcase ch) *korean-keys*)))
                         (v (or (assv ch *korean-vowel-keys*) (assv (char-downcase ch) *korean-vowel-keys*))))
                    (cond (c (korean-consonant (cdr c)) #t)
                          (v (korean-vowel (cdr v)) #t)
                          (else (korean-reset) #f))))
                 ((and (member key '("backspace" "C-h")) (korean-composing?)) (korean-back) #t)
                 (else (korean-reset) #f)))
      (and *korean-previous-handler*
           ((command-procedure *korean-previous-handler*) kind key))))

(defcommand (korean-input)
  "Toggle Korean typed on the 2-set keyboard (korean.scm)."
  (korean-reset)
  (if *korean*
      (begin (set! *korean* #f)
             (when (eq? *modal-key-handler* 'korean-key-handler)
               (set! *modal-key-handler* *korean-previous-handler*))
             (set! *korean-previous-handler* #f)
             (update-display)
             (message "Korean input off"))
      (begin (unless (eq? *modal-key-handler* 'korean-key-handler)
               (set! *korean-previous-handler* *modal-key-handler*)
               (set! *modal-key-handler* 'korean-key-handler))
             (set! *korean* #t)
             (update-display)
             (message "Korean input (2-set): gksrmf 한글, dkssud 안녕; M-x korean-input again: off"))))
