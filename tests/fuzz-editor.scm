;; tests/fuzz-editor.sh: the checkpoints of a random walk, on C-c 8 and C-c 9.
;; Compiled once into the editor (chezemax --compile-scripts), as a user's
;; script in ~/.chezemax/users: C-c 9 undoes every command since the previous
;; checkpoint (undo.scm's history counts them), compares the text with the
;; text then, redoes as many, compares it with the text before, and says
;; (FUZZ N OK) or (FUZZ N BAD ...).  As many redos as undos: a C-/ of the
;; walk leaves a group to redo that is not part of the text now.
(define *fuzz-base* #f)
(define *fuzz-count* 0)
(define (fuzz-text) (buffer-substring 0 (buffer-size)))
(define (fuzz-repeat n thunk) (let loop ((k 0)) (when (< k n) (thunk) (loop (+ k 1)))))
(defcommand (fuzz-start)
  (discard-undo-history)
  (set! *fuzz-base* (fuzz-text))
  (message "FUZZ-START"))
(defcommand (fuzz-check)
  (let* ((now (fuzz-text))
         (h (current-history))
         (n (if h (length (undo-history-done h)) 0)))
    (set! *fuzz-count* (+ *fuzz-count* 1))
    (fuzz-repeat n undo)
    (let ((back (string=? (fuzz-text) *fuzz-base*)))
      (fuzz-repeat n redo)
      (let ((again (string=? (fuzz-text) now)))
        (discard-undo-history)
        (set! *fuzz-base* (fuzz-text))
        (message "(FUZZ " (number->string *fuzz-count*)
                 (if (and back again) " OK" " BAD") (if back "" " undo") (if again "" " redo") ")")))))
(global-set-key "C-c 8" 'fuzz-start)
(global-set-key "C-c 9" 'fuzz-check)
