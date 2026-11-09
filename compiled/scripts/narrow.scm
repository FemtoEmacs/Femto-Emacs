;;;; narrow.scm -- C-x n: narrowing, as in Emacs
;;;;
;;;;   C-x n n   narrow-to-region: only the region is shown and edited
;;;;   C-x n w   widen: the whole text again
;;;;   C-x n s   Org: the subtree of the heading point is under (org.scm)
;;;;
;;;; The text outside stays in the buffer and is saved with it; the cursor
;;;; cannot go there and search does not find it (src/narrow.c).  The mode
;;;; line shows Narrow.  The next buffer, which C-x n was, is C-x <right>
;;;; (C-x <left> the previous one), as in Emacs.
;;;;
;;;; A module adds a key after C-x n with (narrow-key! KEY PROCEDURE).

(define *narrow-keys* '())      ; (key . procedure)

(define (narrow-key! key procedure)
  (set! *narrow-keys* (cons (cons key procedure)
                            (filter (lambda (k) (not (string=? (car k) key))) *narrow-keys*))))

(define (narrowed?) (>= (fe-narrow-start) 0))

(define (narrow-to! from to)
  "Show only [FROM, TO) of the current buffer; #f if that is empty."
  (= 1 (fe-narrow from to)))

(defcommand (narrow-to-region)
  "C-x n n: show and edit only the region (between mark and point)."
  (let ((m (mark)))
    (cond ((not m) (message "Narrow: set the mark first (C-SPC), then move to the other end"))
          ((= m (point)) (message "Narrow: the region is empty"))
          (else (narrow-to! (min m (point)) (max m (point)))
                (deactivate-mark)
                (update-display)
                (message "Narrowed to the region: C-x n w shows everything")))))

(defcommand (widen)
  "C-x n w: the whole text again."
  (if (narrowed?)
      (begin (fe-widen) (update-display) (message "Widened: the whole text"))
      (message "Not narrowed")))

(define (narrow-prefix)
  "C-x n: the key after it."
  (message "C-x n-")
  (let* ((key (get-key))
         (key (if (string=? key "") (get-key-name) key))
         (entry (assoc key *narrow-keys*)))
    (clear-message-line)
    (if entry
        ((cdr entry))
        (unless (member key '("C-g")) (message "C-x n " key " is not bound")))))

(narrow-key! "n" narrow-to-region)
(narrow-key! "w" widen)
(global-set-key "C-x n" narrow-prefix)
