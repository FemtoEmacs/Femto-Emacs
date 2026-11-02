;;;; dired.scm -- C-x C-d (and C-x d), a small directory editor
;;;;
;;;; Port of SBEmacs's lisp/extensions/dired.lisp.
;;;;
;;;;   up/down   move           f or RET  open file / enter directory
;;;;   u         parent dir     g         re-read the directory
;;;;   x or q    exit

(defvar *dired-directory* #f)
(define *dired-header-lines* 3)
(define *dired-max-ops* 5000)
(define *dired-entries* (vector))   ; (name . directory?) in line order
(define *dired-index* 0)

(define (strip-trailing-slash d)
  (if (and (> (length d) 1) (= (aref d (- (length d) 1)) 47)) (byte-substring d 0 (- (length d) 1)) d))

(define (parent-directory dir)
  (let* ((d (strip-trailing-slash dir))
         (slash (byte-position-back d 47)))
    (cond ((not slash) dir)
          ((= slash 0) "/")
          (else (byte-substring d 0 slash)))))

(define (join-path dir name)
  (if (and (> (length dir) 0) (= (aref dir (- (length dir) 1)) 47)) (string-append dir name) (string-append dir "/" name)))

(define (list-directory dir)
  "(name directory? size mtime) for each entry, directories first."
  (let* ((names (filter (lambda (n) (not (member n '("." "..")))) (guard (e (#t '())) (directory-files dir))))
         (entries (map (lambda (n)
                         (let ((info (file-attributes (join-path dir n))))
                           (list n (and info (car info)) (and info (cadr info)) (and info (caddr info)))))
                       names)))
    (sort entries (lambda (a b)
                    (if (eq? (cadr a) (cadr b))
                        (string<? (car a) (car b))
                        (and (cadr a) #t))))))

(define (dired-line e)
  (let ((dirp (cadr e)))
    (string-append "  " (if dirp "d" " ") " "
                   (pad-left (if dirp "" (if (caddr e) (number->string (caddr e)) "?")) 10)
                   "  " (if (cadddr e) (format-time (cadddr e)) (make-spaces 16))
                   "  " (car e) (if dirp "/" "") "\n")))

(define (dired-fill)
  (kill-buffer "*dired*")
  (select-buffer "*dired*")
  (let* ((parent (parent-directory *dired-directory*))
         (has-parent (not (string=? parent *dired-directory*)))
         (entries (list-directory *dired-directory*)))
    (set! *dired-entries* (list->vector (append (if has-parent (list (list ".." #t #f #f)) '()) entries)))
    (insert "  " *dired-directory* "\n  " (vector-length *dired-entries*) " entries\n\n")
    (do ((i 0 (+ i 1))) ((= i (vector-length *dired-entries*)))
      (let ((e (vector-ref *dired-entries* i)))
        (insert (if (and has-parent (= i 0))
                    (string-append "  d " (make-spaces 10) "  " (make-spaces 16) "  ../\n")
                    (dired-line e))))))
  (fe-set-modified 0)
  (set! *dired-index* (min *dired-index* (max 0 (- (vector-length *dired-entries*) 1))))
  (dired-goto))

(define (dired-goto)
  (goto-line (+ *dired-index* *dired-header-lines* 1))
  (end-of-line))

(define (dired-move n)
  (set! *dired-index* (max 0 (min (+ *dired-index* n) (- (vector-length *dired-entries*) 1))))
  (dired-goto))

(define (dired-open)
  "#t when dired should exit (a file was opened)."
  (and (> (vector-length *dired-entries*) 0)
       (let ((e (vector-ref *dired-entries* *dired-index*)))
         (cond ((string=? (car e) "..")
                (set! *dired-directory* (parent-directory *dired-directory*))
                (set! *dired-index* 0) (dired-fill) #f)
               ((cadr e)
                (set! *dired-directory* (join-path *dired-directory* (car e)))
                (set! *dired-index* 0) (dired-fill) #f)
               (else
                (kill-buffer "*dired*")
                (find-file (join-path *dired-directory* (car e)))
                #t)))))

(define (dired-start-directory)
  (let ((file (buffer-filename)))
    (or (and file (let ((d (file-name-directory (absolute-path file)))) (and (> (length d) 0) (strip-trailing-slash d))))
        *dired-directory*
        (path.cwd))))

(defcommand (dired)
  "C-x C-d: browse a directory; RET opens a file or enters a folder."
  (let ((original (get-buffer-name)))
    (set! *dired-directory* (let ((d (dired-start-directory))) (or (real-path d) d)))
    (set! *dired-index* 0)
    (delete-other-windows)
    (dired-fill)
    (let loop ((n 0))
      (when (< n *dired-max-ops*)
        (message "dired: f/RET open, u up, g refresh, x exit")
        (update-display)
        (let ((key (get-key)))
          (cond ((string=? key "")
                 (let ((b (get-key-binding)))
                   (cond ((string=? b "previous-line") (dired-move -1))
                         ((string=? b "next-line") (dired-move 1))
                         ((string=? b "forward-page") (dired-move 10))
                         ((string=? b "backward-page") (dired-move -10))))
                 (loop (+ n 1)))
                ((member key '("f" "o" "\r" "\n"))
                 (unless (dired-open) (loop (+ n 1))))
                ((string=? key "u")
                 (set! *dired-directory* (parent-directory *dired-directory*))
                 (set! *dired-index* 0)
                 (dired-fill)
                 (loop (+ n 1)))
                ((string=? key "g") (dired-fill) (loop (+ n 1)))
                ((member key '("x" "q"))
                 (kill-buffer "*dired*")
                 (select-buffer original))
                (else (loop (+ n 1)))))))
    (clear-message-line)
    (update-display)))
