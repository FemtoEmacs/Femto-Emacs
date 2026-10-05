;;;; grep.lisp -- C-x C-g and C-x !
;;;;
;;;; Port of the grep commands from init.lsp.  The original ran "grep -ni"
;;;; through the shell; this one searches in Lisp (case-insensitively), so
;;;; it behaves the same on Linux, macOS and Windows.
;;;;
;;;; C-x C-g  prompts for a string and a list of wildcards ("*.c *.h"),
;;;;          shows the matches in *grep* as file:line:text
;;;; C-x !    visits the next match

(in-package #:sbemacs)

(defvar *grep-search-string* "")
(defvar *grep-filespec* "*.c *.h *.lisp")
(defvar *grep-buffer* "*grep*")
(defvar *grep-results* #() "Vector of (file line text).")
(defvar *grep-index* -1)

(defun split-spaces (string)
  (loop with start = 0
        for pos = (position #\Space string :start start)
        for word = (subseq string start pos)
        when (plusp (length word)) collect word
        while pos do (setf start (1+ pos))))

(defun grep-files (filespec)
  (remove-duplicates
   (loop for pattern in (split-spaces filespec)
         append (remove-if #'directory-pathname-p
                           (ignore-errors (directory (merge-pathnames pattern)))))
   :test #'equal))

(defun grep-file (file needle)
  (ignore-errors
   (with-open-file (in file :external-format '(:utf-8 :replacement #\?))
     (loop for line = (read-line in nil)
           for n from 1
           while line
           when (search needle line :test #'char-equal)
             collect (list file n line)))))

(defun relative-name (file)
  (let ((here (native (truename *default-pathname-defaults*)))
        (name (native file)))
    (if (and (> (length name) (length here)) (string= here name :end2 (length here)))
        (subseq name (length here))
        name)))

(defun grep-command ()
  (setf *grep-search-string* (prompt "grep search for : " *grep-search-string*))
  (when (string= *grep-search-string* "")
    (return-from grep-command nil))
  (setf *grep-filespec* (prompt "search in files : " *grep-filespec*))
  (setf *grep-results*
        (coerce (loop for f in (grep-files *grep-filespec*)
                      append (grep-file f *grep-search-string*))
                'vector)
        *grep-index* -1)
  (kill-buffer *grep-buffer*)
  (select-buffer *grep-buffer*)
  (loop for (file n text) across *grep-results*
        do (insert (format nil "~A:~D:~A~%" (relative-name file) n text)))
  (beginning-of-buffer)
  (message "~D match~:*~[es~;~:;es~] for \"~A\" -- C-x ! visits the next one"
           (length *grep-results*) *grep-search-string*)
  (update-display))

(defun next-grep ()
  (if (zerop (length *grep-results*))
      (message "no grep results; use C-x C-g first")
      (progn
        (setf *grep-index* (mod (1+ *grep-index*) (length *grep-results*)))
        (destructuring-bind (file n text) (aref *grep-results* *grep-index*)
          (declare (ignore text))
          (find-file (relative-name file))
          (goto-line n)
          (message "match ~D of ~D" (1+ *grep-index*) (length *grep-results*))))))
