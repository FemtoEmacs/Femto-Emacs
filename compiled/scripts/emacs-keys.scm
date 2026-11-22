;;;; emacs-keys.scm -- the GNU Emacs keys FemtoEmacs did not have
;;;;
;;;; In Chez Scheme, compiled by Schemer: the port of scheme/extensions/
;;;; emacs-keys.scm.
;;;;
;;;; The scanners (words, sentences, paragraphs, expressions) take a reader
;;;; GET (offset -> byte, -1 outside the text) and the text's SIZE, so the
;;;; tests can run them on strings; the commands run them on the buffer:
;;;; offsets are bytes.  A line of text taken from the buffer is a string,
;;;; and the procedures on lines (filling, list items, comments) count its
;;;; characters; the marks they look for are ASCII.

;;; ------------------------------------------------------------------
;;; Reading the text
;;; ------------------------------------------------------------------

(define (buffer-get i) (fe-char-at i))

;; A reader over the buffer for one scan: it asks C for the text in blocks
;; of 64 KB (buffer-bytes) and reads the bytes from them.  Asking for each
;; byte (fe-char-at) crossed the bridge once a byte: C-M-f over the
;; outermost list of a 9.7 MB file took 48 seconds (20 November 2026).  A
;; scan does not change the text, so the blocks stay valid while it runs.
(define *reader-block* 65536)
(define (buffer-reader)
  (let ((size (buffer-size)) (start 0) (end 0) (bytes #f))
    (lambda (i)
      (cond ((or (< i 0) (>= i size)) -1)
            ((and bytes (>= i start) (< i end)) (bytevector-u8-ref bytes (- i start)))
            (else
             (set! start (* (quotient i *reader-block*) *reader-block*))
             (set! bytes (buffer-bytes start (min size (+ start *reader-block*))))
             (set! end (+ start (bytevector-length bytes)))
             (bytevector-u8-ref bytes (- i start)))))))

(define (reader-substring get a b)
  "The text from A to B, read with GET (a buffer-reader), as a string."
  (let ((v (make-bytevector (max 0 (- b a)) 0)))
    (let loop ((i a))
      (when (< i b) (bytevector-u8-set! v (- i a) (get i)) (loop (+ i 1))))
    (utf8->string v)))

(define (octets-get s)
  "A reader over the bytes of S (a string or a bytevector), for the tests."
  (let ((b (%utf8 s)))
    (lambda (i) (if (and (>= i 0) (< i (bytevector-length b))) (bytevector-u8-ref b i) -1))))

(define (byte-in b chars)
  "Is B one of the ASCII CHARS?  The scanners ask this of every byte, so it
is a plain loop: string-index (variadic, and a closure a call) cost a
microsecond, and C-M-f over a 9.7 MB list took 42 seconds."
  (and (>= b 0) (<= b 127)
       (let ((n (string-length chars)))
         (let loop ((k 0))
           (cond ((= k n) #f)
                 ((= b (char->integer (string-ref chars k))) #t)
                 (else (loop (+ k 1))))))))

(define (word-constituent-p b)
  "Letters, digits and every non-ASCII byte make words."
  (and (>= b 0) (or (>= b 128) (and (<= 48 b) (<= b 57)) (and (<= 65 b) (<= b 90)) (and (<= 97 b) (<= b 122)))))

(define (blank-byte b) (or (= b 32) (= b 9) (= b 13)))
(define (whitespace-byte b) (or (= b 32) (= b 9) (= b 13) (= b 10)))

(define (char-end get size i)
  (let ((b (get i)))
    (min size (+ i (cond ((< b #xC0) 1) ((< b #xE0) 2) ((< b #xF0) 3) (else 4))))))

(define (char-start-before get i)
  (let loop ((j (max 0 (- i 1))))
    (if (and (> j 0) (= (bitwise-and (get j) #xC0) #x80)) (loop (- j 1)) j)))

;;; lines

(define (line-start-position get i)
  (let loop ((i i)) (if (and (> i 0) (not (= (get (- i 1)) 10))) (loop (- i 1)) i)))

(define (line-end-position get size i)
  (let loop ((i i)) (if (and (< i size) (not (= (get i) 10))) (loop (+ i 1)) i)))

(define (next-line-start get size ls) (min size (+ 1 (line-end-position get size ls))))

(define (prev-line-start-position get ls)
  (if (> ls 0) (line-start-position get (- ls 1)) 0))

(define (blank-line-p get size ls)
  (let loop ((i ls))
    (cond ((>= i size) #t)
          ((= (get i) 10) #t)
          ((blank-byte (get i)) (loop (+ i 1)))
          (else #f))))

(define (indentation-end get size ls)
  (let loop ((i ls)) (if (and (< i size) (blank-byte (get i))) (loop (+ i 1)) i)))

;;; words

(define (forward-word-position get size i)
  (let* ((i (let loop ((i i)) (if (and (< i size) (not (word-constituent-p (get i)))) (loop (+ i 1)) i))))
    (let loop ((i i)) (if (and (< i size) (word-constituent-p (get i))) (loop (+ i 1)) i))))

(define (backward-word-position get size i)
  (let* ((i (let loop ((i i)) (if (and (> i 0) (not (word-constituent-p (get (- i 1))))) (loop (- i 1)) i))))
    (let loop ((i i)) (if (and (> i 0) (word-constituent-p (get (- i 1)))) (loop (- i 1)) i))))

;;; paragraphs: separated by blank lines

(define (forward-paragraph-position get size i)
  (let* ((ls (line-start-position get i))
         (ls (let loop ((ls ls))
               (if (and (< ls size) (blank-line-p get size ls)) (loop (next-line-start get size ls)) ls))))
    (let loop ((ls ls))
      (if (and (< ls size) (not (blank-line-p get size ls)))
          (let ((next (next-line-start get size ls)))
            (if (= next ls) (min ls size) (loop next)))
          (min ls size)))))

(define (backward-paragraph-position get size i)
  (let* ((ls (line-start-position get i))
         (ls (if (and (= ls i) (> ls 0) (blank-line-p get size ls)) (prev-line-start-position get ls) ls))
         (ls (let loop ((ls ls))
               (if (and (> ls 0) (blank-line-p get size ls)) (loop (prev-line-start-position get ls)) ls))))
    (let loop ((ls ls))
      (if (and (> ls 0) (not (blank-line-p get size ls))) (loop (prev-line-start-position get ls)) ls))))

(define (paragraph-text-start get size i)
  (let ((b (backward-paragraph-position get size i)))
    (if (blank-line-p get size b) (next-line-start get size b) b)))

;;; sentences: end with . ? or ! followed by a space or a line end

(define (sentence-end-after get size k)
  (and (byte-in (get k) ".?!")
       (let ((e (let loop ((e (+ k 1)))
                  (if (and (< e size) (byte-in (get e) ")]}\"'")) (loop (+ e 1)) e))))
         (and (or (>= e size) (whitespace-byte (get e))) e))))

(define (forward-sentence-position get size i)
  (let* ((limit (forward-paragraph-position get size i))
         (limit (if (<= limit i) size limit)))
    (let loop ((k i))
      (if (< k limit)
          (let ((e (sentence-end-after get size k)))
            (if (and e (> e i)) e (loop (+ k 1))))
          ;; the paragraph's last sentence: up to its last character
          (let ((e (let back ((e limit))
                     (if (and (> e i) (whitespace-byte (get (- e 1)))) (back (- e 1)) e))))
            (if (> e i) e limit))))))

(define (backward-sentence-position get size i)
  (let* ((start (paragraph-text-start get size (max 0 (- i 1))))
         (start (if (> start i)
                    (paragraph-text-start get size (backward-paragraph-position get size i))
                    start))
         (j (let loop ((j i)) (if (and (> j start) (whitespace-byte (get (- j 1)))) (loop (- j 1)) j))))
    (let loop ((k (- j 1)))
      (if (< k start)
          start
          (let ((e (sentence-end-after get size k)))
            (if (and e (< e j))
                (let skip ((e e)) (if (and (< e size) (whitespace-byte (get e))) (skip (+ e 1)) e))
                (loop (- k 1))))))))

;;; balanced expressions

(define (lisp-buffer-p)
  (let ((lang (language-for-file (or (buffer-filename) (get-buffer-name)))))
    (and lang (member (language-name lang) '("Common Lisp" "Scheme" "VHDL Lisp")) #t)))

(define (open-byte-p b) (or (= b 40) (= b 91) (= b 123)))      ; ( [ {
(define (close-byte-p b) (or (= b 41) (= b 93) (= b 125)))     ; ) ] }

(define (escaped-at-p get i)
  "Is the byte at I a Lisp character literal (#\\x) or escaped (\\x)?"
  (and (>= i 1) (= (get (- i 1)) 92)
       (not (and (>= i 2) (= (get (- i 2)) 92)))))

(define (symbol-byte-p b lispish)
  (and (>= b 0)
       (not (whitespace-byte b))
       (not (byte-in b "()[]{}\""))
       (not (and lispish (byte-in b ";'`,")))
       (not (and (not lispish) (byte-in b ";,")))))

(define (string-end get size i)
  "I is at an opening double quote: the offset after the closing one."
  (let loop ((j (+ i 1)))
    (if (>= j size) #f
        (let ((b (get j)))
          (cond ((= b 92) (loop (+ j 2)))
                ((= b 34) (+ j 1))
                (else (loop (+ j 1))))))))

(define (string-start get i)
  "The byte before I is a closing double quote: the offset of the opening one."
  (let loop ((j (- i 2)))
    (cond ((< j 0) #f)
          ((and (= (get j) 34) (not (escaped-at-p get j))) j)
          (else (loop (- j 1))))))

(define (skip-space-and-comments get size i lispish)
  (let loop ((i i))
    (let ((i (let skip ((i i)) (if (and (< i size) (whitespace-byte (get i))) (skip (+ i 1)) i))))
      (if (and lispish (< i size) (= (get i) 59))
          (loop (line-end-position get size i))
          i))))

(define (list-end get size i lispish)
  "I is at an open bracket: the offset after the matching close, or #f."
  (let loop ((j i) (depth 0))
    (if (>= j size) #f
        (let ((b (get j)))
          (cond ((= b 92) (loop (+ j 2) depth))
                ((= b 34) (let ((e (string-end get size j))) (if e (loop e depth) #f)))
                ((and lispish (= b 59)) (loop (line-end-position get size j) depth))
                ((and (not lispish) (= b 39) (< (+ j 2) size) (= (get (+ j 2)) 39))
                 (loop (+ j 3) depth))
                ((open-byte-p b) (loop (+ j 1) (+ depth 1)))
                ((close-byte-p b)
                 (if (= depth 1) (+ j 1) (loop (+ j 1) (- depth 1))))
                (else (loop (+ j 1) depth)))))))

(define (list-start get i)
  "The byte before I is a close bracket: the offset of the matching open."
  (let loop ((j (- i 1)) (depth 0))
    (if (< j 0) #f
        (let ((b (get j)))
          (cond ((escaped-at-p get j) (loop (- j 1) depth))
                ((= b 34) (let ((s (string-start get (+ j 1)))) (if s (loop (- s 1) depth) #f)))
                ((close-byte-p b) (loop (- j 1) (+ depth 1)))
                ((open-byte-p b)
                 (if (= depth 1) j (loop (- j 1) (- depth 1))))
                (else (loop (- j 1) depth)))))))

(define (forward-sexp-position get size i lispish)
  "The end of the expression after I, or #f at the end of a list."
  (let* ((j (skip-space-and-comments get size i lispish))
         (j (if lispish
                ;; prefixes: 'x `x ,x ,@x #'x #(...)
                (let loop ((j j))
                  (if (< j size)
                      (let ((b (get j)))
                        (cond ((byte-in b "'`,@") (loop (+ j 1)))
                              ((and (= b 35) (< (+ j 1) size) (byte-in (get (+ j 1)) "'("))
                               (loop (+ j 1)))
                              (else j)))
                      j))
                j)))
    (if (>= j size) #f
        (let ((b (get j)))
          (cond ((open-byte-p b) (list-end get size j lispish))
                ((close-byte-p b) #f)
                ;; Outside Lisp, delimiters are punctuation steps, not empty atoms.
                ((and (not lispish) (byte-in b ";,")) (+ j 1))
                ((= b 34) (string-end get size j))
                (else
                 (let loop ((j j))
                   (if (< j size)
                       (let ((c (get j)))
                         (cond ((= c 92) (loop (+ j 2)))
                               ((symbol-byte-p c lispish) (loop (+ j 1)))
                               (else (min j size))))
                       (min j size)))))))))

(define (backward-sexp-position get size i lispish)
  "The start of the expression before I, or #f at the start of a list."
  (let ((j (let loop ((j i)) (if (and (> j 0) (whitespace-byte (get (- j 1)))) (loop (- j 1)) j))))
    (if (<= j 0) #f
        (let* ((b (get (- j 1)))
               (j (cond ((and (close-byte-p b) (not (escaped-at-p get (- j 1)))) (list-start get j))
                        ((and (open-byte-p b) (not (escaped-at-p get (- j 1)))) #f)
                        ((= b 34) (string-start get j))
                        ((and (not lispish) (byte-in b ";,")) (- j 1))
                        (else
                         (let loop ((j j))
                           (if (and (> j 0)
                                    (let ((c (get (- j 1))))
                                      (or (symbol-byte-p c lispish)
                                          (escaped-at-p get (- j 1))
                                          (and (= c 92) (> j 1)))))
                               (loop (- j 1))
                               j))))))
          (if (and j lispish)
              (let loop ((j j)) (if (and (> j 0) (byte-in (get (- j 1)) "'`,@#")) (loop (- j 1)) j))
              j)))))

(define (up-list-position get i)
  "The open bracket of the list around I, or #f."
  (let loop ((j (- i 1)) (depth 0))
    (if (< j 0) #f
        (let ((b (get j)))
          (cond ((escaped-at-p get j) (loop (- j 1) depth))
                ((close-byte-p b) (loop (- j 1) (+ depth 1)))
                ((open-byte-p b) (if (= depth 0) j (loop (- j 1) (- depth 1))))
                (else (loop (- j 1) depth)))))))

(define (down-list-position get size i)
  "Just inside the next list after I, or #f."
  (let loop ((j i))
    (if (>= j size) #f
        (let ((b (get j)))
          (cond ((escaped-at-p get j) (loop (+ j 1)))
                ((= b 34) (loop (or (string-end get size j) size)))
                ((open-byte-p b) (+ j 1))
                ((close-byte-p b) #f)
                (else (loop (+ j 1))))))))

;;; definitions: a ( in column 0 in Lisp; elsewhere a line that starts in
;;; column 0 with a letter (int main(...), def f(...), theorem ...)

(define (defun-start-line-p get size ls lispish)
  (let ((b (get ls)))
    (and (< ls size)
         (if lispish (= b 40) (or (word-constituent-p b) (= b 95))))))

(define (beginning-of-defun-position get size i lispish)
  (let* ((ls (line-start-position get i))
         (ls (if (= ls i) (prev-line-start-position get ls) ls)))
    (let loop ((ls ls))
      (if (or (defun-start-line-p get size ls lispish) (= ls 0)) ls
          (loop (prev-line-start-position get ls))))))

(define (end-of-defun-position get size i lispish)
  (if lispish
      (let* ((start (beginning-of-defun-position get size (next-line-start get size i) #t))
             (end (and (defun-start-line-p get size start #t)
                       (forward-sexp-position get size start #t)))
             (end (if (or (not end) (<= end i))
                      ;; after it: the next one
                      (let ((ls (let loop ((ls (next-line-start get size i)))
                                  (if (or (>= ls size) (defun-start-line-p get size ls #t)) ls
                                      (loop (next-line-start get size ls))))))
                        (if (< ls size) (forward-sexp-position get size ls #t) size))
                      end)))
        (if end (next-line-start get size end) size))
      ;; a } in column 0 closes a C function; otherwise the next definition
      (let loop ((ls (next-line-start get size i)))
        (if (>= ls size) size
            (let ((b (get ls)))
              (cond ((= b 125) (next-line-start get size ls))
                    ((defun-start-line-p get size ls #f) ls)
                    (else (loop (next-line-start get size ls)))))))))

;;; ------------------------------------------------------------------
;;; Editing helpers
;;; ------------------------------------------------------------------

(define (count-characters s)
  "The characters of S: a string, or UTF-8 bytes."
  (if (string? s) (string-length s)
      (let loop ((i 0) (n 0))
        (if (>= i (bytevector-length s)) n
            (loop (+ i 1) (if (= (bitwise-and (bytevector-u8-ref s i) #xC0) #x80) n (+ n 1)))))))

(define (delete-region start end)
  "Delete the text between START and END (no kill ring)."
  (let ((a (min start end)) (b (max start end)))
    (when (< a b) (fe-delete-region a b) (goto-char a))
    #t))

(define (replace-region start end new)
  (delete-region start end)
  (goto-char (min start end))
  (when (> (string-length new) 0) (insert new))
  #t)

(define kill-between
  (case-lambda
    ((start end) (kill-between start end 'forward))
    ((start end direction)
  "Kill the text between START and END into the kill ring.  Consecutive
kills join into one entry, as in Emacs."
  (let ((a (min start end)) (b (max start end))
        (joining (and (eq? *last-command* 'kill-region) (pair? *kill-ring*)))
        (old-mark (mark)))
    (when (< a b)
      (let ((previous (and joining (car *kill-ring*))))
        (push-mark a)
        (goto-char b)
        (kill-region)
        (when previous
          (let* ((piece (car *kill-ring*))
                 (joined (if (eq? direction 'backward)
                             (string-append piece previous)
                             (string-append previous piece))))
            (set! *kill-ring* (cons joined (cddr *kill-ring*)))
            (set-clipboard joined)))
        (when (and old-mark (< old-mark a)) (push-mark old-mark))))
    (set! *this-command* 'kill-region)
    #t))))

(define (read-a-character question)
  "Ask for one key; the typed string (one character), or #f."
  (message question)
  (update-display)
  (let ((k (get-key)))
    (clear-message-line)
    (cond ((> (string-length k) 0) k)
          ((string=? (get-key-name) "SPC") " ")
          (else #f))))

(define (scan f . args) (apply f (buffer-reader) (buffer-size) args))

;;; ------------------------------------------------------------------
;;; Motion
;;; ------------------------------------------------------------------

(defcommand (forward-word-command) (goto-char (scan forward-word-position (point))))
(defcommand (backward-word-command) (goto-char (scan backward-word-position (point))))
(defcommand (forward-sentence) (goto-char (scan forward-sentence-position (point))))
(defcommand (backward-sentence) (goto-char (scan backward-sentence-position (point))))
(defcommand (forward-paragraph) (goto-char (scan forward-paragraph-position (point))))
(defcommand (backward-paragraph) (goto-char (scan backward-paragraph-position (point))))
(defcommand (back-to-indentation) (goto-char (scan indentation-end (line-start))))

(defcommand (forward-sexp)
  (let ((e (scan forward-sexp-position (point) (lisp-buffer-p))))
    (if e (goto-char e) (message "No expression after the cursor"))))

(defcommand (backward-sexp)
  (let ((s (scan backward-sexp-position (point) (lisp-buffer-p))))
    (if s (goto-char s) (message "No expression before the cursor"))))

(defcommand (backward-up-list)
  (let ((s (up-list-position (buffer-reader) (point))))
    (if s (goto-char s) (message "Not inside a list"))))

(defcommand (down-list)
  (let ((s (scan down-list-position (point))))
    (if s (goto-char s) (message "No list ahead"))))

(defcommand (beginning-of-defun) (goto-char (scan beginning-of-defun-position (point) (lisp-buffer-p))))
(defcommand (end-of-defun) (goto-char (scan end-of-defun-position (point) (lisp-buffer-p))))

;;; ------------------------------------------------------------------
;;; Killing
;;; ------------------------------------------------------------------

(defcommand (kill-word) (kill-between (point) (scan forward-word-position (point))))
(defcommand (backward-kill-word)
  (kill-between (scan backward-word-position (point)) (point) 'backward))

(defcommand (kill-sexp)
  (let ((e (scan forward-sexp-position (point) (lisp-buffer-p))))
    (if e (kill-between (point) e) (message "No expression after the cursor"))))

(defcommand (kill-sentence) (kill-between (point) (scan forward-sentence-position (point))))

(define (all-blank? s)
  (let loop ((i 0)) (cond ((>= i (string-length s)) #t) ((blank-byte (c@ s i)) (loop (+ i 1))) (else #f))))

(defcommand (kill-line-command)
  "C-k: kill to the end of the line, or the line end itself when only
blanks are left.  Consecutive C-k's join in the kill ring."
  (let* ((p (point))
         (e (scan line-end-position p))
         (rest (buffer-substring p e)))
    (cond ((>= p (buffer-size)) (message "End of buffer"))
          ((all-blank? rest) (kill-between p (min (buffer-size) (+ e 1))))
          (else (kill-between p e)))))

(defcommand (zap-to-char)
  (let ((c (read-a-character "Zap to char: ")))
    (when c
      ;; the character's first byte, then all of them
      (let* ((p (point)) (size (buffer-size)) (b0 (bytevector-u8-ref (string->utf8 c) 0))
             (found (let loop ((i p)) (cond ((>= i size) #f) ((= (buffer-get i) b0) i) (else (loop (+ i 1)))))))
        (if found
            (kill-between p (min size (+ found (bytes-length c))))
            (message c " not found"))))))

;;; yanking: C-y remembers what it inserted, so that M-y can replace it

(define *yank-start* 0)
(define *yank-end* 0)
(define *yank-index* 0)

(defcommand (yank-command)
  "C-y: insert the last killed text, or what another program copied since;
M-y right after replaces it with earlier kills."
  (let ((start (point)))
    (adopt-system-clipboard)
    (yank)
    (clipboard-helper-missing-notice)
    (set! *yank-start* start)
    (set! *yank-end* (point))
    (set! *yank-index* 0)
    (push-mark start)
    (set! *this-command* 'yank)))

(defcommand (yank-pop)
  (cond ((not (memq *last-command* '(yank yank-pop))) (message "M-y works right after C-y"))
        ((null? *kill-ring*) (message "The kill ring is empty"))
        (else
         (set! *yank-index* (modulo (+ *yank-index* 1) (length *kill-ring*)))
         (let ((text (list-ref *kill-ring* *yank-index*)))
           (replace-region *yank-start* *yank-end* text)
           (set! *yank-end* (point))
           (set-clipboard text)
           (message "Kill ring " (+ 1 *yank-index*) "/" (length *kill-ring*))
           (set! *this-command* 'yank-pop)))))

;;; ------------------------------------------------------------------
;;; Changing text
;;; ------------------------------------------------------------------

(defcommand (transpose-chars)
  (let* ((p (point)) (size (buffer-size))
         (at-end (or (>= p size) (= (buffer-get p) 10)))
         (b (if at-end (char-start-before buffer-get p) p))
         (a (char-start-before buffer-get b))
         (c (if at-end p (char-end buffer-get size p))))
    (if (or (= p 0) (= a b))
        (message "Nothing to transpose")
        (replace-region a c (string-append (buffer-substring b c) (buffer-substring a b))))))

(defcommand (transpose-words)
  (let* ((a (scan backward-word-position (point)))
         (b (scan forward-word-position a))
         (c (scan forward-word-position b))
         (d (scan backward-word-position c)))
    (if (or (<= c b) (< d b) (= a b))
        (message "Need two words")
        (replace-region a c (string-append (buffer-substring d c)
                                           (buffer-substring b d)
                                           (buffer-substring a b))))))

(defcommand (transpose-lines)
  (let ((ls (line-start)))
    (if (= ls 0)
        (message "No line above")
        (let* ((pls (line-start (- ls 1)))
               (le (line-end ls))
               (previous (buffer-substring pls (- ls 1)))
               (current (buffer-substring ls le)))
          (replace-region pls le (string-append current "\n" previous))
          (goto-char (min (buffer-size) (+ 1 (point))))))))

(define (string-capitalize s)
  (let loop ((cs (string->list s)) (in-word #f) (acc '()))
    (if (null? cs) (list->string (reverse acc))
        (let* ((c (car cs)) (word (or (char-alphabetic? c) (char-numeric? c))))
          (loop (cdr cs) word
                (cons (cond ((not word) c) (in-word (char-downcase c)) (else (char-upcase c))) acc))))))

(define (transform-word f)
  (let* ((p (point)) (e (scan forward-word-position p)))
    (when (< p e) (replace-region p e (f (buffer-substring p e))))))

(defcommand (upcase-word) (transform-word string-upcase))
(defcommand (downcase-word) (transform-word string-downcase))
(defcommand (capitalize-word) (transform-word string-capitalize))

(defcommand (open-line) (insert "\n") (backward-char))

(defcommand (delete-horizontal-space)
  (let ((a (let loop ((a (point))) (if (and (> a 0) (blank-byte (buffer-get (- a 1)))) (loop (- a 1)) a)))
        (b (let loop ((b (point))) (if (and (< b (buffer-size)) (blank-byte (buffer-get b))) (loop (+ b 1)) b))))
    (delete-region a b)))

(defcommand (just-one-space) (delete-horizontal-space) (insert " "))

(defcommand (delete-indentation)
  "M-^: join this line to the previous one."
  (let ((ls (line-start)))
    (if (= ls 0)
        (message "No line above")
        (let* ((a (let loop ((a (- ls 1))) (if (and (> a 0) (blank-byte (buffer-get (- a 1)))) (loop (- a 1)) a)))
               (b (let loop ((b ls)) (if (and (< b (buffer-size)) (blank-byte (buffer-get b))) (loop (+ b 1)) b)))
               (before (if (> a 0) (buffer-get (- a 1)) 10))
               (after (buffer-get b)))
          (replace-region a b (if (or (= before 10) (= before 40) (= after 41) (= after -1) (= after 10))
                                  "" " "))
          (goto-char a)))))

(defcommand (delete-blank-lines)
  "C-x C-o: on a blank line, leave one blank line (or none when it is
alone); on a text line, delete the blank lines after it."
  (let* ((size (buffer-size))
         (ls (line-start))
         (blank (lambda (x) (blank-line-p buffer-get size x))))
    (if (blank ls)
        (let ((a (let loop ((a ls)) (if (and (> a 0) (blank (line-start (- a 1)))) (loop (line-start (- a 1))) a)))
              (b (let loop ((b ls)) (if (and (< b size) (blank b)) (loop (min size (+ 1 (line-end b)))) b))))
          (if (and (= a ls) (= b (min size (+ 1 (line-end ls)))))
              (delete-region a b)
              (replace-region a b "\n"))
          (goto-char a))
        (let* ((b (min size (+ 1 (line-end ls))))
               (c (let loop ((c b)) (if (and (< c size) (blank c)) (loop (min size (+ 1 (line-end c)))) c)))
               (p (point)))
          (delete-region b c)
          (goto-char p)))))

;;; filling

(define *fill-column* 70)

(define (line-comment-start)
  "The line comment (\";;\" for Lisp) of the language at the cursor (a
Markdown ```scheme block is Scheme), or #f."
  (let* ((lang (language-at-point))
         (comments (and lang (language-line-comments lang))))
    (and (pair? comments)
         (let ((s (car comments))) (if (string=? s ";") ";;" s)))))

(define (text-buffer-p)
  (let ((lang (language-for-file (or (buffer-filename) (get-buffer-name)))))
    (or (not lang) (string=? (language-name lang) "Text")
        (and (member (language-name lang) '("TeX" "Markdown" "Org")) #t))))

(define (blank-char? c) (or (char=? c #\space) (char=? c #\tab)))

;; SKIP-BLANK-CHARS is in languages/markdown.scm, which comes first

;; the code of the character at I of the string S
(define (c@ s i) (char->integer (string-ref s i)))
;; femtoscheme's (byte-substring s start [end]), on the characters of S
(define %sub
  (case-lambda
    ((s start) (substring s start (string-length s)))
    ((s start end) (substring s start end))))

(define (list-item-prefix line)
  "If LINE is a Markdown list item (- x, * x, + x, 1. x, 1) x), its
indentation and marker with the spaces after it; else #f."
  (let* ((n (string-length line))
         (i (skip-blank-chars line 0))
         (j (cond ((>= i n) #f)
                  ((memv (c@ line i) '(45 42 43)) (+ i 1))
                  ((and (<= 48 (c@ line i)) (<= (c@ line i) 57))
                   (let ((k (let loop ((k i)) (if (and (< k n) (and (<= 48 (c@ line k)) (<= (c@ line k) 57))) (loop (+ k 1)) k))))
                     (and (< k n) (memv (c@ line k) '(46 41)) (+ k 1))))
                  (else #f))))
    (and j (< j n) (= (c@ line j) 32)
         (%sub line 0 (let loop ((k j)) (if (and (< k n) (= (c@ line k) 32)) (loop (+ k 1)) k))))))

(define (left-trim-blanks line) (%sub line (skip-blank-chars line 0)))

(define (block-start-line-p line)
  "Does LINE begin a Markdown block: a list item, heading, quotation,
fence or table row?"
  (let ((l (left-trim-blanks line)))
    (or (list-item-prefix line)
        (and (> (string-length l) 0) (memv (c@ l 0) '(35 62 124)) #t)
        (starts-with-p "```" l) (starts-with-p "~~~" l))))

(define (unfillable-line-p line)
  "Headings, fences and tables are never refilled."
  (let ((l (left-trim-blanks line)))
    (and (> (string-length l) 0)
         (or (and (memv (c@ l 0) '(35 124)) #t)
             (starts-with-p "```" l) (starts-with-p "~~~" l)))))

(define (org-heading-text-p line)
  "Is LINE an Org heading (stars from the first column, then a blank)?
M-q in Org stops at it, whatever its level."
  (let ((n (string-length line)))
    (let loop ((i 0))
      (cond ((and (< i n) (char=? (string-ref line i) #\*)) (loop (+ i 1)))
            (else (and (> i 0) (or (= i n) (memv (string-ref line i) '(#\space #\tab))) #t))))))

(define (fill-prefix-of line comment)
  "Leading blanks of LINE, plus the comment marker and one space when LINE
is a comment."
  (let* ((n (string-length line))
         (i (skip-blank-chars line 0))
         (rest (%sub line i)))
    (if (and comment (> (string-length comment) 0) (starts-with-p comment rest))
        (let* ((c0 (c@ comment 0))
               (j (let loop ((j (+ i (string-length comment)))) (if (and (< j n) (= (c@ line j) c0)) (loop (+ j 1)) j)))
               (k (skip-blank-chars line j)))
          (%sub line 0 (min k (+ j 1))))
        (%sub line 0 i))))

(define fill-words
  (case-lambda
    ((words prefix width) (fill-words words prefix width prefix))
    ((words prefix width rest-prefix)
  "Lines of at most WIDTH columns (when possible).  A line is made once,
when it is full: made again with each word it took, it cost a string for
every word (tests/complexity.sh)."
  (let loop ((words words) (pre #f) (line '()) (n 0) (lines '()))
    (cond ((null? words) (reverse (if pre (cons (filled-line pre line) lines) lines)))
          ((not pre)
           (loop (cdr words) prefix (list (car words))
                 (+ (string-length prefix) (string-length (car words))) lines))
          ((> (+ n 1 (string-length (car words))) width)
           (loop (cdr words) rest-prefix (list (car words))
                 (+ (string-length rest-prefix) (string-length (car words)))
                 (cons (filled-line pre line) lines)))
          (else (loop (cdr words) pre (cons (car words) line)
                      (+ n 1 (string-length (car words))) lines)))))))

;; PREFIX and the WORDS (newest first) of a line, a space between them
(define (filled-line prefix words)
  (string-append prefix (string-join (reverse words) " ")))

;; The lines of the bytes V, as strings, cut at the newlines (one pass: a
;; split at every character took a fifth of a second for 344 KB)
(define (byte-lines v)
  (let ((n (bytevector-length v)))
    (let loop ((i 0) (start 0) (acc '()))
      (cond ((= i n) (reverse (cons (utf8->string v start n) acc)))
            ((= (bytevector-u8-ref v i) 10) (loop (+ i 1) (+ i 1) (cons (utf8->string v start i) acc)))
            (else (loop (+ i 1) start acc))))))

(define (split-words s)
  "The words of S, between spaces, tabs and newlines.  One pass over its
bytes: replacing the tabs and newlines, splitting at spaces and dropping
the empty pieces took a second for 50,000 words (tests/complexity.sh)."
  (let* ((v (%utf8 s)) (n (bytevector-length v)))
    (let loop ((i 0) (start -1) (acc '()))
      (if (= i n)
          (reverse (if (>= start 0) (cons (utf8->string v start n) acc) acc))
          (let ((b (bytevector-u8-ref v i)))
            (if (or (= b 32) (= b 9) (= b 10))
                (loop (+ i 1) -1 (if (>= start 0) (cons (utf8->string v start i) acc) acc))
                (loop (+ i 1) (if (< start 0) i start) acc)))))))

;; M-q never starts a line with a word that would turn the line into
;; something else: a list item (1935.  2)  -  +), a heading (*  ##), a
;; quotation (>), a table row (|...) or Org's fixed-width text (:).  A
;; reference pasted from the Internet put "1935." first on a line, and the
;; LaTeX export made it an enumerate item and lost the year (15 November
;; 2026); Org in Emacs has the same rule (fill-nobreak-predicate).  Such a
;; word is glued to the word before it, so the line breaks before both.
(define (fill-break-word-p w)
  (let ((n (string-length w)))
    (and (> n 0)
         (let ((c (c@ w 0)))
           (or (and (= n 1) (memv c '(45 43 62 58)) #t)
               (= c 124)
               (let same ((i 0)) (cond ((= i n) #t) ((= (c@ w i) 42) (same (+ i 1))) (else #f)))
               (and (<= n 6) (let same ((i 0)) (cond ((= i n) #t) ((= (c@ w i) 35) (same (+ i 1))) (else #f))))
               (and (>= n 2) (memv (c@ w (- n 1)) '(46 41))
                    (let digits ((i 0))
                      (cond ((= i (- n 1)) #t)
                            ((and (<= 48 (c@ w i)) (<= (c@ w i) 57)) (digits (+ i 1)))
                            (else #f)))))))))

(define (glue-break-words words)
  (let loop ((ws words) (acc '()))
    (cond ((null? ws) (reverse acc))
          ((and (pair? acc) (fill-break-word-p (car ws)))
           (loop (cdr ws) (cons (string-append (car acc) " " (car ws)) (cdr acc))))
          (else (loop (cdr ws) (cons (car ws) acc))))))

;; WORDS reversed onto ACC: the words of a paragraph are gathered line by
;; line so, newest first; appended to the list of all the words before, each
;; line copied that list, and M-q on 5,000 lines of 50,000 words took minutes
;; (tests/complexity.sh)
(define (prepend-reversed words acc)
  (if (null? words) acc (prepend-reversed (cdr words) (cons (car words) acc))))

(define (fill-text lines comment width)
  "Refill LINES of one paragraph; the first line gives the prefix.  A list
item keeps its marker, and the lines after it go under its text."
  (let* ((item (and (not comment) (list-item-prefix (car lines))))
         (prefix (or item (fill-prefix-of (car lines) comment)))
         (rest-prefix (if item (make-spaces (string-length item)) prefix))
         (words (let loop ((ls lines) (first #t) (acc '()))
                  (if (null? ls) (reverse acc)
                      (let* ((line (car ls))
                             (p (if (and first item) item (fill-prefix-of line comment))))
                        (loop (cdr ls) #f
                              (prepend-reversed (split-words (%sub line (min (string-length p) (string-length line)))) acc)))))))
    (join-lines (fill-words (glue-break-words words) prefix width rest-prefix))))

;; M-q in a block comment (Lean's /- -/ and /-- -/, C's /* */): the
;; paragraph is the comment's lines between blank lines, and never takes in
;; the comment's markers.  The C tokenizer says whether the line is in one
;; (fe-syntax-open, as for M-;).  Lean files are mostly such comments, and
;; M-q answered "fills comments and text, not code" there (21 Nov 2026).
(define (block-comment-around ls le)
  "(open-position open close) of the block comment containing the line at
LS (ending at LE), or #f."
  (let* ((lang (language-at-point))
         (id (and lang (not (language-highlighter lang)) (language-token-id lang)))
         (pairs (if lang (language-block-comments lang) '()))
         (size (buffer-size)))
    (define (opened-at o)
      (and (>= o 0)
           (let loop ((ps pairs))
             (and (pair? ps)
                  (let* ((open (caar ps)) (n (bytes-length open)))
                    (if (and (<= (+ o n) size) (string=? (buffer-substring o (+ o n)) open))
                        (list o open (cdar ps))
                        (loop (cdr ps))))))))
    ;; a comment that opens and closes on this line: its marker, where
    ;; nothing (a string, a -- comment) is open
    (define (opened-on-line)
      (let loop ((ps pairs))
        (and (pair? ps)
             (let ((at (fe-buffer-search (caar ps) ls le)))
               (if (and (>= at 0) (= (fe-syntax-open id base at) -1))
                   (list at (caar ps) (cdar ps))
                   (loop (cdr ps)))))))
    ;; one scan of the text above: what is open at LS; from there (or from
    ;; LS) to the end of the line is short
    (define at-ls (if (and id (pair? pairs)) (fe-syntax-open id 0 ls) -1))
    (define base (if (>= at-ls 0) at-ls ls))
    (and id (pair? pairs)
         (or (opened-at at-ls)
             (opened-at (fe-syntax-open id base le))
             (opened-on-line)))))

(define (fill-block-comment ls)
  "Refill the paragraph of the block comment at the line LS; #f when the
line is in none."
  (let* ((le (line-end ls))
         (found (block-comment-around ls le)))
    (and found
         (let* ((size (buffer-size))
                (o (car found)) (open (cadr found)) (close (caddr found))
                ;; the text starts after the marker and the bytes that
                ;; decorate it: /-- /-! /**
                ;; Find the closing marker before skipping decoration. In
                ;; /**/ the decorative star also starts the closing marker.
                (rc (let ((c (fe-buffer-search close (+ o (bytes-length open)) size)))
                      (if (< c 0) size c)))
                (ro (let skip ((i (+ o (bytes-length open))))
                      (if (and (< i rc) (let ((c (buffer-get i)))
                                             (and (> c 32) (< c 128)
                                                  (not (or (and (<= 48 c) (<= c 57)) (and (<= 65 c) (<= c 90))
                                                           (and (<= 97 c) (<= c 122)))))))
                          (skip (+ i 1)) i)))
                (deco (and (> (string-length open) 0)
                           (char=? (string-ref open (- (string-length open) 1)) #\*) "*"))
                ;; the part of the line at S inside the comment
                (part (lambda (s) (buffer-substring (max s ro) (min (line-end s) rc))))
                (blank? (lambda (s) (string=? (trim (part s)) "")))
                (first-line (line-start ro))
                (last-line (line-start rc)))
           (cond ((or (< ls first-line) (> ls last-line)) #f)
                 ((blank? ls) (message "No paragraph here") #t)
                 (else
                  (let* ((top (let up ((s ls))
                                (if (and (> s first-line) (not (blank? (line-start (- s 1)))))
                                    (up (line-start (- s 1))) s)))
                         (bottom (let down ((s ls))
                                   (let ((next (+ 1 (line-end s))))
                                     (if (and (<= next last-line) (< next size) (not (blank? next)))
                                         (down next) s))))
                         ;; on the marker's line the text starts after it
                         (a (if (= top first-line)
                                (let sk ((i ro)) (if (and (< i rc) (memv (buffer-get i) '(32 9))) (sk (+ i 1)) i))
                                top))
                         (b (let back ((i (min (line-end bottom) rc)))
                              (if (and (> i a) (memv (buffer-get (- i 1)) '(32 9))) (back (- i 1)) i)))
                         (lines (let loop ((s top) (acc '()))
                                  (let ((acc (cons (buffer-substring (max s a) (min (line-end s) b)) acc)))
                                    (if (>= s bottom) (reverse acc) (loop (+ 1 (line-end s)) acc)))))
                         (lead (string-length (buffer-substring (line-start a) a)))
                         (rest-prefix (cond ((pair? (cdr lines)) (fill-prefix-of (cadr lines) deco))
                                            ((= a top) (fill-prefix-of (car lines) deco))
                                            (else (fill-prefix-of (buffer-substring top a) #f))))
                         (first-prefix (if (= a top) (fill-prefix-of (car lines) deco) ""))
                         (words (let loop ((ls lines) (first #t) (acc '()))
                                  (if (null? ls) (reverse acc)
                                      (let* ((line (car ls))
                                             (p (if (and first (not (= a top))) "" (fill-prefix-of line deco))))
                                        (loop (cdr ls) #f
                                              (prepend-reversed (split-words (%sub line (min (string-length p) (string-length line)))) acc))))))
                         ;; the first line already has LEAD columns before A
                         (filled (fill-words (glue-break-words words)
                                             (string-append (make-spaces (if (= a top) 0 lead)) first-prefix)
                                             *fill-column* rest-prefix))
                         (new (let ((text (join-lines filled)))
                                (if (= a top) text (%sub text (min lead (string-length text)))))))
                    (unless (string=? new (buffer-substring a b))
                      (replace-region a b new))
                    (goto-char (+ a (bytes-length new)))
                    #t)))))))

(defcommand (fill-paragraph)
  "M-q: refill the paragraph (or comment block) at the cursor to
*FILL-COLUMN* columns."
  (let* ((size (buffer-size))
         ;; the text read through one reader (blocks of 64 KB): a call to C
         ;; for each line's start, end and text made M-q on 5,000 lines take
         ;; seconds (tests/complexity.sh)
         (get (buffer-reader))
         (line-start (lambda (i) (line-start-position get i)))
         (line-end (lambda (i) (line-end-position get size i)))
         (buffer-substring (lambda (a b) (reader-substring get a b)))
         (ls (line-start (point)))
         (here (buffer-substring ls (line-end ls)))
         (text-mode (text-buffer-p))
         (lang (language-for-file (or (buffer-filename) (get-buffer-name))))
         (org (and lang (string=? (language-name lang) "Org")))
         (md (and lang (string=? (language-name lang) "Markdown")))
         (comment (if (and text-mode (starts-with-p ">" (string-trim here))) ">" (line-comment-start)))
         (prefix (fill-prefix-of here comment))
         (in-comment (and comment (string-search comment prefix) #t))
         ;; the text of the line at START; the last asked is kept, since
         ;; the walk down the paragraph asks each line twice
         (line-at (let ((at -1) (text ""))
                    (lambda (start)
                      (unless (= start at)
                        (set! text (buffer-substring start (line-end start)))
                        (set! at start))
                      text)))
         ;; Inside a paragraph only "1." or "1)" starts a list (CommonMark);
         ;; "1935." there is text, so M-q takes it into the paragraph -- a
         ;; reference pasted with the break already in it.  In Org too,
         ;; though Org (and Emacs) would read it as an item: Eduardo pressed
         ;; M-q on such a reference and expected the year back in its line.
         (md-text-number?
          (lambda (start)
            (and (or md org) (not in-comment) (> start 0)
                 (let* ((p (list-item-prefix (line-at start)))
                        (m (and p (left-trim-blanks p))))
                   (and m (> (string-length m) 0) (<= 48 (c@ m 0)) (<= (c@ m 0) 57)
                        (not (starts-with-p "1. " m)) (not (starts-with-p "1) " m))))
                 ;; the lines above, back to a blank line or a heading,
                 ;; are text: none is an item (then it would be a list)
                 (let up ((s (line-start (- start 1))) (seen #f))
                   (let ((text (line-at s)))
                     (cond ((blank-line-p get size s) seen)
                           ((and org (org-heading-text-p text)) seen)
                           ((list-item-prefix text) #f)
                           ((block-start-line-p text) seen)
                           ((= s 0) #t)
                           (else (up (line-start (- s 1)) #t))))))))
         (member-line-p
          (lambda (start)
            (let ((text (line-at start)))
              (and (not (blank-line-p get size start))
                   (not (and text-mode (unfillable-line-p text)))
                   (not (and org (org-heading-text-p text)))
                   (if in-comment (and (string-search comment (fill-prefix-of text comment)) #t) #t))))))
    (cond ((and (not text-mode) (fill-block-comment ls)))
          ((blank-line-p get size ls) (message "No paragraph here"))
          ((not (or in-comment text-mode)) (message "M-q fills comments and text, not code"))
          ((and text-mode (or (unfillable-line-p here)
                              ;; org.scm: an Org heading, or a line in a #+BEGIN_ block
                              (and (top-level-bound? 'org-fill-refused?)
                                   ((top-level-value 'org-fill-refused?) ls))))
           (message "Headings, tables and code are not refilled"))
          (else
           (let* ((a (let loop ((a ls))
                       (if (and (> a 0)
                                (not (and text-mode (not in-comment) (block-start-line-p (line-at a))
                                          (not (md-text-number? a))))
                                (member-line-p (line-start (- a 1))))
                           (loop (line-start (- a 1)))
                           a)))
                  (b (let loop ((b ls))
                       (let ((next (min size (+ 1 (line-end b)))))
                         (if (and (< next size) (> next b) (member-line-p next)
                                  (not (and text-mode (not in-comment) (block-start-line-p (line-at next))
                                            (not (md-text-number? next)))))
                             (loop next)
                             b))))
                  (end (line-end b))
                  ;; the paragraph's text read at once, then cut at its newlines
                  (bytes (buffer-bytes a end))
                  (old (utf8->string bytes))
                  (lines (byte-lines bytes))
                  (new (fill-text lines comment *fill-column*)))
             (unless (string=? new old)
               (replace-region a end new))
             (goto-char (min (buffer-size) (+ a (bytes-length new)))))))))

;;; comments

(defvar *comment-column* 32)

(define (line-comment-position-bytes text start language)
  "Find a line-comment run starting on this line, preserving earlier syntax state."
  (let* ((lang (cond ((not language) *default-language*)
                     ((string? language) (or (find-language language) (language-for-file language)))
                     (else language)))
         (len (bytevector-length text))
         (colors (make-colors len)))
    ;; Tokenize the whole language prefix, but inspect only this line.  Building
    ;; highlight-string's substring runs walked and copied every earlier token.
    (highlight-octets lang text len colors)
    (let loop ((i start))
      (cond ((>= i len) #f)
            ((and (= (bytevector-u8-ref colors i) +comment+)
                  (or (= i 0) (not (= (bytevector-u8-ref colors (- i 1)) +comment+)))) i)
            (else (loop (+ i 1)))))))

(define (line-comment-position text start language)
  "Find a real line comment, ignoring markers inside strings and block comments."
  (line-comment-position-bytes (%utf8 text) start language))

(defcommand (comment-dwim)
  "M-;: toggle region comments, or insert/align this line's comment."
  (let ((comment (line-comment-start)))
    (cond ((not comment) (message "No comment syntax for this file"))
          ((and (region-active-p) (not (= (point) (mark))))
           (comment-region-lines comment))
          (else
           ;; the text in the cursor's language: the buffer, or the block
           ;; of a Markdown ``` fence; FROM is where it starts
           (let* ((ls (line-start)) (le (line-end ls))
                  (place (language-place))
                  (language (car place))
                  ;; Where the line's text stands: inside a string or a block
                  ;; comment that began on an earlier line, or not.  The C
                  ;; tokenizer of the language answers, as Emacs's
                  ;; parse-partial-sexp does, scanning from the start of the
                  ;; language's text without copying it here; then only this
                  ;; line, or the string or comment it continues, is lexed in
                  ;; Scheme.  A language with a highlighter of its own (Python,
                  ;; Nim) still lexes from the start.
                  (from (let* ((start (cdr place))
                               (lang (cond ((not language) *default-language*)
                                           ((string? language) (or (find-language language)
                                                                   (language-for-file language)))
                                           (else language)))
                               (id (and (not (language-highlighter lang)) (language-token-id lang)))
                               (open (if id (fe-syntax-open id start ls) -2)))
                          (cond ((>= open 0) open)
                                ((= open -1) ls)
                                (else start))))
                  (text (buffer-bytes from le))
                  (found (let ((at (line-comment-position-bytes text (- ls from) language)))
                           (and at (+ at from))))
                  (single (if (string=? comment ";;") ";" comment))
                  (end (or found le))
                  (code-end (let loop ((i end))
                              (if (and (> i ls) (memv (b@ text (- i from 1)) '(32 9)))
                                  (loop (- i 1)) i))))
             (cond ((= code-end ls)
                    (goto-char (or found le))
                    (unless found (insert comment " ")))
                   (else
                    (replace-region code-end end
                      (make-string (max 1 (- *comment-column* (column-at text (- code-end from)))) #\space))
                    (unless found (insert single " "))))
             (when found
               ;; Re-read the end after alignment changes the byte offsets.
               (let ((end (line-end)))
                 (let loop ()
                   (when (and (< (point) end)
                              (byte-in (buffer-get (point)) (string-append single " \t")))
                     (forward-char) (loop))))))))))

(define (comment-region-lines comment)
  (let* ((a (line-start (min (point) (mark))))
         (z (max (point) (mark)))
         (z (if (and (> z a) (= (buffer-get (- z 1)) 10)) (- z 1) z))
         (b (line-end z))
         (lines (split-lines (buffer-substring a b)))
         (code (filter (lambda (l) (not (string=? (trim l) ""))) lines))
         (commented (and (pair? code)
                         (every (lambda (l) (starts-with-p comment (left-trim-blanks l))) code)))
         (column (if (pair? code) (apply min (map (lambda (l) (skip-blank-chars l 0)) code)) 0))
         (new (map (lambda (l)
                     (cond ((string=? (trim l) "") l)
                           (commented
                            (let* ((i (string-search comment l))
                                   (j (+ i (string-length comment)))
                                   (j (if (and (< j (string-length l)) (= (c@ l j) 32)) (+ j 1) j)))
                              (string-append (%sub l 0 i) (%sub l j))))
                           (else (string-append (%sub l 0 column) comment " " (%sub l column)))))
                   lines)))
    (replace-region a b (join-lines new))
    (deactivate-mark)
    (message (if commented "Uncommented " "Commented ") (plural (length lines) "line"))))

;;; ------------------------------------------------------------------
;;; Mark and region
;;; ------------------------------------------------------------------

(defcommand (keyboard-quit) (deactivate-mark) (message "Quit"))

(defcommand (set-mark-command)
  "C-SPC: set the mark here and start a region.  Again at the same place
deactivates the region."
  (if (and (region-active-p) (eqv? (mark) (point)))
      (begin (deactivate-mark) (message "Mark deactivated"))
      (begin (set-mark) (message "Mark set"))))

(defcommand (mark-whole-buffer) (set-mark (buffer-size)) (goto-char 0) (message "Mark set"))

(defcommand (exchange-point-and-mark)
  (let ((m (mark)))
    (if (not m) (message "No mark set") (begin (set-mark (point)) (goto-char m)))))

(defcommand (mark-paragraph)
  (let* ((end (scan forward-paragraph-position (point)))
         (start (scan backward-paragraph-position end)))
    (set-mark end)
    (goto-char start)))

(defcommand (mark-word)
  (let ((from (if (region-active-p) (mark) (point))))
    (set-mark (scan forward-word-position from))))

(defcommand (mark-sexp)
  (let* ((from (if (region-active-p) (mark) (point)))
         (e (scan forward-sexp-position from (lisp-buffer-p))))
    (if e (set-mark e) (message "No expression after the cursor"))))

(defcommand (copy-region-command)
  "M-w: copy the region; the shading goes away."
  (let ((nonempty (and (mark) (not (= (mark) (point))))))
    (copy-region)
    (when nonempty (remember-kill (get-buffer-name))))
  (deactivate-mark)
  (set! *this-command* 'copy-region))

;;; ------------------------------------------------------------------
;;; Buffers, files, windows
;;; ------------------------------------------------------------------

(define *buffer-picker-buffer* "*buffer-pick*")
(define *buffer-picker-max-keys* 1000)
(define *previous-picked-buffer* #f)

(define (string-prefix-equal prefix s)
  (and (<= (string-length prefix) (string-length s)) (string-ci=? prefix (substring s 0 (string-length prefix)))))

(define (buffer-picker-matches query names)
  (filter (lambda (name) (string-prefix-equal query name)) names))

(define (buffer-picker-common-prefix names)
  "The case-preserving common prefix of NAMES, or \"\"."
  (if (null? names) ""
      (let* ((first (car names))
             (limit (apply min (map string-length names))))
        (let loop ((i 0))
          (if (and (< i limit)
                   (every (lambda (name) (char-ci=? (string-ref first i) (string-ref name i))) (cdr names)))
              (loop (+ i 1))
              (substring first 0 i))))))

(define (buffer-names)
  "The live buffer names, in the core's order; the visible buffer stays."
  (let ((origin (get-buffer-name)))
    (let loop ((i 0) (names '()))
      (if (< i (get-buffer-count))
          (let ((name (get-buffer-name)))
            (execute-builtin "next-buffer")
            (loop (+ i 1) (if (member name names) names (cons name names))))
          (begin (select-buffer origin) (reverse names))))))

(define (buffer-picker-buffer-names)
  (filter (lambda (n) (not (string=? n *buffer-picker-buffer*))) (buffer-names)))

(define (list-index-of x lst)
  (let loop ((l lst) (i 0)) (cond ((null? l) #f) ((equal? (car l) x) i) (else (loop (cdr l) (+ i 1))))))

(define (buffer-picker-initial-index matches origin)
  (or (and *previous-picked-buffer* (list-index-of *previous-picked-buffer* matches))
      (let loop ((l matches) (i 0))
        (cond ((null? l) #f) ((not (string=? (car l) origin)) i) (else (loop (cdr l) (+ i 1)))))
      0))

(define (erase-buffer) (fe-delete-region 0 (buffer-size)) (goto-char 0))

(define (render-buffer-picker query matches selected)
  (select-buffer *buffer-picker-buffer*)
  (erase-buffer)
  (insert "Switch to buffer\nType to filter; TAB completes; arrows select; RET opens; C-g cancels.\n\nFilter: " query)
  (let ((input-point (point)))
    (insert "\n\n")
    (if (pair? matches)
        (let loop ((l matches) (i 0))
          (when (pair? l)
            (insert (if (= i selected) "> " "  ") (car l) "\n")
            (loop (cdr l) (+ i 1))))
        (insert "  No matching buffers\n"))
    (goto-char input-point)
    (fe-set-modified 0)
    (update-display)))

(define (buffer-picker-bound-action)
  (let ((name (get-key-name)) (binding (get-key-binding)))
    (cond ((or (string=? name "C-g") (string=? binding "keyboard-quit")) 'cancel)
          ((or (string=? binding "previous-line") (string=? name "C-p")) 'previous)
          ((or (string=? binding "next-line") (string=? name "C-n")) 'next)
          ((or (string=? binding "backspace") (string=? binding "delete-left")) 'backspace)
          (else #f))))

(define (buffer-picker-key-action key)
  (cond ((or (string=? key "\n") (string=? key "\r")) 'accept)
        ((string=? key "\t") 'complete)
        ((string=? key "") (buffer-picker-bound-action))
        (else 'insert)))

(defcommand (switch-to-buffer)
  "C-x b: choose a live buffer with filtering and completion."
  (let* ((origin (get-buffer-name))
         (names (buffer-picker-buffer-names))
         (query "")
         (selected (buffer-picker-initial-index names origin))
         (answer #f)
         (cancelled #f))
    (set-buffer-hint *buffer-picker-buffer* "type filter; TAB complete; arrows select; RET open; C-g cancel")
    (dynamic-wind
     (lambda () #f)
     (lambda ()
       (let loop ((n 0))
         (when (and (< n *buffer-picker-max-keys*) (not answer) (not cancelled))
           (let* ((matches (buffer-picker-matches query names))
                  (count (length matches)))
             (set! selected (if (> count 0) (min selected (- count 1)) 0))
             (render-buffer-picker query matches selected)
             (let* ((key (get-key)) (action (buffer-picker-key-action key)))
               (case action
                 ((cancel) (set! cancelled #t))
                 ((accept) (when (> count 0) (set! answer (list-ref matches selected))))
                 ((previous) (when (> count 0) (set! selected (modulo (- selected 1) count))))
                 ((next) (when (> count 0) (set! selected (modulo (+ selected 1) count))))
                 ((backspace) (when (> (string-length query) 0)
                                (set! query (substring query 0 (- (string-length query) 1)))
                                (set! selected 0)))
                 ((complete) (let ((prefix (buffer-picker-common-prefix matches)))
                               (when (> (string-length prefix) (string-length query))
                                 (set! query prefix) (set! selected 0))))
                 ((insert) (when (and (= (string-length key) 1) (>= (c@ key 0) 32))
                             (set! query (string-append query key))
                             (set! selected 0))))))
           (loop (+ n 1)))))
     (lambda () (select-buffer origin) (kill-buffer *buffer-picker-buffer*)))
    (if answer
        (begin (set! *previous-picked-buffer* origin)
               (select-buffer answer)
               (message "Buffer: " answer))
        (message "Buffer selection cancelled"))))

(defcommand (find-alternate-file)
  (let ((file (trim (prompt "Find alternate file: " (or (buffer-filename) "")))))
    (when (and (> (string-length file) 0)
               (or (not (buffer-modified-p))
                   (yes-p (concat (get-buffer-name) " is modified; discard the changes?"))))
      (rename-buffer (concat "*old " (random 100000) "*"))
      (let ((old-name (get-buffer-name)))
        (find-file file)
        (kill-buffer old-name)))))

(defcommand (save-some-buffers)
  (let ((origin (get-buffer-name)) (saved 0))
    (let loop ((i 0))
      (when (< i (get-buffer-count))
        (execute-builtin "next-buffer")
        (when (and (buffer-modified-p) (buffer-filename)
                   (yes-p (concat "Save " (buffer-filename) "?")))
          (save-buffer (get-buffer-name))
          (set! saved (+ saved 1)))
        (loop (+ i 1))))
    (select-buffer origin)
    (message (if (= saved 0) "No files saved" (concat "Saved " (plural saved "file"))))))

(defcommand (quoted-insert)
  "C-q: insert the next key as it is (C-q TAB inserts a tab)."
  (message "C-q-")
  (update-display)
  (let ((k (get-key)))
    (clear-message-line)
    (if (> (string-length k) 0)
        (insert k)
        (let ((name (get-key-name)))
          (cond ((and (= (string-length name) 3) (string-prefix? "C-" name) (<= 97 (c@ name 2)) (<= (c@ name 2) 122))
                 (insert (string (integer->char (- (c@ name 2) 96)))))
                ((string=? name "SPC") (insert " "))
                ((string=? name "esc") (insert (string (integer->char 27))))
                (else (message "Cannot insert " (display-key name))))))))

;;; evaluating Scheme

(defcommand (eval-defun)
  "C-M-x: evaluate the top-level form around the cursor."
  (let* ((start (scan beginning-of-defun-position (min (buffer-size) (+ 1 (line-end))) #t))
         (end (scan forward-sexp-position start #t)))
    (if (not end)
        (message "No top-level form here")
        (message (eval-for-message (buffer-substring start end))))))

(defcommand (describe-key)
  "C-x ?: what a key does."
  (message "Describe key: ")
  (update-display)
  (let ((k (get-key)))
    (if (string=? k "")
        (let* ((name (get-key-name)) (fn (hashtable-ref *keymap* name #f)))
          (message (display-key name) " runs "
                   (cond (fn (command-name fn))
                         ((string=? (get-key-binding) "user-defined-function") "nothing")
                         (else (get-key-binding)))))
        (message (value->string k) " inserts itself"))))

(defcommand (toggle-utf8-fix)
  "Turn the UTF-8 fixes of 18 November 2026 off or on, to compare.  Off, as
before: C-f and C-b stop between a letter and the accent typed after it, a
byte that is not a complete character is typed as it is, and a fold may end
inside a character.  On: one press over letter and accent, the byte typed as
U+FFFD, such a fold refused (Lean/utf8-cursor.lean)."
  (let ((on (= (fe-utf8-fix (if (= (fe-utf8-fix -1) 1) 0 1)) 1)))
    (message (if on
                 "UTF-8 fixes on: C-f passes letter and accent at once; stray bytes become U+FFFD"
                 "UTF-8 fixes off: C-f stops before an accent; stray bytes go in as they are"))))

(defcommand (eval-expression)
  "M-:: evaluate a Scheme expression typed on the message line."
  (let ((e (prompt "Eval: " "")))
    (unless (string=? (trim e) "") (message (eval-for-message e)))))

(defcommand (query-replace-command) (execute-builtin "query-replace"))
(defcommand (recenter-command) (recenter))

;;; ------------------------------------------------------------------
;;; Keys
;;; ------------------------------------------------------------------

(global-set-key "C-g" 'keyboard-quit)
(global-set-key "C-space" 'set-mark-command)
(global-set-key "C-k" 'kill-line-command)
(global-set-key "C-y" 'yank-command)
(global-set-key "C-t" 'transpose-chars)
(global-set-key "C-o" 'open-line)
(global-set-key "C-q" 'quoted-insert)
(global-set-key "C-l" 'recenter-command)

(global-set-key "M-f" 'forward-word-command)
(global-set-key "M-b" 'backward-word-command)
(global-set-key "M-F" 'forward-word-command)
(global-set-key "M-B" 'backward-word-command)
(global-set-key "esc [1;5C" 'forward-word-command)   ; C-right
(global-set-key "esc [1;5D" 'backward-word-command)  ; C-left
(global-set-key "M-a" 'backward-sentence)
(global-set-key "M-e" 'forward-sentence)
(global-set-key "M-{" 'backward-paragraph)
(global-set-key "M-}" 'forward-paragraph)
(global-set-key "M-m" 'back-to-indentation)
(global-set-key "C-M-f" 'forward-sexp)
(global-set-key "C-M-b" 'backward-sexp)
(global-set-key "C-M-u" 'backward-up-list)
(global-set-key "C-M-d" 'down-list)
(global-set-key "C-M-a" 'beginning-of-defun)
(global-set-key "C-M-e" 'end-of-defun)

(global-set-key "M-d" 'kill-word)
(global-set-key "M-DEL" 'backward-kill-word)
(global-set-key "C-M-k" 'kill-sexp)
(global-set-key "M-k" 'kill-sentence)
(global-set-key "M-z" 'zap-to-char)
(global-set-key "M-y" 'yank-pop)
(global-set-key "M-t" 'transpose-words)
(global-set-key "C-x C-t" 'transpose-lines)
(global-set-key "M-u" 'upcase-word)
(global-set-key "M-l" 'downcase-word)
(global-set-key "M-c" 'capitalize-word)
(global-set-key "M-^" 'delete-indentation)
(global-set-key "M-\\" 'delete-horizontal-space)
(global-set-key "M-SPC" 'just-one-space)
(global-set-key "C-x C-o" 'delete-blank-lines)
(global-set-key "M-q" 'fill-paragraph)
(global-set-key "M-;" 'comment-dwim)
(global-set-key "C-M-\\" 'indent-region)

(global-set-key "M-w" 'copy-region-command)
(global-set-key "C-x h" 'mark-whole-buffer)
(global-set-key "C-x C-x" 'exchange-point-and-mark)
(global-set-key "M-h" 'mark-paragraph)
(global-set-key "M-@" 'mark-word)
(global-set-key "C-M-space" 'mark-sexp)

(global-set-key "M-%" 'query-replace-command)
(global-set-key "M-:" 'eval-expression)
(global-set-key "C-M-x" 'eval-defun)

(global-set-key "C-x b" 'switch-to-buffer)
(global-set-key "C-x C-v" 'find-alternate-file)
(global-set-key "C-x s" 'save-some-buffers)
(global-set-key "C-x d" 'dired)
(global-set-key "C-x ?" 'describe-key)
