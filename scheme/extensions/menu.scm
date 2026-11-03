;;;; menu.scm -- the mode line, with its buttons
;;;;
;;;; Port of SBEmacs's lisp/extensions/menu.lisp.  Someone who has never
;;;; used Emacs does not know that C-x C-s saves, so every mode line is also
;;;; a menu that the mouse can click:
;;;;
;;;;   teste.lisp, L. 1 [?][SAVE][UNDO][Select][MORE]            [QUIT]
;;;;
;;;; The file name is a button too: it shows what there is to know about the
;;;; file.  This file composes the whole mode line; the C core only paints
;;;; the pieces it gets and says which one was clicked.  A button is
;;;; (LABEL ACTION): ACTION a key ("C-x C-s") or a command (a symbol).  A
;;;; click does exactly what the key does (RUN-KEY-AS-TYPED, core.scm).
;;;;
;;;; To change the buttons, change *MODE-LINE-MENU* in ~/.chezemax/init.scm:
;;;;
;;;;   (set! *mode-line-menu* (append *mode-line-menu* '(("KILL" "C-x k"))))
;;;;
;;;; and (set! *mode-line-menu* '()) brings back the mode line with hints.
;;;; Colours: the faces 'menu and 'menu-pressed (theme.scm, set-color).

;;; ------------------------------------------------------------------
;;; The buttons
;;; ------------------------------------------------------------------

;; [TTFY], Chezemax's own: textify a PDF (extensions/ttfy.scm)
(define *mode-line-menu*
  '(("?" help-menu) ("SAVE" "C-x C-s") ("UNDO" "C-/")
    ("Select" menu-select) ("MORE" more-menu) ("TTFY" ttfy-menu) ("QUIT" "C-x C-c")))

;; buttons a narrow window keeps while it drops the others
(define *mode-line-kept-buttons* '("?" "MORE" "TTFY"))
(define *full-menu*
  '(("?" help-menu) ("SAVE" "C-x C-s") ("OPEN" "C-x C-f")
    ("UNDO" "C-/") ("Select" menu-select) ("COPY" menu-copy)
    ("DELETE" menu-delete) ("PASTE" "C-y") ("BUFS" "C-x b")
    ("WRAP" toggle-word-wrap) ("TTFY" ttfy-menu) ("QUIT" "C-x C-c")))
(define *menu-region* #f)
(define *menu-rendering* #f)    ; true while composing a mode line
(define *menu-filename* #f)     ; the file of the window being composed
(define *menu-full* #f)
(define *menu-popup-active* #f)
(define *help-pending-menu-action* #f)
(define *help-in-progress* #f)

(define (menu-region-p)
  (and (region-active-p) (mark) (not (= (mark) (point)))))

(defcommand (menu-select)
  (set-mark)
  (message "Move the cursor to select text; you can also drag with the mouse."))
(defcommand (menu-copy)
  (if (menu-region-p) (copy-region-command) (message "Select text first.")))
(defcommand (menu-delete)
  (if (menu-region-p)
      (begin (delete-region (mark) (point)) (deactivate-mark))
      (message "Select text first.")))

(define (mode-line-buttons buffer-name)
  "The default *MODE-LINE-BUTTONS-FUNCTION*: *MODE-LINE-MENU*, the same in
every window; with a selection, COPY and DELETE take Select's place."
  (let ((buttons (if *menu-full* *full-menu* *mode-line-menu*)))
    (if (and *menu-region* (not *menu-full*))
        (apply append (map (lambda (b) (if (equal? (car b) "Select")
                                           '(("COPY" menu-copy) ("DELETE" menu-delete))
                                           (list b)))
                           buttons))
        buttons)))

(define *mode-line-buttons-function* 'mode-line-buttons)

(defvar *buffer-menus* (table))   ; buffer name -> its windows' own buttons

(define (set-buffer-menu buffer-name buttons)
  "Give the windows of BUFFER-NAME their own BUTTONS; '() takes them away."
  (if (pair? buttons) (put! *buffer-menus* buffer-name buttons) (table-remove! *buffer-menus* buffer-name))
  buttons)

(defvar *button-usage* (table))

;;; ------------------------------------------------------------------
;;; Composing a mode line
;;; ------------------------------------------------------------------

;; The C core knows a button by a number; these are the actions behind the
;; numbers.  An action keeps its number for the whole session.
(defvar *mode-line-actions* (vector))

(define (action-id action)
  (let ((n (vector-length *mode-line-actions*)))
    (let loop ((i 0))
      (cond ((= i n)
             (set! *mode-line-actions* (vector-append *mode-line-actions* (vector action)))
             (+ n 1))
            ((equal? (vector-ref *mode-line-actions* i) action) (+ i 1))
            (else (loop (+ i 1)))))))

(define (piece-text text)
  "TEXT without the bytes that separate pieces (and line breaks)."
  (let loop ((s text) (bs '(10 13 30 31)))
    (if (null? bs) s (loop (substitute-byte s (car bs) 32) (cdr bs)))))

(define (shorten-left name width)
  "NAME in at most WIDTH characters: the end is kept, ... marks the cut."
  (let ((n (string-length name)))
    (cond ((<= n width) name)
          ((<= width 3) (substring name (- n width) n))
          (else (string-append "..." (substring name (- n (- width 3)) n))))))

(define (encode-pieces pieces)
  "PIECES as the C core reads them (src/display.c): face US id US text,
separated by RS."
  (string-join
   (map (lambda (p)
          (let ((text (car p)) (face (cadr p)) (action (caddr p)))
            (string-append (number->string (color-id face)) (string (integer->char 31))
                           (number->string (if action (action-id action) 0)) (string (integer->char 31))
                           (piece-text text))))
        pieces)
   (string (integer->char 30))))

(define *mode-line-name-maximum* 18)

(define (ai-menu-buffer-p name)
  "The assistants' windows: their own buttons, and no [?] (no help from help)."
  (or (member name '("*assistant*" "*ai-options*" "*discussion*"))
      (string-search "*codex" name) (string-search "*claude" name)))

(define (button-width b) (+ 2 (string-length (car b))))

(define (mode-line-pieces name fname bname line flags cols)
  "The mode line of a window (called by the C core at every redisplay):
NAME as shown, FNAME its file (\"\" if none), BNAME the buffer, LINE the
cursor's line, FLAGS 1 selected, 2 modified, 4 overwrite, 8 special; COLS
the width.  The encoded pieces, or #f for the C core's own mode line."
  (set! *menu-region* (and (= 1 (logand flags 1)) (> (fe-buffer-count) 0) (> (window-count) 0) (menu-region-p)))
  (set! *menu-rendering* #t)
  (set! *menu-filename* fname)
  (let* ((own (get *buffer-menus* bname #f))
         (hint (get *buffer-hints* bname #f))
         ;; help.scm: the help page has [CLOSE], not [?] (help from help)
         (buttons (cond ((equal? bname *help-buffer*) '(("CLOSE" help-close)))
                        (own (if (ai-menu-buffer-p bname) own
                                 (cons '("?" help-menu) (filter (lambda (b) (not (equal? (car b) "?"))) own))))
                        ((ai-menu-buffer-p bname) '(("CLOSE" close-assistant-windows)))
                        (hint '(("?" help-menu)))
                        (else ((command-procedure *mode-line-buttons-function*) bname)))))
    (set! *menu-region* #f)
    (set! *menu-rendering* #f)
    (and (pair? buttons)
         (let* ((quit (assoc "QUIT" buttons))
                (body (filter (lambda (b) (not (equal? (car b) "QUIT"))) buttons))
                (prefix (string-append (shorten-left name (min *mode-line-name-maximum* (max 1 (string-length name))))
                                       (if (= 2 (logand flags 2)) "*" "")
                                       (if (= 16 (logand flags 16)) "%%" "")
                                       (if (bound? 'vim-tag) (vim-tag bname) "")
                                       ", L. " (number->string line) " "))
                (reserve (if quit 9 0)))
           ;; keep the controls ahead of the file name when space is scarce
           (let loop ()
             (when (> (+ (string-length prefix) reserve (apply + (map button-width body))) cols)
               (cond ((> (string-length prefix) 1)
                      (set! prefix (substring prefix 1 (string-length prefix)))
                      (loop))
                     ((> (length body) 1)
                      (let ((victim (or (find (lambda (b) (not (member (car b) *mode-line-kept-buttons*))) (reverse body))
                                        (car (last-pair body)))))
                        (set! body (let rm ((l body)) (cond ((null? l) '()) ((eq? (car l) victim) (cdr l)) (else (cons (car l) (rm (cdr l)))))))
                        (loop))))))
           (let* ((pieces (append (list (list (string-trim-right prefix) 'menu 'file-info)
                                        (list " " 'modeline #f))
                                  (map (lambda (b) (list (string-append "[" (car b) "]") 'menu (cadr b))) body)))
                  (used (apply + (map (lambda (p) (string-length (car p))) pieces)))
                  (pieces (if hint
                              (let ((room (- cols used)))
                                (if (> room 1)
                                    (let ((h (string-append " " hint)))
                                      (append pieces (list (list (substring h 0 (min room (string-length h))) 'modeline #f))))
                                    pieces))
                              pieces))
                  (pieces (if quit
                              (append pieces (list (list (make-spaces (max 3 (- cols used 6))) 'modeline #f)
                                                   (list "[QUIT]" 'menu (cadr quit))))
                              pieces)))
             (encode-pieces pieces))))))

;;; ------------------------------------------------------------------
;;; Clicks
;;; ------------------------------------------------------------------

(define (run-mode-line-action action)
  (cond ((string? action)
         (unless (run-key-as-typed action) (message action " is not bound to anything")))
        ((command-procedure action)
         (command-boundary action)
         (set! *this-command* action)
         (dynamic-wind (lambda () #f)
                       (lambda () (call-command action))
                       (lambda () (note-command-use action) (set! *last-command* *this-command*))))
        (else (message (->string action) " is not a command"))))

(define (run-mode-line-button id)
  "The \"menu\" event: the button numbered ID was clicked."
  (let ((action (and id (<= 1 id) (<= id (vector-length *mode-line-actions*))
                     (vector-ref *mode-line-actions* (- id 1)))))
    (if (not action)
        (message "That button no longer exists")
        (let* ((entry (find (lambda (b) (equal? (cadr b) action)) *mode-line-menu*))
               (label (if entry (car entry) (->string action))))
          (put! *button-usage* label (+ 1 (get *button-usage* label 0)))
          (run-mode-line-action action)))))

;;; ------------------------------------------------------------------
;;; Windows: shown buffers, and calling something in another window
;;; ------------------------------------------------------------------

(define (buffer-shown-p name)
  "Is buffer NAME shown in some window?"
  (let loop ((k 0) (found #f))
    (if (< k (window-count))
        (let ((found (or found (string=? (get-buffer-name) name))))
          (other-window)
          (loop (+ k 1) found))
        found)))

;; Tool windows (the assistants', the shell's) are made by splitting the
;; window of the file they were called from, and closing them deletes them:
;; their rows go back to the window above, and the screen is as it was.
(define (select-window-showing name)
  "Select a window that shows buffer NAME: #t, or #f when none does."
  (let loop ((k 0))
    (cond ((string=? (get-buffer-name) name) #t)
          ((< k (window-count)) (other-window) (loop (+ k 1)))
          (else #f))))

(define (go-to-file-window name)
  "Select the window of buffer NAME, or show NAME in this window."
  (unless (select-window-showing name) (select-buffer name)))

(define (open-window-below buffer)
  "Show BUFFER in a new window below the selected one (half of its rows)
and select it.  A window too small to split becomes the only one first."
  (when (< (window-rows) 7) (delete-other-windows))
  (split-window)
  (other-window)
  (select-buffer buffer))

(defcommand (close-tool-window)
  "C-c q: close the window of the assistant, the shell or the help page
(as its [CLOSE] does) and go back to the file; the other windows are as
they were before it opened."
  (let ((here (get-buffer-name))
        (shell-shown (lambda () (or (buffer-shown-p "*shell-command*") (buffer-shown-p "*output*")))))
    (cond ((and (bound? 'shell-buffer-p) (shell-buffer-p here)) (shell-close))
          ((and (bound? 'help-page-p) (help-page-p)) (help-close))
          ((and (bound? 'assistant-close)
                (or (assistant-buffer-p here) (discussion-buffer-p here)))
           (assistant-close))
          ((and (bound? 'shown-assistant-buffer) (shown-assistant-buffer)) (close-assistant-windows))
          ((and (bound? 'shell-close) (shell-shown)) (shell-close))
          ((and (bound? 'close-discussion-window)
                (or (buffer-shown-p *claude-discussion-buffer*) (buffer-shown-p *codex-discussion-buffer*)))
           (close-discussion-window))
          (else (message "No assistant, shell or help window to close")))
    #t))

(global-set-key "C-c q" 'close-tool-window)

(define (call-in-window-of buffer f)
  "Call F with BUFFER current: in a window that shows it if there is one,
otherwise in this window for a moment.  Its value."
  (let* ((n (window-count))
         (steps (let loop ((steps 0))
                  (if (and (< steps n) (not (string=? (get-buffer-name) buffer)))
                      (begin (other-window) (loop (+ steps 1)))
                      steps))))
    (if (string=? (get-buffer-name) buffer)
        (dynamic-wind (lambda () #f) f
                      (lambda () (when (> steps 0) (do ((k 0 (+ k 1))) ((= k (- n steps))) (other-window)))))
        (let ((here (get-buffer-name)))
          (select-buffer buffer)
          (dynamic-wind (lambda () #f) f (lambda () (select-buffer here)))))))

;;; ------------------------------------------------------------------
;;; [MORE], help and the assistants' choices: a menu in a window of its own
;;; ------------------------------------------------------------------

(define *more-menu-buffer* "*more-actions*")
(define *more-menu-buttons* '())
(define *more-menu-choice* #f)
(define *more-menu-stop* #f)
(define *menu-title* "More actions")
(define *menu-number-keys* #f)
(define *menu-letter-keys* #f)
(define *more-menu-first-line* 4)

(define (more-menu-label label)
  (let ((e (assoc label '(("?" . "Help") ("IND" . "Indent region")
                          ("#" . "Comment / uncomment") ("DEF>" . "Next definition")
                          ("<DEF" . "Previous definition") ("AI" . "AI help")
                          ("BUFS" . "Buffers") ("TTFY" . "Textify PDF")
                          ("WRAP" . "Word wrap on/off (C-c w)")))))
    (cond (e (cdr e))
          ;; button labels (SAVE, BUFS) read better capitalized; other
          ;; labels ("Textify with ChatGPT") are kept as written
          ((string=? label (string-upcase label)) (string-capitalize label))
          (else label))))

(define (more-menu-text buttons)
    (string-append
     *menu-title* "\n"
     (if *menu-letter-keys*
         "h/q/d, arrows + Enter, or click an option then [RUN]. C-g closes."
         "Arrows + Enter, or click an option then [RUN]. q or C-c q closes.")
     "\n\n"
     (let loop ((bs buttons) (i 1) (acc ""))
       (if (null? bs) acc
           (let* ((label (caar bs)) (action (cadar bs))
                  (text (string-append (pad-left (number->string i) 2) "  "
                                       (if *menu-letter-keys* label (more-menu-label label))))
                  (key (if (or *menu-number-keys* *menu-letter-keys*) ""
                           (if (string? action) action (->string action)))))
             (loop (cdr bs) (+ i 1)
                   (string-append acc (string-trim-right (string-append (pad-right text 24) key)) "\n")))))))

(defcommand (more-menu-run)
  "Choose the current row of the menu window."
  (when (string=? (get-buffer-name) *more-menu-buffer*)
    (let ((index (- (line-number) *more-menu-first-line*)))
      (when (and (<= 0 index) (< index (length *more-menu-buttons*)))
        (set! *more-menu-choice* (cadr (list-ref *more-menu-buttons* index)))
        (set! *more-menu-stop* #t)))))

(defcommand (more-menu-close) "Dismiss the menu window." (set! *more-menu-stop* #t))

(define (choose-menu buttons)
  "Show BUTTONS in a window of their own and let the user choose one, by
arrows and Enter, a click, or a number or letter key.  The chosen action,
or #f."
  (if (null? buttons) #f
      (let* ((origin (get-buffer-name))
             (saved-point (point)) (saved-mark (mark)) (saved-active (region-active-p))
             (before (window-count)) (created #f)
             (saved-buttons *more-menu-buttons*) (saved-popup *menu-popup-active*))
        (set! *more-menu-buttons* buttons)
        (set! *menu-popup-active* #t)
        (set! *more-menu-choice* #f)
        (set! *more-menu-stop* #f)
        (dynamic-wind
         (lambda () #f)
         (lambda ()
           (split-window)
           (set! created (> (window-count) before))
           (when created (other-window))
           (select-buffer *more-menu-buffer*)
           (erase-buffer)
           (insert (more-menu-text *more-menu-buttons*))
           (fe-set-modified 0)
           (set-buffer-menu *more-menu-buffer* '(("RUN" more-menu-run) ("CLOSE" more-menu-close)))
           (goto-line *more-menu-first-line*)
           (let loop ()
             (unless *more-menu-stop*
               (message *menu-title* ": "
                        (cond (*menu-letter-keys* "h/q/d; ")
                              (*menu-number-keys*
                               (string-append (string-join (map number->string (iota (length *more-menu-buttons*) 1)) "/") "; "))
                              (else ""))
                        "arrows + Enter; click then RUN; " (if *menu-letter-keys* "C-g" "q") " or C-c q closes")
               (update-display)
               (let* ((key (get-key))
                      (name (if (string=? key "") (get-key-name) ""))
                      (binding (if (string=? key "") (get-key-binding) ""))
                      (digit (and (= (length key) 1) (<= 49 (aref key 0)) (<= (aref key 0) 57) (- (aref key 0) 48))))
                 (cond
                   ((and *menu-letter-keys* (find (lambda (b) (equal? (cadr b) key)) *more-menu-buttons*))
                    (set! *more-menu-choice* key) (set! *more-menu-stop* #t))
                   ((or (member key '("q" "Q")) (member name '("C-g" "C-c q")))
                    (set! *more-menu-stop* #t))
                   ((string=? name "C-x C-c")
                    (set! *more-menu-choice* "C-x C-c") (set! *more-menu-stop* #t))
                   ((and *menu-number-keys* digit (<= digit (length *more-menu-buttons*)))
                    (set! *more-menu-choice* (cadr (list-ref *more-menu-buttons* (- digit 1))))
                    (set! *more-menu-stop* #t))
                   ((string=? binding "mouse") (fe-mouse-event))
                   (else
                    ;; a click in the source window must not send a menu key
                    ;; into that source buffer
                    (call-in-window-of *more-menu-buffer*
                      (lambda ()
                        (cond
                          ((or (member key '("\r" "\n")) (member name '("RET" "C-m" "C-j"))) (more-menu-run))
                          ((or (string=? binding "next-line") (string=? name "C-n"))
                           (goto-line (min (+ *more-menu-first-line* (- (length *more-menu-buttons*) 1))
                                           (+ 1 (line-number)))))
                          ((or (string=? binding "previous-line") (string=? name "C-p"))
                           (goto-line (max *more-menu-first-line* (- (line-number) 1))))))))))
               (loop))))
         (lambda ()
           (set-buffer-menu *more-menu-buffer* '())
           (when (buffer-shown-p *more-menu-buffer*)
             (call-in-window-of *more-menu-buffer*
                                (lambda () (if (and created (> (window-count) 1)) (delete-window) (select-buffer origin)))))
           (unless (string=? (get-buffer-name) origin) (select-buffer origin))
           (goto-char saved-point)
           (if saved-mark (set-mark saved-mark) (clear-mark))
           (unless saved-active (deactivate-mark))
           (set! *more-menu-buttons* saved-buttons)
           (set! *menu-popup-active* saved-popup)
           (clear-message-line)
           (update-display)))
        ;; the caller runs the action after the original buffer is back, so
        ;; that SAVE acts on the user's document and QUIT asks as usual
        *more-menu-choice*)))

(define (perform-menu-choice action)
  (when action
    (cond (*menu-popup-active* (set! *more-menu-choice* action) (set! *more-menu-stop* #t))
          (*help-in-progress* (set! *help-pending-menu-action* action))
          (else (run-mode-line-action action)))))

(define (choose-assistant-menu title)
  (let ((saved (list *more-menu-buffer* *menu-title* *menu-letter-keys*)))
    (set! *more-menu-buffer* "*ai-options*")
    (set! *menu-title* title)
    (set! *menu-letter-keys* #t)
    (let ((choice (dynamic-wind (lambda () #f)
                                (lambda () (choose-menu '(("h Hints" "h") ("q Question" "q") ("d Discussion" "d"))))
                                (lambda ()
                                  (set! *more-menu-buffer* (car saved))
                                  (set! *menu-title* (cadr saved))
                                  (set! *menu-letter-keys* (caddr saved))))))
      (or choice ""))))

(define (assistant-menu-key)
  "Read a key while keeping [?] clickable; defer its action until closing.
Two values: the key, and a button's action (or #f)."
  (set! *help-in-progress* #t)
  (set! *help-pending-menu-action* #f)
  (dynamic-wind
   (lambda () #f)
   (lambda ()
     (let loop ()
       (let ((key (get-key)))
         (if (string=? (get-key-binding) "mouse")
             (begin (fe-mouse-event)
                    (if *help-pending-menu-action* (values "" *help-pending-menu-action*) (loop)))
             (values key #f)))))
   (lambda () (set! *help-in-progress* #f))))

(defcommand (more-menu)
  "All the actions for this window, also those the mode line cannot show."
  (set! *menu-full* #t)
  (set! *menu-region* (menu-region-p))
  (let ((buttons (dynamic-wind (lambda () #f)
                               (lambda () ((command-procedure *mode-line-buttons-function*) (get-buffer-name)))
                               (lambda () (set! *menu-full* #f) (set! *menu-region* #f)))))
    (perform-menu-choice (choose-menu buttons))))

(defcommand (menu-chatgpt)
  (call-in-window-of (if (assistant-buffer-p (get-buffer-name)) (file-behind-assistant) (get-buffer-name))
                     ask-codex))
(defcommand (menu-claude)
  (call-in-window-of (if (assistant-buffer-p (get-buffer-name)) (file-behind-assistant) (get-buffer-name))
                     ask-claude))
(defcommand (menu-keybindings) (unless *help-in-progress* (help)))

(defcommand (help-menu)
  "[?]: Keybindings (C-c h), ChatGPT (C-c g) or Claude (C-c r).
C-c q, q or C-g closes it."
  (if (and *menu-popup-active* (string=? (get-buffer-name) "*help-options*"))
      (message "Choose 1 Keybindings, 2 ChatGPT, or 3 Claude.")
      (let ((saved (list *more-menu-buffer* *menu-title* *menu-number-keys*)))
        (set! *more-menu-buffer* "*help-options*")
        (set! *menu-title* "Help")
        (set! *menu-number-keys* #t)
        (let ((choice (dynamic-wind (lambda () #f)
                                    (lambda () (choose-menu '(("Keybindings" menu-keybindings)
                                                              ("ChatGPT" menu-chatgpt) ("Claude" menu-claude))))
                                    (lambda ()
                                      (set! *more-menu-buffer* (car saved))
                                      (set! *menu-title* (cadr saved))
                                      (set! *menu-number-keys* (caddr saved))))))
          (perform-menu-choice choice)))))

;;; ------------------------------------------------------------------
;;; The file name: what there is to know about the file
;;; ------------------------------------------------------------------

(define (count-lines-words text)
  "Two values: the lines and the words of TEXT."
  (let ((n (length text)))
    (let loop ((i 0) (lines 0) (words 0) (in-word #f))
      (if (>= i n)
          (values (if (and (> n 0) (not (= (aref text (- n 1)) 10))) (+ lines 1) lines) words)
          (let* ((b (aref text i))
                 (space (memv b '(32 9 10 13 12))))
            (loop (+ i 1) (if (= b 10) (+ lines 1) lines)
                  (if (or space in-word) words (+ words 1))
                  (not space)))))))

(define (file-info-text)
  (let* ((file (buffer-filename))
         (text (buffer-substring 0 (buffer-size)))
         (path (and file (absolute-path file)))
         (on-disk (and path (file-attributes path))))
    (let-values (((lines words) (count-lines-words text)))
      (string-append
       (if file (concat "File:       " path "\n")
           (concat "Buffer:     " (get-buffer-name) " (not saved in a file)\n"))
       (concat "Lines:      " lines "\nWords:      " words "\nCharacters: " (string-length text)
               "\nBytes:      " (buffer-size) "\n")
       (concat "Cursor:     line " (line-number) "\n")
       (let ((lang (and file (language-for-file file))))
         (if (and lang (not (eq? lang *default-language*))) (concat "Language:   " (language-name lang) "\n") ""))
       (if (buffer-modified-p) "\nChanged since it was last saved: [SAVE] saves it.\n" "\nEverything is saved.\n")
       (cond (on-disk (concat "On disk:    " (cadr on-disk) " bytes, saved " (format-time (caddr on-disk)) "\n"))
             (file "On disk:    not yet: [SAVE] creates it\n")
             (else ""))))))

(defcommand (file-info)
  "What there is to know about the file in this window (click its name)."
  (let ((file (or (buffer-filename) (get-buffer-name))))
    (show-in-assistant-window (concat "About " (file-name-nondirectory file)) (file-info-text))
    (set-buffer-hint *assistant-buffer* "any key closes this window")
    (message file "   (any key closes the window)")
    (update-display)
    ;; like the help page: the next key (or click) only closes it
    (let ((action #f))
      (dynamic-wind (lambda () #f)
                    (lambda () (let-values (((key chosen) (assistant-menu-key))) (set! action chosen)))
                    (lambda () (close-assistant-windows) (clear-message-line)))
      (when action (run-mode-line-action action))))
  #t)

;;; ------------------------------------------------------------------
;;; [AI]: what the assistants can do, and which key calls which
;;; ------------------------------------------------------------------

(define *ai-help-text*
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

C-c q (or [CLOSE]) closes this window; the other windows stay.")

(defcommand (ai-help)
  "What the assistants (Claude, Codex) can do and how to call them."
  (show-in-assistant-window "AI help" *ai-help-text*)
  (set-buffer-hint *assistant-buffer* "C-c r Claude; C-c g Codex; C-c q close")
  (message "C-c r: ask Claude;  C-c g: ask Codex (ChatGPT)")
  #t)
