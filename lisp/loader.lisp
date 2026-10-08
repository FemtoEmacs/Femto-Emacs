;;;; loader.lisp -- loading the Lisp scripts at start-up
;;;;
;;;; The executable contains only the engine: package.lisp, ffi.lisp, this
;;;; file and core.lisp.  Everything else in lisp/ is a script:
;;;;
;;;;   highlight.lisp      the tokenizer and DEFINE-LANGUAGE
;;;;   indent.lisp         automatic indentation and DEFINE-INDENTATION
;;;;   theme.lisp          the colour theme
;;;;   gui.lisp            font and options for the window (sbemacs --gui)
;;;;   languages/*.lisp    one file per language
;;;;   defaults.lisp       the commands and key bindings that were init.lsp
;;;;   extensions/*.lisp   buffer menu, kill ring, dired, grep
;;;;
;;;; followed by your own ~/.sbemacs/languages/*.lisp and
;;;; ~/.sbemacs/extensions/*.lisp, then ~/.sbemacs/init.lisp.
;;;;
;;;; The scripts are also compiled into the executable, so it works without
;;;; the lisp/ directory.  At start-up each script whose contents differ
;;;; from what the executable holds is loaded again, so editing a script is
;;;; enough: no rebuild.  Changed scripts are compiled once into a cache
;;;; (~/.cache/sbemacs/) so that start-up stays fast.  Inside the editor,
;;;; C-x C-r (reload-scripts) picks up changes without restarting.

(in-package #:sbemacs)

(defvar *script-directory* nil
  "The lisp/ directory the scripts are loaded from.")

(defvar *loaded-scripts* (make-hash-table :test 'equal)
  "Script name -> hash of the contents that are currently loaded.")

(defvar *script-errors* '()
  "Messages for scripts that failed to load, most recent first.")

(defvar *release-build* nil
  "True while build.lisp builds the executable (and in the tests that check
it): a script that does not compile cleanly is then an error that stops
the build.  Interactively (start-up, C-x C-r) such a script is still loaded
from its source, so that the rest of it works, and the error is reported.")

;;; The external format the scripts are read in.  On Windows, CR LF line
;;; ends are read as LF: a file saved with them (by Notepad, or by Git for
;;; Windows without .gitattributes) would otherwise keep a CR at the end of
;;; every line, and a format string continued with "~" and a newline would
;;; get "~" + CR, an unknown directive: the form is then compiled into an
;;; error, raised only when it runs.  SBCL 2.6.9 on Windows reads both line
;;; ends this way; older SBCLs elsewhere ignore :NEWLINE, so it is only used
;;; there (checkouts get LF everywhere from .gitattributes).
(defparameter *script-external-format*
  #+win32 '(:utf-8 :newline :crlf)
  #-win32 :utf-8)

(defun compiler-diagnosis (report)
  "The lines of the compiler's REPORT that say what went wrong: the body of
each \"caught ERROR\" or \"caught WARNING\" (the indented lines after it)."
  (let ((lines '()) (keep nil))
    (with-input-from-string (in report)
      (loop for line = (read-line in nil)
            while line
            do (let ((text (string-trim "; " line)))
                 (cond ((or (search "caught ERROR" line) (search "caught WARNING" line))
                        (setf keep t))
                       ((not (and (>= (length line) 3) (string= ";  " line :end2 3)))
                        (setf keep nil))
                       ((and keep (plusp (length text))) (push text lines))))))
    (let ((found (nreverse lines)))
      (subseq found 0 (min 12 (length found))))))

(define-condition script-compile-error (error)
  ((path :initarg :path :reader script-compile-error-path)
   (messages :initarg :messages :reader script-compile-error-messages))
  (:report (lambda (c stream)
             (format stream "~A does not compile:~{~%  ~A~}"
                     (file-namestring (script-compile-error-path c))
                     (or (script-compile-error-messages c)
                         (list "(the compiler reported a failure)"))))))

(defun script-directory-candidates ()
  (let ((env (sb-ext:posix-getenv "SBEMACS_LISP"))
        (exe (ignore-errors (make-pathname :name nil :type nil :version nil
                                           :defaults (truename sb-ext:*runtime-pathname*)))))
    (remove nil
            (list (and env (plusp (length env))
                       (pathname (if (find (char env (1- (length env))) "/\\")
                                     env
                                     (concatenate 'string env "/"))))
                  (and exe (merge-pathnames "lisp/" exe))
                  (and exe (merge-pathnames "../lib/sbemacs/lisp/" exe))
                  (and *source-directory* (merge-pathnames "lisp/" *source-directory*))))))

(defun find-script-directory ()
  (let ((dir (find-if (lambda (d) (probe-file (merge-pathnames "highlight.lisp" d)))
                      (script-directory-candidates))))
    (and dir (truename dir))))

(defun lisp-files (directory)
  (sort (directory (merge-pathnames "*.lisp" directory))
        #'string< :key #'namestring))

(defun script-files (directory)
  "The scripts in DIRECTORY, in load order."
  (flet ((file (name) (let ((p (merge-pathnames name directory))) (and (probe-file p) (list p)))))
    (append (file "highlight.lisp")
            (file "indent.lisp")
            (file "theme.lisp")
            (file "undo.lisp")
            (file "gui.lisp")
            (lisp-files (merge-pathnames "languages/" directory))
            (file "defaults.lisp")
            (lisp-files (merge-pathnames "extensions/" directory)))))

(defun user-script-files ()
  (let ((home (merge-pathnames ".sbemacs/" (user-homedir-pathname))))
    (append (lisp-files (merge-pathnames "languages/" home))
            (lisp-files (merge-pathnames "extensions/" home)))))

(defun script-name (path)
  "A stable key for PATH: relative to the script directory when inside it."
  (let ((name (native path))
        (dir (and *script-directory* (native *script-directory*))))
    (if (and dir (> (length name) (length dir)) (string= dir name :end2 (length dir)))
        (subseq name (length dir))
        name)))

(defun file-contents-hash (path)
  (with-open-file (in path :external-format '(:utf-8 :replacement #\?))
    (let* ((s (make-string (file-length in)))
           (n (read-sequence s in)))
      (cons n (sxhash (subseq s 0 n))))))

(defun fasl-cache-directory ()
  (merge-pathnames (format nil ".cache/sbemacs/~A/"
                           (substitute-if #\_ (lambda (c) (not (alphanumericp c)))
                                          (lisp-implementation-version)))
                   (user-homedir-pathname)))

(defun cached-fasl (path cache-directory)
  (merge-pathnames
   (make-pathname :name (substitute-if #\_ (lambda (c) (not (alphanumericp c))) (native path))
                  :type "fasl")
   cache-directory))

(defun system-script-p (path)
  (and *script-directory*
       (let ((name (native path)) (dir (native *script-directory*)))
         (and (> (length name) (length dir)) (string= dir name :end2 (length dir))))))

(defun load-script (path &optional (cache-directory (fasl-cache-directory)))
  "Compile PATH into the cache (when the cached fasl is missing or older)
and load it.  Errors are signalled to the caller.  The editor's own
scripts start in package SBEMACS, the user's in SBEMACS-USER."
  (let ((fasl (cached-fasl path cache-directory))
        (*package* (find-package (if (system-script-p path) '#:sbemacs '#:sbemacs-user)))
        (*readtable* (copy-readtable nil))
        (sink (make-broadcast-stream)))
    ;; The compiler's messages are kept off the screen (the editor owns it):
    ;; they are collected, and shown only if the script does not compile.
    ;; (An error in a form is handled inside COMPILE-FILE, which only prints
    ;; it -- "caught ERROR" -- and reports the failure in its third value.)
    (handler-bind ((warning #'muffle-warning))
      (let ((*standard-output* sink) (*error-output* sink))
        (flet ((compile-it ()
                 (ensure-directories-exist fasl)
                 ;; a stale fasl we may not overwrite (left by a build run as
                 ;; another user) can still be removed from our own directory
                 (when (probe-file fasl) (ignore-errors (delete-file fasl)))
                 (let ((report (make-string-output-stream)))
                   (multiple-value-bind (output warnings-p failure-p)
                       (let ((*error-output* report) (*standard-output* report))
                         (compile-file path :output-file fasl
                                            :external-format *script-external-format*))
                     (declare (ignore warnings-p))
                     (when (or (null output) failure-p)
                       (ignore-errors (delete-file fasl))
                       (let ((failure (make-condition 'script-compile-error
                                                      :path path
                                                      :messages (compiler-diagnosis
                                                                 (get-output-stream-string report)))))
                         ;; building the executable: never ship a form compiled
                         ;; into an error
                         (when *release-build* (error failure))
                         ;; interactively: load the source, so that the rest of
                         ;; the script works, and report the failure (the
                         ;; script is not marked as loaded: C-x C-r tries again)
                         (load path :external-format *script-external-format*)
                         (error failure)))))))
          (when (or (not (probe-file fasl))
                    (> (file-write-date path) (file-write-date fasl)))
            (compile-it))
          ;; a fasl compiled against an older version of another script (a
          ;; structure that gained a slot, say) fails to load: compile again
          (handler-case (load fasl)
            (error ()
              (compile-it)
              (load fasl))))))))

(defun load-scripts (&key (files (append (script-files *script-directory*) (user-script-files)))
                          cache-directory force)
  "Load every script in FILES whose contents changed since it was last
loaded (all of them with FORCE).  Returns the names loaded and, as a
second value, error messages."
  (let ((loaded '()) (errors '()))
    (dolist (path files)
      (let ((name (script-name path))
            (hash (ignore-errors (file-contents-hash path))))
        (when (and hash (or force (not (equal hash (gethash name *loaded-scripts*)))))
          (handler-case
              (progn
                (if cache-directory
                    (load-script path cache-directory)
                    (load-script path))
                (setf (gethash name *loaded-scripts*) hash)
                (push name loaded))
            (serious-condition (c)
              (push (format nil "~A: ~A" name (describe-error c)) errors))))))
    (values (nreverse loaded) (nreverse errors))))

(defun start-scripts ()
  "Called by MAIN before the init file: bring the scripts up to date."
  (setf *script-directory* (find-script-directory))
  (multiple-value-bind (loaded errors)
      (load-scripts :files (append (and *script-directory* (script-files *script-directory*))
                                   (user-script-files)))
    (declare (ignore loaded))
    (setf *script-errors* errors)))

(defun reload-scripts (&optional force)
  "C-x C-r: load the scripts that changed since they were last loaded,
then redraw with the (possibly new) colour theme.  With FORCE, all."
  (unless *script-directory* (setf *script-directory* (find-script-directory)))
  (multiple-value-bind (loaded errors)
      (load-scripts :files (append (and *script-directory* (script-files *script-directory*))
                                   (user-script-files))
                    :force force)
    (%reapply-colors)
    (cond (errors (message "~{~A~^; ~}" errors))
          (loaded (message "reloaded ~{~A~^, ~}" loaded))
          (t (message "no script changed~@[ in ~A~]"
                      (and *script-directory* (native *script-directory*)))))
    loaded))
