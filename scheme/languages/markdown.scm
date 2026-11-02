;;;; markdown.scm -- colours, indentation and word wrapping for Markdown
;;;;
;;;; Port of SBEmacs's lisp/languages/markdown.lisp.
;;;;
;;;; Markdown is not made of tokens but of lines: # heading, > quotation,
;;;; - or 1. list item, ``` a block of code.  Inside a line, a few marks
;;;; change the type: *emphasis*, **strong**, `code`, [links](url).  So it
;;;; has a highlighter of its own, which reads the text a line at a time.  A
;;;; block of code whose first line names a language (```lisp, ```python)
;;;; is coloured as that language.
;;;;
;;;;   RET   in a list item, starts the next item ("- ", "2. ", "> "); on an
;;;;         empty item, ends the list with a blank line
;;;;   TAB   on a list item, nests it under the item above (again: back)

;;; ------------------------------------------------------------------
;;; Reading lines
;;; ------------------------------------------------------------------

(define (md-skip-spaces text i end)
  (let loop ((i i)) (if (and (< i end) (= (aref text i) 32)) (loop (+ i 1)) i)))

(define (md-list-marker-end text i end)
  "If a list marker (- * + or 1. 1)) followed by a space starts at I, the
index just after the marker and its spaces."
  (and (< i end)
       (let* ((b (aref text i))
              (after (lambda (j)
                       (and (or (= j end) (= (aref text j) 32) (= (aref text j) 9))
                            (md-skip-spaces text j end)))))
         (cond ((memv b '(45 42 43)) (after (+ i 1)))
               ((and (<= 48 b) (<= b 57))
                (let ((j (let loop ((j i))
                           (if (and (< j end) (and (<= 48 (aref text j)) (<= (aref text j) 57)) (< (- j i) 9)) (loop (+ j 1)) j))))
                  (and (< j end) (memv (aref text j) '(46 41)) (after (+ j 1)))))
               (else #f)))))

(define (md-fence text ls le)
  "If the line [LS, LE) is a code fence (``` or ~~~, up to 3 spaces in),
(fence-byte . length), else #f."
  (let ((i (md-skip-spaces text ls le)))
    (and (<= (- i ls) 3) (< (+ i 2) le)
         (let ((b (aref text i)))
           (and (memv b '(96 126))
                (let ((j (let loop ((j i)) (if (and (< j le) (= (aref text j) b)) (loop (+ j 1)) j))))
                  (and (>= (- j i) 3) (cons b (- j i)))))))))

(define (md-rule-p text ls le)
  "A thematic break: three or more - * or _, nothing else but spaces."
  (let ((i (md-skip-spaces text ls le)))
    (and (< i le)
         (let ((b (aref text i)))
           (and (memv b '(45 42 95))
                (let loop ((k i) (n 0))
                  (if (>= k le) (>= n 3)
                      (let ((c (aref text k)))
                        (and (or (= c b) (= c 32) (= c 9))
                             (loop (+ k 1) (if (= c b) (+ n 1) n)))))))))))

(define (md-setext-underline-p text ls le)
  "A line of = or - only: it makes the paragraph line above a heading."
  (let ((i (md-skip-spaces text ls le)))
    (and (< i le) (<= (- i ls) 3)
         (let ((b (aref text i)))
           (and (memv b '(61 45))
                (let ((j (let loop ((j i)) (if (and (< j le) (= (aref text j) b)) (loop (+ j 1)) j))))
                  (= (md-skip-spaces text j le) le)))))))

(define (md-blank-p text ls le)
  (let loop ((k ls)) (or (>= k le) (and (memv (aref text k) '(32 9 13)) (loop (+ k 1))))))

(define *markdown-code-names*
  '(("lisp" . "Common Lisp") ("cl" . "Common Lisp") ("common-lisp" . "Common Lisp")
    ("elisp" . "Common Lisp") ("py" . "Python") ("lean4" . "Lean")
    ("ocaml" . "ML") ("sml" . "ML") ("latex" . "TeX") ("rb" . "Ruby")
    ("hs" . "Haskell") ("pl" . "Prolog") ("cpp" . "C") ("c++" . "C")))

(define (md-code-language info)
  "The language named by a fence's info string: ```lisp, ```python ..."
  (let* ((word (byte-substring info 0 (or (byte-position info 32) (length info))))
         (name (string-downcase (trim-bytes word " {}."))))
    (and (> (length name) 0)
         (let ((alias (assoc name *markdown-code-names*)))
           (or (and alias (find-language (cdr alias)))
               (find (lambda (l) (string-ci=? (language-name l) name)) *languages*)
               (find (lambda (l) (member (string-append "." name) (language-extensions l))) *languages*))))))

;;; ------------------------------------------------------------------
;;; The highlighter
;;; ------------------------------------------------------------------

;; The line-by-line pass runs at every redisplay, so it is in C
;; (src/highlight.c, fe-highlight-markdown): headings, emphasis, strong,
;; code, links, quotations, lists, tables, rules, comments.  It paints the
;; blocks of code as strings and returns them as (start end info); here the
;; ones whose info string names a language are coloured as that language.
(define (markdown-highlight lang text len colors)
  (let ((text (if (= len (length text)) text (byte-substring text 0 len))))
    (for-each
     (lambda (block)
       (let ((code-lang (md-code-language (caddr block)))
             (start (car block)) (end (cadr block)))
         (when (and code-lang (< start end))
           (let* ((n (- end start))
                  (c (make-colors n)))
             (highlight-octets code-lang (byte-substring text start end) n c)
             (do ((k 0 (+ k 1))) ((= k n)) (aset! colors (+ start k) (aref c k)))))))
     (fe-highlight-markdown text colors)))
  #f)

;;; ------------------------------------------------------------------
;;; Indentation
;;; ------------------------------------------------------------------

(define (md-item-text-column text ls)
  "If the line at LS is a list item or a quotation, the column where its
text starts."
  (let* ((le (line-end-index text ls))
         (i (md-skip-spaces text ls le))
         (after (or (md-list-marker-end text i le)
                    (and (< i le) (= (aref text i) 62) (md-skip-spaces text (+ i 1) le)))))
    (and after (column-at text after))))

(define (md-open-fence text ls)
  "If the line at LS is inside a ``` block, the start of its opening fence
line (counting the fences above it), else #f."
  (let loop ((p 0) (open #f))
    (let ((nl (byte-position text 10 p)))
      (if (and nl (< p ls))
          (loop (+ nl 1) (if (md-fence text p nl) (if open #f p) open))
          open))))

(define (md-inside-code-p text ls)
  "Is the line at LS inside a ``` block (counting the fences above it)?"
  (and (md-open-fence text ls) #t))

(define (md-code-place text ls)
  "Inside a ``` block whose fence names a language (```scheme, ```c ...):
(language . index of the block's first line), else #f."
  (let* ((fence (md-open-fence text ls))
         (fe (and fence (line-end-index text fence)))
         (mark (and fence (md-fence text fence fe)))
         (lang (and mark (md-code-language
                          (byte-substring text (+ (md-skip-spaces text fence fe) (cdr mark)) fe)))))
    (and lang (<= (+ fe 1) ls) (cons lang (+ fe 1)))))

(define (md-code-indentation text ls)
  "Inside a ``` block whose language has indentation rules, the column
those rules give the line at LS, reading the block from its first line."
  (let* ((place (md-code-place text ls))
         (spec (and place (get *indentation* (string-downcase (language-name (car place))) #f))))
    (and spec
         (let* ((body (cdr place))
                (ctx (make-context spec (byte-substring text body (length text)) 0 (- ls body))))
           (and ctx (compute-indentation ctx))))))

(define-indent-style 'markdown
  (lambda (ctx)
    (let* ((text (ictx-text ctx)) (ls (ictx-line ctx))
           (prev (previous-code-line text ls)))
      (cond ((not prev) 0)
            ;; code: by the rules of the fence's language (```scheme), or
            ;; like the line above
            ((md-inside-code-p text ls)
             (or (md-code-indentation text ls) (indentation-at text prev)))
            ;; an item: where the item above starts (its sibling); but TAB on
            ;; an item already there nests it under the text of the one above
            ((let ((le (line-end-index text ls)))
               (md-list-marker-end text (md-skip-spaces text ls le) le))
             (let ((sibling (indentation-at text prev))
                   (nested (md-item-text-column text prev)))
               (if (and *indenting-by-tab* nested (= (indentation-at text ls) sibling))
                   nested
                   sibling)))
            ;; under the text of the item above, or like the line above
            (else (or (md-item-text-column text prev) (indentation-at text prev)))))))

(define (markdown-levels ctx)
  "The columns TAB cycles through."
  (let* ((text (ictx-text ctx)) (ls (ictx-line ctx)))
    (let loop ((p (previous-code-line text ls)) (k 0) (levels '()))
      (if (or (not p) (>= k 20)) levels
          (let* ((ind (indentation-at text p))
                 (c (md-item-text-column text p))
                 (levels (cons ind levels))
                 (levels (if c (cons c levels) levels)))
            (if (= ind 0) levels (loop (previous-code-line text p) (+ k 1) levels)))))))

(define (all-digits-end s i)
  (let loop ((j i)) (if (and (< j (length s)) (and (<= 48 (aref s j)) (<= (aref s j) 57))) (loop (+ j 1)) j)))

(define (markdown-continuation line)
  "For LINE, the beginning of the next line: \"- \" after \"- milk\", \"3. \"
after \"2. eggs\", \"> \" after a quotation.  Two values; the second is
'end when LINE is an empty item, which ends the list."
  (let* ((indent (skip-blank-chars line 0))
         (rest (byte-substring line indent))
         (lead (byte-substring line 0 indent))
         (n (length rest))
         (result (lambda (marker body)
                   (if (= 0 (length (string-trim-both body)))
                       (values marker 'end)
                       (values (string-append lead marker) #f)))))
    (cond ((= n 0) (values #f #f))
          ;; - [ ] task
          ((and (>= n 6) (memv (aref rest 0) '(45 42 43))
                (string=? " [" (byte-substring rest 1 3)) (= (aref rest 4) 93))
           (result (string (integer->char (aref rest 0)) " [ ] ") (byte-substring rest 5)))
          ((and (>= n 2) (memv (aref rest 0) '(45 42 43)) (= (aref rest 1) 32))
           (result (string (integer->char (aref rest 0)) " ") (byte-substring rest 2)))
          ((and (<= 48 (aref rest 0)) (<= (aref rest 0) 57))
           (let ((j (all-digits-end rest 0)))
             (if (and (< (+ j 1) n) (memv (aref rest j) '(46 41)) (= (aref rest (+ j 1)) 32))
                 (result (string (+ 1 (string->number (byte-substring rest 0 j)))
                                 (integer->char (aref rest j)) " ")
                         (byte-substring rest (+ j 2)))
                 (values #f #f))))
          ((= (aref rest 0) 62) (result "> " (byte-substring rest 1)))
          (else (values #f #f)))))

(define (markdown-newline)
  "RET in Markdown: continue a list or a quotation; an empty item ends it.
#f (do the usual RET) elsewhere, and inside blocks of code."
  (let* ((ls (line-start))
         (le (line-end ls))
         (line (buffer-substring ls le))
         (spec (current-indent-spec)))
    (and (= (point) le) spec
         (let ((ctx (buffer-indent-context spec)))
           (and (not (md-inside-code-p (ictx-text ctx) (ictx-line ctx)))
                (let-values (((next state) (markdown-continuation line)))
                  (cond ((eq? state 'end)
                         ;; "- " alone: take the marker away and leave the line
                         ;; blank, which ends the list
                         (fe-delete-region ls le)
                         (goto-char ls)
                         (insert "\n")
                         #t)
                        (next (insert "\n" next) #t)
                        (else #f))))))))

;;; ------------------------------------------------------------------
;;; The language
;;; ------------------------------------------------------------------

(define-language "Markdown"
  'extensions '(".md" ".markdown" ".mdown" ".mkd")
  'highlighter markdown-highlight)

;; M-;, M-q and the rest follow the language of a ``` block
(define-inner-language "Markdown" md-code-place)

(define-indentation "Markdown"
  'style 'markdown 'width 2 'tabs #f
  'cycle #t
  'levels 'markdown-levels
  'newline 'markdown-newline)

;;; ------------------------------------------------------------------
;;; Visual word wrapping.  Offsets are UTF-8 bytes, as in the C core; no
;;; buffer text is changed.
;;; ------------------------------------------------------------------

;; As in Emacs, the blanks at a break stay at the end of the upper row
;; (hanging past the edge) so the next row starts with the word; a newline
;; right after them ends the row too.
(define (markdown-hang-blanks text pos size)
  (let loop ((pos pos))
    (cond ((>= pos size) pos)
          ((memv (aref text pos) '(9 32)) (loop (+ pos 1)))
          ((= (aref text pos) 10) (+ pos 1))
          ((and (= (aref text pos) 13) (< (+ pos 1) size) (= (aref text (+ pos 1)) 10)) (+ pos 2))
          (else pos))))

(define (markdown-wrap-end text columns)
  "Bytes in one visual row: words are kept together where they fit.  Tabs
use eight-column stops; every UTF-8 character takes one cell."
  (let ((size (length text)))
    (let loop ((pos 0) (column 0) (boundary #f))
      (if (>= pos size) pos
          (let* ((byte (aref text pos))
                 (bytes (cond ((and (<= #xC2 byte) (<= byte #xDF)) 2) ((and (<= #xE0 byte) (<= byte #xEF)) 3) ((and (<= #xF0 byte) (<= byte #xF4)) 4) (else 1)))
                 (width (cond ((= byte 13) 0)
                              ((= byte 9) (- 8 (modulo column 8)))
                              ((or (< byte 32) (= byte 127)) 2)
                              (else 1))))
            (cond ((= byte 10) (+ pos 1))
                  ((> (+ column width) columns)
                   (if (and (> pos 0) (memv byte '(9 32)))
                       (markdown-hang-blanks text pos size)
                       (or boundary (if (> pos 0) pos (min size bytes)))))
                  (else
                   (let ((next (+ pos (min bytes (- size pos)))))
                     (loop next (+ column width) (if (memv byte '(9 32)) next boundary))))))))))

;; Prose wraps at word boundaries, like Emacs's visual-line-mode: Markdown,
;; TeX and plain-text files.  M-x toggle-word-wrap switches it per file.
(define *wrapped-languages* '("Markdown" "TeX" "Text"))
(define *word-wrap-overrides* (table))   ; filename -> #t / #f

(define (word-wrap-file-p filename)
  ;; a buffer without a file comes by its name, *scratch* and the like: only
  ;; the view without tags (C-c TAB, C-c l) wraps
  (cond ((string-prefix? "*" filename) (string=? filename "*tags-hidden*"))
        (else (word-wrap-file-p- filename))))

(define (word-wrap-file-p- filename)
  (if (has? *word-wrap-overrides* filename)
      (get *word-wrap-overrides* filename)
      (let ((language (language-for-file filename)))
        (and language (member (language-name language) *wrapped-languages*) #t))))

(define (markdown-wrap-row filename text columns)
  "C display callback: TEXT #f asks whether FILENAME wraps (-1 yes, 0 no);
otherwise the bytes of TEXT in the first visual row."
  (cond ((or (not (string? filename)) (string=? filename "")
             (<= columns 0) (not (word-wrap-file-p filename)))
         0)
        ((or (not text) (= (length text) 0)) -1)
        (else (markdown-wrap-end text columns))))

(defcommand (toggle-word-wrap)
  "Turn word wrapping (Emacs's visual-line-mode) on or off for this file."
  (let ((file (buffer-filename)))
    (if (not file)
        (message "Word wrap works on file buffers only")
        (let ((on (not (word-wrap-file-p file))))
          (put! *word-wrap-overrides* file on)
          (update-display)
          (message (if on "Word wrap on" "Word wrap off"))))))

(defcommand (visual-line-mode)
  "Emacs name for toggle-word-wrap."
  (toggle-word-wrap))

(global-set-key "C-c w" 'toggle-word-wrap)
