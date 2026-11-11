;;;; undo.scm -- undo and redo
;;;;
;;;; Port of SBEmacs's lisp/undo.lisp.  Every change to a text is one of two
;;;; acts -- insert the bytes S at P, delete the bytes S at P -- and each
;;;; undoes the other.  The C core reports every act as it happens
;;;; (src/undo.c, RECORD-CHANGE below), whatever caused it.
;;;;
;;;; What the user undoes is a command, not an act: the acts are grouped by
;;;; the key that caused them (UNDO-BOUNDARY runs before each key).  Typed
;;;; characters in a row join, up to *UNDO-AMALGAMATE*, and so do deletions
;;;; with DEL or C-d, so that undo brings back a word rather than a letter.
;;;;
;;;; Two stacks of groups per buffer: DONE (newest first), which C-/ pops,
;;;; and UNDONE, which redo pops.  A new change empties UNDONE.  The buffer
;;;; is unmodified exactly when the newest done group is the one that was
;;;; newest when the file was saved.
;;;;
;;;;   C-/  C-_  C-x u  C-u     undo           C-M-_  M-_     redo

(define *undo-limit* (* 8 1024 1024))   ; bytes of history kept per buffer
(define *undo-group-limit* 200)
(define *undo-change-limit* 10000)
(define *undo-amalgamate* 20)           ; typed characters that undo together

;; a change: #(kind pos text), kind 'insert or 'delete, text a byte string
(define (make-change kind pos text) (vector kind pos text))
(define (change-kind c) (vector-ref c 0))
(define (change-pos c) (vector-ref c 1))
(define (change-text c) (vector-ref c 2))

;; a group: #(id point changes), changes newest first
(define (make-undo-group id point) (vector id point '()))
(define (undo-group-id g) (vector-ref g 0))
(define (undo-group-point g) (vector-ref g 1))
(define (undo-group-changes g) (vector-ref g 2))

;; a history: #(done undone bytes saved-id blocked-command-id)
(define (make-undo-history) (vector '() '() 0 0 -1))
(define (undo-history-done h) (vector-ref h 0))
(define (undo-history-undone h) (vector-ref h 1))
(define (undo-history-bytes h) (vector-ref h 2))
(define (undo-history-saved-id h) (vector-ref h 3))
(define (undo-history-blocked-command h) (vector-ref h 4))

(defvar *undo-histories* (table))       ; buffer id (never reused) -> history
(define *undoing* #f)

(defvar *command-serial* 1)
(define *command-point* 0)
(define *command-buffer-id* -1)
(define *self-insert-run* 0)
(define *last-boundary-kind* #f)
(define *deleting-keys* '("backspace" "DEL" "C-d"))

(define (undo-boundary (key #t))
  "Before every key (its name, or #t for a typed character)."
  (let ((kind (cond ((eq? key #t) 'typing)
                    ((and (string? key) (member key *deleting-keys*)) 'deleting)
                    (else #f))))
    (unless (and kind (eq? kind *last-boundary-kind*)
                 (< *self-insert-run* *undo-amalgamate*))
      (set! *command-serial* (+ *command-serial* 1))
      (set! *self-insert-run* 0))
    (when kind (set! *self-insert-run* (+ *self-insert-run* 1)))
    (set! *last-boundary-kind* kind)
    ;; without a buffer (scripts run by --eval) there is no point to read
    (let ((live (> (fe-buffer-count) 0)))
      (set! *command-point* (if live (fe-get-point) 0))
      (set! *command-buffer-id* (if live (fe-buffer-id) -1))))
  #f)

(define (history-of id)
  (or (get *undo-histories* id #f)
      (let ((h (make-undo-history))) (put! *undo-histories* id h) h)))

(define (top-id h)
  (let ((done (undo-history-done h))) (if (pair? done) (undo-group-id (car done)) 0)))

(define (merge-change group new)
  "Join NEW to the newest change of GROUP when they are one stretch of
typing or deleting; true if joined."
  (let ((changes (undo-group-changes group)))
    (and (pair? changes)
         (let ((old (car changes)))
           (and (eq? (change-kind old) (change-kind new))
                (let ((op (change-pos old)) (ot (change-text old))
                      (np (change-pos new)) (nt (change-text new)))
                  (cond ((and (eq? (change-kind new) 'insert) (= np (+ op (length ot))))
                         (vector-set! old 2 (string-append ot nt)) #t)
                        ((and (eq? (change-kind new) 'delete) (= np op))          ; C-d, C-d
                         (vector-set! old 2 (string-append ot nt)) #t)
                        ((and (eq? (change-kind new) 'delete) (= (+ np (length nt)) op)) ; DEL, DEL
                         (vector-set! old 2 (string-append nt ot))
                         (vector-set! old 1 np) #t)
                        (else #f))))))))

(define (group-bytes g)
  (fold (lambda (c sum) (+ sum (length (change-text c)))) 0 (undo-group-changes g)))

(define (history-groups h) (append (undo-history-done h) (undo-history-undone h)))
(define (history-actual-bytes h)
  (fold (lambda (g n) (+ n (group-bytes g))) 0 (history-groups h)))
(define (history-change-count h)
  (fold (lambda (g n) (+ n (length (undo-group-changes g)))) 0 (history-groups h)))
(define (trim-history h)
  "Bound both stacks, including the newest/oversized group and metadata."
  (vector-set! h 2 (history-actual-bytes h))
  (let loop ()
    (when (and (pair? (history-groups h))
               (or (> (undo-history-bytes h) (max 0 *undo-limit*))
                   (> (length (history-groups h)) (max 0 *undo-group-limit*))
                   (> (history-change-count h) (max 0 *undo-change-limit*))))
      (let* ((back (pair? (undo-history-done h)))
             (groups (if back (undo-history-done h) (undo-history-undone h)))
             (oldest (car (last-pair groups))))
        (when (= (undo-group-id oldest) *command-serial*)
          (vector-set! h 4 *command-serial*))
        (vector-set! h (if back 0 1) (list-head groups (- (length groups) 1)))
        ;; A discarded saved boundary must never falsely mark text unmodified.
        (when (or (= (undo-group-id oldest) (undo-history-saved-id h))
                  (and back (= (undo-history-saved-id h) 0)))
          (vector-set! h 3 -1))
        (vector-set! h 2 (history-actual-bytes h))
        (loop)))))

(define (record-change id kind pos text)
  "The C core's report (src/undo.c): KIND is 105 #\\i (TEXT inserted at
POS), 100 #\\d (deleted), 114 #\\r (replaced wholesale: forget) or 115
#\\s (saved)."
  (cond
    ((= kind 114) (table-remove! *undo-histories* id))
    ((= kind 115) (let ((h (history-of id))) (vector-set! h 3 (top-id h))))
    ((and (or (= kind 105) (= kind 100))
          (not *undoing*) *undo-mode* (> (length text) 0))
     (let* ((h (history-of id))
            (change (make-change (if (= kind 105) 'insert 'delete) (max pos 0) text))
            (done (undo-history-done h))
            (group (and (pair? done) (car done))))
       (unless (= (undo-history-blocked-command h) *command-serial*)
         (vector-set! h 1 '())            ; a new change: no redo
         (unless (and group (= (undo-group-id group) *command-serial*))
           (set! group (make-undo-group *command-serial*
                                        (if (= id *command-buffer-id*) *command-point* (max pos 0))))
           (vector-set! h 0 (cons group (undo-history-done h))))
         (unless (merge-change group change)
           (vector-set! group 2 (cons change (undo-group-changes group))))
         (vector-set! h 2 (history-actual-bytes h))
         (trim-history h)))))
  #f)

;;; Applying changes, without recording them

(define (revert-change c)
  (let ((pos (change-pos c)) (text (change-text c)))
    (if (eq? (change-kind c) 'insert)
        (fe-delete-region pos (+ pos (length text)))
        (fe-insert-bytes pos text))
    pos))

(define (apply-change c)
  (let ((pos (change-pos c)) (text (change-text c)))
    (if (eq? (change-kind c) 'insert)
        (begin (fe-insert-bytes pos text) (+ pos (length text)))
        (begin (fe-delete-region pos (+ pos (length text))) pos))))

(define (update-modified h)
  (fe-set-modified (if (= (top-id h) (undo-history-saved-id h)) 0 1)))

(define (current-history) (get *undo-histories* (fe-buffer-id) #f))

(define (call-undoing thunk)
  (dynamic-wind (lambda () (set! *undoing* #t)) thunk (lambda () (set! *undoing* #f))))

(defcommand (undo)
  "C-/: undo the last command's changes; again: the one before."
  (let ((h (current-history)))
    (when h (trim-history h))
    (cond ((buffer-read-only?) (message "Read-only: return to Emacs before undo"))
          ((not *undo-mode*) (message "Undo is off (*undo-mode*)"))
          ((or (not h) (null? (undo-history-done h)))
           (message "No further undo information"))
          (else
           (let ((group (car (undo-history-done h))))
             (vector-set! h 0 (cdr (undo-history-done h)))
             (call-undoing (lambda () (for-each revert-change (undo-group-changes group))))
             (vector-set! h 1 (cons group (undo-history-undone h)))
             (goto-char (undo-group-point group))
             (update-modified h)
             (message (if (null? (undo-history-done h)) "Undo (no more); C-M-_ redoes"
                          "Undo; C-M-_ redoes")))))
    (set! *this-command* 'undo)
    #t))

(defcommand (redo)
  "C-M-_ (or M-_): redo what undo took back."
  (let ((h (current-history)))
    (when h (trim-history h))
    (cond ((buffer-read-only?) (message "Read-only: return to Emacs before redo"))
          ((or (not h) (null? (undo-history-undone h))) (message "Nothing to redo"))
          (else
           (let ((group (car (undo-history-undone h))) (end #f))
             (vector-set! h 1 (cdr (undo-history-undone h)))
             (call-undoing
              (lambda ()
                (for-each (lambda (c) (set! end (apply-change c)))
                          (reverse (undo-group-changes group)))))
             (vector-set! h 0 (cons group (undo-history-done h)))
             (when end (goto-char end))
             (update-modified h)
             (message (if (null? (undo-history-undone h)) "Redo (no more)" "Redo")))))
    (set! *this-command* 'redo)
    #t))

(defcommand (undo-status)
  "How much undo history this buffer has."
  (let ((h (current-history)))
    (if (not h)
        (message "No undo history for this buffer")
        (message "Undo: " (plural (length (undo-history-done h)) "step") " back, "
                 (length (undo-history-undone h)) " forward, "
                 (undo-history-bytes h) " bytes kept (limit " *undo-limit* ")"))))

(global-set-key "C-_" 'undo)            ; C-/ in most terminals
(global-set-key "C-x u" 'undo)
(global-set-key "C-u" 'undo)            ; the old key, kept
(global-set-key "C-M-_" 'redo)
(global-set-key "M-_" 'redo)

;; Native stress tester: isolate user globals once per run, never per cycle.
(define *tester-saved-state* #f)
(define *tester-search-baseline* #f)
(define (tester-search-state)
  (value->string (list *kill-ring* (current-history))))
(define (tester-search-unchanged?)
  (and *tester-search-baseline*
       (equal? *tester-search-baseline* (tester-search-state))))
(define (tester-history-begin)
  (when *tester-saved-state* (error "Tester already active"))
  (set! *tester-saved-state*
    (vector *kill-ring* *use-system-clipboard* *undo-mode* *last-command* *this-command*
            *yank-start* *yank-end* *yank-index*))
  (set! *kill-ring* '())
  (set! *tester-search-baseline* #f)
  (set! *use-system-clipboard* #f)
  (set! *undo-mode* #t)
  #t)
(define (tester-history-state)
  (let ((h (current-history)))
    (list (length *kill-ring*) (kill-ring-bytes)
      (if h (length (undo-history-done h)) 0)
      (if h (length (undo-history-undone h)) 0)
      (if h (undo-history-bytes h) 0)
      (if h (history-actual-bytes h) 0)
      (if h (history-change-count h) 0)
      (length (table.keys *undo-histories*)))))
(define (tester-history-end)
  (when *tester-saved-state*
    (let ((s *tester-saved-state*))
      (set! *kill-ring* (vector-ref s 0))
      (trim-kill-ring)
      (set! *use-system-clipboard* (vector-ref s 1))
      (set! *undo-mode* (vector-ref s 2))
      (set! *last-command* (vector-ref s 3))
      (set! *this-command* (vector-ref s 4))
      (set! *yank-start* (vector-ref s 5))
      (set! *yank-end* (vector-ref s 6))
      (set! *yank-index* (vector-ref s 7))
      (set! *tester-saved-state* #f)))
  (set! *tester-search-baseline* #f)
  #t)

(define (tester-history-event action)
  (cond ((string=? action "begin") (tester-history-begin))
        ((string=? action "end") (tester-history-end))
        ((string=? action "search-seed") (push-kill "chez-tester search baseline"))
        ((string=? action "search-baseline")
         (set! *tester-search-baseline* (tester-search-state))))
  ;; A copy probe reports only if M-w actually put the copied text at the
  ;; front of the ring. No mutable history objects cross the C bridge.
  (when (and (or (not (string=? action "search-check"))
                 (tester-search-unchanged?))
             (or (not (string=? action "copy"))
            (and (pair? *kill-ring*) (string=? (car *kill-ring*) (get-clipboard)))))
    (let ((h (current-history)))
      (fe-tester-history-stats (length *kill-ring*) (kill-ring-bytes)
        (if h (length (undo-history-done h)) 0)
        (if h (length (undo-history-undone h)) 0)
        (if h (undo-history-bytes h) 0)
        (if h (history-actual-bytes h) 0)
        (if h (history-change-count h) 0)
        (length (table.keys *undo-histories*))))))
