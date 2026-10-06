;;;; undo.lisp -- undo and redo
;;;;
;;;; A script: edit and press C-x C-r, no rebuild.
;;;;
;;;; How it works, from first principles.  Every change to a text is one of
;;;; two acts:
;;;;
;;;;     insert the bytes S at position P      delete the bytes S at P
;;;;
;;;; and each is undone by the other.  The C core reports every such act
;;;; as it happens (src/undo.c, RECORD-CHANGE below), whatever caused it:
;;;; typing, C-k, C-y, M-q, query-replace, a script.  We keep them in order.
;;;;
;;;; What the user undoes, though, is not an act but a command: C-k is one
;;;; delete, M-q many.  So the acts are grouped by the key that caused them:
;;;; before each key the core calls UNDO-BOUNDARY, and the acts that follow
;;;; form one group.  Typing and deleting characters are the exception: up
;;;; to *UNDO-AMALGAMATE* typed characters in a row make one group, and so
;;;; do deletions with DEL or C-d, as in Emacs, so that undo brings back a
;;;; word rather than a letter.
;;;;
;;;; Two stacks of groups per buffer:
;;;;
;;;;   done     what was done, newest first.  C-/ pops a group, applies the
;;;;            inverse of its acts newest-first, and pushes it on
;;;;   undone   which C-M-_ (redo) pops, applying the acts again oldest
;;;;            first, and pushes back on DONE.
;;;;
;;;; Any new change empties UNDONE: a history is a line, not a tree.
;;;; While undoing or redoing, the core still reports the acts it performs;
;;;; *UNDOING* tells RECORD-CHANGE to ignore them.
;;;;
;;;; The buffer is unmodified exactly when the newest done group is the one
;;;; that was newest when the file was saved; so undoing back to the saved
;;;; text clears the * on the mode line.
;;;;
;;;;   C-/  C-_  C-x u  C-u     undo           C-M-_  M-_     redo

(in-package #:sbemacs)

(declaim (optimize (safety 3) (debug 2)))

(defvar *undo-limit* (* 8 1024 1024)
  "Bytes of history kept per buffer; the oldest groups go first.")
(declaim (type (integer 0) *undo-limit*))

(defvar *undo-amalgamate* 20
  "How many typed characters in a row undo together.")
(declaim (type (integer 1) *undo-amalgamate*))

(deftype octets () '(simple-array (unsigned-byte 8) (*)))

(defstruct (change (:constructor make-change (kind pos text)))
  (kind :insert :type (member :insert :delete))
  (pos 0 :type (integer 0))
  (text (make-array 0 :element-type '(unsigned-byte 8)) :type octets))

(defstruct (undo-group (:constructor make-undo-group (id point)))
  (id 0 :type (integer 0))
  (point 0 :type (integer 0))          ; the cursor before the command
  (changes '() :type list))            ; CHANGEs, newest first

(defstruct undo-history
  (done '() :type list)                ; UNDO-GROUPs, newest first
  (undone '() :type list)              ; what redo can bring back
  (bytes 0 :type (integer 0))
  (saved-id 0 :type (integer 0)))      ; newest group when last saved

(defvar *undo-histories* (make-hash-table)
  "Buffer id (never reused, see b_id in src/header.h) -> its UNDO-HISTORY.")

(defvar *undoing* nil "True while undo or redo changes the text.")

;; the command (key) now running
(defvar *command-serial* 1)
(defvar *command-point* 0)
(defvar *command-buffer-id* -1)
(defvar *self-insert-run* 0)
(defvar *last-boundary-kind* nil)

(defparameter *deleting-keys* '("backspace" "DEL" "C-d")
  "Keys whose runs undo together, like typed characters.")
(declaim (type (integer 0) *command-serial* *command-point* *self-insert-run*)
         (type integer *command-buffer-id*))

(declaim (ftype (function (&optional t) (values null &optional)) undo-boundary))
(defun undo-boundary (&optional key)
  "Called before every key (KEY: its name, or T for a typed character):
the changes that follow undo together.  Typed characters join the
previous typed ones, deletions the previous deletions, up to
*UNDO-AMALGAMATE*."
  (let ((kind (cond ((eq key t) :typing)
                    ((and (stringp key) (member key *deleting-keys* :test #'string=)) :deleting)
                    (t nil))))
    (unless (and kind (eq kind *last-boundary-kind*)
                 (< *self-insert-run* *undo-amalgamate*))
      (incf *command-serial*)
      (setf *self-insert-run* 0))
    (when kind (incf *self-insert-run*))
    (setf *last-boundary-kind* kind
          *command-point* (point)
          *command-buffer-id* (%buffer-id)))
  nil)

(declaim (ftype (function (integer) (values undo-history &optional)) history-of))
(defun history-of (id)
  (or (gethash id *undo-histories*)
      (setf (gethash id *undo-histories*) (make-undo-history))))

(declaim (ftype (function (undo-history) (values (integer 0) &optional)) top-id))
(defun top-id (history)
  (let ((g (first (undo-history-done history))))
    (if g (undo-group-id g) 0)))

(declaim (ftype (function (sb-sys:system-area-pointer (integer 0)) (values octets &optional))
                copy-octets))
(defun copy-octets (sap len)
  (let ((v (make-array len :element-type '(unsigned-byte 8))))
    (dotimes (i len v)
      (setf (aref v i) (sb-sys:sap-ref-8 sap i)))))

(declaim (ftype (function (octets octets) (values octets &optional)) join-octets))
(defun join-octets (a b)
  (let ((v (make-array (+ (length a) (length b)) :element-type '(unsigned-byte 8))))
    (replace v a)
    (replace v b :start1 (length a))
    v))

(declaim (ftype (function (undo-group change) (values t &optional)) merge-change))
(defun merge-change (group new)
  "Join NEW to the newest change of GROUP when they are one stretch of
typing or deleting; true if joined."
  (let ((old (first (undo-group-changes group))))
    (when (and old (eq (change-kind old) (change-kind new)))
      (let ((op (change-pos old)) (ot (change-text old))
            (np (change-pos new)) (nt (change-text new)))
        (cond ((and (eq (change-kind new) :insert) (= np (+ op (length ot))))
               (setf (change-text old) (join-octets ot nt)))
              ((and (eq (change-kind new) :delete) (= np op))          ; C-d, C-d
               (setf (change-text old) (join-octets ot nt)))
              ((and (eq (change-kind new) :delete) (= (+ np (length nt)) op)) ; DEL, DEL
               (setf (change-text old) (join-octets nt ot)
                     (change-pos old) np))
              (t nil))))))

(declaim (ftype (function (undo-history) (values null &optional)) trim-history))
(defun trim-history (history)
  "Forget the oldest groups while the history is over *UNDO-LIMIT*."
  (loop while (and (> (undo-history-bytes history) *undo-limit*)
                   (rest (undo-history-done history)))
        do (let* ((done (undo-history-done history))
                  (oldest (car (last done))))
             (setf (undo-history-done history) (butlast done))
             (decf (undo-history-bytes history)
                   (min (undo-history-bytes history)
                        (reduce #'+ (undo-group-changes oldest)
                                :key (lambda (c) (length (change-text c))))))))
  nil)

(declaim (ftype (function (integer character integer sb-sys:system-area-pointer integer)
                          (values null &optional))
                record-change))
(defun record-change (id kind pos text len)
  "The C core's report of a change (src/undo.c): KIND is #\\i (LEN bytes
TEXT inserted at POS), #\\d (deleted), #\\r (the text was replaced
wholesale: forget the history) or #\\s (saved)."
  (case kind
    (#\r (remhash id *undo-histories*))
    (#\s (let ((h (history-of id)))
           (setf (undo-history-saved-id h) (top-id h))))
    ((#\i #\d)
     (unless (or *undoing* (not *undo-mode*) (<= len 0))
       (let* ((h (history-of id))
              (change (make-change (if (char= kind #\i) :insert :delete)
                                   (max pos 0) (copy-octets text len)))
              (group (first (undo-history-done h))))
         (setf (undo-history-undone h) '())         ; a new change: no redo
         (unless (and group (= (undo-group-id group) *command-serial*))
           (setf group (make-undo-group *command-serial*
                                        (if (= id *command-buffer-id*) *command-point* (max pos 0))))
           (push group (undo-history-done h)))
         (unless (merge-change group change)
           (push change (undo-group-changes group)))
         (incf (undo-history-bytes h) len)
         (trim-history h)))))
  nil)

;;; Applying changes, without recording them

(declaim (ftype (function ((integer 0) octets) (values null &optional)) insert-octets))
(defun insert-octets (pos octets)
  (sb-sys:with-pinned-objects (octets)
    (%insert-bytes pos (sb-sys:vector-sap octets) (length octets)))
  nil)

(declaim (ftype (function (change) (values (integer 0) &optional)) revert-change apply-change))
(defun revert-change (c)
  "Undo C; the position where the cursor belongs afterwards."
  (let ((pos (change-pos c)) (text (change-text c)))
    (ecase (change-kind c)
      (:insert (%delete-region pos (+ pos (length text))))
      (:delete (insert-octets pos text)))
    pos))

(defun apply-change (c)
  "Do C again; the position after it."
  (let ((pos (change-pos c)) (text (change-text c)))
    (ecase (change-kind c)
      (:insert (insert-octets pos text) (+ pos (length text)))
      (:delete (%delete-region pos (+ pos (length text))) pos))))

(declaim (ftype (function (undo-history) (values null &optional)) update-modified))
(defun update-modified (history)
  (%set-modified (if (= (top-id history) (undo-history-saved-id history)) 0 1))
  nil)

(defun current-history ()
  (gethash (%buffer-id) *undo-histories*))

;;; The commands

(defcommand undo ()
  "C-/: undo the last command's changes; again: the one before."
  (let ((h (current-history)))
    (cond ((not *undo-mode*) (message "Undo is off (*undo-mode*)"))
          ((or (null h) (null (undo-history-done h)))
           (message "No further undo information"))
          (t
           (let ((group (pop (undo-history-done h))))
             (let ((*undoing* t))
               (dolist (c (undo-group-changes group))       ; newest first
                 (revert-change c)))
             (push group (undo-history-undone h))
             (goto-char (undo-group-point group))
             (update-modified h)
             (message "Undo~:[~; (no more)~]; C-M-_ redoes" (null (undo-history-done h))))))
    (setf *this-command* 'undo)
    t))

(defcommand redo ()
  "C-M-_ (or M-_): redo what undo took back."
  (let ((h (current-history)))
    (cond ((or (null h) (null (undo-history-undone h)))
           (message "Nothing to redo"))
          (t
           (let ((group (pop (undo-history-undone h)))
                 (end nil))
             (let ((*undoing* t))
               (dolist (c (reverse (undo-group-changes group)))   ; oldest first
                 (setf end (apply-change c))))
             (push group (undo-history-done h))
             (when end (goto-char end))
             (update-modified h)
             (message "Redo~:[~; (no more)~]" (null (undo-history-undone h))))))
    (setf *this-command* 'redo)
    t))

(defcommand undo-status ()
  "How much undo history this buffer has."
  (let ((h (current-history)))
    (if (null h)
        (message "No undo history for this buffer")
        (message "Undo: ~D step~:P back, ~D forward, ~:D bytes kept (limit ~:D)"
                 (length (undo-history-done h)) (length (undo-history-undone h))
                 (undo-history-bytes h) *undo-limit*))))

(global-set-key "C-_" 'undo)            ; C-/ in most terminals
(global-set-key "C-x u" 'undo)
(global-set-key "C-u" 'undo)            ; the old key, kept
(global-set-key "C-M-_" 'redo)          ; Emacs 28's undo-redo
(global-set-key "M-_" 'redo)
