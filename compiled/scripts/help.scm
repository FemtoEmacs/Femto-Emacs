;;;; help.scm -- the keys, one page
;;;;
;;;; In Chez Scheme, compiled by Schemer: the port of scheme/extensions/
;;;; help.scm.
;;;;
;;;; C-c h, C-h or F1 shows this page ([?] on the mode line offers it,
;;;; ChatGPT and Claude: menu.scm).  The page is read-only (read-only.scm):
;;;; j k, the arrows, gg G, C-d C-u, / n and % move; i or [CLOSE]
;;;; returns to the page that asked for help, where the cursor was.  C-c r
;;;; and C-c g close it and ask Claude or ChatGPT (Codex) about that page.

(define *help-buffer* "*chezemax-help*")

;; The help page's mode line has [CLOSE] instead of [?] (menu.scm): help
;; from help would only reopen the page that is already shown.
(define *help-origin* #f)          ; (buffer-name . point) that asked for help

(define (help-page-p) (string=? (get-buffer-name) *help-buffer*))

(defcommand (help-close)
  "i or [CLOSE] on the help page: back to the page that asked for help."
  (let ((origin *help-origin*))
    (set! *help-origin* #f)
    (when (top-level-bound? '*vim-states*)
      (table-remove! (top-level-value '*vim-states*) *help-buffer*)
      (table-remove! (top-level-value '*vim-kinds*) *help-buffer*))
    (when (help-page-p)
      (select-buffer (if origin (car origin) "*scratch*")))
    (kill-buffer *help-buffer*)
    (when origin (goto-char (cdr origin)))
    (clear-message-line)
    #t))

(define *help-header*
  "PRESS i (OR CLICK [CLOSE]) TO CLOSE THIS PAGE and return to your file.
This page is read-only: j and k (or the arrows) move down and up, Ctrl-d
and Ctrl-u a page, gg and G to the top and the end, / searches (n: again).
Ctrl-c h shows this page.  Ctrl-c r (hold down the Ctrl key and press c;
release and press r) asks Claude for help, Ctrl-c g asks ChatGPT; you must
subscribe to them.")

(define *help-notation*
  "C-x means Ctrl-x.  M-x means Esc, then x (or Alt-x; Option-x on a Mac).")

;;; One key per line: (key description).  Keys in Emacs notation.
(define *help-sections*
  '(("Help and assistants"
     ("C-c h" "this page (also C-h and F1)")
     ("C-h" "this page (also F1)")
     ("C-x ?" "name the command for a key or clicked button")
     ("M-x" "run a command by name (TAB completes)")
     ("C-c r" "Claude: a menu for hints, a question or a discussion")
     ("C-c y" "insert the answer's code, or make the buffer it proposes")
     ("C-c t" "in the discussion: insert the snippet under the cursor")
     ("C-c q" "close the help menu or page, the assistant's or the shell's window")
     ("C-c g" "write a request for ChatGPT (Codex); C-c g again sends it")
     ("C-c f" "textify a PDF into Markdown, with ChatGPT or Claude")
     ("C-c p" "plot, or show, the table at the cursor (curves or data)"))
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
     ("C-\\" "redo what undo took back (also C-M-_ and M-_)")
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
     ("C-c w" "word wrap on or off for this file (also MORE > Word wrap)")
     ("C-c TAB" "hide the HTML tags (read-only view); again, show them")
     ("C-c l" "hide the LaTeX commands (read-only view); again, show them")
     ("M-;" "comment: add one, or (un)comment the region")
     ("C-q" "insert the next key as it is (C-q TAB: a tab)")
     ("INS" "overwrite mode on or off")
     ("C-x C-q" "read-only on or off: keys move, nothing edits (see below)"))
    ("Searching and replacing"
     ("C-s" "search forward (C-s again: next match)")
     ("C-r" "search backward")
     ("M-%" "replace, asking each time (also M-r)")
     ("C-x C-g" "grep: search files")
     ("C-x !" "next grep match"))
    ("Narrowing (only a part shown; Narrow on the mode line)"
     ("C-x n n" "narrow to the region")
     ("C-x n s" "narrow to the Org subtree point is in (.org files)")
     ("C-x n w" "widen: the whole text again"))
    ("Buffers and windows"
     ("C-x b" "switch to a buffer by name")
     ("C-x C-b" "buffer menu")
     ("C-x <right>" "next buffer (Ctrl-x, then the right arrow)")
     ("C-x <left>" "previous buffer (Ctrl-x, then the left arrow)")
     ("C-x k" "close a buffer")
     ("C-x 2" "split the window top and bottom")
     ("C-x 3" "split the window side by side")
     ("C-x o" "go to the other window (or click it)")
     ("C-x 0" "close this window")
     ("C-x 1" "close the other windows")
     ("C-x w" "make this window taller"))
    ("Keyboard macros"
     ("C-x (" "start recording keys")
     ("C-x )" "stop recording")
     ("C-x e" "replay them; then e replays again"))
    ("Scheme"
     ("C-x C-e" "evaluate the expression before the cursor")
     ("C-M-x" "evaluate the top-level form around the cursor")
     ("M-:" "evaluate an expression typed at the bottom")
     ("M-]" "evaluate the block and insert the value")
     ("M-!" "shell command window (TAB completes; Enter: more lines)")
     ("C-c m" "shell command in minibuffer (TAB completes; Enter runs)")
     ("C-c s" "in that window: run the command; its output follows it")
     ("C-c q" "close the shell window ([CLOSE]); back to the file")
     ("C-x C-r" "reload the Scheme scripts (no rebuild needed)"))))

;;; Read-only and vim-mode (read-only.scm): the keys, as in nvim's normal mode.
(define *help-vim*
  '(("Read-only and vim mode (M-x read-only or C-x C-q; M-x vim-mode)")
    ("h j k l" "left, down, up, right (the arrows too; space: right)")
    ("w b e" "next word, back a word, end of the word")
    ("0 ^ $" "start of the line, its first non-blank, its last character")
    ("gg G" "first line, last line (5G: line 5)")
    ("Enter + -" "next visual row, next visual row, previous visual row")
    ("C-d C-u" "a page down, a page up")
    ("/ ? n N" "search forward / back; next / previous match")
    ("%" "jump to the matching paren, bracket or brace")
    ("5j 3w ..." "a count first repeats a motion")
    ("yy" "yy copies a whole line; 3yy copies 3 lines")
    ("v" "select by moving; then y copies (both modes are copy-only)")
    ("i" "back to Emacs, from either mode (on this help page: close it)")
    ("vim-mode" "copy-only: v selects, yy and v-move-y copy; i returns to Emacs")
    ("" "delete, paste, undo, redo, replace and open-line keys are disabled")))

;;; Commands with no key of their own: type M-x and the name (TAB completes).
(define *help-commands*
  '(("M-x commands (M-x, then the name; TAB completes)")
    ("run-tester" "alias for chez-tester: current Lean buffer and a chosen text file")
    ("chez-tester" "run current Lean protocol on a chosen existing text file")
    ("toggle-word-wrap" "word wrap on or off for this file (also C-c w)")
    ("visual-line-mode" "the same, by its Emacs name")
    ("polytonic" "polytonic Greek in Beta Code (a)/ ἄ, *)/a Ἄ)")
    ("chinese-input" "Chinese in tonal pinyin (zhong1 then 1: 中; again: off)")
    ("korean-input" "Korean on the 2-set keyboard (gksrmf: 한글; again: off)")
    ("latex-export" "this .org or .md file to LaTeX, beside it (Org: C-c C-e l l)")
    ("term" "a shell (C-c C-c interrupts; C-c KEY is C-x KEY)")
    ("html-mode" "colour this file as HTML, whatever its name")
    ("latex-mode" "colour this file as LaTeX, whatever its name")
    ("fill-paragraph" "refill the paragraph or comment (also M-q)")
    ("indent-buffer" "indent the whole file")
    ("indent-region" "indent the region (also C-x TAB)")
    ("python-mode" "Python colours, indentation and menu")
    ("nim-mode" "Nim colours, indentation and menu")
    ("reload-mode" "reload the active modes from their files")
    ("script-installer" "install this buffer in ~/.chezemax/users/ (terminal/GUI)")
    ("dark-theme" "the dark palette (yellow cursor)")
    ("light-theme" "the light palette (blue cursor)")
    ("file-info" "lines, words, size and full name of this file")
    ("buffer-menu" "the list of buffers (also C-x C-b)")
    ("save-some-buffers" "save every modified file, asking (also C-x s)")
    ("undo-status" "how much undo history this buffer has")
    ("ai-help" "what Claude and ChatGPT (Codex) can do here")
    ("close-tool-window" "close the assistant, shell or help window (C-c q)")
    ("assistant-status" "how the assistant reaches Claude")
    ("codex-status" "how the assistant reaches ChatGPT (Codex)")
    ("describe-key" "what does a key do? (also C-x ?)")
    ("read-only" "keys move and copy as in nvim, nothing edits (C-x C-q)")
    ("vim-mode" "copy-only navigation and selection, implemented in C")
    ("plot-at-point" "plot, or show, the table at the cursor (also C-c p)")
    ("plot-save" "save the plot table at the cursor as a picture, no window")))

(define (help-documented-keys)
  (apply append (map (lambda (section) (map (lambda (e) (normalize-key (car e))) (cdr section)))
                     *help-sections*)))

(define (help-other-keys)
  "Bindings the sections do not mention (yours, say)."
  (let ((documented (help-documented-keys)) (acc '()))
    (hashtable-walk *keymap*
                    (lambda (key fn)
                      (unless (or (member key documented) (string-search "esc [" key))
                        (set! acc (cons (list (display-key key) (command-name fn)) acc)))))
    (sort (lambda (a b) (string<? (car a) (car b))) acc)))

(define (help-commands-text)
  "The M-x section: the names are longer than keys, so they get a wider column."
  (let* ((entries (filter (lambda (e) (command-procedure (string->symbol (car e))))
                          (cdr *help-commands*)))
         (width (apply max 11 (map (lambda (e) (string-length (car e))) entries))))
    (apply string-append "\n" (caar *help-commands*) "\n"
           (map (lambda (e) (string-append "  " (pad-right (car e) width) " " (cadr e) "\n"))
                entries))))

(define (help-vim-text)
  (let ((width (apply max 11 (map (lambda (e) (string-length (car e))) (cdr *help-vim*)))))
    (apply string-append "\n" (caar *help-vim*) "\n"
           (map (lambda (e) (string-append "  " (pad-right (car e) width) " " (cadr e) "\n"))
                (cdr *help-vim*)))))

(define (help-text)
  (let ((section (lambda (title entries)
                   (apply string-append "\n" title "\n"
                          (map (lambda (e)
                            (let ((command (key-command-name (car e))))
                              (string-append "  " (pad-right (car e) 11) " " (cadr e) "\n"
                                             (if (and command (not (equal? command (cadr e))))
                                                 (string-append "             Command: " command "\n") ""))))
                               entries)))))
    (string-append *help-header* "\n\n" *help-notation* "\n"
                   (apply string-append (map (lambda (s) (section (car s) (cdr s))) *help-sections*))
                   (help-commands-text)
                   (help-vim-text)
                   (let ((others (help-other-keys)))
                     (if (pair? others) (section "Other keys" others) "")))))

(define (help-scroll top delta lines rows)
  "The new first line when scrolling by DELTA."
  (max 1 (min (+ top delta) (max 1 (+ (- lines rows) 1)))))

(define (show-help-line line)
  (goto-line line)
  (beginning-of-line)
  (set-window-start (point)))

(defcommand (help)
  "The keys, on a read-only page of their own; i or [CLOSE] closes it."
  (if (help-page-p)
      (message "This is the help page: i or [CLOSE] closes it")
      (let ((origin (get-buffer-name)) (opoint (point)))
        (set! *help-origin* (cons origin opoint))
        (select-buffer *help-buffer*)
        (set-buffer-read-only! #f)
        (erase-buffer)
        (insert (help-text))
        (goto-char 0)
        (fe-set-modified 0)
        (enter-normal-mode 'read)
        (message "Help: j k, gg G, / move; press i or click [CLOSE] to return to " origin)
        #t)))

(set-buffer-hint *help-buffer* "i closes help | j k gg G / % move")

(global-set-key "C-h" 'help)
(global-set-key "C-c h" 'help)
(global-set-key "F1" 'help)
(global-set-key "C-x C-h" 'help)
