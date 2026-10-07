;;;; menu.lisp -- the buttons of the mode line
;;;;
;;;; A script: edit and press C-x C-r, no rebuild.
;;;;
;;;; Someone who has never used Emacs does not know that C-x C-s saves.
;;;; So every mode line ends in buttons that the mouse can click:
;;;;
;;;;   teste.lisp, L. 1 == SBEmacs: [HELP] [SAVE] [OPEN] [COPY] [PASTE] ...
;;;;
;;;; A click lights the button for a moment, then does exactly what its key
;;;; does (RUN-KEY-AS-TYPED in core.lisp): the same command, undone by the
;;;; same C-/.  The C core only draws the buttons and says which one was
;;;; clicked; what they are and what they do is this list.  The buttons
;;;; that do not fit a narrow window are left out, from the right.
;;;;
;;;; Each entry is (LABEL ACTION): ACTION is a key, as in global-set-key,
;;;; or a command (a symbol).  In ~/.sbemacs/init.lisp, for instance:
;;;;
;;;;   (setf *mode-line-menu* (append *mode-line-menu* '(("QUIT" "C-x C-c"))))
;;;;   (install-mode-line-menu)
;;;;
;;;; and (setf *mode-line-menu* nil) (install-mode-line-menu) brings back
;;;; the old mode line, with its hints.  Colours: the faces :menu and
;;;; :menu-pressed (theme.lisp, set-color).

(in-package #:sbemacs)

(declaim (optimize (safety 3) (debug 2)))

(defparameter *mode-line-menu*
  '(("HELP"    "C-h")
    ("SAVE"    "C-x C-s")
    ("OPEN"    "C-x C-f")
    ("COPY"    "M-w")
    ("PASTE"   "C-y")
    ("UNDO"    "C-/")
    ("AI HELP" ai-help)
    ("BUFFERS" "C-x b"))
  "The mode line's buttons: (LABEL ACTION), ACTION a key or a command.")

(declaim (ftype (function () (values (eql t) &optional)) install-mode-line-menu))
(defun install-mode-line-menu ()
  "Give *MODE-LINE-MENU*'s labels to the C core, which draws them."
  (set-mode-line-menu (mapcar #'first *mode-line-menu*)))

(declaim (ftype (function (integer) t) run-mode-line-menu))
(defun run-mode-line-menu (index)
  "The \"menu\" event: button INDEX was clicked."
  (let ((entry (nth index *mode-line-menu*)))
    (destructuring-bind (&optional label action) entry
      (cond ((null entry)
             (message "No such button (~D)" index))
            ((stringp action)
             (unless (run-key-as-typed action)
               (message "[~A]: ~A is not bound to anything" label action)))
            ((and (symbolp action) (fboundp action))
             (command-boundary action)
             (setf *this-command* action)
             (unwind-protect (funcall action)
               (setf *last-command* *this-command*)))
            (t (message "[~A] does nothing: ~S is not a command" label action))))))

;;; [AI HELP]: what the assistants can do, and which key calls which

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

(defun install-mode-line-menu-at-startup ()
  (install-mode-line-menu))

;; the C core forgets the labels when the program ends: give them again at
;; every start (the script itself is compiled into the program), and now,
;; for C-x C-r
(pushnew 'install-mode-line-menu-at-startup *startup-hook*)
(install-mode-line-menu)
