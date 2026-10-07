;;;; markdown.lisp -- colours and indentation for Markdown
;;;;
;;;; Loaded at start-up; edit and press C-x C-r (reload-scripts) to see the
;;;; change.
;;;;
;;;; Markdown is not made of tokens, as programs are, but of lines: a line
;;;; that starts with # is a heading, with > a quotation, with - or 1. a
;;;; list item, with ``` the start of a block of code.  Inside a line, a few
;;;; marks change the type: *emphasis*, **strong**, `code`, [links](url).
;;;; So Markdown has a highlighter of its own (MARKDOWN-HIGHLIGHT), which
;;;; reads the text a line at a time; DEFINE-LANGUAGE's :HIGHLIGHTER puts it
;;;; in place of the tokenizer.  A block of code whose first line names a
;;;; language (```lisp, ```python) is coloured as that language.
;;;;
;;;; Faces: :heading, :emphasis, :strong, :link (set them with SET-COLOR),
;;;; :string for code, :comment for quotations, rules and fences,
;;;; :block-comment for <!-- comments -->, :keyword for list markers.
;;;;
;;;; Indentation:
;;;;   RET     in a list item, starts the next item ("- ", "2. ", "> ");
;;;;           on an empty item, ends the list with a blank line.  Elsewhere the new line
;;;;           keeps the indentation of the text above.
;;;;   TAB     on a list item, nests it under the item above (TAB again:
;;;;           back); on other lines, indents under the text above.  TAB
;;;;           repeated moves the line through the levels of the list.

(in-package #:sbemacs)

(declaim (optimize (safety 3) (debug 2)))

;;; ------------------------------------------------------------------
;;; Reading lines
;;; ------------------------------------------------------------------

(declaim (ftype (function (octets fixnum fixnum) (values fixnum &optional)) md-skip-spaces))
(defun md-skip-spaces (text i end)
  (loop while (and (< i end) (= (aref text i) 32)) do (incf i))
  i)

(declaim (ftype (function (octets fixnum fixnum) (values (or null fixnum) &optional))
                md-list-marker-end))
(defun md-list-marker-end (text i end)
  "If a list marker (- * + or 1. 1)) followed by a space starts at I, the
index just after the marker and its spaces."
  (when (< i end)
    (let ((b (aref text i)))
      (flet ((after (j)
               (when (or (= j end) (= (aref text j) 32) (= (aref text j) 9))
                 (md-skip-spaces text j end))))
        (cond ((member b '(45 42 43)) (after (1+ i)))      ; - * +
              ((<= 48 b 57)
               (let ((j i))
                 (loop while (and (< j end) (<= 48 (aref text j) 57) (< (- j i) 9)) do (incf j))
                 (when (and (< j end) (member (aref text j) '(46 41)))  ; . )
                   (after (1+ j)))))
              (t nil))))))

(declaim (ftype (function (octets fixnum fixnum) (values (or null fixnum) &optional (or null fixnum)))
                md-fence))
(defun md-fence (text ls le)
  "If the line [LS, LE) is a code fence (``` or ~~~, up to 3 spaces in),
its fence character and length."
  (let ((i (md-skip-spaces text ls le)))
    (when (and (<= (- i ls) 3) (< (+ i 2) le))
      (let ((b (aref text i)))
        (when (member b '(96 126))                         ; ` ~
          (let ((j i))
            (loop while (and (< j le) (= (aref text j) b)) do (incf j))
            (when (>= (- j i) 3)
              (values b (- j i)))))))))

(declaim (ftype (function (octets fixnum fixnum) (values t &optional)) md-rule-p))
(defun md-rule-p (text ls le)
  "A thematic break: three or more - * or _, with nothing else but spaces."
  (let ((i (md-skip-spaces text ls le)))
    (when (< i le)
      (let ((b (aref text i)) (n 0))
        (and (member b '(45 42 95))
             (loop for k from i below le
                   for c = (aref text k)
                   always (or (= c b) (= c 32) (= c 9))
                   do (when (= c b) (incf n)))
             (>= n 3))))))

(declaim (ftype (function (octets fixnum fixnum) (values t &optional)) md-setext-underline-p md-blank-p))
(defun md-setext-underline-p (text ls le)
  "A line of = or - only: it makes the paragraph line above a heading."
  (let ((i (md-skip-spaces text ls le)))
    (when (and (< i le) (<= (- i ls) 3))
      (let ((b (aref text i)))
        (and (member b '(61 45))
             (let ((j i))
               (loop while (and (< j le) (= (aref text j) b)) do (incf j))
               (= (md-skip-spaces text j le) le)))))))

(defun md-blank-p (text ls le)
  (loop for k from ls below le always (member (aref text k) '(32 9 13))))

(declaim (ftype (function (string) (values (or null language) &optional)) md-code-language))
(defparameter *markdown-code-names*
  '(("lisp" . "Common Lisp") ("cl" . "Common Lisp") ("common-lisp" . "Common Lisp")
    ("elisp" . "Common Lisp") ("py" . "Python") ("lean4" . "Lean")
    ("ocaml" . "ML") ("sml" . "ML") ("latex" . "TeX") ("rb" . "Ruby")
    ("hs" . "Haskell") ("pl" . "Prolog") ("cpp" . "C") ("c++" . "C"))
  "Names used after ``` that are not a language's name or extension.")

(defun md-code-language (info)
  "The language named by a fence's info string: ```lisp, ```python ..."
  (let ((name (string-downcase (string-trim " {}." (subseq info 0 (or (position #\Space info) (length info)))))))
    (when (plusp (length name))
      (let ((alias (cdr (assoc name *markdown-code-names* :test #'string=))))
        (or (and alias (find-language alias))
            (find-if (lambda (l) (string-equal (language-name l) name)) *languages*)
            (find-if (lambda (l) (member (concatenate 'string "." name) (language-extensions l)
                                         :test #'string=))
                     *languages*))))))

;;; ------------------------------------------------------------------
;;; Inside a line
;;; ------------------------------------------------------------------

(declaim (inline md-word-byte-p md-space-byte-p))
(defun md-word-byte-p (b) (or (<= 48 b 57) (<= 65 b 90) (<= 97 b 122) (>= b 128)))
(defun md-space-byte-p (b) (or (= b 32) (= b 9) (= b 10) (= b 13)))

(declaim (ftype (function (octets fixnum fixnum fixnum fixnum) (values (or null fixnum) &optional))
                md-closing-delimiter))
(defun md-closing-delimiter (text start end b n)
  "Where the closing run of N bytes B (* or _) starts, in [START, END)."
  (loop for k from start to (- end n)
        when (and (loop for m below n always (= (aref text (+ k m)) b))
                  (not (md-space-byte-p (aref text (1- k))))   ; **x** not ** x**
                  (or (>= (+ k n) end) (/= (aref text (+ k n)) b))
                  (or (/= b 95) (>= (+ k n) end) (not (md-word-byte-p (aref text (+ k n))))))
          return k))

(declaim (ftype (function (octets fixnum fixnum octets) (values null &optional)) md-inline))
(defun md-inline (text start end colors)
  "Colour the inline marks of TEXT[START, END)."
  (let ((i start))
    (declare (type fixnum i))
    (loop while (< i end)
          do (let ((b (aref text i)) (next (1+ i)))
               (declare (type fixnum next))
               (cond
                 ;; \* is a literal star
                 ((and (= b 92) (< (1+ i) end))
                  (setf next (+ i 2)))
                 ;; `code`, ``code with ` inside``
                 ((= b 96)
                  (let ((j i))
                    (loop while (and (< j end) (= (aref text j) 96)) do (incf j))
                    (let* ((n (- j i))
                           (close (loop for k from j to (- end n)
                                        when (and (loop for m below n always (= (aref text (+ k m)) 96))
                                                  (or (= (+ k n) end) (/= (aref text (+ k n)) 96)))
                                          return k)))
                      (if close
                          (progn (paint colors i (+ close n) +string+)
                                 (setf next (+ close n)))
                          (setf next j)))))
                 ;; [text](url), ![image](url), [text][ref]
                 ((or (= b 91) (and (= b 33) (< (1+ i) end) (= (aref text (1+ i)) 91)))
                  (let* ((open (if (= b 33) (1+ i) i))
                         (close (position 93 text :start open :end end)))
                    (if (null close)
                        (setf next (1+ open))
                        (progn
                          (paint colors i (1+ close) +link+)
                          (setf next (1+ close))
                          (when (and (< next end) (member (aref text next) '(40 91)))   ; ( [
                            (let ((stop (position (if (= (aref text next) 40) 41 93) text
                                                  :start next :end end)))
                              (when stop
                                (paint colors next (1+ stop) +comment+)
                                (setf next (1+ stop)))))))))
                 ;; <https://...>, <!-- comment --> (one line), <tag>
                 ((= b 60)
                  (let ((close (position 62 text :start i :end end)))
                    (cond ((null close))
                          ((and (< (+ i 3) end) (= (aref text (1+ i)) 33))
                           (paint colors i (1+ close) +block-comment+)
                           (setf next (1+ close)))
                          ((search "://" (sb-ext:octets-to-string text :start i :end close
                                                                       :external-format :latin-1))
                           (paint colors i (1+ close) +link+)
                           (setf next (1+ close))))))
                 ;; a bare https:// address
                 ((and (= b 104) (or (= i start) (not (md-word-byte-p (aref text (1- i)))))
                       (let ((s (sb-ext:octets-to-string text :start i :end (min end (+ i 8))
                                                              :external-format :latin-1)))
                         (or (starts-with-p "https://" s) (starts-with-p "http://" s))))
                  (let ((stop (or (position-if (lambda (c) (or (md-space-byte-p c) (= c 41) (= c 62)))
                                               text :start i :end end)
                                  end)))
                    (paint colors i stop +link+)
                    (setf next stop)))
                 ;; ~~strike~~
                 ((and (= b 126) (< (1+ i) end) (= (aref text (1+ i)) 126))
                  (let ((close (search #.(make-array 2 :element-type '(unsigned-byte 8)
                                                       :initial-contents '(126 126))
                                       text :start2 (+ i 2) :end2 end)))
                    (when close
                      (paint colors i (+ close 2) +comment+)
                      (setf next (+ close 2)))))
                 ;; *emphasis*, **strong**, _emphasis_, __strong__
                 ((member b '(42 95))
                  (let ((j i))
                    (loop while (and (< j end) (= (aref text j) b) (< (- j i) 3)) do (incf j))
                    (let ((n (- j i)))
                      (if (and (< j end)
                               (not (md-space-byte-p (aref text j)))
                               ;; snake_case is not emphasis
                               (or (/= b 95) (= i start) (not (md-word-byte-p (aref text (1- i))))))
                          (let ((close (md-closing-delimiter text (1+ j) end b n)))
                            (if close
                                (progn (paint colors i (+ close n) (if (>= n 2) +strong+ +emphasis+))
                                       ;; marks inside **strong `code`** still count
                                       (md-inline text j close colors)
                                       (when (>= n 2)
                                         (loop for k from j below close
                                               when (= (aref colors k) +alpha+)
                                                 do (setf (aref colors k) +strong+)))
                                       (setf next (+ close n)))
                                (setf next j)))
                          (setf next j)))))
                 (t nil))
               (setf i (max next (1+ i))))))
  nil)

;;; ------------------------------------------------------------------
;;; The highlighter
;;; ------------------------------------------------------------------

(declaim (ftype (function (t octets fixnum octets) (values null &optional)) markdown-highlight))
(defun markdown-highlight (lang text len colors)
  "Colour TEXT[0, LEN) as Markdown.  The text starts at the beginning of
a line (the C core sees to that)."
  (declare (ignore lang))
  (fill colors +alpha+ :end len)
  (let ((ls 0)
        (fence nil) (fence-len 0) (code-start 0) (code-lang nil)
        (comment nil)                   ; inside a <!-- comment -->
        (prev-ls nil) (prev-paragraph nil))
    (declare (type fixnum ls code-start fence-len))
    (flet ((finish-code (end)
             (if code-lang
                 (let* ((n (- end code-start))
                        (sub (subseq text code-start end))
                        (c (make-array n :element-type '(unsigned-byte 8) :initial-element +alpha+)))
                   (highlight-octets code-lang sub n c)
                   (replace colors c :start1 code-start))
                 (paint colors code-start end +string+))))
      (loop while (< ls len)
            do (let* ((le (or (position 10 text :start ls :end len) len))
                      (paragraph nil))
                 (cond
                   ;; inside ```code```
                   (fence
                    (multiple-value-bind (b n) (md-fence text ls le)
                      (when (and b (= b fence) (>= n fence-len)
                                 (= (md-skip-spaces text (+ (md-skip-spaces text ls le) n) le) le))
                        (finish-code ls)
                        (paint colors ls le +comment+)
                        (setf fence nil))))
                   ;; inside a <!-- comment --> that spans lines
                   (comment
                    (let ((close (search "-->" (sb-ext:octets-to-string text :start ls :end le
                                                                             :external-format :latin-1))))
                      (if close
                          (progn (paint colors ls (+ ls close 3) +block-comment+)
                                 (setf comment nil)
                                 (md-inline text (+ ls close 3) le colors))
                          (paint colors ls le +block-comment+))))
                   ;; ``` opens a block of code
                   ((md-fence text ls le)
                    (multiple-value-bind (b n) (md-fence text ls le)
                      (let* ((i (+ (md-skip-spaces text ls le) n))
                             (info (string-trim " " (sb-ext:octets-to-string text :start i :end le
                                                                                   :external-format :latin-1))))
                        (setf fence b fence-len n
                              code-start (min len (1+ le))
                              code-lang (md-code-language info))
                        (paint colors ls le +comment+))))
                   ;; a paragraph line followed by === or --- is a heading
                   ((and prev-paragraph (md-setext-underline-p text ls le))
                    (paint colors prev-ls le +heading+))
                   ;; ---, ***, ___
                   ((md-rule-p text ls le)
                    (paint colors ls le +comment+))
                   ;; # Heading
                   ((let ((i (md-skip-spaces text ls le)))
                      (and (<= (- i ls) 3) (< i le) (= (aref text i) 35)
                           (let ((j i))
                             (loop while (and (< j le) (= (aref text j) 35)) do (incf j))
                             (and (<= (- j i) 6) (or (= j le) (= (aref text j) 32))))))
                    (paint colors ls le +heading+)
                    (md-inline text ls le colors)
                    (loop for k from ls below le
                          unless (= (aref colors k) +string+) do (setf (aref colors k) +heading+)))
                   ;; > quotation
                   ((let ((i (md-skip-spaces text ls le)))
                      (and (< i le) (= (aref text i) 62)))
                    (paint colors ls le +comment+))
                   ;; <!-- a comment
                   ((let ((i (md-skip-spaces text ls le)))
                      (and (< (+ i 3) le)
                           (string= "<!--" (sb-ext:octets-to-string text :start i :end (+ i 4)
                                                                         :external-format :latin-1))
                           (not (search "-->" (sb-ext:octets-to-string text :start i :end le
                                                                            :external-format :latin-1)))))
                    (paint colors ls le +block-comment+)
                    (setf comment t))
                   ;; - item, 1. item
                   ((let ((i (md-skip-spaces text ls le)))
                      (md-list-marker-end text i le))
                    (let* ((i (md-skip-spaces text ls le))
                           (after (md-list-marker-end text i le)))
                      (paint colors i after +keyword+)
                      ;; - [ ] and - [x] task boxes
                      (if (and (< (+ after 2) le) (= (aref text after) 91) (= (aref text (+ after 2)) 93)
                               (member (aref text (1+ after)) '(32 120 88)))         ; [ ] [x] [X]
                          (progn (paint colors after (+ after 3) +keyword+)
                                 (md-inline text (+ after 3) le colors))
                          (md-inline text after le colors))))
                   ;; | table | row |
                   ((let ((i (md-skip-spaces text ls le)))
                      (and (< i le) (= (aref text i) 124)))
                    (if (loop for k from ls below le
                              always (member (aref text k) '(124 45 58 32 9 13)))
                        (paint colors ls le +comment+)         ; |---|:---:|
                        (progn (md-inline text ls le colors)
                               (loop for k from ls below le
                                     when (= (aref text k) 124) do (setf (aref colors k) +keyword+)))))
                   ;; an ordinary line
                   ((md-blank-p text ls le))
                   (t
                    (setf paragraph t)
                    (md-inline text ls le colors)))
                 (setf prev-ls ls
                       prev-paragraph paragraph
                       ls (1+ le))))
      ;; a block of code still open at the end of the visible text
      (when (and fence (< code-start len))
        (finish-code len))))
  nil)

;;; ------------------------------------------------------------------
;;; Indentation
;;; ------------------------------------------------------------------

(declaim (ftype (function (octets fixnum) (values (or null fixnum) &optional)) md-item-text-column))
(defun md-item-text-column (text ls)
  "If the line at LS is a list item or a quotation, the column where its
text starts (under which continuation lines and nested items go)."
  (let* ((le (line-end-index text ls))
         (i (md-skip-spaces text ls le))
         (after (or (md-list-marker-end text i le)
                    (and (< i le) (= (aref text i) 62) (md-skip-spaces text (1+ i) le)))))
    (and after (column-at text after))))

(declaim (ftype (function (octets fixnum) (values t &optional)) md-inside-code-p))
(defun md-inside-code-p (text ls)
  "Is the line at LS inside a ``` block (counting the fences above it)?"
  (let ((open nil))
    (loop for p = 0 then (1+ nl)
          for nl = (position 10 text :start p)
          while (and nl (< p ls))
          do (when (md-fence text p nl) (setf open (not open))))
    open))

(define-indent-style :markdown (ctx)
  (let* ((text (ictx-text ctx))
         (ls (ictx-line ctx))
         (prev (previous-code-line text ls)))
    (cond ((null prev) 0)
          ((md-inside-code-p text ls) (indentation-at text prev))
          ;; an item: where the item above starts (its sibling); but TAB on
          ;; an item already there nests it under the text of the one above
          ((let ((le (line-end-index text ls)))
             (md-list-marker-end text (md-skip-spaces text ls le) le))
           (let ((sibling (indentation-at text prev))
                 (nested (md-item-text-column text prev)))
             (if (and *indenting-by-tab* nested
                      (= (indentation-at text ls) sibling))
                 nested
                 sibling)))
          ;; under the text of the item above, or like the line above
          (t (or (md-item-text-column text prev)
                 (indentation-at text prev))))))

(defun markdown-levels (ctx)
  "The columns TAB cycles through: the margin, the indentation of the
lines above and the text of the items above."
  (let* ((text (ictx-text ctx))
         (ls (ictx-line ctx))
         (levels '()))
    (loop for p = (previous-code-line text ls) then (previous-code-line text p)
          for k from 0 below 20
          while p
          do (push (indentation-at text p) levels)
             (let ((c (md-item-text-column text p))) (when c (push c levels)))
             (when (zerop (indentation-at text p)) (return)))
    levels))

;;; RET: the next item of a list, or the end of it

(declaim (ftype (function (string) (values (or null string) &optional (member nil :end)))
                markdown-continuation))
(defun markdown-continuation (line)
  "For LINE (the text of the current line), the beginning of the next
line: \"- \" after \"- milk\", \"3. \" after \"2. eggs\", \"> \" after a
quotation.  The second value is :END when LINE is an empty item, which
ends the list."
  (let* ((indent (or (position-if-not (lambda (c) (member c '(#\Space #\Tab))) line) (length line)))
         (rest (subseq line indent))
         (lead (subseq line 0 indent)))
    (flet ((result (marker body)
             (if (zerop (length (string-trim " " body)))
                 (values marker :end)
                 (values (concatenate 'string lead marker) nil))))
      (cond ((zerop (length rest)) nil)
            ;; - [ ] task
            ((and (>= (length rest) 6) (member (char rest 0) '(#\- #\* #\+))
                  (string= " [" rest :start2 1 :end2 3) (char= (char rest 4) #\]))
             (result (format nil "~C [ ] " (char rest 0)) (subseq rest 5)))
            ((and (>= (length rest) 2) (member (char rest 0) '(#\- #\* #\+)) (char= (char rest 1) #\Space))
             (result (format nil "~C " (char rest 0)) (subseq rest 2)))
            ((digit-char-p (char rest 0))
             (let ((j (or (position-if-not #'digit-char-p rest) (length rest))))
               (if (and (< (1+ j) (length rest)) (member (char rest j) '(#\. #\)))
                        (char= (char rest (1+ j)) #\Space))
                   (result (format nil "~D~C " (1+ (parse-integer rest :end j)) (char rest j))
                           (subseq rest (+ j 2)))
                   nil)))
            ((char= (char rest 0) #\>)
             (result "> " (subseq rest 1)))
            (t nil)))))

(defun markdown-newline ()
  "RET in Markdown: continue a list or a quotation; an empty item ends it.
Returns NIL (do the usual RET) elsewhere, and inside blocks of code."
  (let* ((ls (line-start))
         (le (line-end ls))
         (line (buffer-substring ls le))
         (spec (current-indent-spec)))
    (when (and (= (point) le) spec
               (not (md-inside-code-p (ictx-text (buffer-indent-context spec))
                                      (ictx-line (buffer-indent-context spec)))))
      (multiple-value-bind (next state) (markdown-continuation line)
        (cond ((eq state :end)
               ;; "- " alone: take the marker away and leave the line
               ;; blank, which ends the list; the cursor goes below it
               (goto-char ls)
               (delete-char (count-if (lambda (b) (/= (logand b #xC0) #x80))
                                      (buffer-octets ls le)))
               (insert (string #\Newline))
               t)
              (next
               (insert (concatenate 'string (string #\Newline) next))
               t)
              (t nil))))))

;;; ------------------------------------------------------------------
;;; The language
;;; ------------------------------------------------------------------

(define-language "Markdown"
  :extensions '(".md" ".markdown" ".mdown" ".mkd")
  :highlighter 'markdown-highlight)

(define-indentation "Markdown"
  :style :markdown :width 2 :tabs nil
  :cycle t
  :levels 'markdown-levels
  :newline 'markdown-newline)


;;; Visual word wrapping. Positions are UTF-8 byte offsets, as in the C core.
;;; No buffer text is changed, including fenced code, links and list markers.

(defun markdown-wrap-end (octets columns)
  "Number of bytes in one visual row. Keep words together where they fit.
Tabs use eight-column stops; every UTF-8 character occupies one screen cell."
  (declare (type (simple-array (unsigned-byte 8) (*)) octets)
           (type (integer 1 *) columns))
  (let ((pos 0) (column 0) (boundary nil) (size (length octets)))
    (loop while (< pos size)
          for byte = (aref octets pos)
          for bytes = (cond ((<= #xC2 byte #xDF) 2)
                            ((<= #xE0 byte #xEF) 3)
                            ((<= #xF0 byte #xF4) 4)
                            (t 1))
          for width = (cond ((= byte 13) 0)
                            ((= byte 9) (- 8 (mod column 8)))
                            ((or (< byte 32) (= byte 127)) 2)
                            (t 1))
          do (when (= byte 10) (return-from markdown-wrap-end (1+ pos)))
             (when (> (+ column width) columns)
               (return-from markdown-wrap-end
                 (if (and (plusp pos) (member byte '(9 32)))
                     pos
                     (or boundary (if (plusp pos) pos (min size bytes))))))
             (incf column width)
             (incf pos (min bytes (- size pos)))
             (when (member byte '(9 32)) (setf boundary pos)))
    pos))

(defun markdown-wrap-row (filename text-sap len columns)
  "C display callback: -1 enables Markdown wrapping; 0 retains fixed rows."
  (declare (type string filename) (type integer len columns))
  (let ((language (language-for-file filename)))
    (cond ((or (null language) (not (string= (language-name language) "Markdown"))
               (not (plusp columns))) 0)
          ((zerop len) -1)
          (t (let ((octets (make-array len :element-type '(unsigned-byte 8))))
               (sb-kernel:copy-ub8-from-system-area text-sap 0 octets 0 len)
               (markdown-wrap-end octets columns))))))
