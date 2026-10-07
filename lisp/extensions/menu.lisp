;;;; menu.lisp -- the mode line, with its buttons
;;;;
;;;; A script: edit and press C-x C-r, no rebuild.
;;;;
;;;; Someone who has never used Emacs does not know that C-x C-s saves.
;;;; So every mode line is also a menu that the mouse can click:
;;;;
;;;;   teste.lisp, L. 1 == SBEmacs: [HELP] [SAVE] [OPEN] ... [QUIT] =====
;;;;
;;;; The file name is a button too: it shows what there is to know about
;;;; the file (its full name, lines, words, size, when it was saved).
;;;;
;;;; This file composes the whole mode line; the C core only paints the
;;;; pieces it gets and says which one was clicked.  A piece is
;;;; (TEXT FACE ACTION): FACE a face of set-color (:modeline, :menu), ACTION
;;;; NIL, a key ("C-x C-s") or a command (a symbol).  A click lights the
;;;; piece while the mouse button is down and, on release, does exactly what
;;;; the key does (RUN-KEY-AS-TYPED, core.lisp): the same command, undone by
;;;; the same C-/.
;;;;
;;;; To change the buttons, change *MODE-LINE-MENU*, here or in
;;;; ~/.sbemacs/init.lisp:
;;;;
;;;;   (setf *mode-line-menu* (remove "AI HELP" *mode-line-menu*
;;;;                                  :key #'first :test #'string=))
;;;;   (setf *mode-line-menu* (append *mode-line-menu* '(("KILL" "C-x k"))))
;;;;
;;;; and (setf *mode-line-menu* nil) brings back the mode line with hints.
;;;; To choose the buttons otherwise -- by how often they are used, say
;;;; (*COMMAND-USAGE*, *BUTTON-USAGE*) -- set *MODE-LINE-BUTTONS-FUNCTION* to a
;;;; function of the window's buffer name that returns such a list.
;;;; Colours: the faces :menu and :menu-pressed (theme.lisp, set-color).

(in-package #:sbemacs)

(declaim (optimize (safety 3) (debug 2)))

;;; ------------------------------------------------------------------
;;; The buttons
;;; ------------------------------------------------------------------

(defparameter *mode-line-menu*
  '(("HELP"    "C-h")
    ("SAVE"    "C-x C-s")
    ("OPEN"    "C-x C-f")
    ("COPY"    "M-w")
    ("PASTE"   "C-y")
    ("UNDO"    "C-/")
    ("AI HELP" ai-help)
    ("BUFFERS" "C-x b")
    ("QUIT"    "C-x C-c"))
  "The mode line's buttons, left to right: (LABEL ACTION), ACTION a key or
a command.  The ones that do not fit a narrow window are left out from the
right, so the last ones should be the least needed.")

(declaim (ftype (function (string) (values list &optional)) mode-line-buttons))
(defun mode-line-buttons (buffer-name)
  "The default *MODE-LINE-BUTTONS-FUNCTION*: *MODE-LINE-MENU*, the same in
every window."
  (declare (ignore buffer-name))
  *mode-line-menu*)

(defvar *mode-line-buttons-function* 'mode-line-buttons
  "Function of a buffer name returning its window's buttons, as in
*MODE-LINE-MENU*.  Replace it to order the buttons by use, say.")

(defvar *button-usage* (make-hash-table :test 'equal)
  "Button label -> how many times it was clicked, this session.")

(defun usage-statistics (&optional (n 20))
  "The N most used commands and buttons of this session, most used first:
two lists of (NAME . COUNT)."
  (flet ((top (table)
           (let ((pairs '()))
             (maphash (lambda (k v) (push (cons k v) pairs)) table)
             (let ((sorted (sort pairs #'> :key #'cdr)))
               (subseq sorted 0 (min n (length sorted)))))))
    (values (top *command-usage*) (top *button-usage*))))

;;; ------------------------------------------------------------------
;;; Composing a mode line
;;; ------------------------------------------------------------------

;; The C core knows a button by a number; these are the actions behind the
;; numbers.  An action keeps its number for the whole session.
(defvar *mode-line-actions* (make-array 16 :adjustable t :fill-pointer 0))

(declaim (ftype (function (t) (values (integer 1) &optional)) action-id))
(defun action-id (action)
  (1+ (or (position action *mode-line-actions* :test #'equal)
          (vector-push-extend action *mode-line-actions*))))

(declaim (ftype (function (string) (values string &optional)) piece-text))
(defun piece-text (text)
  "TEXT without the characters that separate pieces (and line breaks)."
  (substitute-if #\Space (lambda (c) (member (char-code c) '(10 13 #x1E #x1F))) text))

(declaim (ftype (function (string (integer 1)) (values string &optional)) shorten-left))
(defun shorten-left (name width)
  "NAME in at most WIDTH characters: the end is kept, ... marks the cut
(three plain dots: every terminal shows them)."
  (cond ((<= (length name) width) name)
        ((<= width 3) (subseq name (- (length name) width)))
        (t (concatenate 'string "..." (subseq name (- (length name) (- width 3)))))))

(declaim (ftype (function (list) (values string &optional)) encode-pieces))
(defun encode-pieces (pieces)
  "PIECES as the C core reads them (src/display.c): face US id US text,
separated by RS."
  (with-output-to-string (out)
    (loop for (text face action) in pieces
          for first = t then nil
          do (unless first (write-char (code-char #x1E) out))
             (format out "~D~C~D~C~A"
                     (color-id face) (code-char #x1F)
                     (if action (action-id action) 0) (code-char #x1F)
                     (piece-text text)))))

(defparameter *mode-line-name-minimum* 12
  "A long file name is shortened, at the front, down to this width before
any button is left out.")

(defun mode-line-pieces (name fname bname line flags cols)
  "The mode line of a window (called by the C core at every redisplay):
NAME as shown (file or buffer name), FNAME its file (\"\" if none), BNAME
the buffer, LINE the cursor's line, FLAGS 1 selected, 2 modified,
4 overwrite, 8 special buffer; COLS the width.  Returns the encoded pieces,
or NIL for the C core's own mode line."
  (declare (ignore fname))
  (let* ((lch (if (logtest flags 1) "==" "--"))
         (marks (format nil "~:[~;*~]~:[~; [overwrite]~]"
                        (and (logtest flags 2) (not (logtest flags 8)))
                        (logtest flags 4)))
         (where (format nil "~A, L. ~D" marks line))
         (hint (gethash bname *buffer-hints*))
         (buttons (and (null hint) (funcall *mode-line-buttons-function* bname))))
    (cond
      ;; the assistants' windows: their own keys matter more than the menu
      (hint
       (encode-pieces (list (list "SBEmacs: " :modeline nil)
                            (list name :modeline nil)
                            (list (format nil "~A ~A ~A " where lch hint) :modeline nil))))
      ((null buttons) nil)
      (t
       (let* ((labels (mapcar (lambda (b) (format nil "[~A]" (first b))) buttons))
              (widths (mapcar #'length labels))
              (fixed (length where)))
         ;; the widest layout that fits: spaces between the buttons, the
         ;; word SBEmacs, the == after the line number, the whole name; then
         ;; without the spaces, without SBEmacs, without ==, with a shorter
         ;; name; and only then with fewer buttons
         (flet ((width (name-width brand marker spaced count)
                  (+ name-width fixed (if marker 3 0) (if brand 9 0) 1
                     (reduce #'+ (subseq widths 0 count))
                     (if spaced (max 0 (1- count)) 0))))
           (let ((count (length buttons)) (brand t) (marker t) (spaced t)
                 (name-width (length name)))
             (loop
               (let ((over (- (width name-width brand marker spaced count) cols)))
                 (cond ((<= over 0) (return))
                       (spaced (setf spaced nil))
                       (brand (setf brand nil))
                       (marker (setf marker nil))
                       ((> name-width *mode-line-name-minimum*)
                        (setf name-width (max *mode-line-name-minimum* (- name-width over))))
                       ((> count 0) (decf count))
                       (t (return)))))
             (encode-pieces
              (append
               (list (list (shorten-left name (max 1 name-width)) :menu 'file-info)
                     (list (concatenate 'string where
                                        (if marker (concatenate 'string " " lch) "")
                                        (if brand " SBEmacs:" "")
                                        " ")
                           :modeline nil))
               (loop for b in (subseq buttons 0 count)
                     for label in labels
                     for i from 0
                     when (and spaced (plusp i)) collect (list " " :modeline nil)
                     collect (list label :menu (second b))))))))))))

;;; ------------------------------------------------------------------
;;; Clicks
;;; ------------------------------------------------------------------

(declaim (ftype (function (t) t) run-mode-line-action))
(defun run-mode-line-action (action)
  (cond ((stringp action)
         (unless (run-key-as-typed action)
           (message "~A is not bound to anything" action)))
        ((and (symbolp action) (fboundp action))
         (command-boundary action)
         (setf *this-command* action)
         (unwind-protect (funcall action)
           (note-command-use action)
           (setf *last-command* *this-command*)))
        (t (message "~S is not a command" action))))

(defun run-mode-line-button (id)
  "The \"menu\" event: the button numbered ID was clicked."
  (let ((action (and (<= 1 id (length *mode-line-actions*))
                     (aref *mode-line-actions* (1- id)))))
    (if (null action)
        (message "That button no longer exists")
        (let ((entry (find action *mode-line-menu* :key #'second :test #'equal)))
          (incf (the fixnum (gethash (if entry (first entry) (princ-to-string action))
                                     *button-usage* 0)))
          (run-mode-line-action action)))))

;;; ------------------------------------------------------------------
;;; The file name: what there is to know about the file
;;; ------------------------------------------------------------------

(declaim (ftype (function (string) (values (integer 0) (integer 0) &optional)) count-lines-words))
(defun count-lines-words (text)
  (let ((lines 0) (words 0) (in-word nil))
    (declare (type (integer 0) lines words))
    (loop for c across text
          do (when (char= c #\Newline) (incf lines))
             (if (member c '(#\Space #\Tab #\Newline #\Return #\Page))
                 (setf in-word nil)
                 (unless in-word (setf in-word t) (incf words))))
    (when (and (plusp (length text)) (char/= (char text (1- (length text))) #\Newline))
      (incf lines))
    (values lines words)))

(defun format-date (universal-time)
  (multiple-value-bind (s mi h d mo y) (decode-universal-time universal-time)
    (declare (ignore s))
    (format nil "~D-~2,'0D-~2,'0D ~2,'0D:~2,'0D" y mo d h mi)))

(defun file-info-text ()
  (let* ((file (buffer-filename))
         (text (buffer-substring 0 (buffer-size)))
         (on-disk (and file (probe-file file))))
    (multiple-value-bind (lines words) (count-lines-words text)
      (with-output-to-string (out)
        (if file
            (format out "File:       ~A~%" (native (or on-disk (merge-pathnames file))))
            (format out "Buffer:     ~A (not saved in a file)~%" (get-buffer-name)))
        (format out "Lines:      ~:D~%Words:      ~:D~%Characters: ~:D~%Bytes:      ~:D~%"
                lines words (length text) (buffer-size))
        (format out "Cursor:     line ~:D~%" (line-number))
        (let ((lang (and file (language-for-file file))))
          (when lang (format out "Language:   ~A~%" (language-name lang))))
        (format out "~%~:[Everything is saved.~;Changed since it was last saved: [SAVE] saves it.~]~%"
                (buffer-modified-p))
        (cond (on-disk
               (format out "On disk:    ~:D bytes, saved ~A~%"
                       (with-open-file (s on-disk :element-type '(unsigned-byte 8))
                         (file-length s))
                       (format-date (file-write-date on-disk))))
              (file
               (format out "On disk:    not yet: [SAVE] creates it~%")))))))

(defcommand file-info ()
  "What there is to know about the file in this window (click its name on
the mode line)."
  (let ((file (or (buffer-filename) (get-buffer-name))))
    (show-in-assistant-window (format nil "About ~A" (file-namestring file))
                              (file-info-text))
    (set-buffer-hint *assistant-buffer* "C-x 1 close")
    (message "~A" file))
  t)

;;; ------------------------------------------------------------------
;;; [AI HELP]: what the assistants can do, and which key calls which
;;; ------------------------------------------------------------------

(defparameter *ai-help-text*
  "Two assistants can read the file you are editing and answer about it.
Choose one with its key (keep Ctrl down, press c, then press the letter):

   C-c r    Claude
   C-c g    Codex (ChatGPT)

Each one then offers, in this window:

   h   hints about the code around the cursor
   q   a question: write it in a window of its own, then C-c r (or C-c g)
       sends it, and C-c y puts the answer's code in your file
   d   a discussion that stays open; C-c t puts the code under the
       cursor in your file
   s   set-up: is the assistant installed and signed in?

C-x 1 closes this window."
  "The page that [AI HELP] shows.")

(defcommand ai-help ()
  "Show what the assistants (Claude, Codex) can do and how to call them."
  (show-in-assistant-window "AI help" *ai-help-text*)
  (set-buffer-hint *assistant-buffer* "C-c r Claude; C-c g Codex; C-x 1 close")
  (message "C-c r: ask Claude;  C-c g: ask Codex (ChatGPT)")
  t)
