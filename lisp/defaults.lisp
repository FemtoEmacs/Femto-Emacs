;;;; defaults.lisp -- the user functions and key bindings from init.lsp
;;;;
;;;; In FemtoEmacs these lived in ~/init.lsp and had to be copied into the
;;;; home directory together with r5rs.scm.  This is a script (see
;;;; loader.lisp): edit it and press C-x C-r, no rebuild needed.
;;;; ~/.sbemacs/init.lisp is loaded afterwards and overrides what is here.

(in-package #:sbemacs)

;;; ------------------------------------------------------------------
;;; Helpers
;;; ------------------------------------------------------------------

(defun current-line-text ()
  "The text of the line the cursor is on, without moving the cursor."
  (buffer-substring (line-start) (line-end)))

(defun split-lines (string)
  (loop with start = 0
        for pos = (position #\Newline string :start start)
        collect (subseq string start pos)
        while pos do (setf start (1+ pos))))

(defun read-string (string)
  "Read a Lisp object from STRING: (read-string \"(2016 8 31)\") => (2016 8 31)"
  (let ((*read-eval* nil))
    (read-from-string string)))

;;; ------------------------------------------------------------------
;;; Dates
;;; ------------------------------------------------------------------

(defun weekday (n)
  (case n
    (0 "Sunday") (1 "Monday") (2 "Tuesday") (3 "Wednesday")
    (4 "Thursday") (5 "Friday") (6 "Saturday") (t "unknown")))

(defun what-day (ymd)
  "(what-day '(2016 9 3)) => \"Saturday\"   (Zeller-style congruence)"
  (destructuring-bind (y m d) ymd
    (let* ((ax (floor (- 14 m) 12))
           (mm (+ m (* 12 ax) -2))
           (yy (- y ax)))
      (weekday (mod (+ yy
                       (floor (- (* 13 mm) 1) 5)
                       (floor yy 4)
                       (- (floor yy 100))
                       (floor yy 400)
                       d)
                    7)))))

;; C-c z : replace a region holding (y m d) with the name of that day
(defun insert-day ()
  (let ((region (cut-region)))
    (handler-case (insert (what-day (read-string region)))
      (error ()
        (insert region)
        (message "insert-day: the region must contain a date such as (2016 9 3)")))))

;;; ------------------------------------------------------------------
;;; HTML helpers
;;; ------------------------------------------------------------------

;; C-c a
(defun html-p ()
  (insert "<p> </p>")
  (backward-char 5))

;; C-c b
(defun html-h1 ()
  (beginning-of-line)
  (insert "<h1> </h1>")
  (beginning-of-line)
  (forward-char 4))

;; C-c c
(defun html-pp ()
  (end-of-line)
  (insert "<p>-" (get-clipboard) "-</p>"))

;;; ------------------------------------------------------------------
;;; Indentation and case
;;; ------------------------------------------------------------------

;; C-x >
(defun indent-two () (insert "  "))

;; C-x <
(defun deindent-two () (backward-delete-char 2))

(defun transform-region (function)
  (kill-region)
  (set-clipboard (funcall function (get-clipboard)))
  (yank)
  (clear-message-line))

;; C-x C-u
(defun upcase-region () (transform-region #'string-upcase))

;; C-x C-l
(defun downcase-region () (transform-region #'string-downcase))

;;; ------------------------------------------------------------------
;;; C-x C-e: evaluate the Lisp expression before the cursor
;;; ------------------------------------------------------------------

(defun sexp-before (text end)
  "Start index of the Lisp expression that ends just before END in TEXT
(an octet vector), or NIL.  Strings, ; comments and #\\ characters are
skipped while matching parentheses."
  (let ((i end))
    ;; skip blanks back to the end of the expression
    (loop while (and (> i 0) (member (aref text (1- i)) '(32 9 10 13))) do (decf i))
    (when (zerop i) (return-from sexp-before nil))
    (if (member (aref text (1- i)) '(41 93))
        ;; a list: scan forward from the start, pairing parentheses
        (let ((stack '()) (k 0) (start nil) (stop i))
          (loop while (< k stop)
                do (let ((b (aref text k)))
                     (cond ((= b 59) (setf k (or (position 10 text :start k :end stop) stop)))
                           ((= b 34)
                            (incf k)
                            (loop while (and (< k stop) (/= (aref text k) 34))
                                  do (incf k (if (= (aref text k) 92) 2 1)))
                            (incf k))
                           ((and (= b 35) (< (1+ k) stop) (= (aref text (1+ k)) 92))
                            (incf k 3))
                           ((member b '(40 91)) (push k stack) (incf k))
                           ((member b '(41 93))
                            (let ((open (pop stack)))
                              (when (= k (1- stop)) (setf start open)))
                            (incf k))
                           (t (incf k)))))
          ;; include a quote or #' in front of the list
          (when start
            (loop while (and (> start 0) (member (aref text (1- start)) '(39 96 44 35)))
                  do (decf start)))
          start)
        ;; an atom
        (let ((j i))
          (loop while (and (> j 0)
                           (not (member (aref text (1- j)) '(32 9 10 13 40 41 91 93 34 59))))
                do (decf j))
          j))))

(defun eval-last-sexp ()
  "Evaluate the Lisp expression before the cursor and show its value on
the message line (C-x C-e, as in GNU Emacs).  Esc-] does the same but
inserts the value into the buffer."
  (let* ((end (point))
         (from (max 0 (- end 65536)))
         (text (buffer-octets from end))
         (start (sexp-before text (length text))))
    (if (null start)
        (message "No expression before the cursor")
        (let* ((form (sb-ext:octets-to-string text :start start
                                                  :external-format '(:utf-8 :replacement #\?)))
               (value (with-editor-environment (:output out)
                        (let ((v (let ((*package* (find-package '#:sbemacs-user)))
                                   (eval-string form)))
                              (printed (get-output-stream-string out)))
                          (format nil "~@[~A => ~]~S" (and (plusp (length printed)) printed) v)))))
          (message "~A" (substitute #\Space #\Newline value))))))

;;; ------------------------------------------------------------------
;;; Key bindings
;;; ------------------------------------------------------------------

(global-set-key "C-x C-b" 'buffer-menu)
(global-set-key "C-x C-d" 'dired)
(global-set-key "C-x C-u" 'upcase-region)
(global-set-key "C-x C-l" 'downcase-region)
(global-set-key "C-x C-g" 'grep-command)
(global-set-key "C-x !"   'next-grep)

(global-set-key "C-c a" 'html-p)
(global-set-key "C-c b" 'html-h1)
(global-set-key "C-c c" 'html-pp)
(global-set-key "C-c i" 'insert-kill-ring)
(global-set-key "C-c k" 'kill-ring-menu)
(global-set-key "C-c z" 'insert-day)

(global-set-key "C-x C-r" 'reload-scripts)
(global-set-key "C-x C-e" 'eval-last-sexp)
(global-set-key "C-x C-i" 'indent-region)

(global-set-key "C-x >" 'indent-two)        ; C-o and C-t are Emacs's again
(global-set-key "C-x <" 'deindent-two)       ; (lisp/extensions/emacs-keys.lisp)

;;; Copy on select.  In a terminal, SBEmacs takes the mouse (so that clicks
;;; move the cursor and press the mode line's buttons), and the terminal no
;;; longer selects text itself: Cmd-C then has nothing to copy, and iTerm2
;;; says "mouse reporting has prevented making a selection".  So a mouse
;;; drag copies what it selects to the system clipboard at once, as many
;;; terminals do: Cmd-V pastes it in any other program, and C-y here.  The
;;; kill ring does not change until C-y takes it in.  (Holding Option while
;;; dragging -- Shift on Linux -- still gives the terminal's own selection.)

(defvar *copy-on-select* t
  "When true, text selected by dragging the mouse goes to the system
clipboard at once.")

(declaim (ftype (function () (values null &optional)) copy-on-select))
(defun copy-on-select ()
  (let ((m (mark)) (p (point)))
    (when (and *copy-on-select* m (/= m p))
      (let ((text (buffer-substring (min m p) (max m p))))
        (set-system-clipboard text)
        (message "Copied ~:D character~:P to the clipboard: Cmd-V (Ctrl-V) pastes it elsewhere, C-y here"
                 (length text)))))
  nil)

(pushnew 'copy-on-select *select-hook*)

;;; File name completion: TAB in the prompts of C-x C-f, C-x i, C-x C-w.
;;; The C core asks for the names (src/complete.c); they are found here
;;; with SBCL's DIRECTORY, so no shell is needed, on any system.  * and ?
;;; are wild cards; ~/ is the home folder.  Hidden names (.git, say) are
;;; offered only when what was typed starts with a dot.

(defparameter *completion-limit* 500
  "At most this many names are offered.")

(declaim (ftype (function (simple-string simple-string fixnum fixnum) (values boolean &optional))
                wild-match-at))
(defun wild-match-at (pattern name p n)
  "Does PATTERN from P match NAME from N?  * any run of characters, ? one."
  (declare (type fixnum p n))
  (cond ((= p (length pattern)) (= n (length name)))
        ((char= (char pattern p) #\*)
         (loop for k from n to (length name)
               thereis (wild-match-at pattern name (1+ p) k)))
        ((= n (length name)) nil)
        ((or (char= (char pattern p) #\?)
             (char-equal-for-files (char pattern p) (char name n)))
         (wild-match-at pattern name (1+ p) (1+ n)))
        (t nil)))

(declaim (ftype (function (character character) (values boolean &optional)) char-equal-for-files))
(defun char-equal-for-files (a b)
  "Case matters in file names on Linux, not on macOS or Windows."
  #+(or darwin win32) (char-equal a b)
  #-(or darwin win32) (char= a b))

(declaim (ftype (function (string string) (values boolean &optional)) file-name-matches-p))
(defun file-name-matches-p (typed name)
  "Does the file NAME complete TYPED (a prefix, or a pattern with * or ?)?"
  (if (find-if (lambda (c) (member c '(#\* #\?))) typed)
      (wild-match-at (coerce typed 'simple-string) (coerce name 'simple-string) 0 0)
      (and (<= (length typed) (length name))
           (every #'char-equal-for-files typed (subseq name 0 (length typed))))))

(defun file-name-completions (typed &optional (default-directory *default-pathname-defaults*))
  "The names that complete TYPED, as typed (with its folder part), sorted;
a folder ends in /."
  (let* ((cut (position-if (lambda (c) (or (char= c #\/) #+win32 (char= c #\\))) typed
                           :from-end t))
         (folder (if cut (subseq typed 0 (1+ cut)) ""))
         (stem (if cut (subseq typed (1+ cut)) typed))
         (real (cond ((and (>= (length folder) 2) (string= (subseq folder 0 2) "~/"))
                      (merge-pathnames (subseq folder 2) (user-homedir-pathname)))
                     ((string= folder "") default-directory)
                     (t (merge-pathnames (sb-ext:parse-native-namestring folder) default-directory))))
         (names '()))
    (dolist (p (ignore-errors
                (directory (merge-pathnames (make-pathname :name :wild :type :wild) real)
                           :resolve-symlinks nil)))
      (let ((name (if (and (null (pathname-name p)) (null (pathname-type p)))
                      (let ((dirs (pathname-directory p)))
                        (and (consp dirs) (stringp (car (last dirs)))
                             (concatenate 'string (car (last dirs)) "/")))
                      (file-namestring (native p)))))
        (when (and name
                   (or (zerop (length name)) (char/= (char name 0) #\.)
                       (and (plusp (length stem)) (char= (char stem 0) #\.)))
                   (file-name-matches-p stem name))
          (push (concatenate 'string folder name) names))))
    (let ((sorted (sort names #'string<)))
      (subseq sorted 0 (min *completion-limit* (length sorted))))))

;;; Windows' command interpreter, for M-! (shell.lisp) and Codex's npm shim
;;; (codex.lisp).  Not looked up in the PATH: there MSYS2 or Git for Windows
;;; may put a cmd of their own -- a shell script, which Windows cannot start
;;; ("not a valid Win32 application").  COMSPEC names the real one.

#+win32
(declaim (ftype (function () (values string &optional)) windows-command-interpreter))
#+win32
(defun windows-command-interpreter ()
  (let ((comspec (sb-ext:posix-getenv "COMSPEC"))
        (root (or (sb-ext:posix-getenv "SystemRoot") "C:\\Windows")))
    (if (and comspec (probe-file comspec))
        comspec
        (concatenate 'string root "\\System32\\cmd.exe"))))
