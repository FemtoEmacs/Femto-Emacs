;;;; zz-modes.scm -- start-up entry point for the editing modes
;;;;
;;;; Port of SBEmacs's lisp/extensions/zz-modes.lisp.  Named to load after
;;;; the menu library.  The mode loader is modes/load-mode.scm; the Python
;;;; and Nim modes are installed after highlighting, indentation, commands
;;;; and menus are available.

(load-script (string-append *scheme-dir* "/modes/load-mode.scm"))
(load-script (string-append *scheme-dir* "/modes/python-mode.scm"))
(load-script (string-append *scheme-dir* "/modes/nim-mode.scm"))

(for-each (lambda (name)
            (let ((installer (get *editing-modes* name #f)))
              (when installer
                (installer)
                (unless (member name *active-editing-modes*)
                  (set! *active-editing-modes* (cons name *active-editing-modes*))))))
          '("python" "nim"))
