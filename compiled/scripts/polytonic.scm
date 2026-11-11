;;;; polytonic.scm -- polytonic Greek typed in Beta Code (M-x polytonic)
;;;;
;;;; While it is on (the mode line shows "Ἑλ"), the letters type Greek:
;;;;
;;;;   a α  b β  g γ  d δ  e ε  z ζ  h η  q θ  i ι  k κ  l λ  m μ  n ν
;;;;   c ξ  o ο  p π  r ρ  s σ  t τ  u υ  f φ  x χ  y ψ  w ω  v ϝ  j ς
;;;;
;;;; and, typed after a letter, these marks change it (TLG Beta Code):
;;;;
;;;;   )  smooth breathing    (  rough breathing    /  acute    \  grave
;;;;   =  circumflex          |  iota subscript      +  diaeresis
;;;;
;;;; so that  a)/  gives ἄ,  w(=|  ᾧ,  i+/  ΐ,  r(  ῥ.  A capital is * (or
;;;; Shift) before the letter, its marks between them, as in Beta Code:
;;;; *)/a gives Ἄ, *(w Ὡ.  σ at the end of a word becomes ς.  : gives
;;;; the ano teleia (·), ' the apostrophe of elision (’), # the keraia (ʹ).
;;;; A mark typed after anything but a Greek letter, or twice, is the
;;;; character itself: ( ) / still type parentheses and slashes after a
;;;; blank.  A combination with no precomposed character gets a combining
;;;; accent instead (src/width.c draws it on its letter).
;;;;
;;;; The composition table is Unicode's: every precomposed Greek character
;;;; (Greek and Coptic, Greek Extended) with its letter and marks, in the
;;;; normal form NFC (U+03AC for alpha with acute, not U+1F71).

(define *polytonic* #f)

;; Beta Code's letters
(define *polytonic-letters*
  '((#\a . #x3B1) (#\b . #x3B2) (#\g . #x3B3) (#\d . #x3B4) (#\e . #x3B5)
    (#\z . #x3B6) (#\h . #x3B7) (#\q . #x3B8) (#\i . #x3B9) (#\k . #x3BA)
    (#\l . #x3BB) (#\m . #x3BC) (#\n . #x3BD) (#\c . #x3BE) (#\o . #x3BF)
    (#\p . #x3C0) (#\r . #x3C1) (#\s . #x3C3) (#\t . #x3C4) (#\u . #x3C5)
    (#\f . #x3C6) (#\x . #x3C7) (#\y . #x3C8) (#\w . #x3C9) (#\v . #x3DD)
    (#\j . #x3C2)))

;; the marks: their bit in a set of marks, and their combining character
(define *polytonic-marks*
  '((#\) 1 #x313) (#\( 2 #x314) (#\/ 4 #x301) (#\\ 8 #x300) (#\= 16 #x342)
    (#\| 32 #x345) (#\+ 64 #x308)))
(define *polytonic-accents* (+ 4 (+ 8 16)))     ; one of acute, grave, circumflex
(define *polytonic-breathings* (+ 1 2))         ; one of smooth, rough

;; letter * 128 + set of marks -> precomposed character, generated from
;; Unicode's decompositions
(define *polytonic-table* '#(
  #x1C881 #x1F08  #x1C882 #x1F09  #x1C884 #x386  #x1C885 #x1F0C
  #x1C886 #x1F0D  #x1C888 #x1FBA  #x1C889 #x1F0A  #x1C88A #x1F0B
  #x1C891 #x1F0E  #x1C892 #x1F0F  #x1C8A0 #x1FBC  #x1C8A1 #x1F88
  #x1C8A2 #x1F89  #x1C8A5 #x1F8C  #x1C8A6 #x1F8D  #x1C8A9 #x1F8A
  #x1C8AA #x1F8B  #x1C8B1 #x1F8E  #x1C8B2 #x1F8F  #x1CA81 #x1F18
  #x1CA82 #x1F19  #x1CA84 #x388  #x1CA85 #x1F1C  #x1CA86 #x1F1D
  #x1CA88 #x1FC8  #x1CA89 #x1F1A  #x1CA8A #x1F1B  #x1CB81 #x1F28
  #x1CB82 #x1F29  #x1CB84 #x389  #x1CB85 #x1F2C  #x1CB86 #x1F2D
  #x1CB88 #x1FCA  #x1CB89 #x1F2A  #x1CB8A #x1F2B  #x1CB91 #x1F2E
  #x1CB92 #x1F2F  #x1CBA0 #x1FCC  #x1CBA1 #x1F98  #x1CBA2 #x1F99
  #x1CBA5 #x1F9C  #x1CBA6 #x1F9D  #x1CBA9 #x1F9A  #x1CBAA #x1F9B
  #x1CBB1 #x1F9E  #x1CBB2 #x1F9F  #x1CC81 #x1F38  #x1CC82 #x1F39
  #x1CC84 #x38A  #x1CC85 #x1F3C  #x1CC86 #x1F3D  #x1CC88 #x1FDA
  #x1CC89 #x1F3A  #x1CC8A #x1F3B  #x1CC91 #x1F3E  #x1CC92 #x1F3F
  #x1CCC0 #x3AA  #x1CF81 #x1F48  #x1CF82 #x1F49  #x1CF84 #x38C
  #x1CF85 #x1F4C  #x1CF86 #x1F4D  #x1CF88 #x1FF8  #x1CF89 #x1F4A
  #x1CF8A #x1F4B  #x1D082 #x1FEC  #x1D282 #x1F59  #x1D284 #x38E
  #x1D286 #x1F5D  #x1D288 #x1FEA  #x1D28A #x1F5B  #x1D292 #x1F5F
  #x1D2C0 #x3AB  #x1D481 #x1F68  #x1D482 #x1F69  #x1D484 #x38F
  #x1D485 #x1F6C  #x1D486 #x1F6D  #x1D488 #x1FFA  #x1D489 #x1F6A
  #x1D48A #x1F6B  #x1D491 #x1F6E  #x1D492 #x1F6F  #x1D4A0 #x1FFC
  #x1D4A1 #x1FA8  #x1D4A2 #x1FA9  #x1D4A5 #x1FAC  #x1D4A6 #x1FAD
  #x1D4A9 #x1FAA  #x1D4AA #x1FAB  #x1D4B1 #x1FAE  #x1D4B2 #x1FAF
  #x1D881 #x1F00  #x1D882 #x1F01  #x1D884 #x3AC  #x1D885 #x1F04
  #x1D886 #x1F05  #x1D888 #x1F70  #x1D889 #x1F02  #x1D88A #x1F03
  #x1D890 #x1FB6  #x1D891 #x1F06  #x1D892 #x1F07  #x1D8A0 #x1FB3
  #x1D8A1 #x1F80  #x1D8A2 #x1F81  #x1D8A4 #x1FB4  #x1D8A5 #x1F84
  #x1D8A6 #x1F85  #x1D8A8 #x1FB2  #x1D8A9 #x1F82  #x1D8AA #x1F83
  #x1D8B0 #x1FB7  #x1D8B1 #x1F86  #x1D8B2 #x1F87  #x1DA81 #x1F10
  #x1DA82 #x1F11  #x1DA84 #x3AD  #x1DA85 #x1F14  #x1DA86 #x1F15
  #x1DA88 #x1F72  #x1DA89 #x1F12  #x1DA8A #x1F13  #x1DB81 #x1F20
  #x1DB82 #x1F21  #x1DB84 #x3AE  #x1DB85 #x1F24  #x1DB86 #x1F25
  #x1DB88 #x1F74  #x1DB89 #x1F22  #x1DB8A #x1F23  #x1DB90 #x1FC6
  #x1DB91 #x1F26  #x1DB92 #x1F27  #x1DBA0 #x1FC3  #x1DBA1 #x1F90
  #x1DBA2 #x1F91  #x1DBA4 #x1FC4  #x1DBA5 #x1F94  #x1DBA6 #x1F95
  #x1DBA8 #x1FC2  #x1DBA9 #x1F92  #x1DBAA #x1F93  #x1DBB0 #x1FC7
  #x1DBB1 #x1F96  #x1DBB2 #x1F97  #x1DC81 #x1F30  #x1DC82 #x1F31
  #x1DC84 #x3AF  #x1DC85 #x1F34  #x1DC86 #x1F35  #x1DC88 #x1F76
  #x1DC89 #x1F32  #x1DC8A #x1F33  #x1DC90 #x1FD6  #x1DC91 #x1F36
  #x1DC92 #x1F37  #x1DCC0 #x3CA  #x1DCC4 #x390  #x1DCC8 #x1FD2
  #x1DCD0 #x1FD7  #x1DF81 #x1F40  #x1DF82 #x1F41  #x1DF84 #x3CC
  #x1DF85 #x1F44  #x1DF86 #x1F45  #x1DF88 #x1F78  #x1DF89 #x1F42
  #x1DF8A #x1F43  #x1E081 #x1FE4  #x1E082 #x1FE5  #x1E281 #x1F50
  #x1E282 #x1F51  #x1E284 #x3CD  #x1E285 #x1F54  #x1E286 #x1F55
  #x1E288 #x1F7A  #x1E289 #x1F52  #x1E28A #x1F53  #x1E290 #x1FE6
  #x1E291 #x1F56  #x1E292 #x1F57  #x1E2C0 #x3CB  #x1E2C4 #x3B0
  #x1E2C8 #x1FE2  #x1E2D0 #x1FE7  #x1E481 #x1F60  #x1E482 #x1F61
  #x1E484 #x3CE  #x1E485 #x1F64  #x1E486 #x1F65  #x1E488 #x1F7C
  #x1E489 #x1F62  #x1E48A #x1F63  #x1E490 #x1FF6  #x1E491 #x1F66
  #x1E492 #x1F67  #x1E4A0 #x1FF3  #x1E4A1 #x1FA0  #x1E4A2 #x1FA1
  #x1E4A4 #x1FF4  #x1E4A5 #x1FA4  #x1E4A6 #x1FA5  #x1E4A8 #x1FF2
  #x1E4A9 #x1FA2  #x1E4AA #x1FA3  #x1E4B0 #x1FF7  #x1E4B1 #x1FA6
  #x1E4B2 #x1FA7  #x1E904 #x3D3  #x1E940 #x3D4))

(define *polytonic-compose* (make-eqv-hashtable))     ; key -> character
(define *polytonic-decompose* (make-eqv-hashtable))   ; character -> key
(let loop ((i 0))
  (when (< i (vector-length *polytonic-table*))
    (let ((key (vector-ref *polytonic-table* i)) (c (vector-ref *polytonic-table* (+ i 1))))
      (hashtable-set! *polytonic-compose* key c)
      (unless (hashtable-contains? *polytonic-decompose* c)
        (hashtable-set! *polytonic-decompose* c key))
      (loop (+ i 2)))))

(define (polytonic-letter? c)
  "C (a code point) is a Greek letter, accented or not."
  (or (and (<= #x391 c) (<= c #x3C9)) (= c #x3DC) (= c #x3DD)
      (hashtable-contains? *polytonic-decompose* c)))

;; The letters that take marks: the vowels take any, rho the breathings.
;; After any other letter a mark is itself: ")" closes "(λόγος)".
(define (polytonic-takes-mark? letter bit)
  (or (memv letter '(#x3B1 #x3B5 #x3B7 #x3B9 #x3BF #x3C5 #x3C9
                     #x391 #x395 #x397 #x399 #x39F #x3A5 #x3A9))
      (and (memv letter '(#x3C1 #x3A1)) (> (bitwise-and bit *polytonic-breathings*) 0))))

(define (polytonic-capital c)
  (cond ((= c #x3C2) #x3A3) ((= c #x3DD) #x3DC) (else (- c 32))))

(define (polytonic-compose letter marks)
  "LETTER with the set MARKS, as text: the precomposed character, or the
letter followed by combining accents when Unicode has none."
  (let ((c (if (= marks 0) letter (hashtable-ref *polytonic-compose* (+ (* letter 128) marks) #f))))
    (if c (string (integer->char c))
        (let loop ((ms *polytonic-marks*) (s (string (integer->char letter))))
          (cond ((null? ms) s)
                ((= 0 (bitwise-and marks (cadr (car ms)))) (loop (cdr ms) s))
                (else (loop (cdr ms) (string-append s (string (integer->char (caddr (car ms))))))))))))

;; The character before point: its start and code point (#f at the start)
(define (polytonic-previous)
  (let ((p (point)))
    (and (> p 0)
         (let back ((s (- p 1)))
           (let ((b (fe-char-at s)))
             ;; back over continuation bytes, at most three
             (if (and (> s 0) (= (bitwise-and b #xC0) #x80) (< (- p s) 4))
                 (back (- s 1))
                 (let ((n (- p s)))
                   (cons s (cond ((= n 1) b)
                                 ((= n 2) (+ (* 64 (bitwise-and b 31)) (bitwise-and (fe-char-at (+ s 1)) 63)))
                                 ((= n 3) (+ (* 4096 (bitwise-and b 15))
                                             (+ (* 64 (bitwise-and (fe-char-at (+ s 1)) 63))
                                                (bitwise-and (fe-char-at (+ s 2)) 63))))
                                 (else #f))))))))))

;; A mark after a letter: the letter with it.  #f when there is no letter
;; before point, or when the letter has that mark already.
(define (polytonic-add-mark bit)
  (let ((prev (polytonic-previous)))
    (and prev (cdr prev) (polytonic-letter? (cdr prev))
         (let* ((key (hashtable-ref *polytonic-decompose* (cdr prev) #f))
                (letter (if key (quotient key 128) (cdr prev)))
                (marks (if key (remainder key 128) 0)))
           (and (= 0 (bitwise-and marks bit))
                (polytonic-takes-mark? letter bit)
                ;; a new accent replaces the old one, a breathing the other
                (let ((marks (bitwise-ior bit
                               (bitwise-and marks
                                 (- 127 (cond ((> (bitwise-and bit *polytonic-accents*) 0) *polytonic-accents*)
                                              ((> (bitwise-and bit *polytonic-breathings*) 0) *polytonic-breathings*)
                                              (else 0)))))))
                  (replace-region (car prev) (point) (polytonic-compose letter marks))
                  #t))))))

;; σ before point becomes ς when the word ends
(define (polytonic-final-sigma)
  (let ((prev (polytonic-previous)))
    (when (and prev (eqv? (cdr prev) #x3C3))
      (replace-region (car prev) (point) (string (integer->char #x3C2))))))

(define *polytonic-capital* #f)    ; after *: the marks typed so far, or #f

(define (polytonic-self-insert key)
  "The keyboard: KEY is the character typed (a one-character string)."
  (and *polytonic* (= (string-length key) 1)
       (let* ((ch (string-ref key 0))
              (low (char-downcase ch))
              (letter (assv low *polytonic-letters*))
              (mark (assv ch *polytonic-marks*)))
         (cond (*polytonic-capital*
                (cond (mark (set! *polytonic-capital* (bitwise-ior *polytonic-capital* (cadr mark)))
                            (message "Beta Code capital: the letter")
                            #t)
                      (letter (insert (polytonic-compose (polytonic-capital (cdr letter)) *polytonic-capital*))
                              (set! *polytonic-capital* #f)
                              #t)
                      (else (set! *polytonic-capital* #f) (insert "*") #f)))
               ((char=? ch #\*) (set! *polytonic-capital* 0) (message "Beta Code capital: marks, then the letter") #t)
               (letter (insert (string (integer->char (if (char-upper-case? ch) (polytonic-capital (cdr letter)) (cdr letter)))))
                       #t)
               (mark (or (polytonic-add-mark (cadr mark)) (begin (polytonic-final-sigma) #f)))
               ((char=? ch #\:) (polytonic-final-sigma) (insert (string (integer->char #xB7))) #t)
               ((char=? ch #\') (insert (string (integer->char #x2019))) #t)
               ((char=? ch #\#) (insert (string (integer->char #x374))) #t)
               (else (polytonic-final-sigma) #f)))))

(defcommand (polytonic)
  "Toggle the polytonic Greek keyboard, in Beta Code (polytonic.scm)."
  (set! *polytonic* (not *polytonic*))
  (set! *polytonic-capital* #f)
  (update-display)
  (message (if *polytonic*
               "Polytonic Greek (Beta Code): a)/ ἄ, w(=| ᾧ, *)/a Ἄ; M-x polytonic again for Latin letters"
               "Polytonic Greek off")))

;; first of the self-insert hooks: indentation's RET and electric keys come
;; after it (a σ before a RET becomes ς, then RET goes on)
(set! *self-insert-hook* (cons 'polytonic-self-insert
                               (filter (lambda (h) (not (eq? h 'polytonic-self-insert))) *self-insert-hook*)))
