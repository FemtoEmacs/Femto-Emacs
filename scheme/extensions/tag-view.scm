;;;; tag-view.scm -- html-mode and latex-mode; showing and hiding the tags
;;;;
;;;;   M-x html-mode    colour this file as HTML, whatever its name
;;;;   M-x latex-mode   colour this file as LaTeX, whatever its name
;;;;   C-c TAB          hide the HTML tags; again, show them
;;;;   C-c l            hide the LaTeX commands; again, show them
;;;;
;;;; The view is in read mode, as after C-x C-q: nvim's keys move (h j k l,
;;;; w b e, Enter, gg G, C-d C-u, / ? n N), yy and v...y copy, and i (or a,
;;;; C-x C-q) returns to the file, to edit it there.
;;;;
;;;; Hiding shows the text in the same window, in a read-only buffer,
;;;; *tags-hidden*, with the cursor where it was in the text; the file is
;;;; not changed.  The text keeps the colours it has in the file: titles,
;;;; emphasis, links and math look as they do with the tags.  The same key returns to the file, with the cursor at the
;;;; place it had in the text.  To edit, return to the file: the hidden view
;;;; is made again from the file each time.

(define *tag-view-buffer* "*tags-hidden*")
(defvar *tag-view-origin* #f)     ; the buffer whose tags are hidden
(defvar *tag-view-pieces* '())    ; how the view maps back to it

;;; ------------------------------------------------------------------
;;; Writing the view, and remembering where each piece came from
;;; ------------------------------------------------------------------

;; a view being written: #(output length pieces tail).  A piece is
;; #(view-start source-start length copied? face): COPIED pieces are text of
;; the file, in its colours; the others stand for something taken away (a
;; tag, an entity), in FACE, or in the colour of the text before them.
(define (make-tag-view) (vector (buffer) 0 '() ""))

(define (tag-view-push out s src copied (face #f))
  (let ((n (length s)))
    (when (> n 0)
      (io.write (vector-ref out 0) s)
      (vector-set! out 2 (cons (vector (vector-ref out 1) src n copied face) (vector-ref out 2)))
      (vector-set! out 1 (+ (vector-ref out 1) n))
      (let ((tail (string-append (vector-ref out 3) s)))
        (vector-set! out 3 (byte-substring tail (max 0 (- (length tail) 2))))))))

(define (tag-view-copy out text from to)
  "Copy TEXT[FROM, TO) of the file into the view.  Blanks at the very start
of the view are left out, and so is text made only of blanks (the line
breaks between tags) right after a line break: tags already gave one."
  (let* ((blank? (lambda (i) (memv (aref text i) '(32 9 10 13))))
         (from (if (= (vector-ref out 1) 0)
                   (let skip ((i from)) (if (and (< i to) (blank? i)) (skip (+ i 1)) i))
                   from))
         (all-blank (let check ((i from)) (or (>= i to) (and (blank? i) (check (+ i 1))))))
         (after-break (string-suffix? "\n" (vector-ref out 3))))
    (when (and (> to from) (not (and all-blank after-break)))
      (tag-view-push out (byte-substring text from to) from #t))))

(define (tag-view-emit out s src (face #f))
  "Write S, which stands for what was at SRC in the file, in FACE (#f: the
colour of the text before it).  A line break is dropped at the start, and
after two others, so tags never make more than one blank line."
  (if (string=? s "\n")
      (unless (or (= (vector-ref out 1) 0) (string=? (vector-ref out 3) "\n\n"))
        (tag-view-push out s src #f +symbol+))
      (tag-view-push out s src #f face)))

(define (tag-view-text out) (io.tostring! (vector-ref out 0)))
(define (tag-view-piece-list out) (reverse (vector-ref out 2)))

(define (tag-view-source->view pieces p)
  "The place in the view of the file's byte P."
  (let loop ((ps pieces) (best 0))
    (if (null? ps) best
        (let* ((pc (car ps)) (v (vector-ref pc 0)) (s (vector-ref pc 1)) (n (vector-ref pc 2)))
          (if (> s p) best
              (loop (cdr ps) (if (and (vector-ref pc 3) (< p (+ s n))) (+ v (- p s)) (+ v n))))))))

(define (tag-view-view->source pieces v)
  "The place in the file of the view's byte V."
  (let loop ((ps pieces) (best 0))
    (if (null? ps) best
        (let* ((pc (car ps)) (vs (vector-ref pc 0)) (s (vector-ref pc 1)) (n (vector-ref pc 2)))
          (if (> vs v) best
              (loop (cdr ps) (if (vector-ref pc 3) (+ s (min (- v vs) n)) s)))))))

(define (tags-hidden text strip)
  "TEXT through STRIP (HTML-STRIP or LATEX-STRIP): the text, and its pieces."
  (let ((out (make-tag-view)))
    (strip text out)
    (values (tag-view-text out) (tag-view-piece-list out))))

(define (tag-view-faces pieces view-length source-faces)
  "The faces of the view: each copied piece in the colours it has in the
file (SOURCE-FACES), the rest in their own face or the colour before them."
  (let ((faces (make-colors view-length)) (last +alpha+))
    (for-each
     (lambda (pc)
       (let ((v (vector-ref pc 0)) (s (vector-ref pc 1)) (n (vector-ref pc 2)))
         (if (vector-ref pc 3)
             (do ((k 0 (+ k 1))) ((= k n))
               (let ((f (aref source-faces (+ s k))))
                 (aset! faces (+ v k) f)
                 (unless (memv f (list +symbol+ +comment+)) (set! last f))))
             (let ((f (or (vector-ref pc 4) last)))
               (do ((k 0 (+ k 1))) ((= k n)) (aset! faces (+ v k) f))))))
     pieces)
    faces))

;;; ------------------------------------------------------------------
;;; The commands
;;; ------------------------------------------------------------------

(define (tag-view-p) (string=? (get-buffer-name) *tag-view-buffer*))

(define (tag-view-leave)
  "i (and a, C-x C-q ...) in the view: back to the file, to edit it there."
  (if (and *tag-view-origin* (member *tag-view-origin* (buffer-names)))
      (begin (show-tags) (message "Back in the file, at the same place: edit it here"))
      (message "The file of this view is closed")))

(define (show-tags)
  "Back from the view to the file, at the place the cursor had."
  (let ((target (tag-view-view->source *tag-view-pieces* (point)))
        (origin *tag-view-origin*))
    (select-buffer origin)
    (goto-char (min target (buffer-size)))
    (message "Tags shown")))

(define (hide-tags what strip key language)
  (let* ((origin (get-buffer-name))
         (p (point))
         (text (buffer-substring 0 (buffer-size)))
         (source-faces (make-colors (length text))))
    ;; the file's colours, as LANGUAGE (whatever the file's name): the view
    ;; keeps them, so a title is still a title
    (highlight-octets (find-language language) text (length text) source-faces)
    (let-values (((view pieces) (tags-hidden text strip)))
      (set! *tag-view-origin* origin)
      (set! *tag-view-pieces* pieces)
      (put! *buffer-faces* *tag-view-buffer* (tag-view-faces pieces (length view) source-faces))
      (select-buffer *tag-view-buffer*)
      (set-buffer-read-only! #f)
      (erase-buffer)
      (insert view)
      (set-buffer-read-only! #t)
      (fe-set-modified 0)
      (goto-char (min (tag-view-source->view pieces p) (buffer-size)))
      ;; nvim's keys move, as in read-only: hjkl, w b e, Enter, gg G, / n ...
      (enter-normal-mode 'read)
      (set-buffer-hint *tag-view-buffer* (concat key " shows the " what))
      (message "The " what " of " origin " are hidden: nvim's keys move; " key " or i returns to the file"))))

(define (toggle-tags what strip key language)
  (cond ((not (string=? (get-buffer-name) *tag-view-buffer*)) (hide-tags what strip key language))
        ((and *tag-view-origin* (member *tag-view-origin* (buffer-names))) (show-tags))
        (else (message "The file of this view is closed"))))

(defcommand (html-toggle-tags)
  "C-c TAB: hide the HTML tags of this file (read-only view); again, show them."
  (toggle-tags "HTML tags" html-strip "C-c TAB" "HTML"))

(defcommand (latex-toggle-tags)
  "C-c l: hide the LaTeX commands of this file (read-only view); again, show them."
  (toggle-tags "LaTeX commands" latex-strip "C-c l" "TeX"))

(define (set-file-language name)
  (let ((file (buffer-filename)))
    (if (not file)
        (message "Save the buffer in a file first (C-x C-w); then M-x " (string-downcase name) "-mode")
        (begin
          (put! *language-overrides* file name)
          (update-display)
          (message (if (string=? name "TeX") "LaTeX" name) " colours for " (get-buffer-name))))))

(defcommand (html-mode)
  "Colour this file as HTML, whatever its name.  C-c TAB hides the tags."
  (set-file-language "HTML"))

(defcommand (latex-mode)
  "Colour this file as LaTeX, whatever its name.  C-c l hides the commands."
  (set-file-language "TeX"))

(global-set-key "C-c TAB" 'html-toggle-tags)
(global-set-key "C-c l" 'latex-toggle-tags)
