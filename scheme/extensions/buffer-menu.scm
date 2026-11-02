;;;; buffer-menu.scm -- C-x C-b
;;;;
;;;; Port of SBEmacs's lisp/extensions/buffer-menu.lisp (originally
;;;; samples/bufmenu.scm, Hugh Barney, September 2016).
;;;;
;;;; Lists the buffers in the selected window (the other windows stay, as
;;;; in Emacs); move with the arrow keys (or C-n / C-p), then
;;;;   RET  show the buffer in that window
;;;;   1  show it as the only window
;;;;   2  split the window between that buffer and the original one
;;;;   s  save the buffer if modified
;;;;   k  kill the buffer
;;;;   q, x, C-g  exit the menu

(define *bufm-start-line* 3)   ; buffer names start on line 3
(define *bufm-max-ops* 400)
(define *bufm-line* 3)
(define *bufm-last-line* 3)
(define *bufm-stop* #f)
(define *bufm-obuf* "")
(define *bufm-buf* "")
(define *bufm-names* '())

(define (bufm-name-from-line line names)
  ;; Match full live names, including spaces/Unicode and names wider than
  ;; the listing's minimum 16-column field. Never select a truncated name.
  (let* ((tail (byte-substring line (min 11 (length line))))
         (matches (filter (lambda (name) (starts-with-p (string-append name " ") tail)) names)))
    (if (null? matches) ""
        (car (sort matches (lambda (a b) (> (length a) (length b))))))))

(define (bufm-get-bufn)
  "The buffer name on line *BUFM-LINE* of the *buffers* listing."
  (goto-line *bufm-line*)
  (let ((line (current-line-text)))
    (beginning-of-line)
    (bufm-name-from-line line *bufm-names*)))

(define (bufm-buffer-names)
  (let ((saved *bufm-line*))
    (let loop ((l *bufm-start-line*) (acc '()))
      (if (> l *bufm-last-line*)
          (begin (set! *bufm-line* saved) (reverse acc))
          (begin (set! *bufm-line* l) (loop (+ l 1) (cons (bufm-get-bufn) acc)))))))

(define (bufm-move-line n)
  (set! *bufm-line* (max *bufm-start-line* (min (+ *bufm-line* n) *bufm-last-line*))))

(define (bufm-refresh-limits)
  ;; *buffers* itself is not listed, hence the -2
  (set! *bufm-last-line* (+ *bufm-start-line* (get-buffer-count) -2)))

(define (bufm-handle-bound-key)
  (let ((binding (get-key-binding)) (name (get-key-name)))
    (cond ((or (string=? binding "previous-line") (string=? name "C-p")) (bufm-move-line -1))
          ((or (string=? binding "next-line") (string=? name "C-n")) (bufm-move-line 1))
          ((string=? name "C-g") (bufm-handle-single-key "q"))))
  (unless *bufm-stop* (set! *bufm-buf* (bufm-get-bufn))))

(define (bufm-handle-single-key k)
  (let ((several (> (get-buffer-count) 1)))
    (cond ((member k '("x" "q"))
           (if (member *bufm-obuf* (bufm-buffer-names))
               (select-buffer *bufm-obuf*)
               (select-buffer "*scratch*"))
           (set! *bufm-stop* #t))
          ((and (member k '("\r" "\n")) several)
           (select-buffer *bufm-buf*) (set! *bufm-stop* #t))
          ((and (string=? k "1") several)
           (select-buffer *bufm-buf*) (delete-other-windows) (set! *bufm-stop* #t))
          ((member k '("n" " ")) (bufm-move-line 1) (set! *bufm-buf* (bufm-get-bufn)))
          ((string=? k "p") (bufm-move-line -1) (set! *bufm-buf* (bufm-get-bufn)))
          ((and (string=? k "2") several)
           (select-buffer *bufm-buf*) (split-window) (select-buffer *bufm-obuf*) (other-window)
           (set! *bufm-stop* #t))
          ((and (string=? k "s") several)
           (save-buffer *bufm-buf*) (list-buffers) (goto-line *bufm-line*))
          ((and (string=? k "k") several)
           (kill-buffer *bufm-buf*) (set! *bufm-names* (filter (lambda (name) (not (string=? name *bufm-buf*))) *bufm-names*)) (list-buffers) (bufm-refresh-limits) (bufm-move-line 0)
           (set! *bufm-buf* (bufm-get-bufn))))))

(defcommand (buffer-menu)
  "C-x C-b: arrows select; RET opens here; 1 alone; 2 splits; s saves; k kills; q cancels."
  (set! *bufm-obuf* (get-buffer-name))
  (set! *bufm-names* (filter (lambda (name) (not (string=? name "*buffers*"))) (buffer-names)))
  (list-buffers)
  (set! *bufm-line* *bufm-start-line*)
  (set! *bufm-stop* #f)
  (bufm-refresh-limits)
  (set! *bufm-buf* (bufm-get-bufn))
  (let loop ((n 0))
    (when (and (< n *bufm-max-ops*) (not *bufm-stop*))
      (message "Buffer menu: arrows/n/p select; RET opens; 1 alone; 2 split; s save; k kill; q/C-g cancel")
      (update-display)
      (let ((key (get-key)))
        (if (string=? key "") (bufm-handle-bound-key) (bufm-handle-single-key key)))
      (loop (+ n 1))))
  (clear-message-line)
  (update-display))
