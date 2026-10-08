;;;; Startup entry point only; mode loading lives in modes/load-mode.lisp.
;;;; Kept among extensions so it runs after the menu library without changing
;;;; the engine's script order. During builds the definitions enter the image.
(in-package #:sbemacs)
(defvar *editing-mode-directory* nil)
(let ((path (and *script-directory*
                 (probe-file (merge-pathnames "modes/load-mode.lisp" *script-directory*)))))
  (when path
    (setf *editing-mode-directory* (make-pathname :name nil :type nil :defaults path))
    (let ((*default-pathname-defaults* *editing-mode-directory*)) (load-script path))))

;; Python's standard mode is installed only after highlighting, indentation,
;; commands and menus are available. Keep the generic loader reusable.
(let ((installer (gethash "python" *editing-modes*)))
  (unless installer (error "The standard Python mode was not loaded"))
  (funcall installer)
  (pushnew "python" *active-editing-modes* :test #'equal))
