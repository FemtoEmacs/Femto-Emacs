;;;; indent.lisp -- automatic indentation
;;;;
;;;; A script (see loader.lisp): edit it and press C-x C-r, no rebuild.
;;;;
;;;;   TAB      indent the current line (press again to cycle through the
;;;;            possible levels in Python, Haskell, Lean and ML)
;;;;   RET      new line, indented
;;;;   C-x C-i  indent the region between mark and point
;;;;   "electric" keys re-indent the line when it starts with a closing
;;;;   token: } in C, "else:" in Python, "end" in Ruby, \end in TeX
;;;;
;;;; Each language file in languages/ says how it is indented with
;;;; DEFINE-INDENTATION, choosing a style:
;;;;
;;;;   :lisp    Lisp and Scheme: body forms by 2, arguments aligned
;;;;   :c       brace languages: blocks, continuation lines, parentheses
;;;;   :python  colons open blocks, else/elif/except/finally dedent
;;;;   :prolog  clause bodies, parentheses
;;;;   :block   keyword-driven, for Ruby, Haskell, ML, Lean, TeX ...
;;;;
;;;; A new style is a function from an INDENT-CONTEXT to a column (or NIL
;;;; to leave the line alone), registered with DEFINE-INDENT-STYLE.
;;;;
;;;; Everything works on the raw UTF-8 bytes of the buffer (fetched in bulk
;;;; with BUFFER-OCTETS), the way the highlighter does.

(in-package #:sbemacs)

;;; ------------------------------------------------------------------
;;; Languages and styles
;;; ------------------------------------------------------------------

(defstruct (indent-spec (:constructor %make-indent-spec))
  (style :block)
  (width 4)
  (tabs :auto)          ; t, nil, or :auto (follow the file)
  (options '()))

(defvar *indentation* (make-hash-table :test 'equalp)
  "Language name -> INDENT-SPEC.")

(defun define-indentation (language &rest options
                           &key (style :block) (width 4) (tabs :auto) &allow-other-keys)
  "Say how LANGUAGE (the name given to DEFINE-LANGUAGE) is indented.

  (define-indentation \"C\" :style :c :width 4)

:WIDTH is the indentation step.  :TABS is T (indent with tabs, 8 columns
wide), NIL (spaces) or :AUTO (tabs if most indented lines in the file
start with a tab).  :CYCLE T makes a repeated TAB change the level;
:LEVELS names a function of the context returning the columns it cycles
through (default: steps of :WIDTH).  :NEWLINE names a function that RET
calls first; when it returns true it has handled the key (Markdown uses
it to continue lists).  The other options depend on the style; see the
language files for examples."
  (setf (gethash language *indentation*)
        (%make-indent-spec :style style :width width :tabs tabs :options options)))

(defun indent-option (spec key &optional default)
  (getf (indent-spec-options spec) key default))

(defvar *indent-styles* (make-hash-table)
  "Style keyword -> (function line-start-predicate).")

(defmacro define-indent-style (name (context) &body body)
  "Define an indentation style.  BODY computes the column for the line in
CONTEXT, or NIL to leave it alone.  An optional (:start-line-p FN) form
first in BODY names a predicate (text line-start) telling where scanning
may safely begin; without it only the lines just above are looked at."
  (let ((start (when (and (consp (first body)) (eq (car (first body)) :start-line-p))
                 (second (pop body)))))
    `(setf (gethash ,name *indent-styles*)
           (cons (lambda (,context) ,@body) ,start))))

(defstruct (indent-context (:conc-name ictx-))
  text          ; octets: from a safe starting line to the end of the line
  line          ; index in TEXT where the line being indented starts
  spec)

(defun ictx-width (ctx) (indent-spec-width (ictx-spec ctx)))
(defun ictx-option (ctx key &optional default) (indent-option (ictx-spec ctx) key default))

;;; ------------------------------------------------------------------
;;; Byte-level helpers
;;; ------------------------------------------------------------------

(declaim (inline blank-byte-p))
(defun blank-byte-p (b) (or (= b 32) (= b 9) (= b 13) (= b 12)))

(defun word-byte-p* (b)
  (or (<= 48 b 57) (<= 65 b 90) (<= 97 b 122) (= b 95) (>= b 128)))

(defun line-start-index (text i)
  (let ((p (position 10 text :end (min i (length text)) :from-end t)))
    (if p (1+ p) 0)))

(defun line-end-index (text i)
  (or (position 10 text :start (min i (length text))) (length text)))

(defun skip-blanks (text i &optional (end (length text)))
  (loop while (and (< i end) (blank-byte-p (aref text i))) do (incf i))
  i)

(defun column-at (text i)
  "Screen column of byte I (tabs every 8 columns, UTF-8 aware)."
  (let ((col 0))
    (loop for k from (line-start-index text i) below i
          for b = (aref text k)
          do (cond ((= b 9) (setf col (* 8 (1+ (floor col 8)))))
                   ((= (logand b #xC0) #x80))
                   (t (incf col))))
    col))

(defun first-nonblank (text ls)
  "Index of the first non-blank byte of the line starting at LS (it may be
the newline or the end of TEXT for a blank line)."
  (skip-blanks text ls (line-end-index text ls)))

(defun indentation-at (text ls)
  (column-at text (first-nonblank text ls)))

(defun line-blank-p (text ls)
  (let ((i (first-nonblank text ls)))
    (or (>= i (length text)) (= (aref text i) 10))))

(defun octets-string (text start end)
  (sb-ext:octets-to-string text :start start :end end
                                :external-format '(:utf-8 :replacement #\?)))

(defun line-string (text ls)
  "The line at LS without its indentation and trailing blanks."
  (string-right-trim '(#\Space #\Tab #\Return)
                     (octets-string text (first-nonblank text ls) (line-end-index text ls))))

(defun first-word (text ls)
  "The first word of the line: letters, digits and _, plus a leading \\."
  (let* ((i (first-nonblank text ls))
         (j i))
    (when (and (< j (length text)) (= (aref text j) 92)) (incf j))
    (loop while (and (< j (length text)) (word-byte-p* (aref text j))) do (incf j))
    (octets-string text i j)))

(defun starts-with-p (prefix string)
  (and (>= (length string) (length prefix)) (string= prefix string :end2 (length prefix))))

(defun ends-with-p (suffix string)
  (and (>= (length string) (length suffix))
       (string= suffix string :start2 (- (length string) (length suffix)))))

(defun previous-line-start (text ls)
  (and (> ls 0) (line-start-index text (1- ls))))

(defun previous-code-line (text ls &optional comment)
  "Start of the nearest line above LS that is neither blank nor (when
COMMENT, a prefix string, is given) a comment-only line."
  (loop for p = (previous-line-start text ls) then (previous-line-start text p)
        while p
        unless (or (line-blank-p text p)
                   (and comment (starts-with-p comment (line-string text p))))
          return p))

(defun match-octets-at (text i string end)
  (let ((n (length string)))
    (and (<= (+ i n) end)
         (loop for k below n
               always (= (aref text (+ i k)) (char-code (char string k)))))))

;;; ------------------------------------------------------------------
;;; Building the context
;;; ------------------------------------------------------------------

(defun find-start-line (text from to predicate)
  "The last line start in [FROM, TO) satisfying PREDICATE."
  (loop with best = nil
        for ls = from then (1+ nl)
        for nl = (position 10 text :start ls :end to)
        while (< ls to)
        do (when (funcall predicate text ls) (setf best ls))
        while nl
        finally (return best)))

(defun make-context (spec raw from pos)
  "RAW holds buffer bytes starting at offset FROM and reaching past the end
of the line containing POS.  Returns a context, or NIL when RAW does not
reach back far enough to find a safe place to start scanning."
  (let* ((style (gethash (indent-spec-style spec) *indent-styles*))
         (start-p (cdr style))
         (rel (- pos from))
         (ls (line-start-index raw rel))
         (le (line-end-index raw rel))
         (first-ls (if (zerop from)
                       0
                       (let ((nl (position 10 raw :end ls))) (if nl (1+ nl) ls))))
         (scan-start (cond ((null start-p) first-ls)
                           ((find-start-line raw first-ls ls start-p))
                           ((zerop from) 0))))
    (when scan-start
      (make-indent-context :text (subseq raw scan-start le)
                           :line (- ls scan-start)
                           :spec spec))))

(defun buffer-indent-context (spec &optional (pos (point)))
  (let ((size (buffer-size)))
    (loop for look = 16384 then (* look 4)
          do (let* ((from (max 0 (- pos look)))
                    (ctx (make-context spec (buffer-octets from (min size (+ pos 4096))) from pos)))
               (when ctx (return ctx))))))

(defun compute-indentation (ctx)
  (let ((style (gethash (indent-spec-style (ictx-spec ctx)) *indent-styles*)))
    (unless style
      (error "Unknown indentation style ~S" (indent-spec-style (ictx-spec ctx))))
    (let ((col (funcall (car style) ctx)))
      (and col (max 0 col)))))

(defun indentation-for-text (language text)
  "For testing: the column the last line of TEXT would be indented to."
  (let* ((spec (or (gethash language *indentation*)
                   (error "No indentation for ~A" language)))
         (raw (octets text)))
    (compute-indentation (make-context spec raw 0 (length raw)))))

;;; ------------------------------------------------------------------
;;; Changing the buffer
;;; ------------------------------------------------------------------

(defun current-indent-spec ()
  (let ((lang (language-for-file (or (buffer-filename) (get-buffer-name)))))
    (and lang (gethash (language-name lang) *indentation*))))

(defun use-tabs-p (spec text)
  (let ((tabs (indent-spec-tabs spec)))
    (if (eq tabs :auto)
        (let ((with-tabs 0) (with-spaces 0))
          (loop for ls = 0 then (1+ nl)
                for nl = (position 10 text :start ls)
                while (< ls (length text))
                do (when (< ls (length text))
                     (let ((b (aref text ls)))
                       (cond ((= b 9) (incf with-tabs))
                             ((and (= b 32) (< (1+ ls) (length text)) (= (aref text (1+ ls)) 32))
                              (incf with-spaces)))))
                while nl)
          (> with-tabs with-spaces))
        tabs)))

(defun indent-string (column tabs)
  (if tabs
      (concatenate 'string
                   (make-string (floor column 8) :initial-element #\Tab)
                   (make-string (mod column 8) :initial-element #\Space))
      (make-string column :initial-element #\Space)))

(defun set-line-indentation (ctx column)
  "Re-indent the context's line to COLUMN, keeping the cursor on the same
text (or just after the indentation when it was inside it)."
  (let* ((text (ictx-text ctx))
         (ls (ictx-line ctx))
         (ws-end (first-nonblank text ls))
         (old-bytes (- ws-end ls))
         (new (indent-string column (use-tabs-p (ictx-spec ctx) text)))
         (new-bytes (length new))           ; tabs and spaces: one byte each
         (here (point))
         (line-start (current-line-start))
         (offset (- here line-start)))
    (unless (and (= old-bytes new-bytes)
                 (string= new (octets-string text ls ws-end)))
      (goto-char line-start)
      (delete-char old-bytes)
      (insert new))
    (goto-char (+ line-start
                  (if (<= offset old-bytes)
                      new-bytes
                      (+ new-bytes (- offset old-bytes)))))
    column))

(defun current-line-start ()
  "Byte offset of the start of the current line."
  (line-start))

(defvar *last-tab* nil
  "(buffer line-start column) after a TAB, to cycle on the next one.")

(defvar *indenting-by-tab* nil
  "True while TAB (not RET or indent-region) indents a line: a style may
then move the line, e.g. nest a Markdown list item.")

(defun indent-line (&optional cycle)
  "Indent the current line according to its language.  Returns the new
column, or NIL when the language has no indentation rules.  With CYCLE
(a repeated TAB) in a language whose spec has :CYCLE, step down one level
each time, wrapping round to the computed column."
  (let ((spec (current-indent-spec)))
    (when spec
      (let* ((ctx (buffer-indent-context spec))
             (col (let ((*indenting-by-tab* cycle)) (compute-indentation ctx))))
        (when col
          (let ((current (indentation-at (ictx-text ctx) (ictx-line ctx)))
                (w (indent-spec-width spec))
                (last *last-tab*))
            (when (and cycle (indent-option spec :cycle) last
                       (equal (first last) (get-buffer-name))
                       (= (second last) (current-line-start))
                       (= (third last) current))
              (let ((levels (indent-option spec :levels)))
                (setf col
                      (cond (levels
                             ;; the style's own levels: the next one to the
                             ;; right, then back to the leftmost
                             (let ((all (sort (remove-duplicates
                                               (cons 0 (funcall levels ctx)))
                                              #'<)))
                               (or (find-if (lambda (l) (> l current)) all)
                                   (first all))))
                            ((> current 0) (max 0 (- (* w (ceiling current w)) w)))
                            (t col)))))
            (set-line-indentation ctx col)
            (setf *last-tab* (list (get-buffer-name) (current-line-start) col))
            col))))))

(defun newline-and-indent ()
  "Insert a newline and indent the new line."
  (let ((spec (current-indent-spec)))
    (cond ((null spec) (insert (string #\Newline)) nil)
          ;; a language with its own RET (Markdown continues lists)
          ((and (indent-option spec :newline)
                (funcall (indent-option spec :newline))))
          (t
           ;; a line left blank keeps no stray indentation
           (when (indent-option spec :reindent-on-newline)
             (ignore-errors (indent-line)))
           (clear-blank-line)
           (insert (string #\Newline))
           (indent-line)))))

(defun clear-blank-line ()
  "If the current line holds only blanks, delete them."
  (let* ((ls (line-start))
         (text (buffer-octets ls (line-end))))
    (when (and (plusp (length text)) (every #'blank-byte-p text))
      (goto-char ls)
      (delete-char (length text)))))

(defun indent-region ()
  "Indent every line between the mark and the cursor."
  (let ((m (mark)) (p (point)))
    (if (null m)
        (message "No mark set")
        (let* ((start (line-start (min m p)))
               (end (max m p))
               ;; each line depends on the ones above, so go top-down,
               ;; counting lines since offsets move as lines change
               (lines (1+ (count 10 (buffer-octets start end))))
               (ls start)
               (n 0))
          (dotimes (k lines)
            (goto-char ls)
            (when (indent-line) (incf n))
            (let ((e (line-end ls)))
              (when (>= e (buffer-size)) (return))
              (setf ls (1+ e))))
          (goto-char start)
          (message "Indented ~D line~:P" n)))))

(defun indent-buffer ()
  "Indent the whole buffer."
  (beginning-of-buffer)
  (set-mark)
  (end-of-buffer)
  (indent-region)
  (beginning-of-buffer))

(defun indentation-for ()
  "The column the current line would be indented to (or NIL)."
  (let ((spec (current-indent-spec)))
    (and spec (compute-indentation (buffer-indent-context spec)))))

;;; ------------------------------------------------------------------
;;; Keys
;;; ------------------------------------------------------------------

(defun electric-line-p (spec)
  "Does the current line start with one of the language's closing tokens?"
  (let* ((line (trim (current-line-text)))
         (words (indent-option spec :electric-words))
         (prefixes (indent-option spec :electric-prefixes)))
    (or (some (lambda (p) (starts-with-p p line)) prefixes)
        (let ((w (let ((end (or (position-if-not (lambda (c) (or (alphanumericp c) (char= c #\_) (char= c #\\)))
                                                 line)
                                (length line))))
                   (subseq line 0 end))))
          (member w words :test #'string=)))))

(defun indent-self-insert (key)
  "On *SELF-INSERT-HOOK*: TAB, RET and electric keys."
  (let ((spec (current-indent-spec)))
    (when spec
      (cond ((string= key (string #\Tab))
             (indent-line t)
             t)
            ((or (string= key (string #\Newline)) (string= key (string #\Return)))
             (newline-and-indent)
             t)
            ((find (char key 0) (indent-option spec :electric-keys ""))
             (insert key)
             (when (electric-line-p spec)
               (indent-line))
             t)))))

(pushnew 'indent-self-insert *self-insert-hook*)

;;; ------------------------------------------------------------------
;;; Style :lisp
;;; ------------------------------------------------------------------

(defstruct (lisp-frame (:conc-name lf-))
  open col line op (count 0) first-col second-col second-line quoted index parent)

(defun lisp-delimiter-p (b)
  (or (blank-byte-p b) (= b 10) (member b '(40 41 91 93 34 59 39 96 44))))

(defun lisp-scan (text start to)
  "Scan Lisp from START to TO.  Returns the stack of open lists (innermost
first) and the state at TO: :code, :string or :comment."
  (let ((i start) (line 0) (stack '()) (pending nil))
    (flet ((note (pos)
             (let ((f (first stack)))
               (when f
                 (incf (lf-count f))
                 (case (lf-count f)
                   (1 (setf (lf-first-col f) (column-at text pos)))
                   (2 (setf (lf-second-col f) (column-at text pos)
                            (lf-second-line f) line)))))))
      (loop while (< i to)
            do (let ((b (aref text i)))
                 (cond
                   ((= b 10) (incf line) (incf i))
                   ((blank-byte-p b) (incf i))
                   ((= b 59)                ; ; comment
                    (setf i (or (position 10 text :start i :end to) to)))
                   ((and (= b 35) (< (1+ i) to) (= (aref text (1+ i)) 124)) ; #| ... |#
                    (let ((e (search '(124 35) text :start2 (+ i 2) :end2 to)))
                      (unless e (return-from lisp-scan (values stack :comment)))
                      (incf line (count 10 text :start i :end e))
                      (setf i (+ e 2))))
                   ((= b 34)                ; string
                    (note (or pending i)) (setf pending nil)
                    (let ((j (1+ i)))
                      (loop (cond ((>= j to) (return-from lisp-scan (values stack :string)))
                                  ((= (aref text j) 92) (incf j 2))
                                  ((= (aref text j) 34) (return))
                                  (t (when (= (aref text j) 10) (incf line)) (incf j))))
                      (setf i (1+ j))))
                   ((or (= b 40) (= b 91))  ; ( [
                    (let ((start-pos (or pending i))
                          (quoted (and pending t)))
                      (note start-pos)
                      (push (make-lisp-frame :open i :col (column-at text i) :line line
                                             :quoted quoted
                                             :index (if stack (lf-count (first stack)) 0)
                                             :parent (first stack))
                            stack)
                      (setf pending nil)
                      (incf i)))
                   ((or (= b 41) (= b 93))
                    (pop stack) (setf pending nil) (incf i))
                   ((member b '(39 96 44))  ; ' ` , ,@
                    (unless pending (setf pending i))
                    (incf i)
                    (when (and (< i to) (= (aref text i) 64)) (incf i)))
                   ((and (= b 35) (< (1+ i) to) (= (aref text (1+ i)) 92)) ; #\x
                    (note (or pending i)) (setf pending nil)
                    (setf i (min to (+ i 3)))
                    (loop while (and (< i to) (not (lisp-delimiter-p (aref text i)))) do (incf i)))
                   ((and (= b 35) (< (1+ i) to) (member (aref text (1+ i)) '(39 40))) ; #' #(
                    (unless pending (setf pending i))
                    (incf i (if (= (aref text (1+ i)) 39) 2 1)))
                   (t                       ; an atom
                    (let ((j i))
                      (loop while (and (< j to) (not (lisp-delimiter-p (aref text j)))) do (incf j))
                      (let ((f (first stack)))
                        (when (and f (zerop (lf-count f)) (not pending))
                          (setf (lf-op f) (string-downcase (octets-string text i j)))))
                      (note (or pending i))
                      (setf pending nil i (max j (1+ i))))))))
      (values stack :code))))

(defun strip-package (op)
  (let ((colon (position #\: op :from-end t)))
    (if (and colon (plusp colon)) (subseq op (1+ colon)) op)))

(defun lisp-distinguished (ctx frame)
  "How many arguments of FRAME's operator are 'distinguished' (indented by
4 when they start a line); the rest is a body, indented by 2.  NIL for an
ordinary function call."
  (let* ((op (strip-package (lf-op frame)))
         (specials (ictx-option ctx :specials))
         (entry (assoc op specials :test #'string=))
         (parent (lf-parent frame)))
    (cond (entry (cdr entry))
          ;; a local function in flet/labels/macrolet: like defun
          ((and parent (lf-parent parent)
                (member (lf-op (lf-parent parent)) (ictx-option ctx :local-function-forms)
                        :test #'equal)
                (= (lf-index parent) 2))
           1)
          ((and (ictx-option ctx :def-forms t) (starts-with-p "def" op)) 0)
          ((starts-with-p "with-" op) 1)
          ((starts-with-p "do-" op) 1)
          (t nil))))

(define-indent-style :lisp (ctx)
  (:start-line-p (lambda (text ls) (and (< ls (length text)) (= (aref text ls) 40))))
  (let* ((text (ictx-text ctx))
         (ls (ictx-line ctx)))
    ;; ;;; comments are left where they are
    (unless (starts-with-p ";;;" (line-string text ls))
      (multiple-value-bind (stack state) (lisp-scan text 0 ls)
        (when (eq state :code)
          (let ((f (first stack)))
            (if (null f)
                0
                (let ((c (lf-col f))
                      (n (and (lf-op f) (not (lf-quoted f)) (lisp-distinguished ctx f))))
                  (cond ((or (lf-quoted f) (null (lf-op f)))
                         (or (lf-first-col f) (1+ c)))
                        (n (if (< (1- (lf-count f)) n) (+ c 4) (+ c 2)))
                        ((and (lf-second-col f) (= (lf-second-line f) (lf-line f)))
                         (lf-second-col f))
                        (t (or (lf-first-col f) (1+ c))))))))))))

;;; ------------------------------------------------------------------
;;; Scanner shared by :c and :prolog
;;; ------------------------------------------------------------------

(defstruct (brace-frame (:conc-name bf-)) kind open line-start seen-case)

(defun brace-scan (ctx to)
  "Scan C-like text up to TO.  Returns: stack of open braces/parens
(innermost first), state (:code :string :comment), the start of the open
comment, and the index of the last significant byte (outside comments)."
  (let* ((text (ictx-text ctx))
         (line-comments (ictx-option ctx :line-comments '("//")))
         (block-comments (ictx-option ctx :block-comments '(("/*" . "*/"))))
         (string-chars (map 'list #'char-code (ictx-option ctx :strings "\"'")))
         (multiline-strings (ictx-option ctx :multiline-strings nil))
         (preprocessor (ictx-option ctx :preprocessor nil))
         (case-labels (ictx-option ctx :case-labels nil))
         (i 0) (bol t) (stack '()) (last-sig nil))
    (loop while (< i to)
          do (let ((b (aref text i)))
               (cond
                 ((= b 10) (setf bol t) (incf i))
                 ((blank-byte-p b) (incf i))
                 ((and bol preprocessor (= b 35))
                  ;; a preprocessor line, with \ continuations
                  (loop (let ((e (line-end-index text i)))
                          (if (and (< e to) (> e 0) (= (aref text (1- e)) 92))
                              (setf i (1+ e))
                              (return (setf i e))))))
                 (t
                  (when bol
                    (setf bol nil)
                    (when (and case-labels
                               (or (match-octets-at text i "case" to)
                                   (match-octets-at text i "default" to))
                               stack (eq (bf-kind (first stack)) :brace))
                      (setf (bf-seen-case (first stack)) t)))
                  (cond
                    ((some (lambda (c) (match-octets-at text i c to)) line-comments)
                     (setf i (line-end-index text i)))
                    ((let ((bc (find-if (lambda (c) (match-octets-at text i (car c) to)) block-comments)))
                       (when bc
                         (let ((e (search (octets (cdr bc)) text :start2 (+ i (length (car bc))) :end2 to)))
                           (unless e (return-from brace-scan (values stack :comment i last-sig)))
                           (setf i (+ e (length (cdr bc))))
                           t))))
                    ((member b string-chars)
                     (let ((j (1+ i)))
                       (loop (cond ((>= j to) (return-from brace-scan (values stack :string nil last-sig)))
                                   ((= (aref text j) 92) (incf j 2))
                                   ((= (aref text j) b) (return))
                                   ((and (= (aref text j) 10) (not multiline-strings)) (return))
                                   (t (incf j))))
                       (setf last-sig (min j (1- to)) i (1+ j))))
                    ((= b 123)
                     (push (make-brace-frame :kind :brace :open i :line-start (line-start-index text i)) stack)
                     (setf last-sig i) (incf i))
                    ((or (= b 40) (= b 91))
                     (push (make-brace-frame :kind :paren :open i :line-start (line-start-index text i)) stack)
                     (setf last-sig i) (incf i))
                    ((member b '(125 41 93))
                     (pop stack) (setf last-sig i) (incf i))
                    (t (setf last-sig i) (incf i)))))))
    (values stack :code nil last-sig)))

(defun paren-alignment (ctx frame closing)
  "Column for a line inside an open ( or [: under the first argument, or
one step in when the paren ends its line."
  (let* ((text (ictx-text ctx))
         (o (bf-open frame))
         (after (skip-blanks text (1+ o) (line-end-index text o))))
    (if (or (>= after (length text)) (= (aref text after) 10)
            (some (lambda (c) (match-octets-at text after c (length text)))
                  (ictx-option ctx :line-comments '("//"))))
        (+ (indentation-at text (bf-line-start frame)) (if closing 0 (ictx-width ctx)))
        (if closing (column-at text o) (column-at text after)))))

(defun comment-continuation (ctx comment-start)
  (let ((text (ictx-text ctx)))
    (if (starts-with-p "*" (line-string text (ictx-line ctx)))
        (1+ (column-at text comment-start))
        (+ 3 (column-at text comment-start)))))

;;; ------------------------------------------------------------------
;;; Style :c
;;; ------------------------------------------------------------------

(defun c-top-level-line-p (text ls)
  (and (< ls (length text))
       (let ((b (aref text ls)))
         (not (or (blank-byte-p b) (member b '(10 35 47 42 125 41 93)))))))

(define-indent-style :c (ctx)
  (:start-line-p #'c-top-level-line-p)
  (let* ((text (ictx-text ctx))
         (ls (ictx-line ctx))
         (w (ictx-width ctx)))
    (multiple-value-bind (stack state comment-start last-sig) (brace-scan ctx ls)
      (case state
        (:string nil)
        (:comment (comment-continuation ctx comment-start))
        (t
         (let* ((c0 (first-nonblank text ls))
                (b0 (and (< c0 (length text)) (aref text c0)))
                (closing (and b0 (member b0 '(125 41 93))))
                (f (first stack))
                (continued (and last-sig
                                (or (null f) (> last-sig (bf-open f)))
                                (not (member (aref text last-sig) '(59 123 125 58 44)))
                                (not (eql b0 123)))))
           (cond
             ((and b0 (= b0 35) (ictx-option ctx :preprocessor)) 0)
             ((null f) (if continued w 0))
             ((eq (bf-kind f) :paren) (paren-alignment ctx f closing))
             (t
              (let ((base (+ (indentation-at text (bf-line-start f)) w)))
                (cond ((eql b0 125) (- base w))
                      ((and (ictx-option ctx :case-labels)
                            (or (match-octets-at text c0 "case" (length text))
                                (match-octets-at text c0 "default" (length text))))
                       base)
                      (t (+ base
                            (if (bf-seen-case f) w 0)
                            (if continued w 0)))))))))))))

;;; ------------------------------------------------------------------
;;; Style :prolog
;;; ------------------------------------------------------------------

(define-indent-style :prolog (ctx)
  (:start-line-p (lambda (text ls)
                   (and (< ls (length text))
                        (let ((b (aref text ls)))
                          (or (<= 97 b 122) (= b 58))))))   ; a clause head or :- directive
  (let* ((text (ictx-text ctx))
         (ls (ictx-line ctx)))
    (multiple-value-bind (stack state comment-start last-sig) (brace-scan ctx ls)
      (case state
        (:string nil)
        (:comment (comment-continuation ctx comment-start))
        (t
         (let* ((c0 (first-nonblank text ls))
                (b0 (and (< c0 (length text)) (aref text c0)))
                (f (first stack)))
           (cond (f (paren-alignment ctx f (and b0 (member b0 '(41 93 125)))))
                 ((or (null last-sig) (= (aref text last-sig) 46)) 0) ; after a clause's "."
                 (t (ictx-width ctx)))))))))

;;; ------------------------------------------------------------------
;;; Style :python
;;; ------------------------------------------------------------------

(defun python-scan (text to)
  "Returns stack of open brackets (as BRACE-FRAMEs), state (:code or
:string), last significant byte, and the starts of the statements seen
(most recent first)."
  (let ((i 0) (bol t) (stack '()) (last-sig nil) (statements '()) (backslash nil))
    (loop while (< i to)
          do (let ((b (aref text i)))
               (cond
                 ((= b 10)
                  (setf backslash (and last-sig (= (aref text last-sig) 92) (= last-sig (1- i))))
                  (setf bol t) (incf i))
                 ((blank-byte-p b) (incf i))
                 ((= b 35) (setf i (line-end-index text i)))   ; # comment
                 (t
                  (when bol
                    (setf bol nil)
                    (when (and (null stack) (not backslash))
                      (push (line-start-index text i) statements)))
                  (cond
                    ((or (= b 34) (= b 39))
                     (let* ((triple (and (< (+ i 2) to) (= (aref text (1+ i)) b) (= (aref text (+ i 2)) b)))
                            (j (+ i (if triple 3 1))))
                       (loop (cond ((>= j to) (return-from python-scan
                                                (values stack (if triple :string :code) last-sig statements)))
                                   ((= (aref text j) 92) (incf j 2))
                                   ((and triple (< (+ j 2) to) (= (aref text j) b)
                                         (= (aref text (1+ j)) b) (= (aref text (+ j 2)) b))
                                    (incf j 2) (return))
                                   ((and (not triple) (= (aref text j) b)) (return))
                                   ((and (not triple) (= (aref text j) 10)) (return))
                                   (t (incf j))))
                       (setf last-sig (min j (1- to)) i (1+ j))))
                    ((member b '(40 91 123))
                     (push (make-brace-frame :kind :paren :open i :line-start (line-start-index text i)) stack)
                     (setf last-sig i) (incf i))
                    ((member b '(41 93 125))
                     (pop stack) (setf last-sig i) (incf i))
                    (t (setf last-sig i) (incf i)))))))
    (values stack :code last-sig statements)))

(defparameter *python-dedenters*
  '(("else" "if" "elif" "for" "while" "try" "except")
    ("elif" "if" "elif")
    ("except" "try" "except")
    ("finally" "try" "except" "else")
    ("case" "match" "case")))

(define-indent-style :python (ctx)
  (:start-line-p (lambda (text ls)
                   (and (< ls (length text))
                        (let ((b (aref text ls)))
                          (not (or (blank-byte-p b) (member b '(10 35 34 39 41 93 125))))))))
  (let* ((text (ictx-text ctx))
         (ls (ictx-line ctx))
         (w (ictx-width ctx)))
    (multiple-value-bind (stack state last-sig statements) (python-scan text ls)
      (cond
        ((eq state :string) nil)
        (stack (let* ((c0 (first-nonblank text ls))
                      (b0 (and (< c0 (length text)) (aref text c0))))
                 (paren-alignment ctx (first stack) (and b0 (member b0 '(41 93 125))))))
        ((null statements) 0)
        (t
         (let* ((prev (first statements))
                (base (indentation-at text prev))
                (col (cond ((and last-sig (= (aref text last-sig) 58)) (+ base w)) ; :
                           ((member (first-word text prev) '("return" "pass" "break" "continue" "raise")
                                    :test #'string=)
                            (- base w))
                           (t base)))
                (openers (cdr (assoc (first-word text ls) *python-dedenters* :test #'string=))))
           (if openers
               ;; else/elif/except/finally: line up with the matching opener
               (let ((limit col))
                 (dolist (s statements col)
                   (let ((ind (indentation-at text s)))
                     (when (< ind limit)
                       (if (member (first-word text s) openers :test #'string=)
                           (return ind)
                           (setf limit ind))))))
               col)))))))

;;; ------------------------------------------------------------------
;;; Style :block -- keywords open and close blocks
;;; ------------------------------------------------------------------

(defun last-token (line)
  (let ((p (position #\Space line :from-end t)))
    (if p (subseq line (1+ p)) line)))

(define-indent-style :block (ctx)
  (let* ((text (ictx-text ctx))
         (ls (ictx-line ctx))
         (w (ictx-width ctx))
         (comment (ictx-option ctx :comment))
         (prev (previous-code-line text ls comment)))
    (if (null prev)
        0
        (let* ((pline (let ((l (line-string text prev)))
                        ;; drop a trailing comment
                        (let ((c (and comment (search (concatenate 'string " " comment) l))))
                          (string-right-trim " " (if c (subseq l 0 c) l)))))
               (pword (first-word text prev))
               (word (first-word text ls))
               (open-words (ictx-option ctx :open-words))
               (close-words (ictx-option ctx :close-words))
               (mid-words (ictx-option ctx :mid-words))
               (one-line (and close-words
                              (member (last-token pline) close-words :test #'string=)
                              (not (member pword close-words :test #'string=))))
               (opens (and (not one-line)
                           (or (member pword open-words :test #'string=)
                               (member pword mid-words :test #'string=)
                               (some (lambda (e)
                                       (and (ends-with-p e pline)
                                            ;; a word ending must be a whole word
                                            (or (not (alphanumericp (char e 0)))
                                                (= (length e) (length pline))
                                                (not (alphanumericp
                                                      (char pline (- (length pline) (length e) 1)))))))
                                     (ictx-option ctx :open-endings))
                               (some (lambda (s) (search s pline)) (ictx-option ctx :open-anywhere)))
                           (notany (lambda (s) (search s pline)) (ictx-option ctx :not-open-anywhere))))
               (c0 (first-nonblank text ls))
               (closes (or (member word close-words :test #'string=)
                           (member word mid-words :test #'string=)
                           (and (< c0 (length text))
                                (find (code-char (aref text c0)) (ictx-option ctx :close-chars ""))))))
          (+ (indentation-at text prev)
             (if opens w 0)
             (if closes (- w) 0))))))
