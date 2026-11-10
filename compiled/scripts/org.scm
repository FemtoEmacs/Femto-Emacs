;;;; org.scm -- a tiny Org mode: the foundation of a fuller one
;;;;
;;;; In files ending in .org (any case), while Org is on -- it is from the
;;;; start:
;;;;
;;;;   colours    headings (TODO and DONE apart), #+ lines and blocks,
;;;;              *bold* /italic/ _underline_ +strike+ =verbatim= ~code~,
;;;;              [[links]], list bullets, # comments; a #+BEGIN_SRC block
;;;;              in the colours of its language
;;;;   M-RET      a new heading below, at the level of the heading above
;;;;              (a new item, in a list)
;;;;   C-c C-t    the heading's keyword: none -> TODO -> DONE -> none
;;;;   C-c C-c    what point is on: a #+BEGIN_SEXP_TABLE block is computed
;;;;              and aligned (org-table.scm)
;;;;   C-c C-v t  tangle: the #+BEGIN_SRC blocks with :tangle FILE are
;;;;              written to their files (org-babel.scm)
;;;;   C-c C-j    the headings in a list: RET or a click goes to one
;;;;              (org-goto.scm)
;;;;   TAB        on a heading: fold it, show its children, show it all;
;;;;              C-c C-n C-p C-f C-b C-u move between headings
;;;;              (org-fold.scm)
;;;;   C-x n s    narrow to the subtree point is in; C-x n w widens
;;;;              (org-goto.scm, narrow.scm)
;;;;
;;;; M-x org-mode (or M-x orgmode) turns Org off: its keys go back to what
;;;; they were, its language goes, and .org files are plain text, as if Org
;;;; did not exist.  The same command turns it on again.  Elsewhere (a file
;;;; that does not end in .org) its keys do what they did without it.
;;;;
;;;; Modules.  A module adds what C-c C-c does on something with
;;;; (org-c-c-c! NAME APPLIES? RUN): APPLIES? is called with no argument
;;;; in an Org buffer, the first that answers true has its RUN called.  A
;;;; key after C-c C-v is added with (org-babel-key! KEY PROCEDURE).  The
;;;; text is read as UTF-8 bytes (a bytevector), as the C core counts.

(define *org-on* #t)

(define (org-file-p file)
  "Is FILE an Org file, Org being on?"
  (and *org-on* (string? file) (> (string-length file) 4)
       (string-ci=? (substring file (- (string-length file) 4) (string-length file)) ".org")))

(define (org-buffer-p) (org-file-p (buffer-filename)))

;;; ------------------------------------------------------------------
;;; Reading the text: bytes and lines
;;; ------------------------------------------------------------------

(define (org-buffer-bytes)
  "The whole buffer, a bytevector of UTF-8 bytes (offsets as the core's)."
  (string->utf8 (buffer-substring 0 (buffer-size))))

(define (org-line-end text i)
  (let ((n (blen text)))
    (let loop ((i i)) (if (or (>= i n) (= (b@ text i) 10)) i (loop (+ i 1))))))

(define (org-line-start text i)
  (let loop ((i (min i (blen text))))
    (if (or (<= i 0) (= (b@ text (- i 1)) 10)) (max i 0) (loop (- i 1)))))

(define (org-skip-blanks text i end)
  (let loop ((i i)) (if (and (< i end) (memv (b@ text i) '(32 9))) (loop (+ i 1)) i)))

(define (org-upcase-byte b) (if (and (<= 97 b) (<= b 122)) (- b 32) b))

(define (org-at-ci? text i end word)
  "Does WORD (ASCII, upper case) start at I, before END, in any case?"
  (let ((n (string-length word)))
    (and (<= (+ i n) end)
         (let loop ((k 0))
           (or (= k n)
               (and (= (org-upcase-byte (b@ text (+ i k))) (char->integer (string-ref word k)))
                    (loop (+ k 1))))))))

(define (org-keyword-line? text ls le word)
  "Is the line [LS, LE) the line WORD (\"#+BEGIN_SRC\", ...), blanks before
it allowed, in any case?"
  (org-at-ci? text (org-skip-blanks text ls le) le word))

(define (org-heading-level text ls le)
  "The number of stars of the heading line at LS, or #f: stars from the
first column, then a blank (or the end of the line)."
  (let loop ((i ls))
    (cond ((and (< i le) (= (b@ text i) 42)) (loop (+ i 1)))
          ((= i ls) #f)
          ((or (= i le) (memv (b@ text i) '(32 9))) (- i ls))
          (else #f))))

;;; ------------------------------------------------------------------
;;; Colours
;;; ------------------------------------------------------------------

(define (org-paint! colors from to face)
  (do ((i (max from 0) (+ i 1))) ((>= i (min to (bytevector-length colors))))
    (bytevector-u8-set! colors i face)))

(define (org-emphasis-face b)
  (case b ((42) +strong+) ((47 95 43) +emphasis+) ((61 126) +string+) (else #f)))

(define (org-before-ok? b) (memv b '(32 9 40 123 39 34 45 58)))       ; space ( { ' " - :
(define (org-after-ok? b) (memv b '(32 9 46 44 59 58 33 63 41 125 39 34 45 92)))

(define (org-inline! text ls le colors)
  "*bold* /italic/ _underline_ +strike+ =verbatim= ~code~ and [[links]] in
the line [LS, LE)."
  (let loop ((i ls))
    (when (< i le)
      (let ((b (b@ text i)))
        (cond
         ;; [[target]] or [[target][description]]
         ((and (= b 91) (< (+ i 1) le) (= (b@ text (+ i 1)) 91))
          (let find ((j (+ i 2)))
            (cond ((>= (+ j 1) le) (loop (+ i 1)))
                  ((and (= (b@ text j) 93) (= (b@ text (+ j 1)) 93))
                   (org-paint! colors i (+ j 2) +link+) (loop (+ j 2)))
                  (else (find (+ j 1))))))
         ((and (org-emphasis-face b)
               (or (= i ls) (org-before-ok? (b@ text (- i 1))))
               (< (+ i 1) le) (not (memv (b@ text (+ i 1)) (list 32 9 b))))
          (let find ((j (+ i 2)))
            (cond ((>= j le) (loop (+ i 1)))
                  ((and (= (b@ text j) b) (not (memv (b@ text (- j 1)) '(32 9)))
                        (or (= (+ j 1) le) (org-after-ok? (b@ text (+ j 1)))))
                   (org-paint! colors i (+ j 1) (org-emphasis-face b)) (loop (+ j 1)))
                  (else (find (+ j 1))))))
         (else (loop (+ i 1))))))))

(define (org-list-marker-end text i le)
  "After - + (or N. N)) and a blank at I: the index after the blank, or #f."
  (and (< i le)
       (let ((b (b@ text i)))
         (cond ((and (memv b '(45 43)) (< (+ i 1) le) (memv (b@ text (+ i 1)) '(32 9))) (+ i 2))
               ((and (<= 48 b) (<= b 57))
                (let digits ((j i))
                  (cond ((and (< j le) (<= 48 (b@ text j)) (<= (b@ text j) 57)) (digits (+ j 1)))
                        ((and (< (+ j 1) le) (memv (b@ text j) '(46 41)) (memv (b@ text (+ j 1)) '(32 9))) (+ j 2))
                        (else #f))))
               (else #f)))))

(define (org-word-at text i le)
  "The word (letters) at I, as a string."
  (let loop ((j i))
    (if (and (< j le) (let ((b (b@ text j))) (or (and (<= 65 b) (<= b 90)) (and (<= 97 b) (<= b 122)))))
        (loop (+ j 1))
        (bytes->string text i j))))

(define (org-paint-sexp-table-line! text ls le colors)
  "Inside #+BEGIN_SEXP_TABLE: numbers, strings, rules (-----) and the
names ending in : (Title:)."
  (let loop ((i ls))
    (when (< i le)
      (let ((b (b@ text i)))
        (cond ((= b 34)
               (let find ((j (+ i 1)))
                 (cond ((>= j le) (org-paint! colors i le +string+))
                       ((= (b@ text j) 92) (find (+ j 2)))
                       ((= (b@ text j) 34) (org-paint! colors i (+ j 1) +string+) (loop (+ j 1)))
                       (else (find (+ j 1))))))
              ((memv b '(40 41 32 9)) (loop (+ i 1)))
              (else
               (let* ((j (let word ((j i)) (if (and (< j le) (not (memv (b@ text j) '(40 41 32 9 34)))) (word (+ j 1)) j)))
                      (token (bytes->string text i j)))
                 (org-paint! colors i j
                             (cond ((string->number token) +digits+)
                                   ((string-index token (lambda (c) (not (char=? c #\-))))
                                    (if (char=? (string-ref token (- (string-length token) 1)) #\:) +keyword+ +alpha+))
                                   (else +comment+)))
                 (loop j))))))))

(define (org-highlight lang text len colors)
  "The language's highlighter: TEXT, LEN bytes of it, a line at a time."
  (let loop ((ls 0) (block #f) (code-start #f))
    ;; BLOCK: #f, 'src (CODE-START its first line, its language in the
    ;; opening line), 'sexp, 'example, or 'other
    (if (>= ls len)
        ;; a block that goes on past the text shown: its code so far
        (when (eq? block 'src) (org-paint-src! text code-start len colors))
        (let* ((le (let find ((i ls)) (if (or (>= i len) (= (b@ text i) 10)) i (find (+ i 1)))))
               (next (+ le 1))
               (first (org-skip-blanks text ls le)))
          (cond
           ;; the end of a block
           ((and block (org-at-ci? text first le "#+END_"))
            (when (eq? block 'src) (org-paint-src! text code-start ls colors))
            (org-paint! colors ls le +comment+)
            (loop next #f #f))
           ((eq? block 'src) (loop next block code-start))
           ((eq? block 'sexp)
            (if (org-at-ci? text first le "#+TBLFM:")
                (org-paint! colors ls le +comment+)
                (org-paint-sexp-table-line! text ls le colors))
            (loop next block #f))
           ((eq? block 'example) (org-paint! colors ls le +string+) (loop next block #f))
           ;; a heading: TODO or DONE after the stars apart
           ((org-heading-level text ls le)
            => (lambda (level)
                 (org-paint! colors ls le +heading+)
                 (let* ((w (org-skip-blanks text (+ ls level) le))
                        (word (org-word-at text w le)))
                   (when (member word '("TODO" "DONE"))
                     (org-paint! colors w (+ w (string-length word)) +keyword+)))
                 (loop next #f #f)))
           ;; #+ lines; a block starts
           ((org-at-ci? text first le "#+")
            (org-paint! colors ls le +comment+)
            (cond ((org-at-ci? text first le "#+BEGIN_SRC")
                   (set! *org-src-language* (org-src-language text (+ first 11) le))
                   (loop next 'src next))
                  ((org-at-ci? text first le "#+BEGIN_SEXP_TABLE") (loop next 'sexp #f))
                  ((or (org-at-ci? text first le "#+BEGIN_EXAMPLE") (org-at-ci? text first le "#+BEGIN_VERSE"))
                   (loop next 'example #f))
                  ((org-at-ci? text first le "#+BEGIN_") (loop next 'other #f))
                  (else (loop next block #f))))
           ;; # comments
           ((and (= first ls) (< ls le) (= (b@ text ls) 35)
                 (or (= (+ ls 1) le) (memv (b@ text (+ ls 1)) '(32 9))))
            (org-paint! colors ls le +comment+)
            (loop next block #f))
           ;; a table of | cells: the bars
           ((and (< first le) (= (b@ text first) 124))
            (org-inline! text first le colors)
            (do ((i first (+ i 1))) ((>= i le))
              (when (= (b@ text i) 124) (org-paint! colors i (+ i 1) +comment+)))
            (loop next block #f))
           (else
            (let ((after (org-list-marker-end text first le)))
              (when after
                (org-paint! colors first after +keyword+)
                ;; a check box [ ] [X] [-]
                (when (and (< (+ after 2) le) (= (b@ text after) 91) (= (b@ text (+ after 2)) 93))
                  (org-paint! colors after (+ after 3) +keyword+)))
              (org-inline! text (or after first) le colors)
              (loop next block #f)))))))
  #f)

;;; The language of the #+BEGIN_SRC block being coloured
(define *org-src-language* #f)

(define (org-src-language text i le)
  "The language named after #+BEGIN_SRC (scheme, python ...), or #f."
  (let* ((i (org-skip-blanks text i le))
         (j (let word ((j i)) (if (and (< j le) (not (memv (b@ text j) '(32 9)))) (word (+ j 1)) j))))
    (and (< i j) (md-code-language (bytes->string text i j)))))

(define (org-paint-src! text from to colors)
  "The code of a block, [FROM, TO), in the colours of its language."
  (when (and from (< from to))
    (if *org-src-language*
        (let* ((n (- to from)) (c (make-colors n)))
          (highlight-octets *org-src-language* (bytevector-copy text from to) n c)
          (bytevector-copy! colors from c 0 n))
        (org-paint! colors from to +string+))))

;;; ------------------------------------------------------------------
;;; M-q (emacs-keys.scm) refills Org's prose, not its headings or blocks
;;; ------------------------------------------------------------------

(define (org-fill-refused? ls)
  "Is the line at LS an Org heading, or inside a #+BEGIN_ ... #+END_
block (a table, code)?  Then M-q leaves it alone."
  (and (org-buffer-p)
       (let ((text (org-buffer-bytes)))
         (or (and (org-heading-level text ls (org-line-end text ls)) #t)
             (let up ((p ls))
               (and (> p 0)
                    (let* ((s (org-line-start text (- p 1))) (e (org-line-end text s)))
                      (cond ((org-keyword-line? text s e "#+END_") #f)
                            ((org-keyword-line? text s e "#+BEGIN_") #t)
                            (else (up s))))))))))

;;; ------------------------------------------------------------------
;;; Headings: M-RET and C-c C-t
;;; ------------------------------------------------------------------

(define (org-heading-above text p)
  "The level of the heading at or above offset P, or #f."
  (let loop ((ls (org-line-start text p)))
    (let ((level (org-heading-level text ls (org-line-end text ls))))
      (cond (level level)
            ((<= ls 0) #f)
            (else (loop (org-line-start text (- ls 1))))))))

(define (org-meta-return)
  "M-RET: a new item, in a list; else a new heading below, at the level of
the heading above (one star when there is none)."
  (let* ((text (org-buffer-bytes))
         (ls (org-line-start text (point)))
         (le (org-line-end text ls))
         (first (org-skip-blanks text ls le))
         (marker-end (org-list-marker-end text first le)))
    (cond ((and marker-end (not (org-heading-level text ls le)))
           (let ((marker (bytes->string text ls marker-end)))
             (goto-char le)
             (insert "\n" (org-next-marker marker))))
          (else
           (let ((level (or (org-heading-above text (point)) 1)))
             (goto-char le)
             (insert "\n" (make-string level #\*) " "))))))

(define (org-next-marker marker)
  "\"- \" -> \"- \"; \"  3. \" -> \"  4. \"."
  (let* ((n (string-length marker))
         (i (let skip ((i 0)) (if (and (< i n) (memv (string-ref marker i) '(#\space #\tab))) (skip (+ i 1)) i)))
         (j (let digits ((j i)) (if (and (< j n) (char-numeric? (string-ref marker j))) (digits (+ j 1)) j))))
    (if (> j i)
        (string-append (substring marker 0 i)
                       (number->string (+ 1 (string->number (substring marker i j))))
                       (substring marker j n))
        marker)))

(define (org-todo)
  "C-c C-t: the heading's keyword, none -> TODO -> DONE -> none."
  (let* ((text (org-buffer-bytes))
         (ls (let loop ((ls (org-line-start text (point))))
               (cond ((org-heading-level text ls (org-line-end text ls)) ls)
                     ((<= ls 0) #f)
                     (else (loop (org-line-start text (- ls 1)))))))
         (le (and ls (org-line-end text ls))))
    (if (not ls)
        (message "C-c C-t: not under a heading")
        (let* ((w (org-skip-blanks text (+ ls (org-heading-level text ls le)) le))
               (word (org-word-at text w le))
               (here (point))
               (replace (lambda (old new)
                          ;; OLD bytes at W become NEW; point follows
                          (let* ((end (+ w (string-length old)))
                                 (end (if (and (> (string-length old) 0) (< end le) (= (b@ text end) 32)) (+ end 1) end))
                                 (new (if (string=? new "") "" (string-append new " ")))
                                 (delta (- (string-length new) (- end w))))
                            (fe-delete-region w end)
                            (goto-char w)
                            (insert new)
                            (goto-char (cond ((< here w) here)
                                             ((>= here end) (+ here delta))
                                             (else (+ w (string-length new)))))))))
          (cond ((string=? word "TODO") (replace "TODO" "DONE"))
                ((string=? word "DONE") (replace "DONE" ""))
                (else (replace "" "TODO")))))))

;;; ------------------------------------------------------------------
;;; C-c C-c and C-c C-v: what the modules add
;;; ------------------------------------------------------------------

(define *org-c-c-c* '())        ; (name applies? run), first registered first
(define *org-babel-keys* '())   ; (key . procedure)

(define (org-c-c-c! name applies? run)
  (set! *org-c-c-c* (append (filter (lambda (h) (not (equal? (car h) name))) *org-c-c-c*)
                            (list (list name applies? run)))))

(define (org-babel-key! key procedure)
  (set! *org-babel-keys* (cons (cons key procedure)
                               (filter (lambda (k) (not (string=? (car k) key))) *org-babel-keys*))))

(define (org-ctrl-c-ctrl-c)
  (let loop ((hs *org-c-c-c*))
    (cond ((null? hs) (message "C-c C-c: nothing here for Org to do (a #+BEGIN_SEXP_TABLE block?)"))
          (((cadar hs)) ((caddar hs)))
          (else (loop (cdr hs))))))

(define (org-babel-prefix)
  (message "C-c C-v-")
  (let* ((key (get-key))
         (entry (assoc key *org-babel-keys*)))
    (clear-message-line)
    (if entry
        ((cdr entry))
        (message "C-c C-v " key " is not bound"))))

;;; ------------------------------------------------------------------
;;; Turning Org on and off
;;; ------------------------------------------------------------------

;;; Org's keys, in the core's names, and what they run in an Org buffer
(define *org-key-table*
  (list (cons "C-c C-c" org-ctrl-c-ctrl-c)
        (cons "C-c C-v" org-babel-prefix)
        (cons "C-c C-t" org-todo)
        (cons "C-c C-j" (lambda () (org-goto)))     ; org-goto.scm
        (cons "C-c C-n" (lambda () (org-next-heading)))     ; org-fold.scm
        (cons "C-c C-p" (lambda () (org-previous-heading)))
        (cons "C-c C-f" (lambda () (org-forward-same-level)))
        (cons "C-c C-b" (lambda () (org-backward-same-level)))
        (cons "C-c C-u" (lambda () (org-up-heading)))
        (cons "esc C-m" org-meta-return)        ; M-RET
        (cons "esc C-j" org-meta-return)))      ; M-RET, as terminals send it

;;; key -> what it was bound to before Org (#f: nothing)
(define *org-saved-keys* (make-hashtable string-hash string=?))
(define *org-key-commands* (make-hashtable string-hash string=?))
(define *org-language* #f)

(define (org-key-command key procedure)
  "The command bound to KEY: PROCEDURE in an Org buffer, elsewhere what the
key did without Org."
  (lambda ()
    (if (org-buffer-p)
        (procedure)
        (let ((before (hashtable-ref *org-saved-keys* key #f)))
          (if before
              (call-command before)
              (message key " is not bound"))))))

(define (org-on!)
  (set! *org-on* #t)
  ;; TAB on a heading folds (org-fold.scm)
  (set! *self-insert-hook* (cons 'org-tab-key (filter (lambda (h) (not (eq? h 'org-tab-key))) *self-insert-hook*)))
  (set! *org-language* (define-language "Org" 'extensions '(".org") 'highlighter org-highlight))
  (for-each (lambda (k)
              (let ((command (org-key-command (car k) (cdr k))))
                (hashtable-set! *org-saved-keys* (car k) (key-binding (car k)))
                (hashtable-set! *org-key-commands* (car k) command)
                (global-set-key (car k) command)))
            *org-key-table*))

(define (org-off!)
  (set! *org-on* #f)
  (set! *self-insert-hook* (filter (lambda (h) (not (eq? h 'org-tab-key))) *self-insert-hook*))
  (fe-unfold-everywhere)                ; no text stays hidden
  (set! *languages* (filter (lambda (l) (not (eq? l *org-language*))) *languages*))
  (set! *org-language* #f)
  (for-each (lambda (k)
              (let ((key (car k)))
                ;; a key bound to something else since stays as it is
                (when (eq? (key-binding key) (hashtable-ref *org-key-commands* key #f))
                  (let ((before (hashtable-ref *org-saved-keys* key #f)))
                    (if before (global-set-key key before) (global-unset-key key))))
                (hashtable-delete! *org-key-commands* key)
                (hashtable-delete! *org-saved-keys* key)))
            *org-key-table*))

(defcommand (org-mode)
  "Turn the tiny Org mode (.org files) off, or on again."
  (if *org-on* (org-off!) (org-on!))
  (update-display)
  (message (if *org-on* "Org mode on (.org files)" "Org mode off: .org files are plain text")))

(defcommand (orgmode)
  "The same as M-x org-mode."
  (org-mode))

(org-on!)
