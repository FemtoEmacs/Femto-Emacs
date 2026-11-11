;;;; org-goto.scm -- going about an Org file (a module of org.scm)
;;;;
;;;;   C-c C-j   the headings, in a read-only list in the window: move
;;;;             with the arrows (or C-n C-p), then RET, or a click on a
;;;;             heading, goes there; s goes there and narrows to it;
;;;;             q or C-g goes back to where you were
;;;;   C-x n s   narrow to the subtree point is in: its heading and what is
;;;;             under it, down to the next heading of its level or above
;;;;             (C-x n w widens, narrow.scm)
;;;;
;;;; Emacs's names: org-goto, org-narrow-to-subtree, widen.

(define *org-headings-buffer* "*org-headings*")

(define (org-headings text)
  "The headings of TEXT (bytes): ((level start title) ...), in order."
  (let loop ((ls 0) (out '()))
    (if (>= ls (blen text)) (reverse out)
        (let* ((le (org-line-end text ls))
               (level (org-heading-level text ls le)))
          (loop (+ le 1)
                (if level (cons (list level ls (bytes->string text ls le)) out) out))))))

(define (org-subtree text p)
  "The subtree point P is in: (start . end), or #f above the first heading."
  (let ((start (let up ((ls (org-line-start text p)))
                 (cond ((org-heading-level text ls (org-line-end text ls)) ls)
                       ((<= ls 0) #f)
                       (else (up (org-line-start text (- ls 1))))))))
    (and start
         (let ((level (org-heading-level text start (org-line-end text start))))
           (let down ((ls (min (blen text) (+ (org-line-end text start) 1))))
             (cond ((>= ls (blen text)) (cons start (blen text)))
                   ((let ((l (org-heading-level text ls (org-line-end text ls)))) (and l (<= l level)))
                    (cons start ls))
                   (else (down (min (blen text) (+ (org-line-end text ls) 1))))))))))

(define (org-narrow-to-subtree)
  "C-x n s in Org: show and edit only the subtree point is in."
  (if (not (org-buffer-p))
      (message "C-x n s is not bound")
      (let ((range (org-subtree (org-buffer-bytes) (point))))
        (if (not range)
            (message "C-x n s: not under a heading")
            (begin (narrow-to! (car range) (cdr range))
                   (update-display)
                   (message "Narrowed to the subtree: C-x n w shows everything"))))))

(narrow-key! "s" org-narrow-to-subtree)

;;; ------------------------------------------------------------------
;;; C-c C-j: the list of headings
;;; ------------------------------------------------------------------

(define *org-goto-first-line* 3)        ; the headings start on line 3

(define (org-goto-text headings file)
  (string-append "Headings of " file ": RET or a click goes there, s narrows to it, q goes back\n\n"
                 (string-join (map caddr headings) "\n")
                 "\n"))

(define (org-goto-faces text)
  "The colours of the list (a bytevector): the headings as in the file."
  (let* ((bytes (string->utf8 text)) (n (blen bytes)) (colors (make-colors n)))
    (org-highlight #f bytes n colors)
    (let ((first-nl (org-line-end bytes 0)))           ; the first line: a comment
      (org-paint! colors 0 first-nl +comment+))
    colors))

(define (org-goto)
  "C-c C-j: choose a heading from a list, and go there."
  (let* ((text (org-buffer-bytes))
         (headings (org-headings text))
         (origin (get-buffer-name))
         (file (file-name-nondirectory (or (buffer-filename) origin)))
         (here (point)))
    (if (null? headings)
        (message "C-c C-j: this file has no headings")
        (let* ((current (let loop ((hs headings) (k 0) (best 0))
                          (cond ((null? hs) best)
                                ((<= (cadr (car hs)) here) (loop (cdr hs) (+ k 1) k))
                                (else best))))
               (listing (org-goto-text headings file))
               (choice #f) (narrow #f))
          (dynamic-wind
           (lambda () #f)
           (lambda ()
             (select-buffer *org-headings-buffer*)
             (erase-buffer)
             (insert listing)
             (fe-set-modified 0)
             (hashtable-set! *buffer-faces* *org-headings-buffer* (org-goto-faces listing))
             (goto-line (+ *org-goto-first-line* current))
             (let loop ()
               (update-display)
               (let* ((key (get-key))
                      (name (if (string=? key "") (get-key-name) ""))
                      (binding (if (string=? key "") (get-key-binding) ""))
                      (line-index (lambda () (- (line-number) *org-goto-first-line*)))
                      (on-heading (lambda () (and (string=? (get-buffer-name) *org-headings-buffer*)
                                                  (<= 0 (line-index)) (< (line-index) (length headings))))))
                 (cond
                  ((or (member key '("q" "Q")) (string=? name "C-g")) #f)
                  ((or (member key '("\r" "\n")) (member name '("RET" "C-m" "C-j")))
                   (if (on-heading) (set! choice (line-index)) (loop)))
                  ((member key '("s" "S"))
                   (if (on-heading) (begin (set! choice (line-index)) (set! narrow #t)) (loop)))
                  ((string=? binding "mouse")
                   (let ((kind (fe-mouse-kind)))
                     (fe-mouse-event)
                     ;; a click on a heading goes there; the wheel scrolls
                     (if (and (string=? kind "release") (on-heading))
                         (set! choice (line-index))
                         (loop))))
                  ((member binding '("next-line" "previous-line" "forward-page" "backward-page"
                                     "beginning-of-buffer" "end-of-buffer"))
                   (execute-builtin binding)
                   (loop))
                  ((member key '("n" " ")) (execute-builtin "next-line") (loop))
                  ((string=? key "p") (execute-builtin "previous-line") (loop))
                  (else (message "Headings: RET or a click goes there, s narrows to it, q goes back")
                        (loop))))))
           (lambda ()
             (hashtable-delete! *buffer-faces* *org-headings-buffer*)
             (select-buffer origin)
             (kill-buffer *org-headings-buffer*)))
          (if (not choice)
              (begin (goto-char here) (clear-message-line))
              (let* ((heading (list-ref headings choice)) (start (cadr heading)))
                ;; the heading must be shown: outside the narrowed part, widen
                (when (and (narrowed?) (or (< start (fe-narrow-start)) (> start (fe-narrow-end))))
                  (fe-widen))
                (goto-char start)
                (if narrow
                    (org-narrow-to-subtree)
                    (begin (set-window-start start) (message (caddr heading))))))))))
