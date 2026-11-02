;;;; indent.scm -- automatic indentation
;;;;
;;;; Port of SBEmacs's lisp/indent.lisp.  A script: edit and press C-x C-r.
;;;;
;;;;   TAB      indent the current line (again: cycle through the levels in
;;;;            Python, Haskell, Lean, ML and Markdown)
;;;;   RET      new line, indented
;;;;   C-x C-i  indent the region between mark and point (also C-M-\)
;;;;   "electric" keys re-indent the line when it starts with a closing
;;;;   token: } in C, "else:" in Python, "end" in Ruby, \end in TeX
;;;;
;;;; Each language file says how it is indented with DEFINE-INDENTATION,
;;;; choosing a style: lisp, c, python, prolog, block (keyword-driven) or
;;;; markdown.  A new style is a procedure from an indent context to a
;;;; column (or #f to leave the line alone), registered with
;;;; DEFINE-INDENT-STYLE.  Everything works on the raw UTF-8 bytes.

;;; ------------------------------------------------------------------
;;; Languages and styles
;;; ------------------------------------------------------------------

;; spec: #(style width tabs options); tabs is #t, #f or 'auto
(define (indent-spec-style s) (vector-ref s 0))
(define (indent-spec-width s) (vector-ref s 1))
(define (indent-spec-tabs s) (vector-ref s 2))
(define (indent-spec-options s) (vector-ref s 3))

(define *indentation* (table))          ; lower-case language name -> spec

(define (define-indentation language . options)
  "Say how LANGUAGE (the name given to DEFINE-LANGUAGE) is indented:

  (define-indentation \"C\" 'style 'c 'width 4)

'width is the step.  'tabs is #t (tabs, 8 columns wide), #f (spaces) or
'auto (tabs if most indented lines in the file start with a tab).  'cycle
#t makes a repeated TAB change the level; 'levels names a procedure of the
context returning the columns it cycles through.  'newline names a
procedure that RET calls first; when it returns true it handled the key."
  (put! *indentation* (string-downcase language)
        (vector (plist-get options 'style 'block)
                (plist-get options 'width 4)
                (plist-get options 'tabs 'auto)
                options)))

(define (indent-option spec key (default #f))
  (plist-get (indent-spec-options spec) key default))

(define *indent-styles* (table))        ; style -> (procedure . start-line-p)

(define (define-indent-style name procedure (start-line-p #f))
  "PROCEDURE computes the column for the line in a context, or #f.
START-LINE-P (text line-start) tells where scanning may safely begin."
  (put! *indent-styles* name (cons procedure start-line-p)))

;; context: #(text line spec): TEXT runs from a safe starting line to the
;; end of the line being indented, which starts at index LINE
(define (make-indent-context text line spec) (vector text line spec))
(define (ictx-text c) (vector-ref c 0))
(define (ictx-line c) (vector-ref c 1))
(define (ictx-spec c) (vector-ref c 2))
(define (ictx-width c) (indent-spec-width (ictx-spec c)))
(define (ictx-option c key (default #f)) (indent-option (ictx-spec c) key default))

;;; ------------------------------------------------------------------
;;; Byte-level helpers
;;; ------------------------------------------------------------------

(define (blank-byte-p b) (or (= b 32) (= b 9) (= b 13) (= b 12)))

(define (word-byte-p* b) (or (and (<= 48 b) (<= b 57)) (and (<= 65 b) (<= b 90)) (and (<= 97 b) (<= b 122)) (= b 95) (>= b 128)))

(define (line-start-index text i)
  (let ((p (byte-position-back text 10 (min i (length text))))) (if p (+ p 1) 0)))

(define (line-end-index text i)
  (or (byte-position text 10 (min i (length text))) (length text)))

(define (skip-blanks text i (end #f))
  (let ((end (or end (length text))))
    (let loop ((i i)) (if (and (< i end) (blank-byte-p (aref text i))) (loop (+ i 1)) i))))

(define (column-at text i)
  "Screen column of byte I (tabs every 8 columns, UTF-8 aware)."
  (let loop ((k (line-start-index text i)) (col 0))
    (if (>= k i) col
        (let ((b (aref text k)))
          (loop (+ k 1)
                (cond ((= b 9) (* 8 (+ 1 (quotient col 8))))
                      ((= (logand b #xC0) #x80) col)
                      (else (+ col 1))))))))

(define (first-nonblank text ls) (skip-blanks text ls (line-end-index text ls)))
(define (indentation-at text ls) (column-at text (first-nonblank text ls)))

(define (line-blank-p text ls)
  (let ((i (first-nonblank text ls)))
    (or (>= i (length text)) (= (aref text i) 10))))

(define (line-string text ls)
  "The line at LS without its indentation and trailing blanks."
  (let* ((s (first-nonblank text ls))
         (e (let loop ((e (line-end-index text ls)))
              (if (and (> e s) (memv (aref text (- e 1)) '(32 9 13))) (loop (- e 1)) e))))
    (byte-substring text s e)))

(define (first-word text ls)
  "The first word of the line: letters, digits and _, plus a leading \\."
  (let* ((i (first-nonblank text ls))
         (j (if (and (< i (length text)) (= (aref text i) 92)) (+ i 1) i))
         (j (let loop ((j j)) (if (and (< j (length text)) (word-byte-p* (aref text j))) (loop (+ j 1)) j))))
    (byte-substring text i j)))

(define (previous-line-start text ls)
  (and (> ls 0) (line-start-index text (- ls 1))))

(define (previous-code-line text ls (comment #f))
  "Start of the nearest line above LS that is neither blank nor (with
COMMENT, a prefix) a comment-only line."
  (let loop ((p (previous-line-start text ls)))
    (cond ((not p) #f)
          ((or (line-blank-p text p)
               (and comment (starts-with-p comment (line-string text p))))
           (loop (previous-line-start text p)))
          (else p))))

(define (match-octets-at text i s end)
  (let ((n (length s)))
    (and (<= (+ i n) end)
         (let loop ((k 0)) (or (= k n) (and (= (aref text (+ i k)) (aref s k)) (loop (+ k 1))))))))

;;; ------------------------------------------------------------------
;;; Building the context
;;; ------------------------------------------------------------------

(define (find-start-line text from to predicate)
  "The last line start in [FROM, TO) satisfying PREDICATE."
  (let loop ((ls from) (best #f))
    (if (>= ls to) best
        (let ((best (if (predicate text ls) ls best))
              (nl (byte-position text 10 ls to)))
          (if nl (loop (+ nl 1) best) best)))))

(define (make-context spec raw from pos)
  "RAW holds buffer bytes from offset FROM past the end of the line
containing POS.  A context, or #f when RAW does not reach back far enough
to find a safe place to start scanning."
  (let* ((style (get *indent-styles* (indent-spec-style spec) #f))
         (start-p (and style (cdr style)))
         (rel (- pos from))
         (ls (line-start-index raw rel))
         (le (line-end-index raw rel))
         (first-ls (if (= from 0) 0
                       (let ((nl (byte-position raw 10 0 ls))) (if nl (+ nl 1) ls))))
         (scan-start (cond ((not start-p) first-ls)
                           ((find-start-line raw first-ls ls start-p))
                           ((= from 0) 0)
                           (else #f))))
    (and scan-start
         (make-indent-context (byte-substring raw scan-start le) (- ls scan-start) spec))))

(define (buffer-indent-context spec (pos (point)))
  (let ((size (buffer-size)))
    (let loop ((look 16384))
      (let* ((from (max 0 (- pos look)))
             (ctx (make-context spec (buffer-substring from (min size (+ pos 4096))) from pos)))
        (or ctx (loop (* look 4)))))))

(define (compute-indentation ctx)
  (let ((style (get *indent-styles* (indent-spec-style (ictx-spec ctx)) #f)))
    (unless style (error "Unknown indentation style" (indent-spec-style (ictx-spec ctx))))
    (let ((col ((car style) ctx)))
      (and col (max 0 col)))))

(define (indentation-for-text language text)
  "For testing: the column the last line of TEXT would be indented to."
  (let ((spec (or (get *indentation* (string-downcase language) #f)
                  (error "No indentation for" language))))
    (compute-indentation (make-context spec text 0 (length text)))))

;;; ------------------------------------------------------------------
;;; Changing the buffer
;;; ------------------------------------------------------------------

(define (current-indent-spec)
  (let ((lang (language-for-file (or (buffer-filename) (get-buffer-name)))))
    (and lang (get *indentation* (string-downcase (language-name lang)) #f))))

(define (use-tabs-p spec text)
  (let ((tabs (indent-spec-tabs spec)))
    (if (eq? tabs 'auto)
        (let loop ((ls 0) (with-tabs 0) (with-spaces 0))
          (if (>= ls (length text))
              (> with-tabs with-spaces)
              (let* ((b (aref text ls))
                     (nl (byte-position text 10 ls)))
                (let ((wt (if (= b 9) (+ with-tabs 1) with-tabs))
                      (ws (if (and (= b 32) (< (+ ls 1) (length text)) (= (aref text (+ ls 1)) 32))
                              (+ with-spaces 1) with-spaces)))
                  (if nl (loop (+ nl 1) wt ws) (> wt ws))))))
        tabs)))

(define (indent-string column tabs)
  (if tabs
      (string-append (make-string (quotient column 8) #\tab) (make-spaces (remainder column 8)))
      (make-spaces column)))

(define (set-line-indentation ctx column)
  "Re-indent the context's line to COLUMN, keeping the cursor on the same
text (or just after the indentation when it was inside it)."
  (let* ((text (ictx-text ctx))
         (ls (ictx-line ctx))
         (ws-end (first-nonblank text ls))
         (old-bytes (- ws-end ls))
         (new (indent-string column (use-tabs-p (ictx-spec ctx) text)))
         (new-bytes (length new))
         (here (point))
         (line-start (line-start))
         (offset (- here line-start)))
    (unless (and (= old-bytes new-bytes) (string=? new (byte-substring text ls ws-end)))
      (fe-delete-region line-start (+ line-start old-bytes))
      (goto-char line-start)
      (insert new))
    (goto-char (+ line-start (if (<= offset old-bytes) new-bytes (+ new-bytes (- offset old-bytes)))))
    column))

(define *last-tab* #f)            ; (buffer line-start column) after a TAB
(define *indenting-by-tab* #f)    ; true while TAB (not RET) indents a line

(define (indent-line (cycle #f))
  "Indent the current line according to its language: the new column, or
#f when the language has no rules.  With CYCLE (a repeated TAB) in a
language with 'cycle, step through the levels."
  (let ((spec (current-indent-spec)))
    (and spec
         (let* ((ctx (buffer-indent-context spec))
                (col (dynamic-wind (lambda () (set! *indenting-by-tab* cycle))
                                   (lambda () (compute-indentation ctx))
                                   (lambda () (set! *indenting-by-tab* #f)))))
           (and col
                (let* ((current (indentation-at (ictx-text ctx) (ictx-line ctx)))
                       (w (indent-spec-width spec))
                       (last *last-tab*)
                       (col (if (and cycle (indent-option spec 'cycle) last
                                     (equal? (car last) (get-buffer-name))
                                     (= (cadr last) (line-start))
                                     (= (caddr last) current))
                                (let ((levels (indent-option spec 'levels)))
                                  (cond (levels
                                         (let ((all (sort (delete-duplicates
                                                           (cons 0 ((command-procedure levels) ctx)))
                                                          <)))
                                           (or (find (lambda (l) (> l current)) all) (car all))))
                                        ((> current 0)
                                         (max 0 (- (* w (quotient (+ current w -1) w)) w)))
                                        (else col)))
                                col)))
                  (set-line-indentation ctx col)
                  (set! *last-tab* (list (get-buffer-name) (line-start) col))
                  col))))))

(define (clear-blank-line)
  "If the current line holds only blanks, delete them."
  (let* ((ls (line-start)) (text (buffer-substring ls (line-end))))
    (when (and (> (length text) 0)
               (let loop ((i 0)) (or (= i (length text)) (and (blank-byte-p (aref text i)) (loop (+ i 1))))))
      (fe-delete-region ls (+ ls (length text)))
      (goto-char ls))))

(define (newline-and-indent)
  "Insert a newline and indent the new line."
  (let ((spec (current-indent-spec)))
    (cond ((not spec) (insert "\n") #f)
          ;; a language with its own RET (Markdown continues lists)
          ((and (indent-option spec 'newline)
                ((command-procedure (indent-option spec 'newline)))))
          (else
           ;; a line left blank keeps no stray indentation
           (when (indent-option spec 'reindent-on-newline)
             (guard (e (#t #f)) (indent-line)))
           (clear-blank-line)
           (insert "\n")
           (indent-line)))))

(defcommand (indent-region)
  "Indent every line between the mark and the cursor."
  (let ((m (mark)) (p (point)))
    (if (not m)
        (message "No mark set")
        (let* ((start (line-start (min m p)))
               (end (max m p))
               ;; each line depends on the ones above: go top-down, counting
               ;; lines, since offsets move as lines change
               (lines (+ 1 (count-byte (buffer-substring start end) 10))))
          (let loop ((k 0) (ls start) (n 0))
            (if (< k lines)
                (begin
                  (goto-char ls)
                  (let* ((n (if (indent-line) (+ n 1) n))
                         (e (line-end ls)))
                    (if (>= e (buffer-size))
                        (begin (goto-char start) (message "Indented " (plural n "line")))
                        (loop (+ k 1) (+ e 1) n))))
                (begin (goto-char start) (message "Indented " (plural n "line")))))))))

(defcommand (indent-buffer)
  "Indent the whole buffer."
  (beginning-of-buffer) (set-mark) (end-of-buffer) (indent-region) (beginning-of-buffer))

(define (indentation-for)
  (let ((spec (current-indent-spec)))
    (and spec (compute-indentation (buffer-indent-context spec)))))

;;; ------------------------------------------------------------------
;;; Keys
;;; ------------------------------------------------------------------

(define (electric-line-p spec)
  "Does the current line start with one of the language's closing tokens?"
  (let* ((line (trim (buffer-substring (line-start) (line-end))))
         (words (indent-option spec 'electric-words '()))
         (prefixes (indent-option spec 'electric-prefixes '())))
    (or (any (lambda (p) (starts-with-p p line)) prefixes)
        (let ((w (byte-substring line 0
                                 (let loop ((i 0))
                                   (if (and (< i (length line))
                                            (let ((b (aref line i))) (or (word-byte-p* b) (= b 92))))
                                       (loop (+ i 1)) i)))))
          (and (member w words) #t)))))

(define (indent-self-insert key)
  "On *SELF-INSERT-HOOK*: TAB, RET and electric keys."
  (let ((spec (current-indent-spec)))
    (and spec
         (cond ((string=? key "\t") (indent-line #t) #t)
               ((or (string=? key "\n") (string=? key "\r")) (newline-and-indent) #t)
               ((string.find (indent-option spec 'electric-keys "") key 0)
                (insert key)
                (when (electric-line-p spec) (indent-line))
                #t)
               (else #f)))))

(add-hook! '*self-insert-hook* 'indent-self-insert)

(defcommand (newline-and-indent-command) (newline-and-indent))

(global-set-key "C-j" 'newline-and-indent-command)
(global-set-key "C-x C-i" 'indent-region)

;;; ------------------------------------------------------------------
;;; Style lisp
;;; ------------------------------------------------------------------

;; a frame: #(open col line op count first-col second-col second-line quoted index parent)
(define (make-lisp-frame open col line quoted index parent)
  (vector open col line #f 0 #f #f #f quoted index parent))
(define (lf-col f) (vector-ref f 1))
(define (lf-line f) (vector-ref f 2))
(define (lf-op f) (vector-ref f 3))
(define (lf-count f) (vector-ref f 4))
(define (lf-first-col f) (vector-ref f 5))
(define (lf-second-col f) (vector-ref f 6))
(define (lf-second-line f) (vector-ref f 7))
(define (lf-quoted f) (vector-ref f 8))
(define (lf-index f) (vector-ref f 9))
(define (lf-parent f) (vector-ref f 10))

(define (lisp-delimiter-p b)
  (or (blank-byte-p b) (= b 10) (memv b '(40 41 91 93 34 59 39 96 44))))

(define (lisp-scan text start to)
  "Scan Lisp from START to TO: the stack of open lists (innermost first)
and the state at TO: 'code, 'string or 'comment."
  (let ((i start) (line 0) (stack '()) (pending #f) (state 'code))
    (define (note pos)
      (when (pair? stack)
        (let ((f (car stack)))
          (vector-set! f 4 (+ 1 (lf-count f)))
          (case (lf-count f)
            ((1) (vector-set! f 5 (column-at text pos)))
            ((2) (vector-set! f 6 (column-at text pos)) (vector-set! f 7 line))))))
    (let loop ()
      (when (and (< i to) (eq? state 'code))
        (let ((b (aref text i)))
          (cond
            ((= b 10) (set! line (+ line 1)) (set! i (+ i 1)))
            ((blank-byte-p b) (set! i (+ i 1)))
            ((= b 59) (set! i (or (byte-position text 10 i to) to)))
            ((and (= b 35) (< (+ i 1) to) (= (aref text (+ i 1)) 124))     ; #| ... |#
             (let ((e (search-bytes "|#" text (+ i 2) to)))
               (if (not e) (set! state 'comment)
                   (begin (set! line (+ line (count-byte text 10 i e))) (set! i (+ e 2))))))
            ((= b 34)                                                      ; string
             (note (or pending i)) (set! pending #f)
             (let sloop ((j (+ i 1)))
               (cond ((>= j to) (set! state 'string))
                     ((= (aref text j) 92) (sloop (+ j 2)))
                     ((= (aref text j) 34) (set! i (+ j 1)))
                     (else (when (= (aref text j) 10) (set! line (+ line 1))) (sloop (+ j 1))))))
            ((or (= b 40) (= b 91))
             (let ((start-pos (or pending i)) (quoted (and pending #t)))
               (note start-pos)
               (set! stack (cons (make-lisp-frame i (column-at text i) line quoted
                                                  (if (pair? stack) (lf-count (car stack)) 0)
                                                  (if (pair? stack) (car stack) #f))
                                 stack))
               (set! pending #f)
               (set! i (+ i 1))))
            ((or (= b 41) (= b 93))
             (when (pair? stack) (set! stack (cdr stack)))
             (set! pending #f) (set! i (+ i 1)))
            ((memv b '(39 96 44))
             (unless pending (set! pending i))
             (set! i (+ i 1))
             (when (and (< i to) (= (aref text i) 64)) (set! i (+ i 1))))
            ((and (= b 35) (< (+ i 1) to) (= (aref text (+ i 1)) 92))      ; #\x
             (note (or pending i)) (set! pending #f)
             (set! i (min to (+ i 3)))
             (let skip () (when (and (< i to) (not (lisp-delimiter-p (aref text i)))) (set! i (+ i 1)) (skip))))
            ((and (= b 35) (< (+ i 1) to) (memv (aref text (+ i 1)) '(39 40))) ; #' #(
             (unless pending (set! pending i))
             (set! i (+ i (if (= (aref text (+ i 1)) 39) 2 1))))
            (else                                                          ; an atom
             (let ((j (let skip ((j i)) (if (and (< j to) (not (lisp-delimiter-p (aref text j)))) (skip (+ j 1)) j))))
               (when (and (pair? stack) (= 0 (lf-count (car stack))) (not pending))
                 (vector-set! (car stack) 3 (string-downcase (byte-substring text i j))))
               (note (or pending i))
               (set! pending #f)
               (set! i (max j (+ i 1)))))))
        (loop)))
    (values stack state)))

(define (strip-package op)
  (let ((colon (byte-position-back op 58)))
    (if (and colon (> colon 0)) (byte-substring op (+ colon 1)) op)))

(define (lisp-distinguished ctx frame)
  "How many arguments of FRAME's operator are distinguished (indented by 4
when they start a line); the rest is a body, by 2.  #f for a call."
  (let* ((op (strip-package (lf-op frame)))
         (entry (assoc op (ictx-option ctx 'specials '())))
         (parent (lf-parent frame)))
    (cond (entry (cdr entry))
          ;; a local function in flet/labels/macrolet: like defun
          ((and parent (lf-parent parent)
                (member (lf-op (lf-parent parent)) (ictx-option ctx 'local-function-forms '()))
                (= (lf-index parent) 2))
           1)
          ((and (ictx-option ctx 'def-forms #t) (starts-with-p "def" op)) 0)
          ((starts-with-p "with-" op) 1)
          ((starts-with-p "do-" op) 1)
          (else #f))))

(define-indent-style 'lisp
  (lambda (ctx)
    (let ((text (ictx-text ctx)) (ls (ictx-line ctx)))
      ;; ;;; comments are left where they are
      (and (not (starts-with-p ";;;" (line-string text ls)))
           (let-values (((stack state) (lisp-scan text 0 ls)))
             (and (eq? state 'code)
                  (if (null? stack) 0
                      (let* ((f (car stack))
                             (c (lf-col f))
                             (n (and (lf-op f) (not (lf-quoted f)) (lisp-distinguished ctx f))))
                        (cond ((or (lf-quoted f) (not (lf-op f))) (or (lf-first-col f) (+ c 1)))
                              (n (if (< (- (lf-count f) 1) n) (+ c 4) (+ c 2)))
                              ((and (lf-second-col f) (= (lf-second-line f) (lf-line f))) (lf-second-col f))
                              (else (or (lf-first-col f) (+ c 1)))))))))))
  (lambda (text ls) (and (< ls (length text)) (= (aref text ls) 40))))

;;; ------------------------------------------------------------------
;;; Scanner shared by c and prolog
;;; ------------------------------------------------------------------

;; a frame: #(kind open line-start seen-case)
(define (make-brace-frame kind open line-start) (vector kind open line-start #f))
(define (bf-kind f) (vector-ref f 0))
(define (bf-open f) (vector-ref f 1))
(define (bf-line-start f) (vector-ref f 2))
(define (bf-seen-case f) (vector-ref f 3))

(define (brace-scan ctx to)
  "Scan C-like text up to TO: the stack of open braces and parens
(innermost first), the state ('code 'string 'comment), the start of an
open comment, and the index of the last significant byte."
  (let* ((text (ictx-text ctx))
         (line-comments (ictx-option ctx 'line-comments '("//")))
         (block-comments (ictx-option ctx 'block-comments '(("/*" . "*/"))))
         (string-chars (let ((s (ictx-option ctx 'strings "\"'")))
                         (let loop ((i 0) (acc '())) (if (= i (length s)) acc (loop (+ i 1) (cons (aref s i) acc))))))
         (multiline-strings (ictx-option ctx 'multiline-strings #f))
         (preprocessor (ictx-option ctx 'preprocessor #f))
         (case-labels (ictx-option ctx 'case-labels #f))
         (i 0) (bol #t) (stack '()) (last-sig #f)
         (state 'code) (comment-start #f))
    (let loop ()
      (when (and (< i to) (eq? state 'code))
        (let ((b (aref text i)))
          (cond
            ((= b 10) (set! bol #t) (set! i (+ i 1)))
            ((blank-byte-p b) (set! i (+ i 1)))
            ((and bol preprocessor (= b 35))
             ;; a preprocessor line, with \ continuations
             (let pp ()
               (let ((e (line-end-index text i)))
                 (if (and (< e to) (> e 0) (= (aref text (- e 1)) 92))
                     (begin (set! i (+ e 1)) (pp))
                     (set! i e)))))
            (else
             (when bol
               (set! bol #f)
               (when (and case-labels
                          (or (match-octets-at text i "case" to) (match-octets-at text i "default" to))
                          (pair? stack) (eq? (bf-kind (car stack)) 'brace))
                 (vector-set! (car stack) 3 #t)))
             (cond
               ((any (lambda (c) (match-octets-at text i c to)) line-comments)
                (set! i (line-end-index text i)))
               ((find (lambda (c) (match-octets-at text i (car c) to)) block-comments)
                => (lambda (bc)
                     (let ((e (search-bytes (cdr bc) text (+ i (length (car bc))) to)))
                       (if (not e)
                           (begin (set! state 'comment) (set! comment-start i))
                           (set! i (+ e (length (cdr bc))))))))
               ((memv b string-chars)
                (let sloop ((j (+ i 1)))
                  (cond ((>= j to) (set! state 'string))
                        ((= (aref text j) 92) (sloop (+ j 2)))
                        ((= (aref text j) b) (set! last-sig (min j (- to 1))) (set! i (+ j 1)))
                        ((and (= (aref text j) 10) (not multiline-strings))
                         (set! last-sig (min j (- to 1))) (set! i (+ j 1)))
                        (else (sloop (+ j 1))))))
               ((= b 123)
                (set! stack (cons (make-brace-frame 'brace i (line-start-index text i)) stack))
                (set! last-sig i) (set! i (+ i 1)))
               ((or (= b 40) (= b 91))
                (set! stack (cons (make-brace-frame 'paren i (line-start-index text i)) stack))
                (set! last-sig i) (set! i (+ i 1)))
               ((memv b '(125 41 93))
                (when (pair? stack) (set! stack (cdr stack)))
                (set! last-sig i) (set! i (+ i 1)))
               (else (set! last-sig i) (set! i (+ i 1)))))))
        (loop)))
    (values stack state comment-start last-sig)))

(define (paren-alignment ctx frame closing)
  "Column for a line inside an open ( or [: under the first argument, or
one step in when the paren ends its line."
  (let* ((text (ictx-text ctx))
         (o (bf-open frame))
         (after (skip-blanks text (+ o 1) (line-end-index text o))))
    (if (or (>= after (length text)) (= (aref text after) 10)
            (any (lambda (c) (match-octets-at text after c (length text)))
                 (ictx-option ctx 'line-comments '("//"))))
        (+ (indentation-at text (bf-line-start frame)) (if closing 0 (ictx-width ctx)))
        (if closing (column-at text o) (column-at text after)))))

(define (comment-continuation ctx comment-start)
  (let ((text (ictx-text ctx)))
    (if (starts-with-p "*" (line-string text (ictx-line ctx)))
        (+ 1 (column-at text comment-start))
        (+ 3 (column-at text comment-start)))))

;;; ------------------------------------------------------------------
;;; Style c
;;; ------------------------------------------------------------------

(define (c-top-level-line-p text ls)
  (and (< ls (length text))
       (let ((b (aref text ls)))
         (not (or (blank-byte-p b) (memv b '(10 35 47 42 125 41 93)))))))

(define-indent-style 'c
  (lambda (ctx)
    (let* ((text (ictx-text ctx)) (ls (ictx-line ctx)) (w (ictx-width ctx)))
      (let-values (((stack state comment-start last-sig) (brace-scan ctx ls)))
        (case state
          ((string) #f)
          ((comment) (comment-continuation ctx comment-start))
          (else
           (let* ((c0 (first-nonblank text ls))
                  (b0 (and (< c0 (length text)) (aref text c0)))
                  (closing (and b0 (memv b0 '(125 41 93)) #t))
                  (f (and (pair? stack) (car stack)))
                  (continued (and last-sig
                                  (or (not f) (> last-sig (bf-open f)))
                                  (not (memv (aref text last-sig) '(59 123 125 58 44)))
                                  (not (eqv? b0 123)))))
             (cond
               ((and b0 (= b0 35) (ictx-option ctx 'preprocessor)) 0)
               ((not f) (if continued w 0))
               ((eq? (bf-kind f) 'paren) (paren-alignment ctx f closing))
               (else
                (let ((base (+ (indentation-at text (bf-line-start f)) w)))
                  (cond ((eqv? b0 125) (- base w))
                        ((and (ictx-option ctx 'case-labels)
                              (or (match-octets-at text c0 "case" (length text))
                                  (match-octets-at text c0 "default" (length text))))
                         base)
                        (else (+ base (if (bf-seen-case f) w 0) (if continued w 0)))))))))))))
  c-top-level-line-p)

;;; ------------------------------------------------------------------
;;; Style prolog
;;; ------------------------------------------------------------------

(define-indent-style 'prolog
  (lambda (ctx)
    (let* ((text (ictx-text ctx)) (ls (ictx-line ctx)))
      (let-values (((stack state comment-start last-sig) (brace-scan ctx ls)))
        (case state
          ((string) #f)
          ((comment) (comment-continuation ctx comment-start))
          (else
           (let* ((c0 (first-nonblank text ls))
                  (b0 (and (< c0 (length text)) (aref text c0)))
                  (f (and (pair? stack) (car stack))))
             (cond (f (paren-alignment ctx f (and b0 (memv b0 '(41 93 125)) #t)))
                   ((or (not last-sig) (= (aref text last-sig) 46)) 0) ; after a clause's "."
                   (else (ictx-width ctx)))))))))
  (lambda (text ls)
    (and (< ls (length text))
         (let ((b (aref text ls))) (or (and (<= 97 b) (<= b 122)) (= b 58))))))   ; a clause head or :-

;;; ------------------------------------------------------------------
;;; Style python
;;; ------------------------------------------------------------------

(define (python-scan text to)
  "The stack of open brackets, the state ('code or 'string), the last
significant byte, and the starts of the statements seen (latest first)."
  (let ((i 0) (bol #t) (stack '()) (last-sig #f) (statements '()) (backslash #f) (state 'code))
    (let loop ()
      (when (and (< i to) (eq? state 'code))
        (let ((b (aref text i)))
          (cond
            ((= b 10)
             (set! backslash (and last-sig (= (aref text last-sig) 92) (= last-sig (- i 1))))
             (set! bol #t) (set! i (+ i 1)))
            ((blank-byte-p b) (set! i (+ i 1)))
            ((= b 35) (set! i (line-end-index text i)))      ; # comment
            (else
             (when bol
               (set! bol #f)
               (when (and (null? stack) (not backslash))
                 (set! statements (cons (line-start-index text i) statements))))
             (cond
               ((or (= b 34) (= b 39))
                (let ((triple (and (< (+ i 2) to) (= (aref text (+ i 1)) b) (= (aref text (+ i 2)) b))))
                  (let sloop ((j (+ i (if triple 3 1))))
                    (cond ((>= j to) (when triple (set! state 'string)) (set! i to))
                          ((= (aref text j) 92) (sloop (+ j 2)))
                          ((and triple (< (+ j 2) to) (= (aref text j) b)
                                (= (aref text (+ j 1)) b) (= (aref text (+ j 2)) b))
                           (set! last-sig (min (+ j 2) (- to 1))) (set! i (+ j 3)))
                          ((and (not triple) (= (aref text j) b))
                           (set! last-sig (min j (- to 1))) (set! i (+ j 1)))
                          ((and (not triple) (= (aref text j) 10))
                           (set! last-sig (min j (- to 1))) (set! i (+ j 1)))
                          (else (sloop (+ j 1)))))))
               ((memv b '(40 91 123))
                (set! stack (cons (make-brace-frame 'paren i (line-start-index text i)) stack))
                (set! last-sig i) (set! i (+ i 1)))
               ((memv b '(41 93 125))
                (when (pair? stack) (set! stack (cdr stack)))
                (set! last-sig i) (set! i (+ i 1)))
               (else (set! last-sig i) (set! i (+ i 1)))))))
        (loop)))
    (values stack state last-sig statements)))

(define *python-dedenters*
  '(("else" "if" "elif" "for" "while" "try" "except")
    ("elif" "if" "elif")
    ("except" "try" "except")
    ("finally" "try" "except" "else")
    ("case" "match" "case")))

(define-indent-style 'python
  (lambda (ctx)
    (let* ((text (ictx-text ctx)) (ls (ictx-line ctx)) (w (ictx-width ctx)))
      (let-values (((stack state last-sig statements) (python-scan text ls)))
        (cond
          ((eq? state 'string) #f)
          ((pair? stack)
           (let* ((c0 (first-nonblank text ls))
                  (b0 (and (< c0 (length text)) (aref text c0))))
             (paren-alignment ctx (car stack) (and b0 (memv b0 '(41 93 125)) #t))))
          ((null? statements) 0)
          (else
           (let* ((prev (car statements))
                  (base (indentation-at text prev))
                  (col (cond ((and last-sig (= (aref text last-sig) 58)) (+ base w))
                             ((member (first-word text prev) '("return" "pass" "break" "continue" "raise"))
                              (- base w))
                             (else base)))
                  (openers (let ((e (assoc (first-word text ls) *python-dedenters*))) (and e (cdr e)))))
             (if openers
                 ;; else/elif/except/finally: line up with the matching opener
                 (let loop ((ss statements) (limit col))
                   (if (null? ss) col
                       (let ((ind (indentation-at text (car ss))))
                         (if (< ind limit)
                             (if (member (first-word text (car ss)) openers)
                                 ind
                                 (loop (cdr ss) ind))
                             (loop (cdr ss) limit)))))
                 col)))))))
  (lambda (text ls)
    (and (< ls (length text))
         (let ((b (aref text ls)))
           (not (or (blank-byte-p b) (memv b '(10 35 34 39 41 93 125))))))))

;;; ------------------------------------------------------------------
;;; Style block -- keywords open and close blocks
;;; ------------------------------------------------------------------

(define (last-token line)
  (let ((p (byte-position-back line 32))) (if p (byte-substring line (+ p 1)) line)))

(define (alphanumeric-byte? b) (or (and (<= 48 b) (<= b 57)) (and (<= 65 b) (<= b 90)) (and (<= 97 b) (<= b 122)) (>= b 128)))

(define-indent-style 'block
  (lambda (ctx)
    (let* ((text (ictx-text ctx)) (ls (ictx-line ctx)) (w (ictx-width ctx))
           (comment (ictx-option ctx 'comment))
           (prev (previous-code-line text ls comment)))
      (if (not prev) 0
          (let* ((pline (let* ((l (line-string text prev))
                               (c (and comment (string-search (string-append " " comment) l))))
                          (string-trim-right (if c (byte-substring l 0 c) l))))
                 (pword (first-word text prev))
                 (word (first-word text ls))
                 (open-words (ictx-option ctx 'open-words '()))
                 (close-words (ictx-option ctx 'close-words '()))
                 (mid-words (ictx-option ctx 'mid-words '()))
                 (one-line (and (pair? close-words)
                                (member (last-token pline) close-words)
                                (not (member pword close-words))))
                 (opens (and (not one-line)
                             (or (member pword open-words)
                                 (member pword mid-words)
                                 (any (lambda (e)
                                        (and (ends-with-p e pline)
                                             ;; a word ending must be a whole word
                                             (or (not (alphanumeric-byte? (aref e 0)))
                                                 (= (length e) (length pline))
                                                 (not (alphanumeric-byte?
                                                       (aref pline (- (length pline) (length e) 1)))))))
                                      (ictx-option ctx 'open-endings '()))
                                 (any (lambda (s) (string-search s pline)) (ictx-option ctx 'open-anywhere '())))
                             (not (any (lambda (s) (string-search s pline)) (ictx-option ctx 'not-open-anywhere '())))))
                 (c0 (first-nonblank text ls))
                 (closes (or (member word close-words)
                             (member word mid-words)
                             (and (< c0 (length text))
                                  (string.find (ictx-option ctx 'close-chars "")
                                               (string (integer->char (aref text c0))) 0)))))
            (+ (indentation-at text prev) (if opens w 0) (if closes (- w) 0)))))))
