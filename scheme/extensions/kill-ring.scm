;;;; kill-ring.scm -- C-c k and C-c i
;;;;
;;;; Port of SBEmacs's lisp/extensions/kill-ring.lisp (originally
;;;; samples/killring.scm, Hugh Barney, September 2016).  Every kill is
;;;; pushed onto *KILL-RING* by REMEMBER-KILL (core.scm).
;;;;
;;;; C-c k  shows a one-line summary of each kill; move with the arrow keys,
;;;;        c copies the selected kill to the clipboard (then C-y yanks it),
;;;;        x exits.
;;;; C-c i  inserts the whole kill ring into the current buffer.

(define *kr-line* 1)
(define *kr-max-ops* 2000)

(define (summarize-kill text)
  "First line of TEXT, at most 40 characters."
  (let* ((nl (byte-position text 10))
         (line (if nl (byte-substring text 0 nl) text)))
    (if (> (string-length line) 40) (substring line 0 40) line)))

(define (kr-last-line) (max 1 (length *kill-ring*)))
(define (kr-move-line n) (set! *kr-line* (max 1 (min (+ *kr-line* n) (kr-last-line)))))
(define (kr-show-options)
  (message "kill item " *kr-line* " : select (up), (down), (c=copy to clipboard), (x=exit)")
  (update-display))

(defcommand (kill-ring-menu)
  "C-c k: browse the kill ring."
  (let ((original (get-buffer-name)))
    (set! *kr-line* (min *kr-line* (kr-last-line)))
    (kill-buffer "*kill-ring*")
    (select-buffer "*kill-ring*")
    (if (pair? *kill-ring*)
        (for-each (lambda (k) (insert (summarize-kill k) "\n")) *kill-ring*)
        (insert "(the kill ring is empty)"))
    (fe-set-modified 0)
    (goto-line *kr-line*)
    (delete-other-windows)
    (kr-show-options)
    (let loop ((n 0))
      (when (< n *kr-max-ops*)
        (let ((key (get-key)))
          (cond ((string=? key "")
                 (let ((binding (get-key-binding)))
                   (cond ((string=? binding "previous-line") (kr-move-line -1))
                         ((string=? binding "next-line") (kr-move-line 1))))
                 (goto-line *kr-line*)
                 (kr-show-options)
                 (loop (+ n 1)))
                ((string=? key "x")
                 (select-buffer original)
                 (delete-other-windows))
                ((string=? key "c")
                 (when (pair? *kill-ring*) (set-clipboard (list-ref *kill-ring* (- *kr-line* 1))))
                 (message "item " *kr-line* " copied to clipboard")
                 (update-display)
                 (loop (+ n 1)))
                (else (loop (+ n 1)))))))
    (update-display)))

(defcommand (insert-kill-ring)
  "C-c i: insert the whole kill ring."
  (for-each (lambda (k) (insert k "\n#########################\n")) *kill-ring*))
