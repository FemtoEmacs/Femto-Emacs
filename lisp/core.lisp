;;;; core.lisp -- callbacks from C, key bindings, the init file and MAIN
;;;;
;;;; This replaces femtolisp/flcall.c (call_lisp, init_lisp) and the
;;;; keymap interpreter that lived in init.lsp.

(in-package #:sbemacs)

;;; ------------------------------------------------------------------
;;; User key bindings
;;; ------------------------------------------------------------------

(defvar *keymap* (make-hash-table :test 'equal)
  "Key name (\"C-x C-b\") -> function designator.")

(defun normalize-key-token (token)
  "One key in Emacs notation (M-d, C-M-f, M-DEL, C-/ ...) -> the C core's
names (esc d, esc C-f, esc backspace, C-_ ...); may return two tokens."
  (flet ((simple (k)
           (cond ((member k '("DEL" "<backspace>" "BS") :test #'string=) "backspace")
                 ((string= k "<delete>") "DEL")
                 ((string= k "TAB") "C-i")
                 ((string= k "RET") "C-m")
                 ((string= k "ESC") "esc")
                 ((member k '("C-SPC" "C-@") :test #'string=) "C-space")
                 ((member k '("C-/" "C--") :test #'string=) "C-_")
                 ((string= k "<f1>") "F1")
                 ((and (= (length k) 3) (string= (subseq k 0 2) "C-")
                       (upper-case-p (char k 2)))
                  (format nil "C-~C" (char-downcase (char k 2))))
                 (t k))))
    (cond ((or (and (> (length token) 4) (string= (subseq token 0 4) "C-M-"))
               (and (> (length token) 4) (string= (subseq token 0 4) "M-C-")))
           (list "esc" (simple (concatenate 'string "C-" (subseq token 4)))))
          ((and (> (length token) 2) (string= (subseq token 0 2) "M-"))
           (list "esc" (simple (subseq token 2))))
          (t (list (simple token))))))

(defun normalize-key (key)
  "KEY in Emacs notation (\"M-d\", \"C-x C-f\", \"C-M-\\\\\") or as the C core
names it (\"esc d\") -> the core's name."
  (let ((tokens (loop with start = 0
                      for pos = (position #\Space key :start start)
                      for tok = (subseq key start pos)
                      when (plusp (length tok)) collect tok
                      while pos do (setf start (1+ pos)))))
    (format nil "~{~A~^ ~}" (mapcan #'normalize-key-token tokens))))

(defun display-key (name)
  "The core's key name in Emacs notation, for help: esc C-f -> C-M-f."
  (cond ((string= name "esc [1;5C") (return-from display-key "C-right"))
        ((string= name "esc [1;5D") (return-from display-key "C-left")))
  (let* ((tokens (loop with start = 0
                       for pos = (position #\Space name :start start)
                       collect (subseq name start pos)
                       while pos do (setf start (1+ pos))))
         (out '()))
    (loop while tokens
          do (let ((tok (pop tokens)))
               (cond ((and (string= tok "esc") tokens)
                      (let ((next (pop tokens)))
                        (push (cond ((string= next "backspace") "M-DEL")
                                    ((and (> (length next) 2) (string= (subseq next 0 2) "C-"))
                                     (concatenate 'string "C-M-" (subseq next 2)))
                                    (t (concatenate 'string "M-" next)))
                              out)))
                     ((string= tok "C-space") (push "C-SPC" out))
                     ((string= tok "C-i") (push "TAB" out))
                     (t (push tok out)))))
    (format nil "~{~A~^ ~}" (nreverse out))))

(defun global-set-key (key function)
  "Bind KEY to FUNCTION (a symbol or a function of no arguments).

Any key can be bound, in Emacs notation: \"C-c a\", \"C-x h\", \"M-d\",
\"C-M-f\", \"M-DEL\", \"F1\".  A Lisp binding takes precedence over the C
core's; GLOBAL-UNSET-KEY gives the key back to the core."
  (when (symbolp function) (register-command function))
  (setf (gethash (normalize-key key) *keymap*) function))

(defun global-unset-key (key)
  (remhash (normalize-key key) *keymap*))

(defun key-binding (key)
  (gethash (normalize-key key) *keymap*))

(defvar *last-key* ""
  "The name of the key that ran the previous command (\"self-insert\" for
typed text).  Commands such as yank-pop look at it.")

(defvar *this-key* ""
  "The name of the key running the current command.")

(defvar *last-command* nil
  "The previous command: its function symbol, or the key name when the C
core ran it, or SELF-INSERT.  Kill commands set *THIS-COMMAND* to
KILL-REGION so that consecutive kills join, as in Emacs.")

(defvar *this-command* nil
  "The command running now; a command may change it (see *LAST-COMMAND*).")

(defun run-key (key)
  "Run the Lisp binding of KEY.  Returns NIL when KEY has none (the C
core then runs its own)."
  (let ((fn (gethash key *keymap*)))
    (when fn
      (funcall fn)
      t)))

;;; Commands: what M-x offers, besides the C core's own

(defvar *commands* (make-hash-table :test 'equal)
  "Command name -> function symbol, for M-x.")

(defun register-command (symbol)
  (let ((name (string-downcase (symbol-name symbol))))
    (setf (gethash name *commands*) symbol)
    ;; Esc-x completes over these too
    (when *library-path* (ignore-errors (%add-command-name name)))
    symbol))

(defun announce-commands ()
  "Tell the C core (Esc-x) about every Lisp command; at start-up the
scripts compiled into the image are not loaded again."
  (maphash (lambda (name symbol) (declare (ignore symbol)) (%add-command-name name))
           *commands*))

(defmacro defcommand (name args &body body)
  "DEFUN, and make NAME available to M-x."
  `(progn (defun ,name ,args ,@body)
          (register-command ',name)
          ',name))

;;; ------------------------------------------------------------------
;;; Hooks
;;; ------------------------------------------------------------------

(defvar *kill-hook* '()
  "Functions called with the buffer name after a region is killed.")

(defvar *startup-hook* '()
  "Functions called with no arguments once the editor screen is up.")

(defvar *kill-ring* '()
  "Killed regions, most recent first.")

(defvar *kill-ring-max* 60)

(defun remember-kill (buffer-name)
  (declare (ignore buffer-name))
  (let ((text (get-clipboard)))
    (when (plusp (length text))
      (push text *kill-ring*)
      (when (> (length *kill-ring*) *kill-ring-max*)
        (setf *kill-ring* (subseq *kill-ring* 0 *kill-ring-max*))))))

(pushnew 'remember-kill *kill-hook*)

;;; The system clipboard and the kill ring, as in Emacs: every kill or copy
;;; goes to the system clipboard (the C core does it), and C-y first looks
;;; at the clipboard.  If another program copied something since, that
;;; text joins the kill ring and is what C-y inserts; M-y then goes on to
;;; the older kills.

(defvar *use-system-clipboard* t
  "When true, C-y takes in what other programs copied.  Set it to NIL to
keep the kill ring to yourself (kills still reach the clipboard).")

(declaim (ftype (function () (values (or null string) &optional)) adopt-system-clipboard))
(defun adopt-system-clipboard ()
  "If the system clipboard holds text that is not the newest kill, push it
on the kill ring and make it what C-y inserts.  Returns the text, or NIL."
  (let ((text (and *use-system-clipboard* (system-clipboard))))
    (when (and text (not (equal text (first *kill-ring*))))
      (push text *kill-ring*)
      (when (> (length *kill-ring*) *kill-ring-max*)
        (setf *kill-ring* (subseq *kill-ring* 0 *kill-ring-max*)))
      (%set-scrap (text text))
      text)))

(defvar *undo-mode* t
  "Unlimited undo for ordinary buffers.  Set to NIL in your init file on
machines with little memory: the undo history of every modified buffer is
kept in memory.")

(defvar *color-theme* 'default-theme
  "A function of one argument, the number of colours the terminal has,
that sets faces with THEME-FACE.  The default is in lisp/theme.lisp.")

(defun apply-color-theme (colors)
  (when (and *color-theme* (fboundp *color-theme*))
    (funcall *color-theme* colors)))

(defvar *init-errors* '()
  "Problems found while loading the init file, shown after start-up.")

;;; ------------------------------------------------------------------
;;; Running Lisp safely from inside C
;;; ------------------------------------------------------------------
;;;
;;; A callback must never unwind through the C frames below it, never
;;; enter the debugger (the terminal belongs to curses) and never print to
;;; the terminal.  WITH-EDITOR-ENVIRONMENT takes care of all three.

(defun describe-error (condition)
  (let ((text (handler-case (princ-to-string condition)
                (error () (format nil "~S" (type-of condition))))))
    ;; one line, single spaces: it goes to the message line
    (format nil "Error: ~{~A~^ ~}"
            (loop with start = 0
                  for pos = (position-if (lambda (c) (member c '(#\Space #\Tab #\Newline))) text :start start)
                  for word = (subseq text start pos)
                  when (plusp (length word)) collect word
                  while pos do (setf start (1+ pos))))))

(defmacro with-editor-environment ((&key (output (gensym "OUTPUT"))) &body body)
  "Run BODY with output captured into the string stream OUTPUT, input
empty, warnings muffled and every error turned into a string result."
  `(let* ((,output (make-string-output-stream))
          (*standard-output* ,output)
          (*error-output* ,output)
          (*trace-output* ,output)
          (*standard-input* (make-string-input-stream ""))
          (*package* (find-package '#:sbemacs-user)))
     (handler-bind ((warning #'muffle-warning))
       (handler-case (progn ,@body)
         (serious-condition (c) (describe-error c))))))

(defun eval-string (string)
  "Read and evaluate every form in STRING; return the last value as text."
  (let ((value nil) (eof '#:eof))
    (with-input-from-string (in string)
      (loop for form = (read in nil eof)
            until (eq form eof)
            do (setf value (eval form))))
    value))

(defun write-c-string (string sap size)
  "Copy STRING as NUL-terminated UTF-8 into SIZE bytes at SAP, truncating
on a character boundary."
  (let* ((bytes (sb-ext:string-to-octets string :external-format :utf-8))
         (n (min (length bytes) (1- size))))
    ;; do not cut a multi-byte character in half
    (when (< n (length bytes))
      (loop while (and (> n 0) (= (logand (aref bytes n) #xC0) #x80)) do (decf n)))
    (loop for i below n do (setf (sb-sys:sap-ref-8 sap i) (aref bytes i)))
    (setf (sb-sys:sap-ref-8 sap n) 0)
    n))

;;; The three callbacks.  Their C types are in src/interface.c.

(sb-alien:define-alien-callable lisp-eval sb-alien:int
    ((expr sb-alien:c-string) (out sb-alien:system-area-pointer) (size sb-alien:int))
  (let ((result
          (handler-case
              (with-editor-environment (:output output)
                (let* ((value (eval-string expr))
                       (printed (get-output-stream-string output)))
                  (if (string= printed "")
                      (princ-to-string value)
                      (format nil "~A~A" printed value))))
            (serious-condition (c) (describe-error c)))))
    (write-c-string result out size)
    0))

(defvar *self-insert-hook* '()
  "Functions called with a one-character string when a printable ASCII
key, TAB or RET is typed.  The first that returns true has handled the
key, and the C core does not insert it.  Indentation (lisp/indent.lisp)
installs itself here.")

(defun run-self-insert (key)
  (dolist (f *self-insert-hook* nil)
    (when (funcall f key) (return t))))

(sb-alien:define-alien-callable lisp-event sb-alien:int
    ((event sb-alien:c-string) (arg sb-alien:c-string))
  (let* ((handled nil)
         (result
           (handler-case
               (with-editor-environment ()
                 (cond ((string= event "key")
                        (command-boundary arg)
                        (let ((fn (gethash arg *keymap*)))
                          (setf *this-key* arg
                                *this-command* (or fn arg))
                          ;; a bound key counts as handled even if its
                          ;; command fails: C must not run its own
                          (when fn (setf handled :key))
                          (unwind-protect (run-key arg)
                            (setf *last-key* arg
                                  *last-command* *this-command*))))
                       ((string= event "command")
                        (let ((fn (gethash arg *commands*)))
                          (when (and fn (fboundp fn))
                            (setf handled :key
                                  *this-command* fn)
                            (unwind-protect (funcall fn)
                              (setf *last-command* *this-command*)))))
                       ((string= event "self-insert")
                        (command-boundary t)
                        (setf *last-key* "self-insert"
                              *last-command* 'self-insert)
                        (setf handled (run-self-insert arg)))
                       ((string= event "kill") (dolist (f *kill-hook*) (funcall f arg)))
                       ((string= event "startup") (run-startup))
                       ((string= event "colors") (apply-color-theme (parse-integer arg))))
                 nil)
             (serious-condition (c) (describe-error c)))))
    (when (stringp result)
      (ignore-errors (message "~A" result))
      ;; an error in a self-insert function must not swallow the key
      (unless (eq handled :key) (setf handled nil)))
    (if handled 1 0)))

;; defined in lisp/highlight.lisp, a script loaded after the engine
(declaim (ftype (function (t t t t) t) highlight-buffer-text))

(sb-alien:define-alien-callable lisp-highlight sb-alien:void
    ((fname sb-alien:c-string) (bname sb-alien:c-string)
     (text sb-alien:system-area-pointer) (len sb-alien:int)
     (colors sb-alien:system-area-pointer))
  (declare (ignore bname))
  ;; on any error the C side keeps its default colours
  (ignore-errors (highlight-buffer-text fname text len colors))
  (values))

;;; Every change to a buffer's text, reported by the C core (src/undo.c)
;;; for the undo history in lisp/undo.lisp.
(declaim (ftype (function (t t t t t) t) record-change))
(declaim (ftype (function (&optional t) t) undo-boundary))

(sb-alien:define-alien-callable lisp-change sb-alien:void
    ((id sb-alien:long) (kind sb-alien:int) (pos sb-alien:long)
     (text sb-alien:system-area-pointer) (len sb-alien:long))
  ;; must not fail: on any error the change is simply not recorded
  (ignore-errors
   (when (fboundp 'record-change)
     (record-change id (code-char kind) pos text len)))
  (values))

(defun command-boundary (&optional key)
  "Called before each key (its name, or T for a typed character): the
changes a command makes undo together."
  (when (fboundp 'undo-boundary)
    (ignore-errors (undo-boundary key))))

(defun install-hooks ()
  (%set-hooks (sb-alien:alien-sap (sb-alien:alien-callable-function 'lisp-eval))
              (sb-alien:alien-sap (sb-alien:alien-callable-function 'lisp-event))
              (sb-alien:alien-sap (sb-alien:alien-callable-function 'lisp-highlight)))
  (%set-change-hook (sb-alien:alien-sap (sb-alien:alien-callable-function 'lisp-change))))

;;; ------------------------------------------------------------------
;;; Start-up
;;; ------------------------------------------------------------------

(defparameter *banner*
  '("                                     _______.  .______    "
    "                                    /       |  |   _  \\   "
    "                                   |   (----`  |  |_)  |  "
    "                                    \\   \\      |   _  <   "
    "                                .----)   |     |  |_)  |  "
    "                                |_______/      |______/   "
    ""
    "                  _______ .___  ___.      ___       ______     _______.  "
    "                 |   ____||   \\/   |     /   \\     /      |   /       |  "
    "                 |  |__   |  \\  /  |    /  ^  \\   |  ,----'  |   (----`  "
    "                 |   __|  |  |\\/|  |   /  /_\\  \\  |  |        \\   \\      "
    "                 |  |____ |  |  |  |  /  _____  \\ |  `----.----)   |     "
    "                 |_______||__|  |__| /__/     \\__\\ \\______|_______/      "))

(defun show-startup-message ()
  (when (string= "*scratch*" (get-buffer-name))
    (insert (format nil "~%~%~%"))
    (dolist (line *banner*)
      (insert (string-right-trim " " line) (string #\Newline)))
    (insert (format nil "~%                 ~A~%" (get-version-string)))
    (insert (format nil "                 ~A ~A~%~%~%"
                    (lisp-implementation-type) (lisp-implementation-version)))))

(pushnew 'show-startup-message *startup-hook*)

(defun run-startup ()
  (dolist (f (reverse *startup-hook*))
    (funcall f))
  (when *init-errors*
    (message "~{~A~^; ~}" (reverse *init-errors*))))

(defun user-init-file ()
  "~/.sbemacs/init.lisp, or ~/.sbemacs.lisp, whichever exists."
  (or (probe-file (merge-pathnames ".sbemacs/init.lisp" (user-homedir-pathname)))
      (probe-file (merge-pathnames ".sbemacs.lisp" (user-homedir-pathname)))))

(defun load-user-init ()
  (let ((file (user-init-file)))
    (when file
      (handler-case
          (let ((*package* (find-package '#:sbemacs-user)))
            (handler-bind ((warning #'muffle-warning))
              (load file :external-format :utf-8)))
        (serious-condition (c)
          (push (format nil "~A: ~A" (file-namestring file) (describe-error c))
                *init-errors*))))))

;;; ------------------------------------------------------------------
;;; MAIN
;;; ------------------------------------------------------------------

(defun usage ()
  (format t "Usage: sbemacs [--gui] [-q] [--no-mouse] [file]~%~%  --gui, -g   open a window (SDL2) instead of using the terminal;~%              also when started as sbemacs-gui~%  -q          do not load ~~/.sbemacs/init.lisp~%  --no-mouse  leave the mouse to the terminal (its own text selection)~%  --version   print the version and exit~%"))

(defmacro with-foreign-float-traps (&body body)
  "C libraries (SDL, FreeType, graphics drivers) may compute with
infinities and NaNs; SBCL would turn that into a Lisp error."
  `(sb-int:with-float-traps-masked (:overflow :invalid :divide-by-zero :inexact :underflow)
     ,@body))

(defvar *gui-by-default* nil
  "True in the Windows installer's sbemacs.exe, a program without a console:
it always opens a window.")

(defun gui-requested-p (args)
  (or *gui-by-default*
      (member "--gui" args :test #'string=)
      (member "-g" args :test #'string=)
      (search "gui" (file-namestring (or (first sb-ext:*posix-argv*) "")))))

(defun choose-backend (want-gui)
  "Load the GUI library when asked for and a window can be opened here;
otherwise the terminal library.  Returns the backend in use."
  (when want-gui
    (handler-case
        (progn
          (load-core-library :gui)
          (if (= 1 (with-foreign-float-traps (%screen-probe)))
              (return-from choose-backend :gui)
              (progn
                (unload-core-library)
                (format *error-output* "sbemacs: cannot open a window here, using the terminal~%"))))
      (error (e)
        (unload-core-library)
        (format *error-output* "sbemacs: ~A~%sbemacs: using the terminal~%" e))))
  (load-core-library :terminal)
  :terminal)

(defun call-fe-main (args)
  "Call fe_main with a C argv built from ARGS."
  (let* ((argv (cons "sbemacs" args))
         (argc (length argv))
         (strings (mapcar #'sb-alien:make-alien-string argv))
         (array (sb-alien:make-alien (* sb-alien:char) (1+ argc))))
    (unwind-protect
         (progn
           (loop for i from 0 for s in strings
                 do (setf (sb-alien:deref array i) s))
           (setf (sb-alien:deref array argc) (sb-alien:sap-alien (sb-sys:int-sap 0) (* sb-alien:char)))
           (%fe-main argc (sb-alien:cast array (* sb-alien:c-string))))
      (mapc #'sb-alien:free-alien strings)
      (sb-alien:free-alien array))))

(defun main ()
  (sb-ext:disable-debugger)
  (setf sb-impl::*default-external-format* :utf-8
        sb-alien::*default-c-string-external-format* :utf-8)
  (let* ((args (rest sb-ext:*posix-argv*))
         (no-init (member "-q" args :test #'string=)))
    (setf args (remove "-q" args :test #'string=))
    (cond ((member "--version" args :test #'string=)
           (load-core-library)
           (format t "~A~%~A ~A~%" (get-version-string)
                   (lisp-implementation-type) (lisp-implementation-version))
           (sb-ext:exit :code 0))
          ((or (member "--help" args :test #'string=) (member "-h" args :test #'string=))
           (usage)
           (sb-ext:exit :code 0)))
    (let ((want-gui (gui-requested-p args))
          (no-mouse (member "--no-mouse" args :test #'string=)))
      (setf args (remove-if (lambda (a) (member a '("--gui" "-g" "--no-mouse" "+") :test #'string=)) args))
      ;; fe_main takes a final "-" as "no mouse"
      (when no-mouse (setf args (append args (list "-"))))
      (handler-case (choose-backend want-gui)
        (error (e)
          (format *error-output* "sbemacs: ~A~%" e)
          (sb-ext:exit :code 1 :abort t))))
    (install-hooks)
    (start-scripts)
    (announce-commands)
    (announce-buffer-hints)
    (setf *init-errors* (reverse *script-errors*))
    (unless no-init (load-user-init))
    (when *undo-mode* (add-mode-global "undo"))
    (when (and (eq *backend* :gui) (fboundp 'apply-gui-settings))
      (handler-case (funcall 'apply-gui-settings)
        (error (e) (push (describe-error e) *init-errors*))))
    (let ((code (with-foreign-float-traps (call-fe-main args))))
      (finish-output)
      (sb-ext:exit :code code :abort t))))
