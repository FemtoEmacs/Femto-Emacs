;;;; org-babel.scm -- tangling, Org's C-c C-v t (a module of org.scm)
;;;;
;;;;   #+BEGIN_SRC scheme :tangle fib.scm
;;;;   (define (fib n) ...)
;;;;   #+END_SRC
;;;;
;;;; C-c C-v t (or C-c C-v C-t) writes the code of every #+BEGIN_SRC block
;;;; whose header says :tangle FILE to FILE, as Emacs does: the blocks of
;;;; one file in their order, a blank line between them; FILE relative to
;;;; the .org file's folder (~/ is your home); :tangle yes is the .org
;;;; file's name with the language's extension (notes.org, python: notes.py);
;;;; :tangle no, or no :tangle, is not written.  The code is taken from the
;;;; buffer, saved or not; its common indentation is removed, and Org's
;;;; escapes ,* and ,#+ at the start of a line lose their comma.  Only the
;;;; files named are written, and the message says which.

(define *org-tangle-extensions*
  '(("scheme" . "scm") ("emacs-lisp" . "el") ("elisp" . "el") ("lisp" . "lisp")
    ("common-lisp" . "lisp") ("python" . "py") ("c" . "c") ("c++" . "cpp") ("cpp" . "cpp")
    ("sh" . "sh") ("bash" . "sh") ("shell" . "sh") ("nim" . "nim") ("prolog" . "pl")
    ("lean" . "lean") ("haskell" . "hs") ("ocaml" . "ml") ("ruby" . "rb")
    ("javascript" . "js") ("js" . "js") ("latex" . "tex") ("markdown" . "md") ("org" . "org")))

(define (org-words s)
  (filter (lambda (w) (not (string=? w ""))) (string-split (trim s) #\space #\tab)))

(define (org-tangle-target words org-file)
  "From the words after #+BEGIN_SRC (language, then header arguments), the
file to write, or #f."
  (let ((language (if (pair? words) (string-downcase (car words)) ""))
        (value (let loop ((ws words))
                 (cond ((or (null? ws) (null? (cdr ws))) #f)
                       ((string=? (car ws) ":tangle") (cadr ws))
                       (else (loop (cdr ws)))))))
    (cond ((or (not value) (string=? value "no")) #f)
          ((string=? value "yes")
           (let* ((base (file-name-nondirectory org-file))
                  (stem (substring base 0 (- (string-length base) 4)))
                  (ext (let ((e (assoc language *org-tangle-extensions*))) (if e (cdr e) language))))
             (string-append (file-name-directory org-file) stem "." ext)))
          ((starts-with-p "/" value) value)
          ((starts-with-p "~/" value) (absolute-path value))
          (else (string-append (file-name-directory org-file) value)))))

(define (org-unindent lines)
  "LINES without their common indentation and Org's ,* ,#+ escapes."
  (let* ((indent (lambda (l) (let loop ((i 0)) (if (and (< i (string-length l)) (memv (string-ref l i) '(#\space #\tab))) (loop (+ i 1)) i))))
         (common (fold-left min 1000000 (map indent (filter (lambda (l) (not (string=? (trim l) ""))) lines))))
         (common (if (= common 1000000) 0 common)))
    (map (lambda (l)
           (let ((l (if (>= (string-length l) common) (substring l common (string-length l)) "")))
             (if (or (starts-with-p ",*" l) (starts-with-p ",#+" l)) (substring l 1 (string-length l)) l)))
         lines)))

(define (org-tangle-blocks source org-file)
  "The blocks of SOURCE (the buffer's text): ((file . code) ...) in order."
  (let loop ((lines (split-lines source)) (out '()))
    (cond ((null? lines) (reverse out))
          ((starts-with-p "#+BEGIN_SRC" (string-upcase (trim (car lines))))
           (let* ((words (org-words (substring (trim (car lines)) 11 (string-length (trim (car lines))))))
                  (target (org-tangle-target words org-file)))
             (let body ((ls (cdr lines)) (code '()))
               (cond ((null? ls) (reverse out))             ; never closed: not written
                     ((starts-with-p "#+END_SRC" (string-upcase (trim (car ls))))
                      (loop (cdr ls)
                            (if target
                                (cons (cons target (string-append (join-lines (org-unindent (reverse code))) "\n")) out)
                                out)))
                     (else (body (cdr ls) (cons (car ls) code)))))))
          (else (loop (cdr lines) out)))))

(define (org-tangle)
  "C-c C-v t: write the blocks with :tangle FILE to their files."
  (let ((file (buffer-filename)))
    (if (not file)
        (message "Tangle: this buffer has no file")
        (let* ((org-file (absolute-path file))
               (blocks (org-tangle-blocks (buffer-substring 0 (buffer-size)) org-file))
               (files (fold-left (lambda (fs b) (if (member (car b) fs) fs (append fs (list (car b))))) '() blocks)))
          (if (null? files)
              (message "Tangle: no #+BEGIN_SRC block has :tangle FILE")
              (let ((failed '()))
                (for-each
                 (lambda (target)
                   (let ((code (string-join (map cdr (filter (lambda (b) (string=? (car b) target)) blocks)) "\n")))
                     (guard (e (#t (set! failed (cons target failed))))
                       (when (file-exists-p target) (delete-file target))
                       (call-with-output-file target (lambda (p) (write-string code p))))))
                 files)
                (let ((names (map (lambda (f) (if (starts-with-p (file-name-directory org-file) f)
                                                  (substring f (string-length (file-name-directory org-file)) (string-length f))
                                                  f))
                                  files)))
                  (if (null? failed)
                      (message "Tangled " (number->string (length blocks)) " block" (if (= (length blocks) 1) "" "s")
                               " to " (string-join names ", "))
                      (message "Tangle: could not write " (string-join (reverse failed) ", "))))))))))

(org-babel-key! "t" org-tangle)
(org-babel-key! "C-t" org-tangle)
