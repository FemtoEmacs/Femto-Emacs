;;;; emacs-keys.lisp -- the GNU Emacs keys FemtoEmacs did not have
;;;;
;;;; A script: edit it and press C-x C-r; no rebuild.  Every key reaches the
;;;; Lisp keymap first, so any key can be bound here.
;;;;
;;;; The scanners below (words, sentences, paragraphs, expressions) take a
;;;; reader GET (offset -> byte, -1 outside the text) and the text's SIZE,
;;;; so the tests can run them on strings; the commands run them on the
;;;; buffer.  Offsets are bytes; text is UTF-8.

(in-package #:sbemacs)

;;; ------------------------------------------------------------------
;;; Reading the text
;;; ------------------------------------------------------------------

(defun buffer-get (i) (%char-at i))

(defun octets-get (v)
  "A reader over the octet vector V, for the tests."
  (lambda (i) (if (< -1 i (length v)) (aref v i) -1)))

(declaim (inline byte-in))
(defun byte-in (b chars)
  (and (<= 0 b 127) (find (code-char b) chars)))

(defun word-constituent-p (b)
  "Letters, digits and every non-ASCII byte make words."
  (and (>= b 0) (or (>= b 128) (<= 48 b 57) (<= 65 b 90) (<= 97 b 122))))

(defun blank-byte (b) (byte-in b '(#\Space #\Tab #\Return)))
(defun whitespace-byte (b) (byte-in b '(#\Space #\Tab #\Return #\Newline)))

(defun char-end (get size i)
  "Offset after the UTF-8 character at I."
  (let ((b (funcall get i)))
    (min size (+ i (cond ((< b #xC0) 1) ((< b #xE0) 2) ((< b #xF0) 3) (t 4))))))

(defun char-start-before (get i)
  "Offset of the UTF-8 character before I."
  (let ((j (max 0 (1- i))))
    (loop while (and (> j 0) (= (logand (funcall get j) #xC0) #x80)) do (decf j))
    j))

;;; lines

(defun line-start-position (get i)
  (loop while (and (> i 0) (/= (funcall get (1- i)) 10)) do (decf i))
  i)

(defun line-end-position (get size i)
  (loop while (and (< i size) (/= (funcall get i) 10)) do (incf i))
  i)

(defun next-line-start (get size ls)
  (min size (1+ (line-end-position get size ls))))

(defun prev-line-start-position (get ls)
  (if (> ls 0) (line-start-position get (1- ls)) 0))

(defun blank-line-p (get size ls)
  (loop for i from ls below size
        for b = (funcall get i)
        until (= b 10)
        always (blank-byte b)))

(defun indentation-end (get size ls)
  "The first non-blank offset of the line starting at LS."
  (loop for i from ls
        while (and (< i size) (blank-byte (funcall get i)))
        finally (return i)))

;;; words

(defun forward-word-position (get size i)
  (loop while (and (< i size) (not (word-constituent-p (funcall get i)))) do (incf i))
  (loop while (and (< i size) (word-constituent-p (funcall get i))) do (incf i))
  i)

(defun backward-word-position (get size i)
  (declare (ignore size))
  (loop while (and (> i 0) (not (word-constituent-p (funcall get (1- i))))) do (decf i))
  (loop while (and (> i 0) (word-constituent-p (funcall get (1- i)))) do (decf i))
  i)

;;; paragraphs: separated by blank lines

(defun forward-paragraph-position (get size i)
  "The start of the blank line after the paragraph at or after I."
  (let ((ls (line-start-position get i)))
    (loop while (and (< ls size) (blank-line-p get size ls))
          do (setf ls (next-line-start get size ls)))
    (loop while (and (< ls size) (not (blank-line-p get size ls)))
          do (let ((next (next-line-start get size ls)))
               (when (= next ls) (return))
               (setf ls next)))
    (min ls size)))

(defun backward-paragraph-position (get size i)
  "The start of the blank line before the paragraph at or before I."
  (let ((ls (line-start-position get i)))
    (when (and (= ls i) (> ls 0) (blank-line-p get size ls))
      (setf ls (prev-line-start-position get ls)))
    (loop while (and (> ls 0) (blank-line-p get size ls))
          do (setf ls (prev-line-start-position get ls)))
    (loop while (and (> ls 0) (not (blank-line-p get size ls)))
          do (setf ls (prev-line-start-position get ls)))
    ls))

(defun paragraph-text-start (get size i)
  (let ((b (backward-paragraph-position get size i)))
    (if (blank-line-p get size b) (next-line-start get size b) b)))

;;; sentences: end with . ? or ! followed by a space or a line end

(defun sentence-end-after (get size k)
  "If a sentence ends with the punctuation at K, the offset after it."
  (when (byte-in (funcall get k) ".?!")
    (let ((e (1+ k)))
      (loop while (and (< e size) (byte-in (funcall get e) ")]}\"'")) do (incf e))
      (when (or (>= e size) (whitespace-byte (funcall get e)))
        e))))

(defun forward-sentence-position (get size i)
  (let ((limit (forward-paragraph-position get size i)))
    (when (<= limit i) (setf limit size))
    (loop for k from i below limit
          for e = (sentence-end-after get size k)
          when (and e (> e i)) do (return-from forward-sentence-position e))
    ;; the paragraph's last sentence: up to its last character
    (let ((e limit))
      (loop while (and (> e i) (whitespace-byte (funcall get (1- e)))) do (decf e))
      (if (> e i) e limit))))

(defun backward-sentence-position (get size i)
  (let ((start (paragraph-text-start get size (max 0 (1- i))))
        (j i))
    (when (> start i) (setf start (paragraph-text-start get size (backward-paragraph-position get size i))))
    (loop while (and (> j start) (whitespace-byte (funcall get (1- j)))) do (decf j))
    (loop for k from (1- j) downto start
          for e = (sentence-end-after get size k)
          when (and e (< e j))
            do (loop while (and (< e size) (whitespace-byte (funcall get e))) do (incf e))
               (return-from backward-sentence-position e))
    start))

;;; balanced expressions

(defun lisp-buffer-p ()
  (let ((lang (language-for-file (or (buffer-filename) (get-buffer-name)))))
    (and lang (member (language-name lang) '("Common Lisp" "Scheme" "VHDL Lisp")
                      :test #'string=))))

(defun open-byte-p (b) (byte-in b "([{"))
(defun close-byte-p (b) (byte-in b ")]}"))

(defun escaped-at-p (get i)
  "Is the byte at I a Lisp character literal (#\\x) or escaped (\\x)?"
  (and (>= i 1) (= (funcall get (1- i)) 92)
       (not (and (>= i 2) (= (funcall get (- i 2)) 92)))))

(defun symbol-byte-p (b lispish)
  (and (>= b 0)
       (not (whitespace-byte b))
       (not (byte-in b "()[]{}\""))
       (not (and lispish (byte-in b ";'`,")))
       (not (and (not lispish) (byte-in b ";,")))))

(defun string-end (get size i)
  "I is at an opening double quote: the offset after the closing one."
  (loop with j = (1+ i)
        while (< j size)
        do (let ((b (funcall get j)))
             (cond ((= b 92) (incf j 2))
                   ((= b 34) (return (1+ j)))
                   (t (incf j))))
        finally (return nil)))

(defun string-start (get i)
  "The byte before I is a closing double quote: the offset of the opening one."
  (loop for j from (- i 2) downto 0
        when (and (= (funcall get j) 34) (not (escaped-at-p get j)))
          do (return j)
        finally (return nil)))

(defun skip-space-and-comments (get size i lispish)
  (loop
    (loop while (and (< i size) (whitespace-byte (funcall get i))) do (incf i))
    (if (and lispish (< i size) (= (funcall get i) 59))   ; ;
        (setf i (line-end-position get size i))
        (return i))))

(defun list-end (get size i lispish)
  "I is at an open bracket: the offset after the matching close, or NIL."
  (let ((depth 0) (j i))
    (loop while (< j size)
          do (let ((b (funcall get j)))
               (cond ((= b 92) (incf j))                      ; \x, #\(
                     ((= b 34) (setf j (or (string-end get size j) (return nil)))
                      (decf j))
                     ((and lispish (= b 59)) (setf j (1- (line-end-position get size j))))
                     ((and (not lispish) (= b 39)              ; 'c' in C
                           (< (+ j 2) size) (= (funcall get (+ j 2)) 39))
                      (incf j 2))
                     ((open-byte-p b) (incf depth))
                     ((close-byte-p b)
                      (decf depth)
                      (when (zerop depth) (return (1+ j))))))
             (incf j))))

(defun list-start (get i)
  "The byte before I is a close bracket: the offset of the matching open."
  (let ((depth 0) (j (1- i)))
    (loop while (>= j 0)
          do (let ((b (funcall get j)))
               (cond ((escaped-at-p get j))
                     ((= b 34) (setf j (or (string-start get (1+ j)) (return nil))))
                     ((close-byte-p b) (incf depth))
                     ((open-byte-p b)
                      (decf depth)
                      (when (zerop depth) (return j)))))
             (decf j))))

(defun forward-sexp-position (get size i lispish)
  "The end of the expression after I, or NIL at the end of a list."
  (let ((j (skip-space-and-comments get size i lispish)))
    (when lispish
      ;; prefixes: 'x `x ,x ,@x #'x #(...)
      (loop while (< j size)
            do (let ((b (funcall get j)))
                 (cond ((byte-in b "'`,@") (incf j))
                       ((and (= b 35) (< (1+ j) size)
                             (byte-in (funcall get (1+ j)) "'("))
                        (incf j))
                       (t (return))))))
    (when (>= j size) (return-from forward-sexp-position nil))
    (let ((b (funcall get j)))
      (cond ((open-byte-p b) (list-end get size j lispish))
            ((close-byte-p b) nil)
            ((= b 34) (string-end get size j))
            (t (loop while (< j size)
                     do (let ((c (funcall get j)))
                          (cond ((= c 92) (incf j 2))          ; #\( and \x
                                ((symbol-byte-p c lispish) (incf j))
                                (t (return)))))
               (min j size))))))

(defun backward-sexp-position (get size i lispish)
  "The start of the expression before I, or NIL at the start of a list."
  (declare (ignore size))
  (let ((j i))
    (loop while (and (> j 0) (whitespace-byte (funcall get (1- j)))) do (decf j))
    (when (<= j 0) (return-from backward-sexp-position nil))
    (let ((b (funcall get (1- j))))
      (setf j (cond ((and (close-byte-p b) (not (escaped-at-p get (1- j)))) (list-start get j))
                    ((and (open-byte-p b) (not (escaped-at-p get (1- j)))) nil)
                    ((= b 34) (string-start get j))
                    (t (loop while (and (> j 0)
                                        (let ((c (funcall get (1- j))))
                                          (or (symbol-byte-p c lispish)
                                              (escaped-at-p get (1- j))
                                              (and (= c 92) (> j 1)))))
                             do (decf j))
                       j))))
    (when (and j lispish)
      (loop while (and (> j 0) (byte-in (funcall get (1- j)) "'`,@#")) do (decf j)))
    j))

(defun up-list-position (get i)
  "The open bracket of the list around I, or NIL."
  (let ((depth 0))
    (loop for j from (1- i) downto 0
          for b = (funcall get j)
          do (cond ((escaped-at-p get j))
                   ((close-byte-p b) (incf depth))
                   ((open-byte-p b)
                    (if (zerop depth) (return j) (decf depth))))
          finally (return nil))))

(defun down-list-position (get size i)
  "Just inside the next list after I, or NIL."
  (loop for j from i below size
        for b = (funcall get j)
        do (cond ((escaped-at-p get j))
                 ((= b 34) (setf j (1- (or (string-end get size j) size))))
                 ((open-byte-p b) (return (1+ j)))
                 ((close-byte-p b) (return nil)))
        finally (return nil)))

;;; definitions: a ( in column 0 in Lisp; elsewhere a line that starts in
;;; column 0 with a letter (int main(...), def f(...), theorem ...)

(defun defun-start-line-p (get size ls lispish)
  (let ((b (funcall get ls)))
    (and (< ls size)
         (if lispish (= b 40) (or (word-constituent-p b) (= b 95))))))

(defun beginning-of-defun-position (get size i lispish)
  (let ((ls (line-start-position get i)))
    (when (= ls i) (setf ls (prev-line-start-position get ls)))
    (loop until (or (defun-start-line-p get size ls lispish) (= ls 0))
          do (setf ls (prev-line-start-position get ls)))
    ls))

(defun end-of-defun-position (get size i lispish)
  (if lispish
      (let* ((start (beginning-of-defun-position get size (next-line-start get size i) t))
             (end (and (defun-start-line-p get size start t)
                       (forward-sexp-position get size start t))))
        (when (or (null end) (<= end i))
          ;; after it: the next one
          (let ((ls (next-line-start get size i)))
            (loop until (or (>= ls size) (defun-start-line-p get size ls t))
                  do (setf ls (next-line-start get size ls)))
            (setf end (if (< ls size) (forward-sexp-position get size ls t) size))))
        (if end (next-line-start get size end) size))
      ;; a } in column 0 closes a C function; otherwise the next definition
      (let ((ls (next-line-start get size i)))
        (loop while (< ls size)
              do (let ((b (funcall get ls)))
                   (cond ((= b 125) (return-from end-of-defun-position (next-line-start get size ls)))
                         ((defun-start-line-p get size ls nil)
                          (return-from end-of-defun-position ls))))
                 (setf ls (next-line-start get size ls)))
        size)))

;;; ------------------------------------------------------------------
;;; Editing helpers
;;; ------------------------------------------------------------------

(defmacro scan (function &rest args)
  "Call a scanner on the current buffer at the cursor."
  `(,function #'buffer-get (buffer-size) ,@args))

(defun count-characters (octets)
  (count-if (lambda (b) (/= (logand b #xC0) #x80)) octets))

(defun delete-region (start end)
  "Delete the text between START and END (no kill ring); one undo step."
  (let ((a (min start end)) (b (max start end)))
    (when (< a b)
      (goto-char a)
      (delete-char (count-characters (buffer-octets a b))))
    t))

(defun replace-region (start end new)
  (delete-region start end)
  (goto-char (min start end))
  (when (plusp (length new)) (insert new))
  t)

(defun kill-between (start end &key (direction :forward))
  "Kill the text between START and END into the kill ring.  Consecutive
kills join into one entry, as in Emacs."
  (let ((a (min start end)) (b (max start end))
        (append (and (eq *last-command* 'kill-region) *kill-ring*))
        (old-mark (mark)))
    (when (< a b)
      (let ((previous (and append (first *kill-ring*))))
        (push-mark a)
        (goto-char b)
        (kill-region)
        (when previous
          (let* ((piece (pop *kill-ring*))
                 (joined (if (eq direction :backward)
                             (concatenate 'string piece previous)
                             (concatenate 'string previous piece))))
            (setf (first *kill-ring*) joined)
            (set-clipboard joined)))
        (when (and old-mark (< old-mark a)) (push-mark old-mark))))
    (setf *this-command* 'kill-region)
    t))

(defun read-a-character (question)
  "Ask for one key; return the character typed (or NIL)."
  (message "~A" question)
  (update-display)
  (let ((k (get-key)))
    (clear-message-line)
    (if (plusp (length k))
        (char k 0)
        (let ((name (get-key-name)))
          (cond ((string= name "SPC") #\Space)
                (t nil))))))

;;; ------------------------------------------------------------------
;;; Motion
;;; ------------------------------------------------------------------

(defcommand forward-word-command ()
  "M-f: to the end of the next word."
  (goto-char (scan forward-word-position (point))))

(defcommand backward-word-command ()
  "M-b: to the start of the previous word."
  (goto-char (scan backward-word-position (point))))

(defcommand forward-sentence ()
  (goto-char (scan forward-sentence-position (point))))

(defcommand backward-sentence ()
  (goto-char (scan backward-sentence-position (point))))

(defcommand forward-paragraph ()
  (goto-char (scan forward-paragraph-position (point))))

(defcommand backward-paragraph ()
  (goto-char (scan backward-paragraph-position (point))))

(defcommand back-to-indentation ()
  (goto-char (scan indentation-end (line-start))))

(defcommand forward-sexp ()
  (let ((e (scan forward-sexp-position (point) (lisp-buffer-p))))
    (if e (goto-char e) (message "No expression after the cursor"))))

(defcommand backward-sexp ()
  (let ((s (scan backward-sexp-position (point) (lisp-buffer-p))))
    (if s (goto-char s) (message "No expression before the cursor"))))

(defcommand backward-up-list ()
  (let ((s (up-list-position #'buffer-get (point))))
    (if s (goto-char s) (message "Not inside a list"))))

(defcommand down-list ()
  (let ((s (scan down-list-position (point))))
    (if s (goto-char s) (message "No list ahead"))))

(defcommand beginning-of-defun ()
  (goto-char (scan beginning-of-defun-position (point) (lisp-buffer-p))))

(defcommand end-of-defun ()
  (goto-char (scan end-of-defun-position (point) (lisp-buffer-p))))

;;; ------------------------------------------------------------------
;;; Killing
;;; ------------------------------------------------------------------

(defcommand kill-word ()
  (kill-between (point) (scan forward-word-position (point))))

(defcommand backward-kill-word ()
  (kill-between (scan backward-word-position (point)) (point) :direction :backward))

(defcommand kill-sexp ()
  (let ((e (scan forward-sexp-position (point) (lisp-buffer-p))))
    (if e (kill-between (point) e) (message "No expression after the cursor"))))

(defcommand kill-sentence ()
  (kill-between (point) (scan forward-sentence-position (point))))

(defcommand kill-line-command ()
  "C-k: kill to the end of the line, or the line end itself when there is
only blank space before it.  Consecutive C-k's join in the kill ring."
  (let* ((p (point))
         (e (scan line-end-position p))
         (rest (buffer-octets p e)))
    (cond ((>= p (buffer-size)) (message "End of buffer"))
          ((every #'blank-byte rest) (kill-between p (min (buffer-size) (1+ e))))
          (t (kill-between p e)))))

(defcommand zap-to-char ()
  (let ((c (read-a-character "Zap to char: ")))
    (when c
      (let* ((p (point))
             (target (sb-ext:string-to-octets (string c) :external-format :utf-8))
             (size (buffer-size))
             (found (loop for i from p below size
                          when (= (buffer-get i) (aref target 0))
                            do (return i))))
        (if found
            (kill-between p (min size (+ found (length target))))
            (message "~C not found" c))))))

;;; yanking: C-y remembers what it inserted, so that M-y can replace it

(defvar *yank-start* 0)
(defvar *yank-end* 0)
(defvar *yank-index* 0)

(defcommand yank-command ()
  "C-y: insert the last killed text; M-y right after replaces it with
earlier kills."
  (let ((start (point)))
    (yank)
    (setf *yank-start* start *yank-end* (point) *yank-index* 0)
    (push-mark start)
    (setf *this-command* 'yank)))

(defcommand yank-pop ()
  (cond ((not (member *last-command* '(yank yank-pop)))
         (message "M-y works right after C-y"))
        ((null *kill-ring*) (message "The kill ring is empty"))
        (t
         (setf *yank-index* (mod (1+ *yank-index*) (length *kill-ring*)))
         (let ((text (nth *yank-index* *kill-ring*)))
           (replace-region *yank-start* *yank-end* text)
           (setf *yank-end* (point))
           (set-clipboard text)
           (message "Kill ring ~D/~D" (1+ *yank-index*) (length *kill-ring*))
           (setf *this-command* 'yank-pop)))))

;;; ------------------------------------------------------------------
;;; Changing text
;;; ------------------------------------------------------------------

(defcommand transpose-chars ()
  (let* ((p (point)) (size (buffer-size))
         (at-end (or (>= p size) (= (buffer-get p) 10))))
    (multiple-value-bind (a b c)
        (if at-end
            (let ((b (char-start-before #'buffer-get p)))
              (values (char-start-before #'buffer-get b) b p))
            (values (char-start-before #'buffer-get p) p (char-end #'buffer-get size p)))
      (if (or (= p 0) (= a b))
          (message "Nothing to transpose")
          (let ((x (buffer-substring a b)) (y (buffer-substring b c)))
            (replace-region a c (concatenate 'string y x)))))))

(defcommand transpose-words ()
  (let* ((a (scan backward-word-position (point)))
         (b (scan forward-word-position a))
         (c (scan forward-word-position b))
         (d (scan backward-word-position c)))
    (if (or (<= c b) (< d b) (= a b))
        (message "Need two words")
        (replace-region a c (concatenate 'string (buffer-substring d c)
                                         (buffer-substring b d)
                                         (buffer-substring a b))))))

(defcommand transpose-lines ()
  (let* ((ls (line-start)))
    (if (= ls 0)
        (message "No line above")
        (let* ((pls (line-start (1- ls)))
               (le (line-end ls))
               (previous (buffer-substring pls (1- ls)))
               (current (buffer-substring ls le)))
          (replace-region pls le (format nil "~A~%~A" current previous))
          (goto-char (min (buffer-size) (1+ (point))))))))

(defun transform-word (function)
  (let* ((p (point)) (e (scan forward-word-position p)))
    (when (< p e)
      (replace-region p e (funcall function (buffer-substring p e))))))

(defcommand upcase-word () (transform-word #'string-upcase))
(defcommand downcase-word () (transform-word #'string-downcase))
(defcommand capitalize-word () (transform-word #'string-capitalize))

(defcommand open-line ()
  (insert (string #\Newline))
  (backward-char))

(defcommand delete-horizontal-space ()
  (let ((a (point)) (b (point)))
    (loop while (and (> a 0) (blank-byte (buffer-get (1- a)))) do (decf a))
    (loop while (and (< b (buffer-size)) (blank-byte (buffer-get b))) do (incf b))
    (delete-region a b)))

(defcommand just-one-space ()
  (delete-horizontal-space)
  (insert " "))

(defcommand delete-indentation ()
  "M-^: join this line to the previous one."
  (let ((ls (line-start)))
    (if (= ls 0)
        (message "No line above")
        (let ((a (1- ls)) (b ls))
          (loop while (and (> a 0) (blank-byte (buffer-get (1- a)))) do (decf a))
          (loop while (and (< b (buffer-size)) (blank-byte (buffer-get b))) do (incf b))
          (let ((before (if (> a 0) (buffer-get (1- a)) 10))
                (after (buffer-get b)))
            (replace-region a b (if (or (= before 10) (= before 40) (= after 41) (= after -1)
                                        (= after 10))
                                    "" " "))
            (goto-char a))))))

(defcommand delete-blank-lines ()
  "C-x C-o: on a blank line, leave just one blank line (or none when it is
alone); on a text line, delete the blank lines after it."
  (let* ((size (buffer-size))
         (ls (line-start)))
    (flet ((blank (x) (blank-line-p #'buffer-get size x)))
      (if (blank ls)
          (let ((a ls) (b ls))
            (loop while (and (> a 0) (blank (line-start (1- a)))) do (setf a (line-start (1- a))))
            (loop while (and (< b size) (blank b)) do (setf b (min size (1+ (line-end b)))))
            (if (and (= a ls) (= b (min size (1+ (line-end ls)))))
                (delete-region a b)
                (replace-region a b (string #\Newline)))
            (goto-char a))
          (let* ((b (min size (1+ (line-end ls)))) (c b))
            (loop while (and (< c size) (blank c)) do (setf c (min size (1+ (line-end c)))))
            (let ((p (point)))
              (delete-region b c)
              (goto-char p)))))))

;;; filling

(defvar *fill-column* 70)

(defun line-comment-start ()
  "The current language's line comment (\";;\" for Lisp), or NIL."
  (let* ((lang (language-for-file (or (buffer-filename) (get-buffer-name))))
         (first (and lang (first (language-line-comments lang)))))
    (when first
      (let ((s (sb-ext:octets-to-string first :external-format :utf-8)))
        (if (string= s ";") ";;" s)))))

(defun text-buffer-p ()
  (let ((lang (language-for-file (or (buffer-filename) (get-buffer-name)))))
    (or (null lang) (member (language-name lang) '("TeX" "Markdown") :test #'string=))))

(defun list-item-prefix (line)
  "If LINE is a Markdown list item (- x, * x, + x, 1. x, 1) x), its
indentation and marker with the spaces after it; else NIL."
  (let* ((i (or (position-if-not (lambda (c) (member c '(#\Space #\Tab))) line) (length line)))
         (j (cond ((>= i (length line)) nil)
                  ((member (char line i) '(#\- #\* #\+)) (1+ i))
                  ((digit-char-p (char line i))
                   (let ((k (or (position-if-not #'digit-char-p line :start i) (length line))))
                     (and (< k (length line)) (member (char line k) '(#\. #\))) (1+ k))))
                  (t nil))))
    (when (and j (< j (length line)) (char= (char line j) #\Space))
      (subseq line 0 (or (position #\Space line :start j :test-not #'char=) (length line))))))

(defun block-start-line-p (line)
  "Does LINE begin a Markdown block that a paragraph does not run into:
a list item, a heading, a quotation, a fence or a table row?"
  (let ((l (string-left-trim '(#\Space #\Tab) line)))
    (or (list-item-prefix line)
        (and (plusp (length l)) (member (char l 0) '(#\# #\> #\|)))
        (starts-with-p "```" l) (starts-with-p "~~~" l))))

(defun unfillable-line-p (line)
  "Headings, fences and tables are never refilled."
  (let ((l (string-left-trim '(#\Space #\Tab) line)))
    (and (plusp (length l))
         (or (member (char l 0) '(#\# #\|))
             (starts-with-p "```" l) (starts-with-p "~~~" l)))))

(defun fill-prefix-of (line comment)
  "Leading blanks of LINE, plus the comment marker and one space when LINE
is a comment."
  (let* ((i (or (position-if-not (lambda (c) (member c '(#\Space #\Tab))) line) (length line)))
         (rest (subseq line i)))
    (if (and comment (plusp (length comment))
             (>= (length rest) (length comment))
             (string= comment rest :end2 (length comment)))
        (let* ((j (+ i (length comment)))
               ;; ;;; and ;; alike
               (j (or (position-if-not (lambda (c) (char= c (char comment 0))) line :start j) (length line)))
               (k (or (position-if-not (lambda (c) (member c '(#\Space #\Tab))) line :start j) (length line))))
          (subseq line 0 (min k (1+ j))))
        (subseq line 0 i))))

(defun fill-words (words prefix width &optional (rest-prefix prefix))
  "Lines of at most WIDTH columns (when possible); the first starts with
PREFIX, the others with REST-PREFIX."
  (let ((lines '()) (current nil))
    (dolist (w words)
      (cond ((null current) (setf current (concatenate 'string prefix w)))
            ((> (+ (length current) 1 (length w)) width)
             (push current lines)
             (setf current (concatenate 'string rest-prefix w)))
            (t (setf current (concatenate 'string current " " w)))))
    (when current (push current lines))
    (nreverse lines)))

(defun split-words (string)
  (loop with start = 0
        for pos = (position-if (lambda (c) (member c '(#\Space #\Tab #\Newline))) string :start start)
        for w = (subseq string start pos)
        when (plusp (length w)) collect w
        while pos do (setf start (1+ pos))))

(defun fill-text (lines comment width)
  "Refill LINES (strings) of one paragraph; the first line gives the prefix.
A list item (- x, 1. x) keeps its marker, and the lines after it go under
its text."
  (let* ((item (and (null comment) (list-item-prefix (first lines))))
         (prefix (or item (fill-prefix-of (first lines) comment)))
         (rest-prefix (if item (make-string (length item) :initial-element #\Space) prefix))
         (words (loop for line in lines
                      for first = t then nil
                      for p = (if (and first item) item (fill-prefix-of line comment))
                      nconc (split-words (subseq line (min (length p) (length line)))))))
    (format nil "~{~A~^~%~}" (fill-words words prefix width rest-prefix))))

(defcommand fill-paragraph ()
  "M-q: refill the paragraph (or comment block) at the cursor to
*FILL-COLUMN* columns."
  (let* ((size (buffer-size))
         (ls (line-start))
         (here (buffer-substring ls (line-end ls)))
         (text-mode (text-buffer-p))
         ;; a > quotation is filled like a comment that starts with >
         (comment (if (and text-mode (starts-with-p ">" (string-left-trim " " here)))
                      ">"
                      (line-comment-start)))
         (prefix (fill-prefix-of here comment))
         (in-comment (and comment (search comment prefix))))
    (flet ((line-at (start) (buffer-substring start (line-end start)))
           (member-line-p (start)
             (let ((text (buffer-substring start (line-end start))))
               (and (not (blank-line-p #'buffer-get size start))
                    (not (and text-mode (unfillable-line-p text)))
                    (if in-comment
                        (search comment (fill-prefix-of text comment))
                        t)))))
      (cond ((blank-line-p #'buffer-get size ls) (message "No paragraph here"))
            ((not (or in-comment text-mode))
             (message "M-q fills comments and text, not code"))
            ((and text-mode (unfillable-line-p here))
             (message "Headings, tables and code are not refilled"))
            (t
             (let ((a ls) (b ls))
               ;; in Markdown a list item starts a paragraph of its own
               (loop while (and (> a 0)
                                (not (and text-mode (not in-comment) (block-start-line-p (line-at a))))
                                (member-line-p (line-start (1- a))))
                     do (setf a (line-start (1- a))))
               (loop for next = (min size (1+ (line-end b)))
                     while (and (< next size) (> next b) (member-line-p next)
                                (not (and text-mode (not in-comment) (block-start-line-p (line-at next)))))
                     do (setf b next))
               (let* ((end (line-end b))
                      (lines (loop with s = a
                                   collect (buffer-substring s (line-end s))
                                   until (>= s b)
                                   do (setf s (1+ (line-end s)))))
                      (new (fill-text lines comment *fill-column*)))
                 (unless (string= new (buffer-substring a end))
                   (replace-region a end new))
                 (goto-char (min (buffer-size) (+ a (length (sb-ext:string-to-octets new :external-format :utf-8))))))))))))

;;; comments

(defcommand comment-dwim ()
  "M-;: with an active region, comment or uncomment its lines; otherwise
go to this line's comment, or start one."
  (let ((comment (line-comment-start)))
    (cond ((null comment) (message "No comment syntax for this file"))
          ((region-active-p) (comment-region-lines comment))
          (t
           (let* ((ls (line-start)) (le (line-end ls))
                  (text (buffer-substring ls le))
                  (single (if (string= comment ";;") ";" comment))
                  (found (search single text)))
             (cond (found
                    (goto-char (+ ls (length (sb-ext:string-to-octets (subseq text 0 found)
                                                                       :external-format :utf-8))))
                    (loop while (and (< (point) le) (byte-in (buffer-get (point)) (concatenate 'string single " ")))
                          do (forward-char)))
                   ((blank-line-p #'buffer-get (buffer-size) ls)
                    (goto-char le)
                    (insert (concatenate (quote string) comment " ")))
                   (t (goto-char le)
                      (insert (concatenate (quote string) "  " single " ")))))))))

(defun comment-region-lines (comment)
  (let* ((a (line-start (min (point) (mark))))
         (z (max (point) (mark)))
         (z (if (and (> z a) (= (buffer-get (1- z)) 10)) (1- z) z))
         (b (line-end z))
         (lines (split-lines (buffer-substring a b)))
         (code (remove-if (lambda (l) (string= (trim l) "")) lines))
         (commented (and code (every (lambda (l) (let ((tl (string-left-trim '(#\Space #\Tab) l)))
                                                   (and (>= (length tl) (length comment))
                                                        (string= comment tl :end2 (length comment)))))
                                     code)))
         (column (if code
                     (reduce #'min (mapcar (lambda (l) (or (position-if-not (lambda (c) (member c '(#\Space #\Tab))) l) 0))
                                           code))
                     0))
         (new (mapcar (lambda (l)
                        (cond ((string= (trim l) "") l)
                              (commented
                               (let* ((i (search comment l))
                                      (j (+ i (length comment)))
                                      (j (if (and (< j (length l)) (char= (char l j) #\Space)) (1+ j) j)))
                                 (concatenate 'string (subseq l 0 i) (subseq l j))))
                              (t (concatenate 'string (subseq l 0 column) comment " " (subseq l column)))))
                      lines)))
    (replace-region a b (format nil "~{~A~^~%~}" new))
    (deactivate-mark)
    (message "~:[Commented~;Uncommented~] ~D line~:P" commented (length lines))))

;;; ------------------------------------------------------------------
;;; Mark and region
;;; ------------------------------------------------------------------

(defcommand keyboard-quit ()
  "C-g: deactivate the region; cancel."
  (deactivate-mark)
  (message "Quit"))

(defcommand set-mark-command ()
  "C-SPC: set the mark here and start a region (shaded).  Again at the
same place deactivates the region."
  (if (and (region-active-p) (eql (mark) (point)))
      (progn (deactivate-mark) (message "Mark deactivated"))
      (progn (set-mark) (message "Mark set"))))

(defcommand mark-whole-buffer ()
  (set-mark (buffer-size))
  (goto-char 0)
  (message "Mark set"))

(defcommand exchange-point-and-mark ()
  (let ((m (mark)))
    (if (null m)
        (message "No mark set")
        (progn (set-mark (point)) (goto-char m)))))

(defcommand mark-paragraph ()
  (let* ((p (point))
         (end (scan forward-paragraph-position p))
         (start (scan backward-paragraph-position end)))
    (set-mark end)
    (goto-char start)))

(defcommand mark-word ()
  (let ((from (if (region-active-p) (mark) (point))))
    (set-mark (scan forward-word-position from))))

(defcommand mark-sexp ()
  (let* ((from (if (region-active-p) (mark) (point)))
         (e (scan forward-sexp-position from (lisp-buffer-p))))
    (if e (set-mark e) (message "No expression after the cursor"))))

(defcommand copy-region-command ()
  "M-w: copy the region; the shading goes away."
  (copy-region)
  (deactivate-mark)
  (setf *this-command* 'copy-region))

;;; ------------------------------------------------------------------
;;; Buffers, files, windows
;;; ------------------------------------------------------------------

(defparameter *buffer-picker-buffer* "*buffer-pick*")
(defparameter *buffer-picker-max-keys* 1000)
(defvar *previous-picked-buffer* nil)

(defun string-prefix-equal (prefix string)
  "True when PREFIX is a case-insensitive prefix of STRING."
  (and (<= (length prefix) (length string))
       (string-equal prefix string :end2 (length prefix))))

(defun buffer-picker-matches (query names)
  "Buffer names beginning with QUERY, without changing their order."
  (remove-if-not (lambda (name) (string-prefix-equal query name)) names))

(defun buffer-picker-common-prefix (names)
  "The case-preserving common prefix of NAMES, or the empty string."
  (if (null names)
      ""
      (let* ((first (first names))
             (limit (reduce #'min names :key #'length)))
        (subseq first 0
                (loop for i below limit
                      while (every (lambda (name)
                                     (char-equal (char first i) (char name i)))
                                   (rest names))
                      finally (return i))))))

(defun buffer-picker-buffer-names ()
  "Return the live buffer names.  NEXT-BUFFER is used only to walk the
core's buffer ring; the buffer visible to the user is restored before this
function returns."
  (let ((origin (get-buffer-name))
        (names nil))
    (unwind-protect
         (dotimes (i (get-buffer-count))
           (declare (ignore i))
           (pushnew (get-buffer-name) names :test #'string=)
           (execute-builtin "next-buffer"))
      (select-buffer origin))
    (nreverse (remove *buffer-picker-buffer* names :test #'string=))))

(defun buffer-picker-initial-index (matches origin)
  (or (and *previous-picked-buffer*
           (position *previous-picked-buffer* matches :test #'string=))
      (position-if (lambda (name) (not (string= name origin))) matches)
      0))

(defun render-buffer-picker (query matches selected)
  (select-buffer *buffer-picker-buffer*)
  (delete-region 0 (buffer-size))
  (insert "Switch to buffer\n"
          "Type to filter; TAB completes; arrows select; RET opens; C-g cancels.\n\n"
          "Filter: " query "\n\n")
  (if matches
      (loop for name in matches
            for i from 0
            do (insert (if (= i selected) "> " "  ") name "\n"))
      (insert "  No matching buffers\n"))
  (goto-char (buffer-size))
  (update-display))

(defun buffer-picker-bound-action ()
  (let ((name (get-key-name))
        (binding (get-key-binding)))
    (cond ((or (string= name "C-g") (string= binding "keyboard-quit")) :cancel)
          ((string= binding "previous-line") :previous)
          ((string= binding "next-line") :next)
          ((or (string= binding "backspace") (string= binding "delete-left")) :backspace)
          (t nil))))

(defun buffer-picker-key-action (key)
  (cond ((or (string= key (string #\Newline))
             (string= key (string #\Return))) :accept)
        ((string= key (string #\Tab)) :complete)
        ((string= key "") (buffer-picker-bound-action))
        (t :insert)))

(defcommand switch-to-buffer ()
  "C-x b: choose a live buffer with filtering and completion."
  (let* ((origin (get-buffer-name))
         (names (buffer-picker-buffer-names))
         (query "")
         (matches names)
         (selected (buffer-picker-initial-index matches origin))
         (answer nil)
         (cancelled nil))
    (set-buffer-hint *buffer-picker-buffer*
                     "type filter; TAB complete; arrows select; RET open; C-g cancel")
    (unwind-protect
         (loop repeat *buffer-picker-max-keys*
               until (or answer cancelled)
               do (setf matches (buffer-picker-matches query names)
                        selected (if matches (min selected (1- (length matches))) 0))
                  (render-buffer-picker query matches selected)
                  (let* ((key (get-key))
                         (action (buffer-picker-key-action key)))
                    (case action
                      (:cancel (setf cancelled t))
                      (:accept (when matches (setf answer (nth selected matches))))
                      (:previous (when matches
                                   (setf selected (mod (1- selected) (length matches)))))
                      (:next (when matches
                               (setf selected (mod (1+ selected) (length matches)))))
                      (:backspace (when (plusp (length query))
                                    (setf query (subseq query 0 (1- (length query)))
                                          selected 0)))
                      (:complete (let ((prefix (buffer-picker-common-prefix matches)))
                                   (when (> (length prefix) (length query))
                                     (setf query prefix selected 0))))
                      (:insert (when (and (= (length key) 1)
                                          (graphic-char-p (char key 0)))
                                 (setf query (concatenate 'string query key)
                                       selected 0))))))
      (select-buffer origin))
    (cond (answer
           (setf *previous-picked-buffer* origin)
           (select-buffer answer)
           (message "Buffer: ~A" answer))
          (t (message "Buffer selection cancelled")))))

(defun yes-p (question)
  (string-equal (trim (prompt (format nil "~A (y/n) " question) "")) "y"))

(defcommand find-alternate-file ()
  (let ((file (trim (prompt "Find alternate file: " (or (buffer-filename) "")))))
    (when (and (plusp (length file))
               (or (not (buffer-modified-p))
                   (yes-p (format nil "~A is modified; discard the changes?" (get-buffer-name)))))
      (let ((old (rename-buffer (format nil "*old ~D*" (random 100000)))))
        (declare (ignore old))
        (let ((old-name (get-buffer-name)))
          (find-file file)
          (kill-buffer old-name))))))

(defcommand save-some-buffers ()
  (let ((origin (get-buffer-name)) (saved 0))
    (loop repeat (get-buffer-count)
          do (execute-builtin "next-buffer")
             (when (and (buffer-modified-p) (buffer-filename)
                        (yes-p (format nil "Save ~A?" (buffer-filename))))
               (save-buffer (get-buffer-name))
               (incf saved)))
    (select-buffer origin)
    (message "~[No files saved~:;Saved ~:*~D file~:P~]" saved)))

(defcommand quoted-insert ()
  "C-q: insert the next key as it is (C-q TAB inserts a tab)."
  (message "C-q-")
  (update-display)
  (let ((k (get-key)))
    (clear-message-line)
    (if (plusp (length k))
        (insert k)
        (let ((name (get-key-name)))
          (cond ((and (= (length name) 3) (string= (subseq name 0 2) "C-")
                      (lower-case-p (char name 2)))
                 (insert (string (code-char (1+ (- (char-code (char name 2)) (char-code #\a)))))))
                ((string= name "SPC") (insert " "))
                ((string= name "esc") (insert (string (code-char 27))))
                (t (message "Cannot insert ~A" (display-key name))))))))

(defcommand eval-defun ()
  "C-M-x: evaluate the top-level form around the cursor."
  (let* ((start (scan beginning-of-defun-position (min (buffer-size) (1+ (line-end))) t))
         (end (scan forward-sexp-position start t)))
    (if (null end)
        (message "No top-level form here")
        (let* ((form (buffer-substring start end))
               (value (with-editor-environment (:output out)
                        (let ((v (let ((*package* (find-package '#:sbemacs-user)))
                                   (eval-string form)))
                              (printed (get-output-stream-string out)))
                          (format nil "~@[~A => ~]~S" (and (plusp (length printed)) printed) v)))))
          (message "~A" (substitute #\Space #\Newline value))))))

(defcommand describe-key ()
  "C-x ?: what a key does."
  (message "Describe key: ")
  (update-display)
  (let ((k (get-key)))
    (if (string= k "")
        (let* ((name (get-key-name))
               (fn (gethash name *keymap*)))
          (message "~A runs ~(~A~)" (display-key name)
                   (cond (fn fn)
                         ((string= (get-key-binding) "user-defined-function") "nothing")
                         (t (get-key-binding)))))
        (message "~S inserts itself" k))))

(defun builtin-command (name)
  (lambda () (execute-builtin name)))

(defcommand eval-expression () (execute-builtin "exec-lisp-command"))
(defcommand query-replace-command () (execute-builtin "query-replace"))
(defcommand shell-command-command () (execute-builtin "shell-command"))
(defcommand recenter-command () (recenter))

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
;; undo and redo: lisp/undo.lisp

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
(global-set-key "M-!" 'shell-command-command)
(global-set-key "C-M-x" 'eval-defun)

(global-set-key "C-x b" 'switch-to-buffer)
(global-set-key "C-x C-v" 'find-alternate-file)
(global-set-key "C-x s" 'save-some-buffers)
(global-set-key "C-x d" 'dired)
(global-set-key "C-x ?" 'describe-key)
