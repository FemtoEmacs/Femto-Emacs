;;;; highlight.lisp -- syntax highlighting, in Common Lisp
;;;;
;;;; FemtoEmacs had a tokenizer in C whose tables (keywords, comment
;;;; delimiters) were filled from femtolisp with (newlanguage ...) and
;;;; (keyword ...).  Here the whole tokenizer is Lisp.  Before painting a
;;;; window the C core passes us the visible text (plus some text above it,
;;;; so comments opened off-screen are seen) as raw UTF-8 bytes, and we
;;;; return one face per byte.
;;;;
;;;; Working on bytes rather than characters keeps the colour array aligned
;;;; with the C buffer.  All delimiters and keywords are ASCII; bytes >= 128
;;;; (the pieces of UTF-8 characters) are treated as word constituents.

(in-package #:sbemacs)

(defconstant +symbol+ 1)
(defconstant +keyword+ 4)
(defconstant +alpha+ 5)
(defconstant +digits+ 6)
(defconstant +comment+ 7)
(defconstant +block-comment+ 8)
(defconstant +string+ 9)
;; faces for prose (Markdown): heading, emphasis, strong, link
(defconstant +heading+ 11)
(defconstant +emphasis+ 12)
(defconstant +strong+ 13)
(defconstant +link+ 14)

(deftype octets () '(simple-array (unsigned-byte 8) (*)))

(defun octets (string)
  (coerce (sb-ext:string-to-octets string :external-format :utf-8) 'octets))

(defstruct (language (:constructor %make-language))
  (name "" :type string)
  (extensions '() :type list)
  (line-comments '() :type list)        ; list of octet vectors
  (block-comments '() :type list)       ; list of (start . end) octet vectors
  (strings '() :type list)              ; list of octet vectors, longest first
  (escape (char-code #\\))              ; escape byte inside strings, or nil
  (char-prefix nil)                     ; e.g. #\ in Lisp: skip the next char
  (backslash-commands nil)              ; TeX: \word is a keyword
  (case-insensitive nil)
  (word-bytes (make-array 256 :element-type 'bit :initial-element 0)
   :type simple-bit-vector)
  ;; keywords indexed by their first byte; each bucket longest first
  (keywords (make-array 256 :initial-element nil) :type simple-vector)
  ;; a function (lang text len colors) that replaces the tokenizer, for
  ;; languages that are not made of tokens (Markdown)
  (highlighter nil))

(defvar *languages* '()
  "All defined languages, most recently defined first.")

(defvar *default-language* nil
  "Used for files whose extension no language claims.")

(defun word-byte-p (lang b)
  (= 1 (sbit (language-word-bytes lang) b)))

(defun make-word-table (extra)
  (let ((table (make-array 256 :element-type 'bit :initial-element 0)))
    (loop for b from 0 below 256
          when (or (<= 48 b 57) (<= 65 b 90) (<= 97 b 122) (= b 95) (>= b 128))
            do (setf (sbit table b) 1))
    (loop for c across extra do (setf (sbit table (char-code c)) 1))
    table))

(defun normalise-extension (ext)
  (string-downcase (if (and (plusp (length ext)) (char= (char ext 0) #\.))
                       ext
                       (concatenate 'string "." ext))))

(defun ensure-list (x) (if (listp x) x (list x)))

(defun define-language (name &key extensions line-comment block-comment
                                  (strings '("\"")) (escape #\\)
                                  char-prefix backslash-commands
                                  case-insensitive (word-chars "")
                                  keywords highlighter)
  "Define (or redefine) syntax highlighting for a language.

  (define-language \"C\"
    :extensions '(\".c\" \".h\")
    :line-comment \"//\"                  ; a string or a list of strings
    :block-comment '(\"/*\" . \"*/\")      ; a pair or a list of pairs
    :strings '(\"\\\"\" \"'\")              ; string delimiters
    :keywords '(\"if\" \"else\" \"while\"))

Other options: :ESCAPE (character, default #\\\\, or NIL), :CHAR-PREFIX
(e.g. \"#\\\\\" for Lisp character syntax), :BACKSLASH-COMMANDS (TeX),
:CASE-INSENSITIVE, :WORD-CHARS, extra characters that may appear inside
identifiers (\"-*+!?<>=/:%&\" for Lisp), and :HIGHLIGHTER, a function of
(LANGUAGE TEXT LENGTH COLORS) that colours the text itself instead of the
tokenizer (see languages/markdown.lisp)."
  (let* ((lang (%make-language
                :name name
                :extensions (mapcar #'normalise-extension (ensure-list extensions))
                :line-comments (mapcar #'octets (remove "" (ensure-list line-comment) :test #'equal))
                :block-comments (mapcar (lambda (pair) (cons (octets (car pair)) (octets (cdr pair))))
                                        (if (and (consp block-comment) (stringp (car block-comment)))
                                            (list block-comment)
                                            block-comment))
                :strings (sort (mapcar #'octets (ensure-list strings)) #'> :key #'length)
                :escape (and escape (char-code escape))
                :char-prefix (and char-prefix (octets char-prefix))
                :backslash-commands backslash-commands
                :case-insensitive case-insensitive
                :word-bytes (make-word-table word-chars)
                :highlighter highlighter)))
    (dolist (k (remove-duplicates keywords :test #'string=))
      (let ((o (octets (if case-insensitive (string-downcase k) k))))
        (when (plusp (length o))
          (push o (svref (language-keywords lang) (aref o 0))))))
    (loop for i below 256
          do (setf (svref (language-keywords lang) i)
                   (sort (svref (language-keywords lang) i) #'> :key #'length)))
    (setf *languages* (cons lang (remove name *languages* :key #'language-name :test #'string-equal)))
    lang))

(defparameter *lisp-word-chars* "-*+!?<>=/:%&$^~."
  "Characters that may appear inside Lisp symbols, for :WORD-CHARS.")

;;; Files with no known extension: numbers and "strings" only.
(setf *default-language* (%make-language :name "Text"
                                          :strings (list (octets "\""))
                                          :word-bytes (make-word-table "")))

(defun find-language (name)
  (find name *languages* :key #'language-name :test #'string-equal))

(defun file-extension (filename)
  (let ((slash (position-if (lambda (c) (member c '(#\/ #\\))) filename :from-end t))
        (dot (position #\. filename :from-end t)))
    (if (and dot (or (null slash) (> dot slash)))
        (string-downcase (subseq filename dot))
        "")))

(defun language-for-file (filename)
  (let ((ext (file-extension (or filename ""))))
    (or (and (plusp (length ext))
             (find-if (lambda (l) (member ext (language-extensions l) :test #'string=))
                      *languages*))
        *default-language*)))

;;; ------------------------------------------------------------------
;;; The tokenizer
;;; ------------------------------------------------------------------

(declaim (inline match-at))
(defun match-at (text len i pattern &optional case-insensitive)
  "Does the octet vector PATTERN occur in TEXT at I?"
  (declare (type octets text pattern) (type fixnum len i))
  (let ((n (length pattern)))
    (and (<= (+ i n) len)
         (loop for k of-type fixnum below n
               for a = (aref text (+ i k))
               for b = (aref pattern k)
               always (or (= a b)
                          (and case-insensitive (<= 65 a 90) (= (+ a 32) b)))))))

(defun default-face (b)
  (if (or (<= 48 b 57) (<= 65 b 90) (<= 97 b 122) (= b 95) (>= b 128)) +alpha+ +symbol+))

(defun paint (colors from to face)
  (fill colors face :start from :end to))

(defun scan-string-end (lang text len i delim)
  "I is just after an opening DELIM; return the index just after the closing one."
  (declare (type octets text delim) (type fixnum len i))
  (let ((escape (language-escape lang)))
    (loop while (< i len)
          do (cond ((and escape (= (aref text i) escape)) (incf i 2))
                   ((match-at text len i delim) (return-from scan-string-end (+ i (length delim))))
                   (t (incf i))))
    len))

(defun scan-number (lang text len i)
  "If a number starts at I, return the index after it, else NIL."
  (declare (type octets text) (type fixnum len i))
  (flet ((digitp (j) (and (< j len) (<= 48 (aref text j) 57))))
    (let ((j i))
      (when (and (< j len) (member (aref text j) '(43 45)) (digitp (1+ j))) ; sign
        (incf j))
      (unless (digitp j) (return-from scan-number nil))
      (if (and (= (aref text j) 48) (< (1+ j) len) (member (aref text (1+ j)) '(120 88))) ; 0x
          (progn (incf j 2)
                 (loop while (and (< j len) (digit-char-p (code-char (aref text j)) 16)) do (incf j)))
          (progn
            (loop while (digitp j) do (incf j))
            (when (and (< j len) (= (aref text j) 46) (digitp (1+ j))) ; .
              (incf j)
              (loop while (digitp j) do (incf j)))
            (when (and (< j len) (member (aref text j) '(101 69)) ; e E
                       (or (digitp (1+ j))
                           (and (< (1+ j) len) (member (aref text (1+ j)) '(43 45)) (digitp (+ j 2)))))
              (incf j 2)
              (loop while (digitp j) do (incf j)))))
      (if (and (< j len) (word-byte-p lang (aref text j)))
          nil                           ; 12abc is not a number
          j))))

(defun scan-keyword (lang text len i)
  "If a keyword starts at I, return the index after it, else NIL."
  (declare (type octets text) (type fixnum len i))
  (let* ((ci (language-case-insensitive lang))
         (b (aref text i))
         (bucket (svref (language-keywords lang) (if (and ci (<= 65 b 90)) (+ b 32) b))))
    (dolist (kw bucket nil)
      (let ((end (+ i (length kw))))
        (when (and (match-at text len i kw ci)
                   ;; a keyword ending in a word character must end the word
                   (or (not (word-byte-p lang (aref kw (1- (length kw)))))
                       (>= end len)
                       (not (word-byte-p lang (aref text end)))))
          (return end))))))

(defun highlight-octets (lang text len colors)
  "Fill COLORS[0..LEN) with faces for TEXT[0..LEN)."
  (declare (type octets text colors) (type fixnum len))
  (when (language-highlighter lang)
    (return-from highlight-octets
      (progn (funcall (language-highlighter lang) lang text len colors) colors)))
  (let ((i 0))
    (declare (type fixnum i))
    (loop
      (when (>= i len) (return))
      (let ((b (aref text i))
            (token-start (or (= i 0) (not (word-byte-p lang (aref text (1- i))))))
            next)
        (cond
          ;; block comments
          ((loop for (open . close) in (language-block-comments lang)
                 when (match-at text len i open)
                   do (let ((end (or (search close text :start2 (+ i (length open)) :end2 len) len)))
                        (setf next (min len (+ end (length close))))
                        (paint colors i next +block-comment+)
                        (return t))))
          ;; line comments, up to the newline
          ((loop for open in (language-line-comments lang)
                 thereis (match-at text len i open))
           (setf next (or (position 10 text :start i :end len) len))
           (paint colors i next +comment+))
          ;; strings
          ((loop for delim in (language-strings lang)
                 when (match-at text len i delim)
                   do (setf next (scan-string-end lang text len (+ i (length delim)) delim))
                      (paint colors i next +string+)
                      (return t)))
          ;; Lisp character syntax: #\a, #\", #\( ...
          ((and (language-char-prefix lang) (match-at text len i (language-char-prefix lang)))
           (setf next (min len (+ i (length (language-char-prefix lang)) 1)))
           (loop while (and (< next len) (word-byte-p lang (aref text next))) do (incf next))
           (paint colors i next +alpha+))
          ;; TeX commands
          ((and token-start (language-backslash-commands lang) (= b 92)
                (< (1+ i) len) (alpha-char-p (code-char (aref text (1+ i)))))
           (setf next (1+ i))
           (loop while (and (< next len) (alpha-char-p (code-char (aref text next)))) do (incf next))
           (paint colors i next +keyword+))
          ;; numbers
          ((and token-start (setf next (scan-number lang text len i)))
           (paint colors i next +digits+))
          ;; keywords
          ((and token-start (setf next (scan-keyword lang text len i)))
           (paint colors i next +keyword+))
          ;; an ordinary word: colour it as a whole so that digits inside
          ;; identifiers (x1, utf8) are not mistaken for numbers
          ((word-byte-p lang b)
           (setf next (1+ i))
           (loop while (and (< next len) (word-byte-p lang (aref text next))) do (incf next))
           (loop for k from i below next do (setf (aref colors k) (default-face (aref text k)))))
          (t
           (setf next (1+ i))
           (setf (aref colors i) (default-face b))))
        (setf i (max next (1+ i)))))
    colors))

(defun highlight-string (string &optional (language *default-language*))
  "For testing: return a list of (face-id . substring) runs for STRING."
  (let* ((lang (if (stringp language) (or (find-language language) (language-for-file language)) language))
         (text (octets string))
         (colors (make-array (length text) :element-type '(unsigned-byte 8) :initial-element 0)))
    (highlight-octets lang text (length text) colors)
    (let ((runs '()) (start 0))
      (loop for i from 1 to (length text)
            when (or (= i (length text)) (/= (aref colors i) (aref colors start)))
              do (push (cons (aref colors start)
                             (sb-ext:octets-to-string text :start start :end i :external-format :utf-8))
                       runs)
                 (setf start i))
      (nreverse runs))))

;;; Called from C (through the callback in core.lisp)

(defun highlight-buffer-text (filename text-sap len colors-sap)
  (let ((lang (language-for-file filename))
        (text (make-array len :element-type '(unsigned-byte 8)))
        (colors (make-array len :element-type '(unsigned-byte 8) :initial-element +alpha+)))
    (sb-kernel:copy-ub8-from-system-area text-sap 0 text 0 len)
    (when lang
      (highlight-octets lang text len colors))
    (sb-kernel:copy-ub8-to-system-area colors 0 colors-sap 0 len)))
