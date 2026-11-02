;;;; modes.scm -- the editing modes active from the start
;;;;
;;;; In Chez Scheme, compiled by Schemer: the port of scheme/extensions/
;;;; zz-modes.scm.  The mode loader is load-mode.scm; the Python and Nim
;;;; modes are installed after highlighting, indentation, commands and menus
;;;; are available.

(for-each (lambda (name)
            (let ((installer (hashtable-ref *editing-modes* name #f)))
              (when installer
                (installer)
                (unless (member name *active-editing-modes*)
                  (set! *active-editing-modes* (cons name *active-editing-modes*))))))
          '("python" "nim"))
