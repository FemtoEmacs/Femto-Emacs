;;;; kill-ring.lisp -- C-c k and C-c i
;;;;
;;;; Port of samples/killring.scm (Hugh Barney, September 2016).
;;;; Every kill is pushed onto *KILL-RING* by REMEMBER-KILL (see core.lisp).
;;;;
;;;; C-c k  shows a one-line summary of each kill; move with the arrow keys,
;;;;        c copies the selected kill to the clipboard (then C-y yanks it),
;;;;        x exits.
;;;; C-c i  inserts the whole kill ring into the current buffer.

(in-package #:sbemacs)

(defvar *kr-line* 1)
(defvar *kr-stop* nil)
(defparameter *kr-max-ops* 2000)

(defun summarize-kill (text)
  "First line of TEXT, at most 40 characters."
  (let* ((nl (position #\Newline text))
         (line (if nl (subseq text 0 nl) text)))
    (if (> (length line) 40) (subseq line 0 40) line)))

(defun kr-last-line () (max 1 (length *kill-ring*)))

(defun kr-move-line (n)
  (setf *kr-line* (max 1 (min (+ *kr-line* n) (kr-last-line)))))

(defun kr-show-options ()
  (message "kill item ~D : select (up), (down), (c=copy to clipboard), (x=exit)" *kr-line*)
  (update-display))

(defun kill-ring-menu ()
  (let ((original (get-buffer-name)))
    (setf *kr-stop* nil
          *kr-line* (min *kr-line* (kr-last-line)))
    (kill-buffer "*kill-ring*")
    (select-buffer "*kill-ring*")
    (if *kill-ring*
        (dolist (k *kill-ring*) (insert (summarize-kill k) (string #\Newline)))
        (insert "(the kill ring is empty)"))
    (goto-line *kr-line*)
    (delete-other-windows)
    (kr-show-options)
    (loop repeat *kr-max-ops*
          until *kr-stop*
          do (let ((key (get-key)))
               (cond ((string= key "")
                      (let ((binding (get-key-binding)))
                        (cond ((string= binding "previous-line") (kr-move-line -1))
                              ((string= binding "next-line") (kr-move-line 1))))
                      (goto-line *kr-line*)
                      (kr-show-options))
                     ((string= key "x")
                      (select-buffer original)
                      (delete-other-windows)
                      (setf *kr-stop* t))
                     ((string= key "c")
                      (when *kill-ring*
                        (set-clipboard (nth (1- *kr-line*) *kill-ring*)))
                      (message "item ~D copied to clipboard" *kr-line*)
                      (update-display)))))
    (update-display)))

(defun insert-kill-ring ()
  (dolist (k *kill-ring*)
    (insert k)
    (insert (format nil "~%#########################~%"))))
