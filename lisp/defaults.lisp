;;;; defaults.lisp -- the user functions and key bindings from init.lsp
;;;;
;;;; In FemtoEmacs these lived in ~/init.lsp and had to be copied into the
;;;; home directory together with r5rs.scm.  Now they are compiled into the
;;;; editor; ~/.sbemacs/init.lisp is only needed for your own changes, and
;;;; anything it defines or binds overrides what is here.

(in-package #:sbemacs)

;;; ------------------------------------------------------------------
;;; Helpers
;;; ------------------------------------------------------------------

(defun current-line-text ()
  "The text of the line the cursor is on, without moving the cursor."
  (let ((here (point)))
    (beginning-of-line)
    (let ((start (point)))
      (end-of-line)
      (let* ((end (point))
             (bytes (make-array (max 0 (- end start)) :element-type '(unsigned-byte 8))))
        (loop for p from start below end
              for i from 0
              do (setf (aref bytes i) (logand #xff (%char-at p))))
        (goto-char here)
        (sb-ext:octets-to-string bytes :external-format '(:utf-8 :replacement #\?))))))

(defun read-string (string)
  "Read a Lisp object from STRING: (read-string \"(2016 8 31)\") => (2016 8 31)"
  (let ((*read-eval* nil))
    (read-from-string string)))

;;; ------------------------------------------------------------------
;;; Dates
;;; ------------------------------------------------------------------

(defun weekday (n)
  (case n
    (0 "Sunday") (1 "Monday") (2 "Tuesday") (3 "Wednesday")
    (4 "Thursday") (5 "Friday") (6 "Saturday") (t "unknown")))

(defun what-day (ymd)
  "(what-day '(2016 9 3)) => \"Saturday\"   (Zeller-style congruence)"
  (destructuring-bind (y m d) ymd
    (let* ((ax (floor (- 14 m) 12))
           (mm (+ m (* 12 ax) -2))
           (yy (- y ax)))
      (weekday (mod (+ yy
                       (floor (- (* 13 mm) 1) 5)
                       (floor yy 4)
                       (- (floor yy 100))
                       (floor yy 400)
                       d)
                    7)))))

;; C-c z : replace a region holding (y m d) with the name of that day
(defun insert-day ()
  (let ((region (cut-region)))
    (handler-case (insert (what-day (read-string region)))
      (error ()
        (insert region)
        (message "insert-day: the region must contain a date such as (2016 9 3)")))))

;;; ------------------------------------------------------------------
;;; HTML helpers
;;; ------------------------------------------------------------------

;; C-c a
(defun html-p ()
  (insert "<p> </p>")
  (backward-char 5))

;; C-c b
(defun html-h1 ()
  (beginning-of-line)
  (insert "<h1> </h1>")
  (beginning-of-line)
  (forward-char 4))

;; C-c c
(defun html-pp ()
  (end-of-line)
  (insert "<p>-" (get-clipboard) "-</p>"))

;;; ------------------------------------------------------------------
;;; Indentation and case
;;; ------------------------------------------------------------------

;; C-t
(defun indent-two () (insert "  "))

;; C-o
(defun deindent-two () (backward-delete-char 2))

(defun transform-region (function)
  (kill-region)
  (set-clipboard (funcall function (get-clipboard)))
  (yank)
  (clear-message-line))

;; C-x C-u
(defun upcase-region () (transform-region #'string-upcase))

;; C-x C-l
(defun downcase-region () (transform-region #'string-downcase))

;;; ------------------------------------------------------------------
;;; Key bindings
;;; ------------------------------------------------------------------

(global-set-key "C-x C-b" 'buffer-menu)
(global-set-key "C-x C-d" 'dired)
(global-set-key "C-x C-u" 'upcase-region)
(global-set-key "C-x C-l" 'downcase-region)
(global-set-key "C-x C-g" 'grep-command)
(global-set-key "C-x !"   'next-grep)

(global-set-key "C-c a" 'html-p)
(global-set-key "C-c b" 'html-h1)
(global-set-key "C-c c" 'html-pp)
(global-set-key "C-c i" 'insert-kill-ring)
(global-set-key "C-c k" 'kill-ring-menu)
(global-set-key "C-c z" 'insert-day)

(global-set-key "C-o" 'deindent-two)
(global-set-key "C-t" 'indent-two)
