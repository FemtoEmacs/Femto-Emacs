;;;; highlight.scm -- syntax highlighting, in Scheme
;;;;
;;;; Port of SBEmacs's lisp/highlight.lisp.  Before painting a window the C
;;;; core passes the visible text (plus some above it, so comments opened
;;;; off-screen are seen) as raw UTF-8 bytes, and we fill one face per byte.
;;;; Working on bytes keeps the colours aligned with the C buffer.  Bytes
;;;; >= 128 (the pieces of UTF-8 characters) are word constituents.

(define +symbol+ 1)
(define +keyword+ 4)
(define +alpha+ 5)
(define +digits+ 6)
(define +comment+ 7)
(define +block-comment+ 8)
(define +string+ 9)
(define +heading+ 11)
(define +emphasis+ 12)
(define +strong+ 13)
(define +link+ 14)

;; A language is a vector; the accessors name its fields.
(define (make-language-record name extensions line-comments block-comments strings escape
                              char-prefix backslash-commands case-insensitive word-chars
                              keywords highlighter)
  (vector 'language name extensions line-comments block-comments strings escape
          char-prefix backslash-commands case-insensitive (make-word-table word-chars) keywords highlighter
          ;; the C tokenizer's copy of the tables (src/highlight.c)
          (and (not highlighter)
               (fe-define-token-language word-chars line-comments block-comments strings
                                         escape char-prefix backslash-commands case-insensitive
                                         keywords))))
(define (language-name l) (vector-ref l 1))
(define (language-extensions l) (vector-ref l 2))
(define (language-line-comments l) (vector-ref l 3))     ; list of strings
(define (language-block-comments l) (vector-ref l 4))    ; list of (open . close)
(define (language-strings l) (vector-ref l 5))           ; longest first
(define (language-escape l) (vector-ref l 6))            ; a byte, or #f
(define (language-char-prefix l) (vector-ref l 7))
(define (language-backslash-commands l) (vector-ref l 8))
(define (language-case-insensitive l) (vector-ref l 9))
(define (language-word-bytes l) (vector-ref l 10))       ; 256 booleans
(define (language-keywords l) (vector-ref l 11))         ; the keywords
(define (language-highlighter l) (vector-ref l 12))
(define (language-token-id l) (vector-ref l 13))

(define *languages* '())          ; most recently defined first
(define *default-language* #f)    ; files no language claims

(define (word-byte-p lang b) (vector-ref (language-word-bytes lang) b))

(define (make-word-table extra)
  (let ((t (make-vector 256 #f)))
    (do ((b 0 (+ b 1))) ((= b 256))
      (when (or (and (<= 48 b) (<= b 57)) (and (<= 65 b) (<= b 90)) (and (<= 97 b) (<= b 122)) (= b 95) (>= b 128))
        (vector-set! t b #t)))
    (do ((i 0 (+ i 1))) ((= i (length extra)))
      (vector-set! t (aref extra i) #t))
    t))

(define (normalise-extension ext)
  (string-downcase (if (and (> (length ext) 0) (= (aref ext 0) 46)) ext (string-append "." ext))))

(define (ensure-list x) (if (or (pair? x) (null? x)) x (list x)))

(define (plist-get plist key default)
  (cond ((null? plist) default)
        ((null? (cdr plist)) default)
        ((eq? (car plist) key) (cadr plist))
        (else (plist-get (cddr plist) key default))))

(define (define-language name . options)
  "Define (or redefine) syntax highlighting for a language:

  (define-language \"C\"
    'extensions '(\".c\" \".h\")
    'line-comment \"//\"                ; a string or a list of strings
    'block-comment '(\"/*\" . \"*/\")    ; a pair or a list of pairs
    'strings '(\"\\\"\" \"'\")            ; string delimiters
    'keywords '(\"if\" \"else\" \"while\"))

Other options: 'escape (a character, default #\\\\, or #f), 'char-prefix
(\"#\\\\\" for Lisp characters), 'backslash-commands (TeX),
'case-insensitive, 'word-chars (extra characters inside identifiers) and
'highlighter, a procedure (language text length colors) that colours the
text itself (see languages/markdown.scm).  The tables go to the tokenizer
in C (src/highlight.c), which runs at every redisplay."
  (let* ((opt (lambda (k d) (plist-get options k d)))
         (block (opt 'block-comment '()))
         (blocks (if (and (pair? block) (string? (car block))) (list block) block))
         (escape (opt 'escape #\\))
         (ci (opt 'case-insensitive #f))
         (keywords (delete-duplicates
                    (filter (lambda (k) (> (length k) 0))
                            (map (lambda (k) (if ci (string-downcase k) k)) (opt 'keywords '())))))
         (lang (make-language-record
                name
                (map normalise-extension (ensure-list (opt 'extensions '())))
                (filter (lambda (s) (> (length s) 0)) (ensure-list (opt 'line-comment '())))
                blocks
                (sort (ensure-list (opt 'strings '("\""))) (lambda (a b) (> (length a) (length b))))
                (and escape (char->integer escape))
                (opt 'char-prefix #f)
                (opt 'backslash-commands #f)
                ci
                (opt 'word-chars "")
                keywords
                (opt 'highlighter #f))))
    (set! *languages* (cons lang (filter (lambda (l) (not (string-ci=? (language-name l) name))) *languages*)))
    lang))

(define *lisp-word-chars* "-*+!?<>=/:%&$^~.")

(set! *default-language*
      (make-language-record "Text" '() '() '() '("\"") 92 #f #f #f "" '() #f))

(define (find-language name)
  (find (lambda (l) (string-ci=? (language-name l) name)) *languages*))

(define (file-extension filename)
  (let ((slash (byte-position-back filename 47))
        (dot (byte-position-back filename 46)))
    (if (and dot (or (not slash) (> dot slash)))
        (string-downcase (byte-substring filename dot))
        "")))

;; file name -> language name, set by M-x html-mode, latex-mode ...
(defvar *language-overrides* (table))

(define (language-for-file filename)
  (let ((ext (file-extension (or filename "")))
        (forced (and filename (get *language-overrides* filename #f))))
    (or (and forced (find-language forced))
        (and (> (length ext) 0)
             (find (lambda (l) (member ext (language-extensions l))) *languages*))
        *default-language*)))

;; A language may hold pieces of other languages: Markdown's ``` blocks
;; (```scheme).  Its procedure, given the buffer's text up to the end of a
;; line and that line's start, answers (language . start of the piece) or
;; #f.  Indentation, M-; and M-q then follow the piece's language.
(defvar *inner-languages* (table))      ; lower-case language name -> procedure

(define (define-inner-language language procedure)
  (put! *inner-languages* (string-downcase language) procedure))

(define (language-place (pos (point)))
  "(language . start): the language at POS in this buffer, and where the
text in that language starts (0 for the whole buffer).  #f: none."
  (let* ((lang (language-for-file (or (buffer-filename) (get-buffer-name))))
         (inner (and lang (get *inner-languages* (string-downcase (language-name lang)) #f)))
         (ls (line-start pos)))
    (or (and inner (inner (buffer-substring 0 (line-end ls)) ls))
        (and lang (cons lang 0)))))

(define (language-at-point (pos (point)))
  (let ((place (language-place pos))) (and place (car place))))

;;; ------------------------------------------------------------------
;;; The tokenizer
;;; ------------------------------------------------------------------

(define (match-at text len i pattern (case-insensitive #f))
  "Does PATTERN occur in TEXT at I?"
  (let ((n (length pattern)))
    (and (<= (+ i n) len)
         (let loop ((k 0))
           (or (= k n)
               (let ((a (aref text (+ i k))) (b (aref pattern k)))
                 (and (or (= a b) (and case-insensitive (and (<= 65 a) (<= a 90)) (= (+ a 32) b)))
                      (loop (+ k 1)))))))))

(define (default-face b)
  (if (or (and (<= 48 b) (<= b 57)) (and (<= 65 b) (<= b 90)) (and (<= 97 b) (<= b 122)) (= b 95) (>= b 128)) +alpha+ +symbol+))

(define (paint colors from to face)
  (do ((i from (+ i 1))) ((>= i to)) (aset! colors i face)))

(define (search-bytes needle text start end)
  "Index of NEEDLE in TEXT within [START, END), or #f."
  (let ((found (string.find text needle start)))
    (and found (<= (+ found (length needle)) end) found)))

;;; The tokenizer is in C (src/highlight.c); a language with a highlighter
;;; of its own (Markdown, Python, Nim) colours the text itself.

(define (highlight-octets lang text len colors)
  "Fill COLORS[0..LEN) with faces for TEXT (LEN bytes)."
  (if (language-highlighter lang)
      ((language-highlighter lang) lang text len colors)
      (fe-highlight-tokens (language-token-id lang)
                           (if (= len (length text)) text (byte-substring text 0 len))
                           colors))
  colors)

(define (make-colors n (fill +alpha+))
  "A byte array of N faces."
  (let ((v (array 'uint8)))
    (if (= n 0) v
        (let ((s (make-string n (integer->char fill))))
          (string->utf8 s)))))

(define (highlight-string string (language #f))
  "For testing: a list of (face . substring) runs for STRING."
  (let* ((lang (cond ((not language) *default-language*)
                     ((string? language) (or (find-language language) (language-for-file language)))
                     (else language)))
         (len (length string))
         (colors (make-colors len)))
    (highlight-octets lang string len colors)
    (let loop ((i 1) (start 0) (runs '()))
      (cond ((= len 0) '())
            ((or (= i len) (not (= (aref colors i) (aref colors start))))
             (let ((runs (cons (cons (aref colors start) (byte-substring string start i)) runs)))
               (if (= i len) (reverse runs) (loop (+ i 1) i runs))))
            (else (loop (+ i 1) start runs))))))

;; buffer name -> the faces of its whole text, made in advance (a byte
;; array): the view without tags (tag-view.scm) keeps the file's colours
(defvar *buffer-faces* (table))

;;; Called from C (src/hooks.c): TEXT is a byte string that starts at offset
;;; START of the buffer BUFFER, COLORS a byte array to fill.  On any error
;;; the C side keeps its default colours.
(define (highlight-buffer-text filename text colors (buffer "") (start 0))
  (let ((faces (get *buffer-faces* buffer #f)))
    (if faces
        (let ((n (length faces)))
          (do ((i 0 (+ i 1))) ((= i (length text)))
            (aset! colors i (if (< (+ start i) n) (aref faces (+ start i)) +alpha+))))
        (let ((lang (language-for-file filename)))
          (when lang (highlight-octets lang text (length text) colors))))
    #t))
