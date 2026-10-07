;;;; help.lisp -- C-h or F1: the keys, one page
;;;;
;;;; A script: edit the entries below and press C-x C-r; no rebuild.
;;;;
;;;; The page replaces the file in the selected window.  The arrows (or C-n
;;;; and C-p) scroll it; C-c r and C-c g ask Claude or ChatGPT (Codex); any
;;;; other key goes back to the file, closing the assistants' windows.

(in-package #:sbemacs)

(defvar *help-buffer* "*sbemacs-help*")

(defparameter *help-header*
  "Arrows or Ctrl-n and Ctrl-p to scroll down and up.
Ctrl-c r (hold down the Ctrl key and press c; release and press r) to ask
help from Claude.  Ctrl-c g to ask help from ChatGPT.  You must subscribe
to ask help from them.  Any other key, leave this page and return to the
file you are editing.")

(defparameter *help-notation*
  "C-x means Ctrl-x.  M-x means Esc, then x (or Alt-x; Option-x on a Mac).")

;;; One key per line: (key description).  Keys in Emacs notation.
(defparameter *help-sections*
  '(("Help and assistants"
     ("C-h" "this page (also F1)")
     ("C-x ?" "what does a key do?")
     ("M-x" "run a command by name (TAB completes)")
     ("C-c r" "Claude: a menu for hints, a question or a discussion")
     ("C-c y" "insert the code of the last answer; closes its window")
     ("C-c t" "in the discussion: insert the snippet under the cursor")
     ("C-c g" "write a request for ChatGPT (Codex); C-c g again sends it"))
    ("Files"
     ("C-x C-f" "open a file")
     ("C-x C-s" "save")
     ("C-x C-w" "save as")
     ("C-x s" "save every modified file, asking")
     ("C-x i" "insert a file at the cursor")
     ("C-x C-v" "open another file in place of this one")
     ("C-x d" "list a directory")
     ("C-x C-c" "quit"))
    ("Moving"
     ("C-f" "forward one character (also the right arrow)")
     ("C-b" "back one character (also the left arrow)")
     ("C-n" "next line (also the down arrow)")
     ("C-p" "previous line (also the up arrow)")
     ("M-f" "forward one word")
     ("M-b" "back one word")
     ("C-a" "beginning of the line")
     ("C-e" "end of the line")
     ("M-m" "first non-blank character of the line")
     ("M-a" "back to the start of the sentence")
     ("M-e" "forward to the end of the sentence")
     ("M-{" "back one paragraph")
     ("M-}" "forward one paragraph")
     ("C-v" "next screen")
     ("M-v" "previous screen")
     ("M-<" "beginning of the file")
     ("M->" "end of the file")
     ("M-g" "go to a line number")
     ("C-l" "put the cursor's line in the middle of the window")
     ("C-M-f" "forward over an expression (Lisp: an s-expression)")
     ("C-M-b" "back over an expression")
     ("C-M-u" "out to the enclosing parenthesis")
     ("C-M-d" "into the next parenthesis")
     ("C-M-a" "beginning of the definition (defun, function)")
     ("C-M-e" "end of the definition"))
    ("Selecting (the region is shaded)"
     ("C-SPC" "set the mark: the region runs from it to the cursor")
     ("mouse" "click to move the cursor or choose a window; drag to select")
     ("[SAVE] ..." "the buttons of the mode line do what their keys do")
     ("file name" "click it on the mode line: lines, words, size, full name")
     ("C-x h" "select the whole file")
     ("M-h" "select the paragraph")
     ("M-@" "select to the end of the word")
     ("C-M-SPC" "select to the end of the expression")
     ("C-x C-x" "swap the cursor and the mark")
     ("C-g" "unselect; cancel a command"))
    ("Killing (cutting) and yanking (pasting)"
     ("C-w" "kill the region")
     ("M-w" "copy the region")
     ("C-y" "yank the last kill")
     ("M-y" "right after C-y: replace it with the kill before")
     ("C-k" "kill to the end of the line (again: joins the kills)")
     ("M-d" "kill the next word")
     ("M-DEL" "kill the previous word")
     ("M-k" "kill to the end of the sentence")
     ("C-M-k" "kill the next expression")
     ("M-z" "kill up to and including a character")
     ("C-d" "delete the character under the cursor")
     ("DEL" "delete the character before the cursor (Backspace)")
     ("C-c i" "choose a kill to insert")
     ("C-c k" "browse the kill ring"))
    ("Changing text"
     ("C-/" "undo the last command; again: the one before (also C-x u, C-u)")
     ("C-M-_" "redo what undo took back (also M-_)")
     ("C-t" "swap the two characters at the cursor")
     ("M-t" "swap two words")
     ("C-x C-t" "swap this line with the one above")
     ("M-u" "upper-case the next word")
     ("M-l" "lower-case the next word")
     ("M-c" "capitalize the next word")
     ("C-x C-u" "upper-case the region")
     ("C-x C-l" "lower-case the region")
     ("C-o" "open a line after the cursor")
     ("C-j" "new line, indented")
     ("TAB" "indent the line (again: other levels, in Python)")
     ("C-x TAB" "indent the region (also C-M-\\)")
     ("C-x >" "insert two spaces")
     ("C-x <" "delete two characters back")
     ("M-^" "join this line to the previous one")
     ("M-\\" "delete the spaces around the cursor")
     ("M-SPC" "leave just one space")
     ("C-x C-o" "delete blank lines")
     ("M-q" "refill the paragraph or comment")
     ("M-;" "comment: add one, or (un)comment the region")
     ("C-q" "insert the next key as it is (C-q TAB: a tab)")
     ("INS" "overwrite mode on or off"))
    ("Searching and replacing"
     ("C-s" "search forward (C-s again: next match)")
     ("C-r" "search backward")
     ("M-%" "replace, asking each time (also M-r)")
     ("C-x C-g" "grep: search files")
     ("C-x !" "next grep match"))
    ("Buffers and windows"
     ("C-x b" "switch to a buffer by name")
     ("C-x C-b" "buffer menu")
     ("C-x n" "next buffer")
     ("C-x k" "close a buffer")
     ("C-x 2" "split the window")
     ("C-x o" "go to the other window (or click it)")
     ("C-x 0" "close this window")
     ("C-x 1" "close the other windows")
     ("C-x ^" "make this window taller"))
    ("Keyboard macros"
     ("C-x (" "start recording keys")
     ("C-x )" "stop recording")
     ("C-x e" "replay them; then e replays again"))
    ("Lisp"
     ("C-x C-e" "evaluate the expression before the cursor")
     ("C-M-x" "evaluate the top-level form around the cursor")
     ("M-:" "evaluate an expression typed at the bottom")
     ("M-]" "evaluate the block and insert the value")
     ("M-!" "run a shell command")
     ("C-x C-r" "reload the Lisp scripts (no rebuild needed)")))
  "The help page.  Bindings that are not listed here appear at the end
under \"Other keys\".")

(defun help-documented-keys ()
  (loop for (nil . entries) in *help-sections*
        nconc (loop for (key) in entries collect (normalize-key key))))

(defun help-other-keys ()
  "Lisp bindings the sections do not mention (yours, say)."
  (let ((documented (help-documented-keys)) (others '()))
    (maphash (lambda (key fn)
               (unless (or (member key documented :test #'string=)
                           (search "esc [" key))
                 (push (list (display-key key)
                             (if (symbolp fn) (string-downcase (symbol-name fn)) "a function"))
                       others)))
             *keymap*)
    (sort others #'string< :key #'first)))

(defun help-text ()
  (with-output-to-string (out)
    (format out "~A~%~%~A~%" *help-header* *help-notation*)
    (flet ((section (title entries)
             (format out "~%~A~%" title)
             (dolist (e entries)
               (format out "  ~11A ~A~%" (first e) (second e)))))
      (loop for (title . entries) in *help-sections*
            do (section title entries))
      (let ((others (help-other-keys)))
        (when others (section "Other keys" others))))))

;;; The page

(defun help-scroll (top delta lines rows)
  "The new first line when scrolling by DELTA."
  (max 1 (min (+ top delta) (max 1 (- lines rows -1)))))

(defun show-help-line (line)
  (goto-line line)
  (beginning-of-line)
  (set-window-start (point)))

(defcommand help ()
  "C-h or F1: the keys, on a page of their own."
  (let* ((origin (get-buffer-name))
         (from (if (assistant-buffer-p origin) (file-behind-assistant) origin))
         (opoint (point))
         (text (help-text))
         (lines (1+ (count #\Newline text)))
         (top 1)
         (action nil))
    (select-buffer *help-buffer*)
    (goto-char 0)
    (delete-char (buffer-size))
    (insert text)
    (show-help-line 1)
    (unwind-protect
         (loop
           (message "Help: arrows scroll; C-c r Claude, C-c g ChatGPT; any other key returns to ~A" from)
           (update-display)
           (let* ((k (get-key))
                  (name (if (string= k "") (get-key-name) k))
                  (rows (max 1 (window-rows))))
             (cond ((member name '("down" "C-n") :test #'string=)
                    (setf top (help-scroll top 1 lines rows)))
                   ((member name '("up" "C-p") :test #'string=)
                    (setf top (help-scroll top -1 lines rows)))
                   ((member name '("PgDn" "C-v") :test #'string=)
                    (setf top (help-scroll top (max 1 (- rows 2)) lines rows)))
                   ((member name '("PgUp" "esc v" "esc V") :test #'string=)
                    (setf top (help-scroll top (- (max 1 (- rows 2))) lines rows)))
                   ;; C-h b is the Emacs way to this page: stay
                   ((and (string= name "b") (= top 1)))
                   ((string= name "C-c r") (setf action 'ask-claude) (return))
                   ((string= name "C-c g") (setf action 'ask-codex) (return))
                   (t (return)))
             (show-help-line top)))
      ;; however we leave: the file again, the assistants' windows closed
      (select-buffer origin)
      (goto-char opoint)
      (close-assistant-windows)
      (when (string= (get-buffer-name) *help-buffer*)
        (select-buffer from))
      (kill-buffer *help-buffer*)
      (clear-message-line))
    (when (and action (fboundp action))
      (funcall action))
    t))

(set-buffer-hint *help-buffer* "arrows scroll; other keys: back")

(global-set-key "C-h" 'help)
(global-set-key "F1" 'help)
(global-set-key "C-x C-h" 'help)
