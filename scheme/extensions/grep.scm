;;;; grep.scm -- C-x C-g and C-x !
;;;;
;;;; Port of SBEmacs's lisp/extensions/grep.lisp: the search runs in Scheme
;;;; (case-insensitively), so it needs no grep program.
;;;;
;;;; C-x C-g  prompts for a string and a list of wildcards ("*.c *.h"), and
;;;;          shows the matches in *grep* as file:line:text
;;;; C-x !    visits the next match

(defvar *grep-search-string* "")
(defvar *grep-filespec* "*.c *.h *.scm *.lisp")
(define *grep-buffer* "*grep*")
(defvar *grep-results* (vector))   ; #(file line text) ...
(defvar *grep-index* -1)

(define (grep-files filespec)
  "The files matching the space-separated wildcards of FILESPEC."
  (delete-duplicates
   (apply append
          (map (lambda (pattern)
                 (filter (lambda (f) (let ((i (file-attributes f))) (and i (not (car i)))))
                         (map (lambda (name) (absolute-path name))
                              (map (lambda (c) (if (ends-with-p "/" c) (byte-substring c 0 (- (length c) 1)) c))
                                   (file-name-completions pattern)))))
               (filter (lambda (w) (> (length w) 0)) (string-split filespec " "))))))

(define (grep-file file needle)
  (let ((text (file-contents file))
        (lower (string-downcase needle)))
    (if (not text) '()
        (let loop ((lines (split-lines text)) (n 1) (acc '()))
          (if (null? lines) (reverse acc)
              (loop (cdr lines) (+ n 1)
                    (if (string-search lower (string-downcase (car lines)))
                        (cons (vector file n (remove-byte (car lines) 13)) acc)
                        acc)))))))

(define (relative-name file)
  (let ((here (string-append (path.cwd) "/")))
    (if (starts-with-p here file) (byte-substring file (length here)) file)))

(defcommand (grep-command)
  "C-x C-g: search files for a string."
  (set! *grep-search-string* (prompt "grep search for : " *grep-search-string*))
  (unless (string=? *grep-search-string* "")
    (set! *grep-filespec* (prompt "search in files : " *grep-filespec*))
    (set! *grep-results*
          (list->vector (apply append (map (lambda (f) (grep-file f *grep-search-string*))
                                           (grep-files *grep-filespec*)))))
    (set! *grep-index* -1)
    (kill-buffer *grep-buffer*)
    (select-buffer *grep-buffer*)
    (do ((i 0 (+ i 1))) ((= i (vector-length *grep-results*)))
      (let ((r (vector-ref *grep-results* i)))
        (insert (relative-name (vector-ref r 0)) ":" (vector-ref r 1) ":" (vector-ref r 2) "\n")))
    (fe-set-modified 0)
    (beginning-of-buffer)
    (let ((n (vector-length *grep-results*)))
      (message n (if (= n 1) " match" " matches") " for \"" *grep-search-string* "\" -- C-x ! visits the next one"))
    (update-display)))

(defcommand (next-grep)
  "C-x !: visit the next match of C-x C-g."
  (if (= 0 (vector-length *grep-results*))
      (message "no grep results; use C-x C-g first")
      (begin
        (set! *grep-index* (modulo (+ *grep-index* 1) (vector-length *grep-results*)))
        (let ((r (vector-ref *grep-results* *grep-index*)))
          (find-file (relative-name (vector-ref r 0)))
          (goto-line (vector-ref r 1))
          (message "match " (+ *grep-index* 1) " of " (vector-length *grep-results*))))))
