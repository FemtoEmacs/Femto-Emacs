;;;; menu.lisp -- the mode line, with its buttons
;;;;
;;;; A script: edit and press C-x C-r, no rebuild.
;;;;
;;;; Someone who has never used Emacs does not know that C-x C-s saves.
;;;; So every mode line is also a menu that the mouse can click:
;;;;
;;;;   teste.lisp, L. 1 == SBEmacs: [?] [SAVE] [OPEN] ... [QUIT] =====
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
;;;;   (setf *mode-line-menu* (remove "AI" *mode-line-menu*
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
  '(("?" help-menu) ("SAVE" "C-x C-s") ("UNDO" "C-/")
    ("Select" menu-select) ("MORE" more-menu) ("QUIT" "C-x C-c")))
(defparameter *full-menu*
  '(("?" help-menu) ("SAVE" "C-x C-s") ("OPEN" "C-x C-f")
    ("UNDO" "C-/") ("Select" menu-select) ("COPY" menu-copy)
    ("DELETE" menu-delete) ("PASTE" "C-y") ("BUFS" "C-x b")
    ("QUIT" "C-x C-c")))
(defvar *menu-rendering* nil)
(defvar *menu-filename* nil)
(defvar *menu-region* nil)
(defvar *menu-full* nil)
(defvar *menu-popup-active* nil)
(defvar *help-pending-menu-action* nil)
(defvar *help-in-progress* nil)
(defun menu-region-p ()
  (and (region-active-p) (mark) (/= (mark) (point))))
(defcommand menu-select ()
  (set-mark)
  (message "Move the cursor to select text; you can also drag with the mouse."))
(defcommand menu-copy ()
  (if (menu-region-p) (copy-region-command) (message "Select text first.")))
(defcommand menu-delete ()
  (if (menu-region-p)
      (progn (delete-region (mark) (point)) (deactivate-mark))
      (message "Select text first.")))
(defcommand menu-indent ()
  (if (and (menu-region-p) (python-mode-file-p (buffer-filename)))
      (indent-region) (message "Select Python lines first.")))

(declaim (ftype (function (string) (values list &optional)) mode-line-buttons))
(defun mode-line-buttons (buffer-name)
  "The default *MODE-LINE-BUTTONS-FUNCTION*: *MODE-LINE-MENU*, the same in
every window."
  (declare (ignore buffer-name))
  (let ((buttons (if *menu-full* *full-menu* *mode-line-menu*)))
    (if (and *menu-region* (not *menu-full*))
        (loop for button in buttons append
          (if (equal (first button) "Select")
              '(("COPY" menu-copy) ("DELETE" menu-delete)) (list button)))
        buttons)))

(defvar *mode-line-buttons-function* 'mode-line-buttons
  "Function of a buffer name returning its window's buttons, as in
*MODE-LINE-MENU*.  Replace it to order the buttons by use, say.")

(defvar *buffer-menus* (make-hash-table :test 'equal)
  "Buffer name -> the buttons of its own windows, in place of the main
menu: the shell command window has [SEND - C-c s] [CLOSE - C-x 1].")

(declaim (ftype (function (string list) (values list &optional)) set-buffer-menu))
(defun set-buffer-menu (buffer-name buttons)
  "Give the windows of BUFFER-NAME their own BUTTONS, as in
*MODE-LINE-MENU*; NIL takes them away."
  (if buttons
      (setf (gethash buffer-name *buffer-menus*) buttons)
      (remhash buffer-name *buffer-menus*))
  buttons)

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

(defparameter *mode-line-name-maximum* 18
  "A file name longer than this is shown shortened at the front
\(\"...src/fib.lisp\"); a click on it shows the whole name.")

(defparameter *mode-line-name-minimum* 12
  "In a narrow window a file name is shortened further, down to this
width, before any button is left out.")

(declaim (ftype (function (string) t) ai-menu-buffer-p))
(defun ai-menu-buffer-p (name)
  (or (member name '("*assistant*" "*ai-options*") :test #'equal)
      (search "*codex" name) (search "*claude" name)))

(defun mode-line-pieces (name fname bname line flags cols)
  "The mode line of a window (called by the C core at every redisplay):
NAME as shown (file or buffer name), FNAME its file (\"\" if none), BNAME
the buffer, LINE the cursor's line, FLAGS 1 selected, 2 modified,
4 overwrite, 8 special buffer; COLS the width.  Returns the encoded pieces,
or NIL for the C core's own mode line."
  (let* ((*menu-rendering* t) (*menu-filename* fname)
         (*menu-region* (and (logtest flags 1) (plusp (window-count)) (menu-region-p)))
         (own (gethash bname *buffer-menus*))
         (hint (gethash bname *buffer-hints*))
         (buttons (cond (own (if (ai-menu-buffer-p bname) own
                                  (cons '("?" help-menu) (remove "?" own :key #'first :test #'equal))))
                        ((ai-menu-buffer-p bname) '(("CLOSE" close-assistant-windows)))
                        (hint '(("?" help-menu)))
                        (t (funcall *mode-line-buttons-function* bname))))
         (quit (find "QUIT" buttons :key #'first :test #'equal))
         (body (remove "QUIT" buttons :key #'first :test #'equal))
         (prefix (format nil "~A~:[~;*~], L. ~D "
                         (shorten-left name (min 18 (max 1 (length name))))
                         (logtest flags 2) line))
         (reserve (if quit 9 0)))
    (unless buttons (return-from mode-line-pieces nil))
    ;; Keep the controls ahead of the filename when space becomes scarce.
    (loop while (> (+ (length prefix) reserve
                         (loop for b in body sum (+ 2 (length (first b))))) cols)
          do (cond ((> (length prefix) 1)
                    (setf prefix (subseq prefix 1)))
                   ((> (length body) 1)
                    (let ((victim (or (find-if (lambda (b) (not (member (first b) '("?" "MORE") :test #'equal)))
                                              (reverse body)) (car (last body)))))
                      (setf body (remove victim body :test #'eq :count 1))))
                   (t (return))))
    (let* ((pieces (append (list (list (string-right-trim " " prefix) :menu 'file-info) (list " " :modeline nil))
                           (loop for (label action) in body
                                 collect (list (format nil "[~A]" label) :menu action))))
           (used (loop for p in pieces sum (length (first p)))))
      (when hint
        (let ((room (- cols used)))
          (when (> room 1)
            (setf pieces (append pieces (list (list (subseq (concatenate 'string " " hint) 0
                                                             (min room (1+ (length hint)))) :modeline nil)))))))
      (when quit
        (setf pieces (append pieces
                            (list (list (make-string (max 3 (- cols used 6)) :initial-element #\Space) :modeline nil)
                                  (list "[QUIT]" :menu (second quit))))))
      (encode-pieces pieces))))

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
;;; [MORE]: all actions for the current buffer, independent of line width
;;; ------------------------------------------------------------------

;; Mouse input is decoded by GET-KEY; dispatch it through the same existing
;; C handler as the main editor loop. It is not a named builtin command.
(sb-alien:define-alien-routine ("editor_mouse_event" %more-menu-mouse) sb-alien:void)

(defparameter *more-menu-buffer* "*more-actions*")
(defvar *more-menu-buttons* nil)
(defvar *more-menu-choice* nil)
(defvar *more-menu-stop* nil)
(defvar *menu-title* "More actions")
(defvar *menu-number-keys* nil)
(defvar *menu-letter-keys* nil)
(defparameter *more-menu-first-line* 4)

(declaim (ftype (function (string) string) more-menu-label)
         (ftype (function (list) string) more-menu-text))
(defun more-menu-label (label)
  (or (cdr (assoc label '(("?" . "Help") ("IND" . "Indent region")
                          ("#" . "Comment / uncomment") ("DEF>" . "Next definition")
                          ("<DEF" . "Previous definition") ("AI" . "AI help")
                          ("BUFS" . "Buffers")) :test #'equal))
      (if (member label '("ChatGPT" "Keybindings" "Claude") :test #'equal) label (string-capitalize label))))

(defun more-menu-text (buttons)
  (with-output-to-string (out)
    (format out "~A~%~A~%~%" *menu-title* (if *menu-letter-keys* "h/q/d, arrows + Enter, or click an option then [RUN]. C-g closes." "Arrows + Enter, or click an option then [RUN]. q closes."))
    (loop for (label action) in buttons for i from 1 do
      (format out "~2D  ~A~25T~A~%" i (if *menu-letter-keys* label (more-menu-label label))
              (if (or *menu-number-keys* *menu-letter-keys*) "" (if (stringp action) action (string-downcase (symbol-name action))))))))

(defcommand more-menu-run ()
  "Choose the current row of the More actions window."
  (when (string= (get-buffer-name) *more-menu-buffer*)
    (let ((index (- (line-number) *more-menu-first-line*)))
      (when (<= 0 index (1- (length *more-menu-buttons*)))
        (setf *more-menu-choice* (second (nth index *more-menu-buttons*))
              *more-menu-stop* t)))))

(defcommand more-menu-close ()
  "Dismiss the More actions window."
  (setf *more-menu-stop* t))

(defun choose-menu (buttons)
  "Show every current-buffer menu action, even those that do not fit."
  (let* ((origin (get-buffer-name))
         (*more-menu-buttons* (copy-tree buttons))
         (*menu-popup-active* t)
         (saved-point (point)) (saved-mark (mark)) (saved-active (region-active-p))
         (*more-menu-choice* nil) (*more-menu-stop* nil)
         (before (window-count)) (created nil))
    (when (null *more-menu-buttons*) (return-from choose-menu nil))
    (unwind-protect
        (progn
          (split-window)
          (setf created (> (window-count) before))
          (when created (other-window))
          (select-buffer *more-menu-buffer*)
          (goto-char 0) (delete-char (buffer-size))
          (insert (more-menu-text *more-menu-buttons*))
          (set-buffer-menu *more-menu-buffer* '(("RUN" more-menu-run) ("CLOSE" more-menu-close)))
          (goto-line *more-menu-first-line*)
          (loop until *more-menu-stop* do
            (message "~A: ~Aarrows + Enter; click then RUN; ~A closes" *menu-title* (cond (*menu-letter-keys* "h/q/d; ") (*menu-number-keys* "1/2/3; ") (t "")) (if *menu-letter-keys* "C-g" "q"))
            (update-display)
            (let* ((key (get-key)) (name (if (equal key "") (get-key-name) ""))
                   (binding (if (equal key "") (get-key-binding) "")))
              (cond
                ((and *menu-letter-keys* (find key *more-menu-buttons* :key #'second :test #'equal))
                 (setf *more-menu-choice* key *more-menu-stop* t))
                ((or (member key '("q" "Q") :test #'equal) (equal name "C-g"))
                 (setf *more-menu-stop* t))
                ((equal name "C-x C-c")
                 (setf *more-menu-choice* "C-x C-c" *more-menu-stop* t))
                ((and *menu-number-keys* (= (length key) 1)
                      (digit-char-p (char key 0))
                      (<= 1 (digit-char-p (char key 0)) (length *more-menu-buttons*)))
                 (setf *more-menu-choice* (second (nth (1- (digit-char-p (char key 0))) *more-menu-buttons*))
                       *more-menu-stop* t))
                ((equal binding "mouse") (%more-menu-mouse))
                (t
                 ;; A click in the source window must not redirect a menu
                 ;; selection or a navigation key into that source buffer.
                 (call-in-window-of *more-menu-buffer*
                   (lambda ()
                   (cond
                     ((or (member key (list (string #\Return) (string #\Newline)) :test #'equal)
                          (member name '("RET" "C-m" "C-j") :test #'equal)) (more-menu-run))
                     ((or (equal binding "next-line") (equal name "C-n"))
                      (goto-line (min (+ *more-menu-first-line* (1- (length *more-menu-buttons*))) (1+ (line-number)))))
                     ((or (equal binding "previous-line") (equal name "C-p"))
                      (goto-line (max *more-menu-first-line* (1- (line-number)))))))))))))
      (set-buffer-menu *more-menu-buffer* nil)
      (when (buffer-shown-p *more-menu-buffer*)
        (call-in-window-of *more-menu-buffer*
                          (lambda () (if (and created (> (window-count) 1)) (delete-window) (select-buffer origin)))))
      (unless (string= (get-buffer-name) origin) (select-buffer origin))
      (goto-char saved-point)
      (if saved-mark (set-mark saved-mark) (clear-mark))
      (unless saved-active (deactivate-mark))
      (clear-message-line)
      (update-display))
    ;; Execute after restoring the original buffer, so SAVE/IND/# act on
    ;; the user's document and QUIT invokes its normal save confirmation.
    *more-menu-choice*))

(defun perform-menu-choice (action)
  (when action
    (cond (*menu-popup-active* (setf *more-menu-choice* action *more-menu-stop* t))
          (*help-in-progress* (setf *help-pending-menu-action* action))
          (t (run-mode-line-action action)))))
(declaim (ftype (function (string) (values string &optional)) choose-assistant-menu))
(defun choose-assistant-menu (title)
  (let ((*more-menu-buffer* "*ai-options*") (*menu-title* title)
        (*menu-letter-keys* t))
    (or (choose-menu '(("h Hints" "h") ("q Question" "q") ("d Discussion" "d"))) "")))

(defun assistant-menu-key ()
  "Read a modal key while keeping [?] clickable; defer its action until closing."
  (let ((*help-in-progress* t) (*help-pending-menu-action* nil))
    (loop for key = (get-key) do
      (if (equal (get-key-binding) "mouse")
          (progn (%more-menu-mouse)
                 (when *help-pending-menu-action*
                   (return (values "" *help-pending-menu-action*))))
          (return (values key nil))))))

(defcommand more-menu ()
  (let* ((*menu-full* t) (*menu-region* (menu-region-p))
         (buttons (funcall *mode-line-buttons-function* (get-buffer-name))))
    (perform-menu-choice (choose-menu buttons))))
(defcommand menu-chatgpt ()
  (call-in-window-of (if (assistant-buffer-p (get-buffer-name)) (file-behind-assistant) (get-buffer-name)) #'ask-codex))
(defcommand menu-claude ()
  (call-in-window-of (if (assistant-buffer-p (get-buffer-name)) (file-behind-assistant) (get-buffer-name)) #'ask-claude))
(defcommand menu-keybindings () (unless *help-in-progress* (help)))
(defcommand help-menu ()
  (when (and *menu-popup-active* (string= (get-buffer-name) "*help-options*"))
    (return-from help-menu (message "Choose 1 Keybindings, 2 ChatGPT, or 3 Claude.")))
  (let ((*more-menu-buffer* "*help-options*") (*menu-title* "Help") (*menu-number-keys* t))
    (perform-menu-choice (choose-menu '(("Keybindings" menu-keybindings)
                                       ("ChatGPT" menu-chatgpt) ("Claude" menu-claude))))))

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

(defun file-info-date (universal-time)
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
                       (file-info-date (file-write-date on-disk))))
              (file
               (format out "On disk:    not yet: [SAVE] creates it~%")))))))

(defcommand file-info ()
  "What there is to know about the file in this window (click its name on
the mode line)."
  (let ((file (or (buffer-filename) (get-buffer-name))))
    (show-in-assistant-window (format nil "About ~A" (file-namestring file))
                              (file-info-text))
    (set-buffer-hint *assistant-buffer* "any key closes this window")
    (message "~A   (any key closes the window)" file)
    (update-display)
    ;; like the help page: the next key (or click) only closes it
    (let ((action nil))
      (unwind-protect (multiple-value-bind (key chosen) (assistant-menu-key)
                       (declare (ignore key)) (setf action chosen))
        (close-assistant-windows)
        (clear-message-line))
      (when action (run-mode-line-action action))))
  t)

;;; ------------------------------------------------------------------
;;; [AI]: what the assistants can do, and which key calls which
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
  "The page that [AI] shows.")

(defcommand ai-help ()
  "Show what the assistants (Claude, Codex) can do and how to call them."
  (show-in-assistant-window "AI help" *ai-help-text*)
  (set-buffer-hint *assistant-buffer* "C-c r Claude; C-c g Codex; C-x 1 close")
  (message "C-c r: ask Claude;  C-c g: ask Codex (ChatGPT)")
  t)
