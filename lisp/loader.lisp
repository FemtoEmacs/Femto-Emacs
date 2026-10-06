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
    (handler-bind ((warning #'muffle-warning))
      (let ((*standard-output* sink) (*error-output* sink))
        (when (or (not (probe-file fasl))
                  (> (file-write-date path) (file-write-date fasl)))
          (ensure-directories-exist fasl)
          ;; a stale fasl we may not overwrite (left by a build run as
          ;; another user) can still be removed from our own directory
          (when (probe-file fasl) (ignore-errors (delete-file fasl)))
          (multiple-value-bind (output warnings-p failure-p)
              (compile-file path :output-file fasl :external-format :utf-8)
            (declare (ignore warnings-p))
            (when (or (null output) failure-p)
              ;; load the source instead, so the real error is reported
              (ignore-errors (delete-file fasl))
              (return-from load-script
                (load path :external-format :utf-8)))))
        (load fasl)))))

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
