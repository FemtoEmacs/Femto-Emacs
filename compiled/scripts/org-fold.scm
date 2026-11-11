;;;; org-fold.scm -- folding headings with TAB (a module of org.scm)
;;;;
;;;; TAB on a heading line cycles its subtree, as Emacs's org-cycle does:
;;;;
;;;;   FOLDED    the heading alone, "..." at its end
;;;;   CHILDREN  its text and the headings just under it, each folded
;;;;   SUBTREE   everything under it
;;;;
;;;; FOLDED -> CHILDREN -> SUBTREE -> FOLDED; a heading without headings
;;;; under it goes FOLDED -> SUBTREE; one with nothing under it says
;;;; "EMPTY ENTRY".  TAB elsewhere does what it did.  As in Emacs, a
;;;; heading that is not folded folds, unless the key just before was TAB
;;;; on it, showing its children: then all of it shows.  Emacs's own
;;;; org-cycle is the oracle of tests/org-fold.sh: the same file, the same
;;;; TABs, the same lines shown.
;;;;
;;;; The hiding is the C core's (src/fold.c): the cursor steps over folded
;;;; text; a search or a jump into it opens it; typing in it opens it.
;;;;
;;;; Moving between headings (Emacs's keys; folded ones are skipped):
;;;;   C-c C-n  the next heading       C-c C-p  the previous heading
;;;;   C-c C-f  the next of this level C-c C-b  the previous of this level
;;;;   C-c C-u  the heading above this one (its parent)

(define (org-fold-range text ls)
  "For the heading at LS: (a . b), the bytes TAB hides -- from the newline
ending the heading line to the newline before the next heading of its
level or above (or the end of the text); #f when nothing is under it."
  (let* ((le (org-line-end text ls))
         (b (- (cdr (org-subtree text ls)) 1)))
    (and (< le (blen text)) (> b le) (cons le b))))

(define (org-direct-children text ls)
  "The line starts of the headings just under the heading at LS: those
with only deeper headings between them and it."
  (let* ((end (cdr (org-subtree text ls)))
         (under (let loop ((p (min (blen text) (+ (org-line-end text ls) 1))) (out '()))
                  (if (>= p end) (reverse out)
                      (let ((l (org-heading-level text p (org-line-end text p))))
                        (loop (min (blen text) (+ (org-line-end text p) 1))
                              (if l (cons (cons l p) out) out))))))
         (children (let loop ((hs under) (lowest 1000) (out '()))
                     ;; a heading is a child when every heading between it
                     ;; and this one is deeper: under * Top, *** Deep then
                     ;; ** Mid are both children, as Emacs shows them
                     (cond ((null? hs) (reverse out))
                           ((< (caar hs) lowest) (loop (cdr hs) (caar hs) (cons (cdar hs) out)))
                           ((= (caar hs) lowest) (loop (cdr hs) lowest (cons (cdar hs) out)))
                           (else (loop (cdr hs) lowest out))))))
    children))

(define (org-fold! range) (fe-fold (car range) (cdr range)))
(define (org-unfold-all! range) (fe-unfold (car range) (cdr range)))
(define (org-folded? range) (= (fe-folded-at (car range)) (cdr range)))

;;; The last TAB that showed a heading's children: (buffer heading-end key
;;; point size), where KEY is the last bound key seen (*this-key*, which a
;;; TAB, being typed text, does not change).  It still holds when nothing
;;; but TAB came since: then TAB shows the whole subtree, as Emacs's
;;; org-cycle does when the command before it was org-cycle.
(define *org-cycle-children* #f)

(define (org-cycle-stamp a)
  (list (get-buffer-name) a *this-key* (point) (buffer-size)))

(define (org-cycle)
  "TAB on a heading: FOLDED -> CHILDREN -> SUBTREE -> FOLDED."
  (let* ((text (org-buffer-bytes))
         (ls (org-line-start text (point)))
         (range (org-fold-range text ls)))
    (if (not range)
        (begin (set! *org-cycle-children* #f) (message "EMPTY ENTRY"))
        (let* ((children (org-direct-children text ls))
               (child-ranges (filter (lambda (r) r) (map (lambda (c) (org-fold-range text c)) children)))
               (after-children (equal? *org-cycle-children* (org-cycle-stamp (car range)))))
          (set! *org-cycle-children* #f)
          (cond
           ;; FOLDED -> CHILDREN, or SUBTREE when there are no headings under it
           ((org-folded? range)
            (org-unfold-all! range)
            (if (null? children)
                (message "SUBTREE (NO CHILDREN)")
                (begin (for-each org-fold! child-ranges)
                       (set! *org-cycle-children* (org-cycle-stamp (car range)))
                       (message "CHILDREN"))))
           ;; CHILDREN, just shown by the TAB before -> SUBTREE
           (after-children
            (org-unfold-all! range)
            (message "SUBTREE"))
           ;; anything else -> FOLDED
           (else
            (org-unfold-all! range)
            (org-fold! range)
            (message "FOLDED")))
          (update-display)))))

(define (org-visible-outline)
  "For tests, as Emacs shows the buffer: its lines shown, joined by |, a
folded heading's ending in ...  (tests/org-fold.sh)"
  (let ((text (org-buffer-bytes)))
    (let loop ((ls 0) (out '()))
      (if (>= ls (blen text)) (string-join (reverse out) "|")
          (let ((le (org-line-end text ls)))
            (loop (+ le 1)
                  (if (= 1 (fe-hidden-p ls)) out
                      (cons (string-append (bytes->string text ls le)
                                           (if (and (< le (blen text)) (>= (fe-folded-at le) 0)) "..." ""))
                            out))))))))

(define (org-tab-key key)
  "*self-insert-hook*: TAB on a heading line of an Org buffer folds."
  (and (string=? key "\t") (org-buffer-p)
       (let ((text (org-buffer-bytes)))
         (let ((ls (org-line-start text (point))))
           (and (org-heading-level text ls (org-line-end text ls))
                (begin (org-cycle) #t))))))

;;; ------------------------------------------------------------------
;;; Moving between headings
;;; ------------------------------------------------------------------

(define (org-visible-headings text)
  "The headings shown (not inside folded text): ((level start title) ...)."
  (filter (lambda (h) (not (= 1 (fe-hidden-p (cadr h))))) (org-headings text)))

(define (org-current-heading text p)
  "The start of the heading at or above P, or #f."
  (let up ((ls (org-line-start text p)))
    (cond ((org-heading-level text ls (org-line-end text ls)) ls)
          ((<= ls 0) #f)
          (else (up (org-line-start text (- ls 1)))))))

(define (org-go heading what)
  (if heading
      (goto-char (cadr heading))
      (message "No " what " heading")))

(define (org-next-heading)
  "C-c C-n: the next heading shown."
  (let* ((text (org-buffer-bytes)) (le (org-line-end text (point))))
    (org-go (find (lambda (h) (> (cadr h) le)) (org-visible-headings text)) "next")))

(define (org-previous-heading)
  "C-c C-p: the previous heading shown."
  (let* ((text (org-buffer-bytes)) (ls (org-line-start text (point))))
    (org-go (find (lambda (h) (< (cadr h) ls)) (reverse (org-visible-headings text))) "previous")))

(define (org-same-level direction)
  "C-c C-f (1) / C-c C-b (-1): the next or previous heading of this one's
level under the same parent."
  (let* ((text (org-buffer-bytes))
         (here (org-current-heading text (point)))
         (level (and here (org-heading-level text here (org-line-end text here))))
         (hs (org-visible-headings text))
         (hs (if (> direction 0) (filter (lambda (h) (> (cadr h) here)) (or (and here hs) '()))
                 (reverse (filter (lambda (h) (< (cadr h) here)) (or (and here hs) '()))))))
    (if (not here) (message "Not under a heading")
        (let loop ((hs hs))
          (cond ((null? hs) (message "No " (if (> direction 0) "next" "previous") " heading at this level"))
                ((< (car (car hs)) level) (message "No " (if (> direction 0) "next" "previous") " heading at this level"))
                ((= (car (car hs)) level) (goto-char (cadr (car hs))))
                (else (loop (cdr hs))))))))

(define (org-forward-same-level) (org-same-level 1))
(define (org-backward-same-level) (org-same-level -1))

(define (org-up-heading)
  "C-c C-u: the heading above this one."
  (let* ((text (org-buffer-bytes))
         (here (org-current-heading text (point)))
         (level (and here (org-heading-level text here (org-line-end text here)))))
    (if (not here) (message "Not under a heading")
        (org-go (find (lambda (h) (and (< (cadr h) here) (< (car h) level)))
                      (reverse (org-headings text)))
                "parent"))))
