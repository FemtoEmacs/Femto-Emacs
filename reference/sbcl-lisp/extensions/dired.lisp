;;;; dired.lisp -- C-x C-d, a small directory editor
;;;;
;;;; samples/dired.scm only ran "ls -la $HOME" and left the rest "as a
;;;; challenge for the reader".  This version lists the directory with
;;;; Common Lisp's DIRECTORY, so it needs no ls and works on Windows too.
;;;;
;;;;   up/down   move           f or RET  open file / enter directory
;;;;   u         parent dir     g         re-read the directory
;;;;   x or q    exit

(in-package #:sbemacs)

(defvar *dired-directory* nil
  "The directory dired shows; starts at the current buffer's directory.")

(defparameter *dired-header-lines* 3)
(defparameter *dired-max-ops* 5000)

(defvar *dired-entries* #()
  "Pathnames shown, in line order (line = index + header lines + 1).")
(defvar *dired-index* 0)

(defun directory-pathname-p (p)
  (and (null (pathname-name p)) (null (pathname-type p))))

(defun entry-name (p)
  (if (directory-pathname-p p)
      (concatenate 'string (car (last (pathname-directory p))) "/")
      (file-namestring p)))

(defun file-size (p)
  (ignore-errors
   (with-open-file (s p :element-type '(unsigned-byte 8)) (file-length s))))

(defun format-date (universal-time)
  (if universal-time
      (multiple-value-bind (s mi h d mo y) (decode-universal-time universal-time)
        (declare (ignore s))
        (format nil "~4D-~2,'0D-~2,'0D ~2,'0D:~2,'0D" y mo d h mi))
      "                "))

(defun parent-directory (dir)
  (let ((d (pathname-directory dir)))
    (if (and (consp d) (rest d))
        (make-pathname :directory (butlast d) :name nil :type nil :defaults dir)
        dir)))

(defun list-directory (dir)
  (let ((entries (directory (merge-pathnames "*.*" dir) :resolve-symlinks nil)))
    (sort entries
          (lambda (a b)
            (let ((da (directory-pathname-p a)) (db (directory-pathname-p b)))
              (if (eq da db)
                  (string< (entry-name a) (entry-name b))
                  da))))))                ; directories first

(defun dired-line (p)
  (let ((dirp (directory-pathname-p p)))
    (format nil "  ~A ~10@A  ~A  ~A~%"
            (if dirp "d" " ")
            (if dirp "" (or (file-size p) "?"))
            (format-date (ignore-errors (file-write-date p)))
            (entry-name p))))

(defun dired-fill ()
  (kill-buffer "*dired*")
  (select-buffer "*dired*")
  (let* ((parent (parent-directory *dired-directory*))
         (has-parent (not (equal parent *dired-directory*))))
    (setf *dired-entries*
          (coerce (append (when has-parent (list parent))
                          (list-directory *dired-directory*))
                  'vector))
    (insert (format nil "  ~A~%  ~D entries~%~%"
                    (native *dired-directory*) (length *dired-entries*)))
    (loop for p across *dired-entries*
          for i from 0
          do (insert (if (and has-parent (zerop i))
                         (format nil "  d ~10@A  ~16A  ../~%" "" "")
                         (dired-line p)))))
  (setf *dired-index* (min *dired-index* (max 0 (1- (length *dired-entries*)))))
  (dired-goto))

(defun dired-goto ()
  (goto-line (+ *dired-index* *dired-header-lines* 1))
  (end-of-line))

(defun dired-move (n)
  (setf *dired-index* (max 0 (min (+ *dired-index* n) (1- (length *dired-entries*)))))
  (dired-goto))

(defun dired-open ()
  "Returns T when dired should exit (a file was opened)."
  (when (plusp (length *dired-entries*))
    (let ((p (aref *dired-entries* *dired-index*)))
      (cond ((directory-pathname-p p)
             (setf *dired-directory* p *dired-index* 0)
             (dired-fill)
             nil)
            (t
             (kill-buffer "*dired*")
             (find-file (native p))
             t)))))

(defun dired-start-directory ()
  (let ((file (buffer-filename)))
    (or (and file (ignore-errors
                   (make-pathname :name nil :type nil :version nil
                                  :defaults (merge-pathnames file))))
        *dired-directory*
        *default-pathname-defaults*)))

(defun dired (&optional directory)
  (let ((original (get-buffer-name)))
    (setf *dired-directory*
          (truename (if directory
                        (make-pathname :name nil :type nil :defaults
                                       (pathname (concatenate 'string (string-right-trim "/" directory) "/")))
                        (dired-start-directory)))
          *dired-index* 0)
    (delete-other-windows)
    (dired-fill)
    (loop repeat *dired-max-ops*
          do (message "dired: f/RET open, u up, g refresh, x exit")
             (update-display)
             (let ((key (get-key)))
               (cond ((string= key "")
                      (let ((b (get-key-binding)))
                        (cond ((string= b "previous-line") (dired-move -1))
                              ((string= b "next-line") (dired-move 1))
                              ((string= b "forward-page") (dired-move 10))
                              ((string= b "backward-page") (dired-move -10)))))
                     ((member key '("f" "o" #.(string #\Return) #.(string #\Newline)) :test #'string=)
                      (when (dired-open) (return)))
                     ((string= key "u")
                      (setf *dired-directory* (parent-directory *dired-directory*)
                            *dired-index* 0)
                      (dired-fill))
                     ((string= key "g") (dired-fill))
                     ((member key '("x" "q") :test #'string=)
                      (kill-buffer "*dired*")
                      (select-buffer original)
                      (return)))))
    (clear-message-line)
    (update-display)))
