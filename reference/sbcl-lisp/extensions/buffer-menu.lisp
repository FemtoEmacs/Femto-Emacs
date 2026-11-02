;;;; buffer-menu.lisp -- C-x C-b
;;;;
;;;; Port of samples/bufmenu.scm (Hugh Barney, September 2016).
;;;;
;;;; Lists the buffers; move with the arrow keys (or C-n / C-p), then
;;;;   1  switch to the buffer as a single window
;;;;   2  split the screen between that buffer and the original one
;;;;   s  save the buffer if modified
;;;;   k  kill the buffer
;;;;   x  exit the menu

(in-package #:sbemacs)

(defparameter *bufm-start-line* 3
  "Buffer names start on line 3, after the two header lines.")
(defparameter *bufm-max-ops* 400)

(defvar *bufm-line* 3)
(defvar *bufm-last-line* 3)
(defvar *bufm-stop* nil)
(defvar *bufm-obuf* "")
(defvar *bufm-buf* "")

(defun bufm-get-bufn ()
  "The buffer name on line *BUFM-LINE* of the *buffers* listing."
  (goto-line *bufm-line*)
  (let ((line (current-line-text)))
    (beginning-of-line)
    (trim (subseq line (min 11 (length line)) (min 27 (length line))))))

(defun bufm-buffer-names ()
  (let ((saved *bufm-line*))
    (prog1 (loop for *bufm-line* from *bufm-start-line* to *bufm-last-line*
                 collect (bufm-get-bufn))
      (setf *bufm-line* saved))))

(defun bufm-move-line (n)
  (setf *bufm-line* (max *bufm-start-line* (min (+ *bufm-line* n) *bufm-last-line*))))

(defun bufm-refresh-limits ()
  ;; *buffers* itself is not listed, hence the -2
  (setf *bufm-last-line* (+ *bufm-start-line* (get-buffer-count) -2)))

(defun bufm-handle-bound-key ()
  (let ((binding (get-key-binding)))
    (cond ((string= binding "previous-line") (bufm-move-line -1))
          ((string= binding "next-line") (bufm-move-line 1))))
  (setf *bufm-buf* (bufm-get-bufn)))

(defun bufm-handle-single-key (k)
  (let ((several (> (get-buffer-count) 1)))
    (cond ((string= k "x")
           (if (member *bufm-obuf* (bufm-buffer-names) :test #'string=)
               (select-buffer *bufm-obuf*)
               (select-buffer "*scratch*"))
           (setf *bufm-stop* t))
          ((and (string= k "1") several)
           (select-buffer *bufm-buf*)
           (delete-other-windows)
           (setf *bufm-stop* t))
          ((and (string= k "2") several)
           (select-buffer *bufm-buf*)
           (split-window)
           (select-buffer *bufm-obuf*)
           (other-window)
           (setf *bufm-stop* t))
          ((and (string= k "s") several)
           (save-buffer *bufm-buf*)
           (list-buffers)
           (goto-line *bufm-line*))
          ((and (string= k "k") several)
           (kill-buffer *bufm-buf*)
           (list-buffers)
           (bufm-refresh-limits)
           (bufm-move-line 0)
           (setf *bufm-buf* (bufm-get-bufn))))))

(defun buffer-menu ()
  (setf *bufm-obuf* (get-buffer-name))
  (list-buffers)
  (setf *bufm-line* *bufm-start-line*
        *bufm-stop* nil)
  (bufm-refresh-limits)
  (delete-other-windows)
  (setf *bufm-buf* (bufm-get-bufn))
  (loop repeat *bufm-max-ops*
        until *bufm-stop*
        do (message "buffer menu: 1,2,s,k,x")
           (update-display)
           (let ((key (get-key)))
             (if (string= key "")
                 (bufm-handle-bound-key)
                 (bufm-handle-single-key key))))
  (clear-message-line)
  (update-display))
