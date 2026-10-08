;;;; build.lisp -- compile the Lisp side and save the sbemacs executable
;;;;
;;;;   sbcl --non-interactive --no-sysinit --no-userinit --load build.lisp
;;;;
;;;; (make does this for you.)  The result, sbemacs (sbemacs.exe on
;;;; Windows), must stay next to libsbemacs-term and libsbemacs-gui
;;;; (.so, .dylib or .dll).


(defparameter *root*
  (make-pathname :name nil :type nil :defaults (or *load-truename* *default-pathname-defaults*)))

;; The engine; everything else in lisp/ is a script (see lisp/loader.lisp)
(defparameter *engine*
  '("lisp/package" "lisp/ffi" "lisp/loader" "lisp/core"))

(setf sb-impl::*default-external-format* :utf-8)

;; Efficiency notes ("unable to optimize due to type uncertainty", "doing
;; SAP to pointer coercion") are advice, not problems: recent SBCLs print
;; them for the C callbacks.  Keep the build output to warnings and errors.
(declaim (sb-ext:muffle-conditions sb-ext:compiler-note))

(defun build-file (name)
  "Compile and load one engine file.  COMPILE-FILE's third value says
whether the file compiled cleanly: a form it could not compile becomes code
that signals \"Execution of a form compiled with errors\" only when it runs,
so a failure must stop the build here, not surface in the user's hands."
  (let* ((source (merge-pathnames (concatenate 'string name ".lisp") *root*))
         (output (merge-pathnames (concatenate 'string "build/" name ".fasl") *root*)))
    (ensure-directories-exist output)
    (multiple-value-bind (fasl warnings-p failure-p)
        (compile-file source :output-file output :verbose nil :print nil
                             :external-format #+win32 '(:utf-8 :newline :crlf) #-win32 :utf-8)
      (declare (ignore warnings-p))
      (when (or (null fasl) failure-p)
        (error "Compilation of ~A failed (see the messages above)" source))
      (load fasl))))

;; Load the core library first so that the foreign symbols resolve at
;; compile time.  It is loaded with :dont-save: the executable finds it
;; again at start-up, next to itself (see LOAD-CORE-LIBRARY).
;;
;; The Windows installer builds a program for the window only, without a
;; console (windows/build-installer.sh): SBEMACS_WINDOW_APP=1.  It has no
;; terminal library, so the window's library resolves the symbols.
(defparameter *window-app* (equal (sb-ext:posix-getenv "SBEMACS_WINDOW_APP") "1"))

(sb-alien:load-shared-object
 (sb-ext:native-namestring
  (merge-pathnames (format nil "libsbemacs-~A.~A" (if *window-app* "gui" "term")
                           #+darwin "dylib" #+win32 "dll" #-(or darwin win32) "so")
                   *root*))
 :dont-save t)

(handler-bind ((style-warning #'muffle-warning))
  (mapc #'build-file *engine*))

;; Compile the scripts into the image too, so that the executable works
;; without lisp/.  Their contents are remembered: at start-up only scripts
;; that were edited since are loaded again.
(setf sbemacs::*script-directory* (truename (merge-pathnames "lisp/" *root*)))
;; *RELEASE-BUILD*: a script that does not compile cleanly is an error
;; (lisp/loader.lisp), reported below, and the executable is not saved
(setf sbemacs::*release-build* t)
(multiple-value-bind (loaded errors)
    (sbemacs::load-scripts :files (sbemacs::script-files sbemacs::*script-directory*)
                           :cache-directory (merge-pathnames "build/scripts/" *root*))
  (format t "~&Compiled ~D scripts into the image~%" (length loaded))
  (when errors
    (error "Scripts failed to load:~%~{  ~A~%~}" errors)))
(setf sbemacs::*script-directory* nil
      sbemacs::*release-build* nil)

(when *window-app*
  (setf sbemacs::*gui-by-default* t))

(sb-ext:save-lisp-and-die
 (merge-pathnames #+win32 "sbemacs.exe" #-win32 "sbemacs" *root*)
 :executable t
 #+win32 :application-type #+win32 (if *window-app* :gui :console)
 :save-runtime-options t
 :toplevel #'sbemacs:main)
