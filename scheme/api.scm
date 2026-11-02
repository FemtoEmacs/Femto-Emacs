;;;; api.scm -- the editor, as scripts see it
;;;;
;;;; Port of the public part of SBEmacs's lisp/ffi.lisp.  Offsets are bytes
;;;; of UTF-8 text; the fe-* primitives are the C core's (src/native.c,
;;;; src/primitives.c).

;; movement -- all take an optional repeat count, default 1
(define (forward-char (n 1)) (fe-forward-char n) #t)
(define (backward-char (n 1)) (fe-backward-char n) #t)
(define (forward-word (n 1)) (fe-forward-word n) #t)
(define (backward-word (n 1)) (fe-backward-word n) #t)
(define (forward-page (n 1)) (fe-forward-page n) #t)
(define (backward-page (n 1)) (fe-backward-page n) #t)
(define (next-line (n 1)) (fe-next-line n) #t)
(define (previous-line (n 1)) (fe-previous-line n) #t)
(define (beginning-of-line) (fe-beginning-of-line) #t)
(define (end-of-line) (fe-end-of-line) #t)
(define (beginning-of-buffer) (fe-beginning-of-buffer) #t)
(define (end-of-buffer) (fe-end-of-buffer) #t)
(define (goto-line n) (fe-goto-line n) #t)

(define (point) (fe-get-point))
(define (goto-char p) (fe-set-point p) (fe-get-point))
(define (mark) (let ((m (fe-get-mark))) (if (< m 0) #f m)))
(define (set-mark (position (point)))
  "Set the mark at POSITION and activate the region (shaded)."
  (fe-set-mark-at position) (fe-set-mark-active 1) #t)
(define (push-mark (position (point))) (fe-set-mark-at position) #t)
(define (clear-mark) (fe-set-mark-at -1) (fe-set-mark-active 0) #t)
(define (region-active-p) (= 1 (fe-mark-active)))
(define (activate-mark) (when (mark) (fe-set-mark-active 1)) #t)
(define (deactivate-mark) (fe-set-mark-active 0) #t)

(define (buffer-size) (fe-buffer-size))
(define (line-start (p (point))) (fe-line-start p))
(define (line-end (p (point)))
  "Offset of the newline ending the line containing P (or the end)."
  (let ((size (buffer-size)))
    (let loop ((start p))
      (let* ((end (min size (+ start 4096)))
             (chunk (buffer-substring start end))
             (nl (byte-position chunk 10)))
        (cond (nl (+ start nl))
              ((>= end size) size)
              (else (loop end)))))))
(define (char-after (p (point)))
  (let ((c (fe-char-at p))) (if (< c 0) #f (integer->char c))))

;; editing
(define (insert . things)
  (for-each (lambda (x) (let ((s (->string x))) (when (> (length s) 0) (fe-insert s)))) things)
  #t)
(define (backward-delete-char (n 1)) (fe-backward-delete-char n) #t)
(define (delete-char (n 1)) (fe-delete-char n) #t)
(define (kill-region) (fe-kill-region) #t)
(define (copy-region) (fe-copy-region) #t)
(define (yank) (fe-yank) #t)
(define (kill-line) (fe-kill-line) #t)
(define (discard-undo-history) (fe-discard-undo-history) #t)
(define (get-clipboard) (or (fe-get-clipboard) ""))
(define (set-clipboard s) (fe-set-clipboard (->string s)) s)
(define (set-system-clipboard s) (fe-set-system-clipboard (->string s)) s)
(define (system-clipboard)
  (let ((s (fe-get-system-clipboard)))
    (and (string? s) (> (length s) 0) s)))
(define (cut-region) (kill-region) (get-clipboard))

;; searching
(define (search-forward s) (= 1 (fe-search-forward (->string s))))
(define (search-backward s) (= 1 (fe-search-backward (->string s))))

;; buffers
(define (get-buffer-count) (fe-buffer-count))
(define (get-buffer-name) (fe-buffer-name))
(define (buffer-filename)
  (let ((f (fe-buffer-filename))) (if (or (not (string? f)) (string=? f "")) #f f)))
(define (buffer-modified-p) (= 1 (fe-buffer-modified)))
(define (select-buffer name) (= 1 (fe-select-buffer (->string name))))
(define (kill-buffer name) (= 1 (fe-kill-buffer (->string name))))
(define (save-buffer name) (= 1 (fe-save-buffer (->string name))))
(define (find-file filename) (fe-find-file (->string filename)) #t)
(define (list-buffers) (fe-list-buffers) #t)
(define (rename-buffer name) (fe-rename-buffer (->string name)))

;; windows and display
(define (delete-other-windows) (fe-delete-other-windows) #t)
(define (other-window) (fe-other-window) #t)
(define (split-window) (fe-split-window) #t)
(define (update-display) (fe-update-display) #t)
(define (refresh-screen) (fe-refresh) #t)
(define (delete-window) (fe-delete-window) #t)
(define (window-count) (fe-window-count))
(define (window-rows) (fe-window-rows))
(define (recenter) (fe-recenter) #t)
(define (set-window-start p) (fe-set-window-start p) #t)
(define (line-number (p (point))) (fe-line-number p))

(define (set-mode-line-hints help tail) (fe-set-modeline-hints (->string help) (->string tail)) #t)

(defvar *buffer-hints* (table))
(define (set-buffer-hint buffer hint)
  "Show HINT at the end of the mode line of BUFFER instead of the usual
hints; #f or \"\" goes back to them."
  (let ((name (->string buffer)) (hint (if hint (->string hint) "")))
    (if (string=? hint "") (table-remove! *buffer-hints* name) (put! *buffer-hints* name hint))
    (fe-set-buffer-hint name hint))
  #t)

(define (execute-builtin name) (= 1 (fe-execute-command (->string name))))
(define (builtin-command-names)
  (let loop ((i 0) (acc '()))
    (let ((name (fe-command-name i)))
      (if (and (string? name) (not (string=? name ""))) (loop (+ i 1) (cons name acc)) (reverse acc)))))
(define (screen-rows) (fe-screen-rows))
(define (screen-columns) (fe-screen-cols))

;; message line
(define (message . parts) (fe-message (apply concat parts)) #t)
(define (clear-message-line) (fe-clear-message-line) #t)
(define (log-debug s) (fe-log-debug (->string s)) #t)

;; keyboard
(define (get-key)
  "Wait for a key: the typed string, or \"\" for a bound key, which
GET-KEY-NAME and GET-KEY-BINDING then describe."
  (let ((k (fe-get-key))) (if (string? k) k "")))
(define (get-key-name) (let ((k (fe-get-key-name))) (if (string? k) k "")))
(define (get-key-binding) (let ((k (fe-get-key-binding))) (if (string? k) k "")))
(define (prompt question (initial ""))
  (let ((r (fe-prompt (->string question) (->string initial)))) (if (string? r) r "")))
(define (yes-p question)
  (string-ci=? (trim (prompt (concat question " (y/n) ") "")) "y"))

(define (add-mode-global mode) (= 1 (fe-add-mode-global (->string mode))))
(define (get-version-string) (fe-version))
(define (quit-editor) (fe-quit) #t)
(define (backend) (fe-backend))

;;; colours

(define *color-ids*
  '((symbol . 1) (modeline . 2) (brace . 3) (keyword . 4) (alpha . 5)
    (digits . 6) (comment . 7) (block-comment . 8) (string . 9)
    (region . 10) (heading . 11) (emphasis . 12) (strong . 13) (link . 14)
    (menu . 15) (menu-pressed . 16)))

(define *basic-colors*
  '((default . -1) (black . 0) (red . 1) (green . 2) (yellow . 3)
    (blue . 4) (magenta . 5) (cyan . 6) (white . 7)))

(define *face-attributes*
  '((bold . 1) (underline . 2) (reverse . 4) (dim . 8) (italic . 16)))

(define +rgb-flag+ #x1000000)

(define (color-id face)
  (let ((p (assq face *color-ids*)))
    (if p (cdr p) (error "Unknown face" face))))

(define (hex-digits? s)
  (every (lambda (c) (memv (char-downcase c) (string->list "0123456789abcdef"))) (string->list s)))

(define (color-number x)
  "A colour for C: -1 (default), 0-255, or a 24-bit \"#rrggbb\"."
  (cond ((assq x *basic-colors*) => cdr)
        ((and (integer? x) (and (<= -1 x) (<= x 255))) x)
        ((and (string? x) (= (length x) 7) (char=? (string-ref x 0) #\#) (hex-digits? (byte-substring x 1)))
         (logior +rgb-flag+ (string->number (byte-substring x 1) 16)))
        (else (error "Unknown colour; use a name, 0-255 or \"#rrggbb\"" x))))

(define (attribute-bits attributes)
  (fold (lambda (a sum)
          (+ sum (let ((p (assq a *face-attributes*))) (if p (cdr p) (error "Unknown attribute" a)))))
        0 attributes))

(define (set-color face foreground (background 'default) . attributes)
  "Change how FACE is drawn, overriding the theme:
  (set-color 'keyword 'red)  (set-color 'comment 244)
  (set-color 'string 'green 'default 'bold)"
  (= 1 (fe-set-color (color-id face) (color-number foreground) (color-number background)
                     (attribute-bits attributes))))

(define (theme-face face foreground (background 'default) . attributes)
  "Like SET-COLOR, inside a colour theme (theme.scm)."
  (= 1 (fe-set-theme-face (color-id face) (color-number foreground) (color-number background)
                          (attribute-bits attributes))))

(define (terminal-colors) (fe-colors))
