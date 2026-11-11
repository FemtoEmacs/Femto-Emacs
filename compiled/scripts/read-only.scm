;;;; read-only.scm -- command/search glue for native C READ and copy-only Vim.
;;;; Movement, counts, selections, yy and visual copying run in src/read-mode.c.
;;;; Both modes prohibit deletion, paste, undo, redo, replace and open-line.
;;;; i explicitly returns to Emacs editing; help and tag views return to origin.
;;;; Compatibility helpers below remain available to existing scripts.

(define *vim-states* (make-hashtable string-hash string=?))      ; buffer name -> normal | visual
(define *vim-kinds* (make-hashtable string-hash string=?))       ; buffer name -> read | vim
(define *vim-count* 0)             ; a count being typed (3 in 3dd)
(define *vim-pending* #f)          ; "d", "y", "g", "dg", "yg": waiting for a key
(define *vim-register* #f)         ; (text . linewise?) of the last d/y/x
(define *vim-search* #f)           ; (text . forward?) of the last / or ?

(define (vim-state)
  (let ((s (fe-read-state (get-buffer-name))))
    (cond ((= s 0) #f) ((>= s 3) 'visual) (else 'normal))))

(define (vim-active?) (and (vim-state) #t))

(define (vim-kind) (hashtable-ref *vim-kinds* (get-buffer-name) #f))
(define (vim-editing?) #f)

(define (vim-tag buffer-name)
  (let ((s (fe-read-state buffer-name)))
    (cond ((= s 0) "") ((>= s 3) " VISUAL") ((= s 2) " NORMAL") (else " READ"))))

(define (vim-reset)
  (set! *vim-count* 0)
  (set! *vim-pending* #f))

(define (enter-normal-mode kind)
  (fe-read-mode (if (eq? kind 'vim) 2 1))
  (hashtable-set! *vim-states* (get-buffer-name) 'normal)
  (hashtable-set! *vim-kinds* (get-buffer-name) kind)
  (set-buffer-read-only! #t)
  (deactivate-mark)
  (vim-reset)
  (update-display)
  (message (if (eq? kind 'vim)
               "NORMAL (copy-only): hjkl move, yy copies, v selects then y copies; i edits"
               "READ: hjkl, gg, G, / move; yy and v...y copy; i or C-x C-q edits; C-h lists all")))

(define leave-normal-mode
  (case-lambda
    (() (leave-normal-mode "Emacs mode: the buffer can be edited"))
    ((why)
     ;; the view without tags (tag-view.scm) is never edited: i, a, C-x C-q ...
     ;; go back to the file, at the same place, to edit it there
     (if (tag-view-p)
         (tag-view-leave)
         (leave-normal-mode- why)))))

(define (leave-normal-mode- why)
  (fe-read-mode 0)
  (table-remove! *vim-states* (get-buffer-name))
  (table-remove! *vim-kinds* (get-buffer-name))
  (set-buffer-read-only! #f)
  (deactivate-mark)
  (vim-reset)
  (update-display)
  (message why))

(define (toggle-mode kind)
  "Enter mode KIND; in it already: back to Emacs; in the other one: switch."
  (cond ((help-page-p)
         (message "The help page stays read-only: i or [CLOSE] closes it"))
        ((and (tag-view-p) (eq? kind 'vim))
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
  "Copy-only Vim navigation: v selects, yy and v-move-y copy.
Again (or i): back to Emacs to edit."
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

(define (vim-search forward)
  (let ((s (prompt (if forward "/" "?") "")))
    (when (> (string-length s) 0)
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
                       (goto-char (- (point) (bytes-length s)))
                       (begin (goto-char p) (message "Not found: " s))))
            (unless (search-backward s) (goto-char p) (message "Not found: " s))))))

(define (vim-key key)
  ;; Native event dispatch normally handles movement before Scheme. This
  ;; wrapper also serves callers of vim-key and the compatibility runtime.
  (if (= (fe-read-key key) 1) #t
      (cond ((string=? key "i")
             (if (help-page-p) (help-close) (leave-normal-mode)) #t)
            ((string=? key "/") (vim-search #t) #t)
            ((string=? key "?") (vim-search #f) #t)
            ((string=? key "n") (vim-search-again #f) #t)
            ((string=? key "N") (vim-search-again #t) #t)
            (else #f))))

(define (vim-key-handler kind key)
  "The modal key handler (core.scm): the keys of a buffer in read mode."
  (and (vim-active?)
       (if (and (help-page-p) (member key '("C-c r" "C-c g")))
           ;; asking an assistant from the help page: about the page that asked
           (begin (help-close) (run-key-as-typed key) #t)
       (if (eq? kind 'char)
           (vim-key key)
           ;; named keys: arrows move (keeping a selection), the normal-mode
           ;; control keys run; anything else (C-x C-s, M-x ...) is Emacs's
           (and (member key '("up" "down" "left" "right" "C-r" "C-d" "C-u" "C-g" "C-y" "RET"))
                (vim-key (if (string=? key "RET") "\r" key)))))))

(set! *modal-key-handler* 'vim-key-handler)
