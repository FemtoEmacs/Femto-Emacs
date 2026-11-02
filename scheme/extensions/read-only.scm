;;;; read-only.scm -- read mode and vim mode, both on a read-only buffer
;;;;
;;;; Two modes, as in nvim's normal mode: letters are commands, not text.
;;;; The buffer is read-only underneath (the C core refuses every change),
;;;; so Emacs keys such as C-k or C-y cannot edit it either.
;;;;
;;;; M-x read-only (also M-x read-mode, M-x read-only-mode, C-x C-q): only
;;;; keys that change nothing.
;;;;   h j k l, arrows  move          w b e   word forward / back / end
;;;;   0 ^ $            line start, first non-blank, last character
;;;;   gg G             first line / end of the text; 42G line 42; Enter next line
;;;;   %                the matching paren, bracket or brace (d% y% too)
;;;;   C-d C-u          page down / up         /  ?  n  N   search
;;;;   yy y{motion}     copy lines / to where the motion goes (yw, y$)
;;;;   v                select by moving, then y copies (to the clipboard too)
;;;;   i                back to Emacs (editing)
;;;;
;;;; M-x vim-mode: all of the above, and the keys that edit, each one
;;;; undoable on its own:
;;;;   x                delete the character   dd d{motion}  delete lines / span
;;;;   p P              paste after / before (whole lines go below / above);
;;;;                    what another program copied since comes first.  C-y
;;;;                    (Cmd-V in the window) pastes at the cursor
;;;;   u  C-r           undo / redo            v ... d   delete the selection
;;;;   o O              open a line below / above, then edit
;;;;   .                repeat the last change (3. repeats it 3 times)
;;;;   J                join the next line to this one (3J: three lines)
;;;;   r{char}          replace the character (3rx: three of them)
;;;;   :w :wq :x :q     save, save and quit, quit; :42 goes to line 42
;;;;   a A I            back to Emacs: after the cursor, line end, line start
;;;;
;;;; A count first repeats: 3dd, 5j, 2yy.  C-g cancels a count, an operator
;;;; or the selection.  The same command again (or i) returns to Emacs.  The
;;;; mode line shows %% and READ, NORMAL or VISUAL.  Deleted and copied text
;;;; goes on the kill ring, so C-y in Emacs pastes it too.

(define *vim-states* (table))      ; buffer name -> normal | visual
(define *vim-kinds* (table))       ; buffer name -> read | vim
(define *vim-count* 0)             ; a count being typed (3 in 3dd)
(define *vim-pending* #f)          ; "d", "y", "g", "dg", "yg": waiting for a key
(define *vim-register* #f)         ; (text . linewise?) of the last d/y/x
(define *vim-search* #f)           ; (text . forward?) of the last / or ?

(define (vim-state) (get *vim-states* (get-buffer-name) #f))
(define (vim-active?) (and (vim-state) #t))

(define (vim-kind) (get *vim-kinds* (get-buffer-name) #f))
(define (vim-editing?) (eq? (vim-kind) 'vim))

(define (vim-tag buffer-name)
  "For the mode line: \" READ\", \" NORMAL\", \" VISUAL\" or \"\"."
  (let ((s (get *vim-states* buffer-name #f)))
    (cond ((eq? s 'visual) " VISUAL")
          ((not s) "")
          ((eq? (get *vim-kinds* buffer-name #f) 'vim) " NORMAL")
          (else " READ"))))

(define (vim-reset)
  (set! *vim-count* 0)
  (set! *vim-pending* #f))

(define (enter-normal-mode kind)
  (put! *vim-states* (get-buffer-name) 'normal)
  (put! *vim-kinds* (get-buffer-name) kind)
  (set-buffer-read-only! #t)
  (deactivate-mark)
  (vim-reset)
  (update-display)
  (message (if (eq? kind 'vim)
               "NORMAL (vim): hjkl move, dd yy p, v selects, u undoes, i edits; C-h lists all"
               "READ: hjkl, gg, G, / move; yy and v...y copy; i or C-x C-q edits; C-h lists all")))

(define (leave-normal-mode (why "Emacs mode: the buffer can be edited"))
  ;; the view without tags (tag-view.scm) is never edited: i, a, C-x C-q ...
  ;; go back to the file, at the same place, to edit it there
  (if (and (bound? 'tag-view-p) (tag-view-p))
      (tag-view-leave)
      (leave-normal-mode- why)))

(define (leave-normal-mode- why)
  (table-remove! *vim-states* (get-buffer-name))
  (table-remove! *vim-kinds* (get-buffer-name))
  (set-buffer-read-only! #f)
  (deactivate-mark)
  (vim-reset)
  (update-display)
  (message why))

(define (toggle-mode kind)
  "Enter mode KIND; in it already: back to Emacs; in the other one: switch."
  (cond ((and (bound? 'help-page-p) (help-page-p))
         (message "The help page stays read-only: i or [CLOSE] closes it"))
        ((and (bound? 'tag-view-p) (tag-view-p) (eq? kind 'vim))
         (message "This view is read-only: i returns to the file, to edit it"))
        ((not (vim-active?)) (enter-normal-mode kind))
        ((eq? (vim-kind) kind) (leave-normal-mode))
        (else (enter-normal-mode kind))))

(defcommand (read-only)
  "Read-only: the keys move, search and copy (hjkl, gg, G, /, yy, v...y),
as in nvim's normal mode, and nothing edits.  Again (or i): back to Emacs.
Also M-x read-mode, M-x read-only-mode, C-x C-q."
  (toggle-mode 'read))

(defcommand (read-mode) "Another name for read-only (C-x C-q)." (read-only))
(defcommand (read-only-mode) "Another name for read-only." (read-only))

(defcommand (vim-mode)
  "nvim's normal mode: read-only's keys, and dd, x, p, P, u, C-r, o, O,
v...d that edit.  Again (or i): back to Emacs."
  (toggle-mode 'vim))

(global-set-key "C-x C-q" 'read-only)

;;; ------------------------------------------------------------------
;;; Text around the cursor
;;; ------------------------------------------------------------------

(define (byte-at p) (if (and (>= p 0) (< p (buffer-size))) (fe-char-at p) -1))

(define (char-class b)
  "word, punct, space (newline included) or #f past the buffer's ends."
  (cond ((< b 0) #f)
        ((memv b '(32 9 10 13)) 'space)
        ((or (>= b 128) (= b 95)
             (and (>= b 48) (<= b 57)) (and (>= b 65) (<= b 90)) (and (>= b 97) (<= b 122)))
         'word)
        (else 'punct)))

(define (first-non-blank p)
  (let loop ((q (line-start p)))
    (if (memv (byte-at q) '(32 9)) (loop (+ q 1)) q)))

(define (last-char-of-line p)
  "Vim's $: on the last character, not after it (an empty line: its start)."
  (let ((s (line-start p)) (e (line-end p)))
    (if (> e s) (- e 1) s)))

(define (save-point thunk)
  (let ((p (point)))
    (dynamic-wind (lambda () #f) thunk (lambda () (goto-char p)))))

(define (line-of p) (line-number p))

(define (line-count)
  "Lines of text: a final newline does not start another line, as in vim."
  (let ((size (buffer-size)))
    (if (and (> size 0) (= (byte-at (- size 1)) 10))
        (line-number (- size 1))
        (line-number size))))

(define (point-of-line n)
  "Where line N starts (lines past the end: the last line)."
  (let loop ((p 0) (k 1))
    (if (>= k n) p
        (let ((e (line-end p)))
          (if (>= (+ e 1) (buffer-size)) p (loop (+ e 1) (+ k 1)))))))

;;; ------------------------------------------------------------------
;;; Motions: (target . linewise?)
;;; ------------------------------------------------------------------

(define (word-forward p)
  (let* ((size (buffer-size)) (c (char-class (byte-at p))))
    (let skip-same ((q p))
      (if (and (< q size) c (not (eq? c 'space)) (eq? (char-class (byte-at q)) c))
          (skip-same (+ q 1))
          (let skip-space ((r q))
            (if (and (< r size) (eq? (char-class (byte-at r)) 'space)) (skip-space (+ r 1)) r))))))

(define (word-backward p)
  (let skip-space ((q (- p 1)))
    (cond ((< q 0) 0)
          ((eq? (char-class (byte-at q)) 'space) (skip-space (- q 1)))
          (else
           (let ((c (char-class (byte-at q))))
             (let skip-same ((r q))
               (if (and (> r 0) (eq? (char-class (byte-at (- r 1))) c)) (skip-same (- r 1)) r)))))))

(define (word-end p)
  (let ((size (buffer-size)))
    (let skip-space ((q (+ p 1)))
      (if (and (< q size) (eq? (char-class (byte-at q)) 'space))
          (skip-space (+ q 1))
          (let ((c (char-class (byte-at q))))
            (let skip-same ((r q))
              (if (and (< (+ r 1) size) (eq? (char-class (byte-at (+ r 1))) c))
                  (skip-same (+ r 1))
                  (min r (max 0 (- size 1))))))))))

(define (vertical p n)
  "N lines down (up if negative), keeping the column where it fits."
  (let* ((col (- p (line-start p)))
         (target (max 1 (min (line-count) (+ (line-of p) n))))
         (s (point-of-line target)))
    (min (+ s col) (last-char-of-line s))))

(define (repeat f p n) (if (<= n 0) p (repeat f (f p) (- n 1))))

(define *bracket-pairs* '((40 . 41) (91 . 93) (123 . 125)))   ; () [] {}

(define (matching-bracket p)
  "Vim's %: the bracket matching the one under P; or, when P is not on a
bracket, the match of the first bracket after P on its line.  #f if none."
  (let* ((e (line-end p))
         (start (let find ((q p))
                  (cond ((>= q e) #f)
                        ((or (assv (byte-at q) *bracket-pairs*)
                             (find-tail (lambda (pr) (= (cdr pr) (byte-at q))) *bracket-pairs*))
                         q)
                        (else (find (+ q 1)))))))
    (and start
         (let* ((b (byte-at start))
                (open (assv b *bracket-pairs*))
                (pair (or open (find (lambda (pr) (= (cdr pr) b)) *bracket-pairs*)))
                (step (if open 1 -1))
                (size (buffer-size)))
           (let scan ((q (+ start step)) (depth 1))
             (if (or (< q 0) (>= q size)) #f
                 (let* ((c (byte-at q))
                        (depth (cond ((= c b) (+ depth 1))
                                     ((= c (if open (cdr pair) (car pair))) (- depth 1))
                                     (else depth))))
                   (if (= depth 0) q (scan (+ q step) depth)))))))))

(define (motion key p n)
  "(target . linewise?) for motion KEY repeated N times, or #f."
  (cond ((member key '("h" "left")) (cons (max (line-start p) (- p n)) #f))
        ((member key '("l" "right" " ")) (cons (min (last-char-of-line p) (+ p n)) #f))
        ((member key '("j" "down")) (cons (vertical p n) #t))
        ((member key '("k" "up")) (cons (vertical p (- n)) #t))
        ((member key '("\r" "\n" "+")) (cons (first-non-blank (vertical p n)) #t))
        ((string=? key "-") (cons (first-non-blank (vertical p (- n))) #t))
        ((string=? key "w") (cons (repeat word-forward p n) #f))
        ((string=? key "b") (cons (repeat word-backward p n) #f))
        ((string=? key "e") (cons (repeat word-end p n) #f))
        ((string=? key "0") (cons (line-start p) #f))
        ((string=? key "^") (cons (first-non-blank p) #f))
        ((string=? key "$") (cons (last-char-of-line (vertical p (- n 1))) #f))
        ;; G: the end of the text, its last character (as M-> does); 42G
        ;; goes to line 42
        ((string=? key "G") (cons (if (> *vim-count* 0) (first-non-blank (point-of-line n)) (buffer-size)) #t))
        ((string=? key "gg") (cons (first-non-blank (point-of-line (if (> *vim-count* 0) n 1))) #t))
        ((string=? key "%") (let ((m (matching-bracket p))) (and m (cons m #f))))
        (else #f)))

;; d{motion} stops before the target for these, and takes it for the rest
;; (de, d$): as in vim
(define *exclusive-motions* '("w" "b" "h" "left" "0" "^"))

;;; ------------------------------------------------------------------
;;; Changing the text: the only way past read-only
;;; ------------------------------------------------------------------

(define (vim-edit thunk)
  "Run THUNK with the buffer writable for a moment, as one undo step."
  (command-boundary "vim")
  (set! *vim-changed* #t)
  (set-buffer-read-only! #f)
  (dynamic-wind (lambda () #f) thunk
                (lambda () (when (vim-active?) (set-buffer-read-only! #t)))))

(define (remember text linewise)
  "TEXT copied or deleted: on the kill ring, what C-y and p paste, and on
the system clipboard, so Cmd-V (Ctrl-V) pastes it in other programs too."
  (set! *vim-register* (cons text linewise))
  (push-kill text)
  (if *use-system-clipboard* (set-clipboard text) (fe-set-scrap text)))

(define (span start end linewise)
  "START..END, widened to whole lines when LINEWISE."
  (if linewise
      (cons (line-start (min start end))
            (min (buffer-size) (+ 1 (line-end (max start end)))))
      (cons (min start end) (max start end))))

(define (vim-copy start end linewise)
  (let* ((r (span start end linewise))
         (text (buffer-substring (car r) (cdr r))))
    (remember (if (and linewise (not (string-suffix? "\n" text))) (string-append text "\n") text) linewise)
    r))

(define (vim-delete start end linewise)
  (let ((r (vim-copy start end linewise)))
    (vim-edit (lambda () (fe-delete-region (car r) (cdr r))))
    (goto-char (if linewise
                   (first-non-blank (min (car r) (max 0 (- (buffer-size) 1))))
                   (car r)))))

(define (vim-paste before n)
  ;; what another program copied since (Grammarly, a browser) comes first,
  ;; as for C-y; text copied here is already the newest kill
  (adopt-system-clipboard)
  (let* ((reg (if (and *vim-register* (pair? *kill-ring*) (string=? (car *vim-register*) (car *kill-ring*)))
                  *vim-register*
                  (cons (if (pair? *kill-ring*) (car *kill-ring*) (get-clipboard)) #f)))
         (text (apply string-append (map (lambda (i) (car reg)) (iota n))))
         (p (point)))
    (cond ((= (length text) 0) (message "Nothing to paste"))
          ((cdr reg)                                      ; whole lines
           (let ((at (if before (line-start p) (min (buffer-size) (+ 1 (line-end p))))))
             (vim-edit (lambda ()
                         (goto-char at)
                         (when (and (not before) (> at 0) (not (= (byte-at (- at 1)) 10)))
                           (insert "\n") (set! at (+ at 1)))
                         (insert text)))
             (goto-char (first-non-blank at))))
          (else
           (let ((at (if (or before (>= p (buffer-size)) (= (byte-at p) 10)) p (+ p 1))))
             (vim-edit (lambda () (goto-char at) (insert text)))
             (goto-char (max at (- (+ at (length text)) 1))))))))

(define (open-line-and-edit above)
  (vim-edit (lambda ()
              (if above
                  (begin (goto-char (line-start)) (insert "\n") (goto-char (- (point) 1)))
                  (begin (goto-char (line-end)) (insert "\n")))))
  (leave-normal-mode "Emacs mode: type the new line (C-x C-q: read mode again)"))

(define (vim-search forward)
  (let ((s (prompt (if forward "/" "?") "")))
    (when (> (length s) 0)
      (set! *vim-search* (cons s forward))
      (vim-search-again #f))))

(define (vim-search-again reverse)
  (if (not *vim-search*)
      (message "No previous search (/ searches)")
      (let* ((s (car *vim-search*))
             (forward (if reverse (not (cdr *vim-search*)) (cdr *vim-search*)))
             (p (point)))
        (if forward
            (begin (goto-char (min (buffer-size) (+ p 1)))
                   (if (search-forward s)
                       (goto-char (- (point) (length s)))
                       (begin (goto-char p) (message "Not found: " s))))
            (unless (search-backward s) (goto-char p) (message "Not found: " s))))))

;;; ------------------------------------------------------------------
;;; The keys
;;; ------------------------------------------------------------------

(define (vim-count-or-1) (if (> *vim-count* 0) *vim-count* 1))

(define (visual-bounds)
  "The selection as vim sees it: both ends included."
  (let ((m (or (mark) (point))) (p (point)))
    (cons (min m p) (min (buffer-size) (+ 1 (max m p))))))

(define (back-to-normal)
  (put! *vim-states* (get-buffer-name) 'normal)
  (deactivate-mark))

(define (vim-operator op key n visual)
  "The second key after d or y (OP): dd, yy, or a motion."
  (let ((m (motion key (point) n)))
    (cond ((string=? key op)                              ; dd, yy: N whole lines
           (let ((end (vertical (point) (- n 1))))
             (if (string=? op "d")
                 (vim-delete (point) end #t)
                 (begin (vim-copy (point) end #t) (message n (if (= n 1) " line" " lines") " copied")))))
          ((not m) (message op key " is not a normal-mode command here"))
          (else
           ;; an inclusive motion takes the character at both ends (de, d$,
           ;; d%), backwards too
           (let* ((p (point)) (target (car m))
                  (inclusive (not (or (cdr m) (member key *exclusive-motions*))))
                  (start (if (and inclusive (< target p)) (+ p 1) p))
                  (end (if (and inclusive (>= target p)) (+ target 1) target)))
             (if (string=? op "d")
                 (vim-delete start end (cdr m))
                 (begin (vim-copy start end (cdr m))
                        (when (< target p) (goto-char target))   ; as vim: y moves back
                        (message "Copied"))))))))

(define *editing-keys* '("x" "p" "P" "C-y" "u" "C-r" "o" "O" "a" "A" "I" "." "J" "r" ":"))

(define (refused-in-read-only? key)
  "In read-only (not vim-mode), the keys that would edit say so instead."
  (and (not (vim-editing?))
       (or (member key *editing-keys*)
           (and (string=? key "d") (not *vim-pending*)))
       (begin
         (vim-reset)
         (when (eq? (vim-state) 'visual) (fe-set-mark-active 1))
         (message (if (and (bound? 'help-page-p) (help-page-p))
                      "The help page is read-only: i or [CLOSE] closes it"
                      (concat "Read-only: " key " would edit; M-x vim-mode edits with dd, x, p, o; i returns to Emacs")))
         #t)))

(define (vim-key key)
  "Run normal-mode KEY (a character such as \"j\", or a key name such as
\"C-r\").  True when the key was taken."
  (if (and (not (and (= (length key) 1) (char-numeric? (string-ref key 0))))
           (refused-in-read-only? key))
      #t
      (vim-key-recorded key)))

;;; . repeats the last change: the keys of the last command that edited
;;; (3dd, dw, x, p, J, r a), or a thunk for v ... d.  Undo, redo and the
;;; keys that leave for Emacs (o, O, a ...) are not repeated.
(define *vim-keys* '())            ; keys of the command being typed
(define *vim-changed* #f)          ; did it edit?
(define *vim-last-change* #f)      ; keys (a list) or a thunk
(define *vim-replaying* #f)
(define *unrepeatable* '("u" "C-r" "o" "O" "."))

(define (vim-key-recorded key)
  (when (and (not *vim-pending*) (= *vim-count* 0))
    (set! *vim-keys* '())
    (set! *vim-changed* #f))
  (when (list? *vim-keys*) (set! *vim-keys* (append *vim-keys* (list key))))
  (let ((taken (vim-key-allowed key)))
    ;; (*vim-keys* is #f when v ... d has just recorded itself as a thunk)
    (when (and *vim-changed* (pair? *vim-keys*) (not *vim-pending*) (= *vim-count* 0)
               (not *vim-replaying*) (not (member key *unrepeatable*)))
      (set! *vim-last-change* *vim-keys*))
    taken))

(define (vim-repeat n)
  "Run the last change again; a count N (0: none) replaces its count."
  (let ((change *vim-last-change*))
    (cond ((not change) (message "Nothing to repeat yet"))
          ((procedure? change) (change (max 1 n)))
          (else
           (let ((keys (if (= n 0) change
                           (let strip ((k change))
                             (if (and (pair? k) (char-numeric? (string-ref (car k) 0)) (not (string=? (car k) "0")))
                                 (strip (cdr k)) k)))))
             (dynamic-wind
              (lambda () (set! *vim-replaying* #t))
              (lambda ()
                (vim-reset)
                (for-each vim-key-allowed
                          (append (if (> n 0) (map string (string->list (number->string n))) '()) keys)))
              (lambda () (set! *vim-replaying* #f))))))))

(define (vim-key-allowed key)
  (let ((visual (eq? (vim-state) 'visual))
        (n (vim-count-or-1)))
    (define (done) (set! *vim-count* 0) (when (eq? (vim-state) 'visual) (fe-set-mark-active 1)) #t)
    (cond
     ;; a count: 1-9, then any digit
     ((and (= (length key) 1) (char-numeric? (string-ref key 0))
           (or (> *vim-count* 0) (not (string=? key "0"))))
      (set! *vim-count* (+ (* *vim-count* 10) (string->number key)))
      (message (or *vim-pending* "") *vim-count*)
      #t)
     ((string=? key "C-g")
      (vim-reset)
      (when visual (back-to-normal))
      (message "NORMAL")
      #t)
     ;; the key after g, d, y (gg, dd, yy, dw, dgg ...)
     (*vim-pending*
      (let ((op *vim-pending*))
        (set! *vim-pending* #f)
        (cond ((string=? op "r") (vim-replace-char key n))
              ((member op '("dg" "yg"))
               (if (string=? key "g") (vim-operator (substring op 0 1) "gg" n #f) (message op key " is not a command here")))
              ((string=? op "g")
               (if (string=? key "g") (vim-move "gg" n) (message "g" key " is not a command here")))
              ((string=? key "g") (set! *vim-pending* (string-append op "g")))
              (else (vim-operator op key n visual))))
      (unless *vim-pending* (set! *vim-count* 0))
      (when (eq? (vim-state) 'visual) (fe-set-mark-active 1))
      #t)
     ((motion key (point) n) (vim-move key n) #t)
     ((string=? key "%") (message "%: no bracket here, or no match") (done))
     ((member key '("d" "y"))
      (if visual
          (let ((b (visual-bounds)))
            (if (string=? key "d")
                (let ((len (- (cdr b) (car b))))
                  (vim-delete (car b) (cdr b) #f)
                  (unless *vim-replaying*
                    (set! *vim-keys* #f)
                    (set! *vim-last-change*
                          (lambda (n) (let ((p (point))) (vim-delete p (min (buffer-size) (+ p len)) #f))))))
                (begin (vim-copy (car b) (cdr b) #f) (message "Copied to the clipboard")))
            (back-to-normal)
            (vim-reset))
          (begin (set! *vim-pending* key) (message (if (> *vim-count* 0) *vim-count* "") key)))
      #t)
     ((string=? key "g") (set! *vim-pending* "g") #t)
     ((string=? key "x")
      (if visual
          (vim-key "d")
          (let ((p (point)))
            (unless (or (>= p (buffer-size)) (= (byte-at p) 10))
              (vim-delete p (min (line-end p) (+ p n)) #f))
            (done))))
     ((string=? key "p") (vim-paste #f n) (done))
     ((string=? key "P") (vim-paste #t n) (done))
     ;; C-y, and Cmd-V in the window (which sends C-y): paste at the cursor
     ((string=? key "C-y") (vim-paste #t n) (done))
     ((string=? key "u") (vim-edit (lambda () (undo))) (done))
     ((string=? key "C-r") (vim-edit (lambda () (redo))) (done))
     ((string=? key "v")
      (if visual
          (begin (back-to-normal) (message "NORMAL"))
          (begin (put! *vim-states* (get-buffer-name) 'visual)
                 (set-mark (point))
                 (message "VISUAL: move, then d deletes or y copies; v or C-g cancels")))
      #t)
     ((and visual (string=? key "o"))                     ; the other end
      (let ((m (mark)) (p (point))) (fe-set-mark-at p) (goto-char m) (fe-set-mark-active 1))
      #t)
     ((string=? key "o") (open-line-and-edit #f) #t)
     ((string=? key "O") (open-line-and-edit #t) #t)
     ((string=? key "i")
      (if (and (bound? 'help-page-p) (help-page-p)) (help-close) (leave-normal-mode))
      #t)
     ((string=? key "a")
      (unless (or (>= (point) (buffer-size)) (= (byte-at (point)) 10)) (forward-char 1))
      (leave-normal-mode)
      #t)
     ((string=? key "A") (goto-char (line-end)) (leave-normal-mode) #t)
     ((string=? key "I") (goto-char (first-non-blank (point))) (leave-normal-mode) #t)
     ((string=? key "/") (vim-search #t) (done))
     ((string=? key "?") (vim-search #f) (done))
     ((string=? key "n") (vim-search-again #f) (done))
     ((string=? key "N") (vim-search-again #t) (done))
     ((string=? key "C-d") (forward-page) (done))
     ((string=? key "C-u") (backward-page) (done))
     ((string=? key ".") (let ((k *vim-count*)) (set! *vim-count* 0) (vim-repeat k) (clear-message-line)) #t)
     ((string=? key "J") (vim-join (max 2 n)) (done))
     ((string=? key "r") (set! *vim-pending* "r") (message (if (> *vim-count* 0) *vim-count* "") "r") #t)
     ((string=? key ":") (vim-ex (prompt ":" "")) (done))
     ((= (count-characters key) 1)            ; any other character: never typed in
      (vim-reset)
      (message (vim-tag (get-buffer-name)) ": " key " is not a command here; i returns to Emacs")
      #t)
     (else #f))))                              ; other keys (C-x C-s, M-x ...) as usual

(define (vim-move key n)
  (let ((m (motion key (point) n)))
    (when m (goto-char (car m)))
    (set! *vim-count* 0)
    (when (eq? (vim-state) 'visual) (fe-set-mark-active 1))
    (clear-message-line)))

(define (vim-join lines)
  "J: join LINES lines (2 by default) with single spaces, as vim does."
  (vim-edit
   (lambda ()
     (let loop ((k (- lines 1)))
       (when (> k 0)
         (let ((e (line-end (point))) (size (buffer-size)))
           (when (< e size)
             (let skip ((q (+ e 1)))
               (if (memv (byte-at q) '(32 9))
                   (skip (+ q 1))
                   (let ((space (not (or (= e (line-start e))           ; empty line
                                          (memv (byte-at (- e 1)) '(32 9))
                                          (>= q size) (= (byte-at q) 10)
                                          (= (byte-at q) 41)))))      ; )
                     (fe-delete-region e q)
                     (goto-char e)
                     (when space (insert " ") (goto-char e))
                     (loop (- k 1)))))))))))
  #t)

(define (vim-replace-char key n)
  "r{char}: replace N characters under the cursor with KEY."
  (let* ((p (point)) (e (line-end p)))
    (cond ((> (+ p n) e) (message "r: not enough characters on this line"))
          ((not (or (= (count-characters key) 1) (string=? key "\r")))
           (message "r: type the character to put"))
          (else
           (vim-edit (lambda ()
                       (fe-delete-region p (+ p n))
                       (goto-char p)
                       (if (string=? key "\r")
                           (insert "\n")
                           (insert (apply string-append (map (lambda (i) key) (iota n)))))))
           (goto-char (if (string=? key "\r") (+ p 1) (+ p n -1)))))))

(define (vim-ex command)
  "The : commands: w (save), wq and x (save, then quit), q (quit), a line number."
  (let ((c (trim command)))
    (cond ((string=? c "") #f)
          ((string=? c "w") (run-key-as-typed "C-x C-s"))
          ((member c '("wq" "x")) (run-key-as-typed "C-x C-s") (run-key-as-typed "C-x C-c"))
          ((member c '("q" "q!")) (run-key-as-typed "C-x C-c"))
          ((string->number c)
           (goto-char (first-non-blank (point-of-line (string->number c)))))
          (else (message "Not a : command here: " c " (w, wq, x, q, or a line number)")))))

(define (vim-key-handler kind key)
  "The modal key handler (core.scm): the keys of a buffer in read mode."
  (and (vim-active?)
       (if (and (bound? 'help-page-p) (help-page-p) (member key '("C-c r" "C-c g")))
           ;; asking an assistant from the help page: about the page that asked
           (begin (help-close) (run-key-as-typed key) #t)
       (if (eq? kind 'char)
           (vim-key key)
           ;; named keys: arrows move (keeping a selection), the normal-mode
           ;; control keys run; anything else (C-x C-s, M-x ...) is Emacs's
           (and (member key '("up" "down" "left" "right" "C-r" "C-d" "C-u" "C-g" "C-y" "RET"))
                (vim-key (if (string=? key "RET") "\r" key)))))))

(set! *modal-key-handler* 'vim-key-handler)
