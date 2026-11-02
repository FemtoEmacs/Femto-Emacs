;;;; api.scm -- the editor, as scripts see it
;;;;
;;;; In Chez Scheme, compiled by Schemer: the port of scheme/api.scm.
;;;; Offsets are bytes of UTF-8 text; the fe-* procedures are the C core's
;;;; (compiled/editor-functions.scm, compiled/system.scm).

;; movement -- all take an optional repeat count, default 1
(define-syntax %counted
  (syntax-rules ()
    ((_ name c-function)
     (define name
       (case-lambda
         (() (c-function 1) #t)
         ((n) (c-function n) #t))))))
(%counted forward-char fe-forward-char)
(%counted backward-char fe-backward-char)
(%counted forward-word fe-forward-word)
(%counted backward-word fe-backward-word)
(%counted forward-page fe-forward-page)
(%counted backward-page fe-backward-page)
(%counted next-line fe-next-line)
(%counted previous-line fe-previous-line)
(define (beginning-of-line) (fe-beginning-of-line) #t)
(define (end-of-line) (fe-end-of-line) #t)
(define (beginning-of-buffer) (fe-beginning-of-buffer) #t)
(define (end-of-buffer) (fe-end-of-buffer) #t)
(define (goto-line n) (fe-goto-line n) #t)

(define (point) (fe-get-point))
(define (goto-char p) (fe-set-point p) (fe-get-point))
(define (mark) (let ((m (fe-get-mark))) (if (< m 0) #f m)))
(define set-mark
  (case-lambda
    (() (set-mark (point)))
    ((position)
     "Set the mark at POSITION and activate the region (shaded)."
     (fe-set-mark-at position) (fe-set-mark-active 1) #t)))
(define push-mark
  (case-lambda
    (() (push-mark (point)))
    ((position) (fe-set-mark-at position) #t)))
(define (clear-mark) (fe-set-mark-at -1) (fe-set-mark-active 0) #t)
(define (region-active-p) (= 1 (fe-mark-active)))
(define (activate-mark) (when (mark) (fe-set-mark-active 1)) #t)
(define (deactivate-mark) (fe-set-mark-active 0) #t)

(define (buffer-size) (fe-buffer-size))
(define line-start
  (case-lambda
    (() (line-start (point)))
    ((p) (fe-line-start p))))
(define line-end
  (case-lambda
    (() (line-end (point)))
    ((p)
     "Offset of the newline ending the line containing P (or the end)."
     (let ((size (buffer-size)))
       (let loop ((start p))
         (let* ((end (min size (+ start 4096)))
                (nl (byte-position (buffer-bytes start end) 10)))
           (cond (nl (+ start nl))
                 ((>= end size) size)
                 (else (loop end)))))))))
(define char-after
  (case-lambda
    (() (char-after (point)))
    ((p) (let ((c (fe-char-at p))) (if (< c 0) #f (integer->char c))))))

;; editing
(define (insert . things)
  (for-each (lambda (x) (let ((s (->string x))) (when (> (string-length s) 0) (fe-insert s)))) things)
  #t)
(%counted backward-delete-char fe-backward-delete-char)
(%counted delete-char fe-delete-char)
(define (kill-region) (fe-kill-region) #t)
(define (copy-region) (fe-copy-region) #t)
(define (yank) (fe-yank) #t)
(define (kill-line) (fe-kill-line) #t)
(define (discard-undo-history) (fe-discard-undo-history) #t)
(define (get-clipboard) (let ((s (fe-get-clipboard))) (if (string? s) s "")))
(define (set-clipboard s) (fe-set-clipboard (->string s)) s)
(define (set-system-clipboard s) (fe-set-system-clipboard (->string s)) s)
(define (system-clipboard)
  (let ((s (fe-get-system-clipboard)))
    (and (string? s) (> (string-length s) 0) s)))
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
(define line-number
  (case-lambda
    (() (line-number (point)))
    ((p) (fe-line-number p))))

(define (set-mode-line-hints help tail) (fe-set-modeline-hints (->string help) (->string tail)) #t)

(defvar *buffer-hints* (make-hashtable string-hash string=?))
(define (set-buffer-hint buffer hint)
  "Show HINT at the end of the mode line of BUFFER instead of the usual
hints; #f or \"\" goes back to them."
  (let ((name (->string buffer)) (hint (if hint (->string hint) "")))
    (if (string=? hint "") (table-remove! *buffer-hints* name) (hashtable-set! *buffer-hints* name hint))
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
(define prompt
  (case-lambda
    ((question) (prompt question ""))
    ((question initial)
     (let ((r (fe-prompt (->string question) (->string initial)))) (if (string? r) r "")))))
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
        ((and (integer? x) (<= -1 x) (<= x 255)) x)
        ((and (string? x) (= (string-length x) 7) (char=? (string-ref x 0) #\#) (hex-digits? (substring x 1 7)))
         (bitwise-ior +rgb-flag+ (string->number (substring x 1 7) 16)))
        (else (error "Unknown colour; use a name, 0-255 or \"#rrggbb\"" x))))

(define (attribute-bits attributes)
  (fold (lambda (a sum)
          (+ sum (let ((p (assq a *face-attributes*))) (if p (cdr p) (error "Unknown attribute" a)))))
        0 attributes))

;;; (set-color face foreground [background attribute ...])
(define (%face-colors who face foreground more)
  (let ((background (if (pair? more) (car more) 'default))
        (attributes (if (pair? more) (cdr more) '())))
    (= 1 (who (color-id face) (color-number foreground) (color-number background)
              (attribute-bits attributes)))))

(define (set-color face foreground . more)
  "Change how FACE is drawn, overriding the theme:
  (set-color 'keyword 'red)  (set-color 'comment 244)
  (set-color 'string 'green 'default 'bold)"
  (%face-colors fe-set-color face foreground more))

(define (theme-face face foreground . more)
  "Like SET-COLOR, inside a colour theme (theme.scm)."
  (%face-colors fe-set-theme-face face foreground more))

(define (terminal-colors) (fe-colors))
