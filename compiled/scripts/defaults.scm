;;;; defaults.scm -- the user functions and key bindings from init.lsp
;;;;
;;;; In Chez Scheme, compiled by Schemer: the port of scheme/defaults.scm.  In FemtoEmacs these lived in
;;;; ~/init.lsp.  ~/.chezemax/init.scm is loaded afterwards and overrides
;;;; what is here.

(define (current-line-text)
  "The text of the line the cursor is on, without moving the cursor."
  (buffer-substring (line-start) (line-end)))

(define (read-string string)
  "Read a Scheme object from STRING: (read-string \"(2016 8 31)\") => (2016 8 31)"
  (read (open-input-string string)))

;;; ------------------------------------------------------------------
;;; Dates
;;; ------------------------------------------------------------------

(define (weekday n)
  (case n
    ((0) "Sunday") ((1) "Monday") ((2) "Tuesday") ((3) "Wednesday")
    ((4) "Thursday") ((5) "Friday") ((6) "Saturday") (else "unknown")))

(define (what-day ymd)
  "(what-day '(2016 9 3)) => \"Saturday\"   (Zeller-style congruence)"
  (let* ((y (car ymd)) (m (cadr ymd)) (d (caddr ymd))
         (ax (floor-quotient (- 14 m) 12))
         (mm (+ m (* 12 ax) -2))
         (yy (- y ax)))
    (weekday (modulo (+ yy
                        (floor-quotient (- (* 13 mm) 1) 5)
                        (floor-quotient yy 4)
                        (- (floor-quotient yy 100))
                        (floor-quotient yy 400)
                        d)
                     7))))

(defcommand (insert-day)
  "C-c z: replace a region holding (y m d) with the name of that day."
  (let ((region (cut-region)))
    (guard (e (#t (insert region)
                  (message "insert-day: the region must contain a date such as (2016 9 3)")))
      (insert (what-day (read-string region))))))

;;; ------------------------------------------------------------------
;;; HTML helpers
;;; ------------------------------------------------------------------

(defcommand (html-p) (insert "<p> </p>") (backward-char 5))                          ; C-c a
(defcommand (html-h1) (beginning-of-line) (insert "<h1> </h1>") (beginning-of-line) (forward-char 4)) ; C-c b
(defcommand (html-pp) (end-of-line) (insert "<p>-" (get-clipboard) "-</p>"))          ; C-c c

;;; ------------------------------------------------------------------
;;; Indentation and case
;;; ------------------------------------------------------------------

(defcommand (indent-two) (insert "  "))                 ; C-x >
(defcommand (deindent-two) (backward-delete-char 2))    ; C-x <

(define (transform-region f)
  (if (not (mark))
      (message "No mark set")
      (let* ((a (min (mark) (point))) (b (max (mark) (point)))
             (new (f (buffer-substring a b))))
        (fe-delete-region a b)
        (goto-char a)
        (insert new)
        (push-mark a)
        (clear-message-line))))

(defcommand (upcase-region) (transform-region string-upcase))       ; C-x C-u
(defcommand (downcase-region) (transform-region string-downcase))   ; C-x C-l

;;; ------------------------------------------------------------------
;;; C-x C-e: evaluate the Scheme expression before the cursor
;;; ------------------------------------------------------------------

(define (sexp-before text end)
  "Start index of the expression that ends just before END in TEXT (a
bytevector), or #f.  Strings, ; comments and #\\ characters are skipped while
matching parentheses."
  (let ((i (let loop ((i end)) (if (and (> i 0) (memv (b@ text (- i 1)) '(32 9 10 13))) (loop (- i 1)) i))))
    (cond
      ((= i 0) #f)
      ((memv (b@ text (- i 1)) '(41 93))
       ;; a list: scan forward from the start, pairing parentheses
       (let ((stop i))
         (let loop ((k 0) (stack '()) (start #f))
           (if (>= k stop)
               ;; include a quote or #' in front of the list
               (and start
                    (let back ((s start))
                      (if (and (> s 0) (memv (b@ text (- s 1)) '(39 96 44 35))) (back (- s 1)) s)))
               (let ((b (b@ text k)))
                 (cond ((= b 59) (loop (or (byte-position text 10 k stop) stop) stack start))
                       ((= b 34)
                        (let s ((k (+ k 1)))
                          (if (and (< k stop) (not (= (b@ text k) 34)))
                              (s (+ k (if (= (b@ text k) 92) 2 1)))
                              (loop (+ k 1) stack start))))
                       ((and (= b 35) (< (+ k 1) stop) (= (b@ text (+ k 1)) 92)) (loop (+ k 3) stack start))
                       ((memv b '(40 91)) (loop (+ k 1) (cons k stack) start))
                       ((memv b '(41 93))
                        (let ((open (and (pair? stack) (car stack))))
                          (loop (+ k 1) (if (pair? stack) (cdr stack) stack)
                                (if (= k (- stop 1)) open start))))
                       (else (loop (+ k 1) stack start))))))))
      (else
       ;; an atom
       (let loop ((j i))
         (if (and (> j 0) (not (memv (b@ text (- j 1)) '(32 9 10 13 40 41 91 93 34 59))))
             (loop (- j 1))
             j))))))

(defcommand (eval-last-sexp)
  "C-x C-e: evaluate the expression before the cursor; its value goes to
the message line."
  (let* ((end (point))
         (from (max 0 (- end 65536)))
         (text (buffer-bytes from end))
         (start (sexp-before text (blen text))))
    (if (not start)
        (message "No expression before the cursor")
        (message (eval-for-message (bytes->string text start (blen text)))))))

;;; ------------------------------------------------------------------
;;; Copy on select.  In a terminal, Chezemax takes the mouse, and the
;;; terminal no longer selects text itself; so a mouse drag copies what it
;;; selects to the system clipboard at once, as many terminals do.  The kill
;;; ring does not change until C-y takes it in.
;;; ------------------------------------------------------------------

(defvar *copy-on-select* #t)

(define (copy-on-select)
  (let ((m (mark)) (p (point)))
    (when (and *copy-on-select* m (not (= m p)))
      (let ((text (buffer-substring (min m p) (max m p))))
        (set-system-clipboard text)
        (message "Copied " (plural (string-length text) "character")
                 " to the clipboard: Cmd-V (Ctrl-V) pastes it elsewhere, C-y here"))))
  #f)

(add-hook! '*select-hook* 'copy-on-select)

;;; ------------------------------------------------------------------
;;; File name completion: TAB in the prompts of C-x C-f, C-x i, C-x C-w.
;;; * and ? are wild cards; ~/ is the home folder.  Hidden names are offered
;;; only when what was typed starts with a dot.
;;; ------------------------------------------------------------------

(define *completion-limit* 500)

;; case matters in file names on Linux, not on macOS
(define *case-insensitive-file-names* (path.exists? "/System/Library/CoreServices"))

(define (char-equal-for-files a b)
  (if *case-insensitive-file-names* (char-ci=? a b) (char=? a b)))

(define (wild-match-at pattern name p n)
  "Does PATTERN (a list of characters) from P match NAME from N?"
  (cond ((null? pattern) (null? name))
        ((char=? (car pattern) #\*)
         (let loop ((rest name))
           (or (wild-match-at (cdr pattern) rest p n)
               (and (pair? rest) (loop (cdr rest))))))
        ((null? name) #f)
        ((or (char=? (car pattern) #\?) (char-equal-for-files (car pattern) (car name)))
         (wild-match-at (cdr pattern) (cdr name) p n))
        (else #f)))

(define (file-name-matches-p typed name)
  "Does the file NAME complete TYPED (a prefix, or a pattern with * or ?)?"
  (if (or (string-index typed #\*) (string-index typed #\?))
      (wild-match-at (string->list typed) (string->list name) 0 0)
      (let ((tl (string->list typed)) (nl (string->list name)))
        (let loop ((tl tl) (nl nl))
          (cond ((null? tl) #t)
                ((null? nl) #f)
                ((char-equal-for-files (car tl) (car nl)) (loop (cdr tl) (cdr nl)))
                (else #f))))))

(define file-name-completions
  (case-lambda
    ((typed) (file-name-completions typed #f))
    ((typed default-directory)
     "The names that complete TYPED, as typed (with its folder part), sorted;
a folder ends in /."
     (let* ((cut (string-index-right typed #\/))
            (folder (if cut (substring typed 0 (+ cut 1)) ""))
            (stem (if cut (substring typed (+ cut 1) (string-length typed)) typed))
            (base (or default-directory "."))
            (real (cond ((starts-with-p "~/" folder) (concat (home-directory) "/" (substring folder 2 (string-length folder))))
                        ((string=? folder "") base)
                        ((starts-with-p "/" folder) folder)
                        (else (concat base "/" folder))))
            (entries (guard (e (#t '())) (directory-files real)))
            (names (filter-map
                    (lambda (entry)
                      (and (not (member entry '("." "..")))
                           (or (not (string-prefix? "." entry))
                               (string-prefix? "." stem))
                           (file-name-matches-p stem entry)
                           (string-append folder entry
                                          (if (directory-p (concat real "/" entry)) "/" ""))))
                    entries))
            (sorted (sort string<? names)))
       (if (> (length sorted) *completion-limit*) (list-head sorted *completion-limit*) sorted)))))

;;; ------------------------------------------------------------------
;;; Key bindings
;;; ------------------------------------------------------------------

(global-set-key "C-x C-b" 'buffer-menu)
(global-set-key "C-x C-d" 'dired)
(global-set-key "C-x C-u" 'upcase-region)
(global-set-key "C-x C-l" 'downcase-region)
(global-set-key "C-x C-g" 'grep-command)
(global-set-key "C-x !"   'next-grep)

(global-set-key "C-c a" 'html-p)
(global-set-key "C-c b" 'html-h1)
(global-set-key "C-c c" 'html-pp)
(global-set-key "C-c i" 'insert-kill-ring)
(global-set-key "C-c k" 'kill-ring-menu)
(global-set-key "C-c z" 'insert-day)

(global-set-key "C-x C-r" 'reload-scripts)
(global-set-key "C-x C-e" 'eval-last-sexp)
(global-set-key "C-x C-i" 'indent-region)

(global-set-key "C-x >" 'indent-two)
(global-set-key "C-x <" 'deindent-two)

(defcommand (enlarge-window-command) (execute-builtin "enlarge-window"))

(global-set-key "C-^" 'enlarge-window-command)
(global-set-key "C-\\" 'enlarge-window-command)
