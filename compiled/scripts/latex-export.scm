;;;; latex-export.scm -- Org and Markdown to LaTeX (M-x latex-export)
;;;;
;;;; M-x latex-export in a .org or .md buffer writes the LaTeX beside the
;;;; file (paper.md -> paper.tex), asking first if that file exists, and
;;;; opens it.  In Org, C-c C-e l l does the same, as in Emacs.  The text is
;;;; for XeLaTeX: fontspec, so Unicode goes
;;;; through as typed; a font with Greek is chosen when the text has Greek,
;;;; kotex when it has Hangul, xeCJK when it has Chinese characters.
;;;;
;;;; What is exported:
;;;;   headings          Org: * ** *** ....  Markdown: # ## ### ....
;;;;                     Org's #+TITLE, #+AUTHOR, #+DATE; in Markdown a
;;;;                     single # heading on the first line is the title
;;;;   paragraphs        with *bold* /italic/ _underline_ =verbatim= ~code~
;;;;                     +strike+ (Org) or **bold** *em* `code` ~~strike~~
;;;;                     (Markdown); links [[url][text]], [text](url),
;;;;                     <url>; images [[file.png]], ![alt](file.png)
;;;;   math              $...$, $$...$$, \(...\), \[...\] and
;;;;                     \begin{...}...\end{...} go through untouched; a $
;;;;                     that does not open math (US$5) is escaped
;;;;   lists             - + * and 1. 1), nested by indentation; Org's
;;;;                     [ ] [X] check boxes and "term :: text" lists
;;;;   code              fenced ``` blocks, #+BEGIN_SRC, #+BEGIN_EXAMPLE and
;;;;                     ": " lines: verbatim
;;;;   quotes            > lines, #+BEGIN_QUOTE; #+BEGIN_CENTER
;;;;   tables            | tables of both (a rule under the first row makes it
;;;;                     the header), and Org's sexp tables, their formulas
;;;;                     computed, the Title: as the caption
;;;;   rules             --- (Markdown), ----- (Org)
;;;;   raw LaTeX         #+LATEX: lines and #+BEGIN_EXPORT latex blocks
;;;; Left out: Org's comments (# ...), drawers (:PROPERTIES: ... :END:),
;;;; other #+ lines and heading tags; Markdown's <!-- comments -->.
;;;;
;;;; Nothing here runs until the command does.

;;; ------------------------------------------------------------------
;;; Text
;;; ------------------------------------------------------------------

(define (lx-escape-char c)
  (case c
    ((#\\) "\\textbackslash{}") ((#\{) "\\{") ((#\}) "\\}") ((#\$) "\\$")
    ((#\&) "\\&") ((#\#) "\\#") ((#\%) "\\%") ((#\_) "\\_")
    ((#\~) "\\textasciitilde{}") ((#\^) "\\textasciicircum{}")
    (else #f)))

(define (lx-escape s)
  "S as LaTeX text: the special characters escaped."
  (let ((p (open-output-string)) (n (string-length s)))
    (let loop ((i 0))
      (when (< i n)
        (let* ((c (string-ref s i)) (e (lx-escape-char c)))
          (if e (display e p) (write-char c p))
          (loop (+ i 1)))))
    (get-output-string p)))

(define (lx-url s)
  "A URL for \\href and \\url: % and # escaped, the rest as written."
  (let ((p (open-output-string)) (n (string-length s)))
    (let loop ((i 0))
      (when (< i n)
        (let ((c (string-ref s i)))
          (when (memv c '(#\% #\#)) (write-char #\\ p))
          (write-char c p)
          (loop (+ i 1)))))
    (get-output-string p)))

(define (lx-image? s)
  (let ((s (string-downcase s)))
    (or (string-suffix? ".png" s) (string-suffix? ".jpg" s) (string-suffix? ".jpeg" s)
        (string-suffix? ".pdf" s) (string-suffix? ".eps" s) (string-suffix? ".svg" s))))

(define (lx-blank-char? c) (memv c '(#\space #\tab #\newline)))

(define (lx-find s what from)
  (string-search-forward what s from))

;; Math: where the math starting at I ends (the index after it), or #f.
;; $x$ opens when the next character is no blank, and closes at a $ after
;; no blank that no digit follows (so US$5 and $5 and $6 stay money).
(define (lx-math-end s i)
  (let ((n (string-length s)))
    (define (at k t) (and (<= (+ k (string-length t)) n) (string=? (substring s k (+ k (string-length t))) t)))
    (cond ((at i "$$") (let ((e (lx-find s "$$" (+ i 2)))) (and e (+ e 2))))
          ((at i "\\(") (let ((e (lx-find s "\\)" (+ i 2)))) (and e (+ e 2))))
          ((at i "\\[") (let ((e (lx-find s "\\]" (+ i 2)))) (and e (+ e 2))))
          ((and (at i "$") (< (+ i 1) n) (not (lx-blank-char? (string-ref s (+ i 1))))
                (not (and (> i 0) (char-numeric? (string-ref s (- i 1))))))
           (let loop ((k (+ i 1)))
             (cond ((>= k n) #f)
                   ((and (char=? (string-ref s k) #\$)
                         (not (lx-blank-char? (string-ref s (- k 1))))
                         (not (and (< (+ k 1) n) (char-numeric? (string-ref s (+ k 1))))))
                    (+ k 1))
                   ((char=? (string-ref s k) #\newline) #f)      ; $x$ stays on its line
                   (else (loop (+ k 1))))))
          (else #f))))

;;; ------------------------------------------------------------------
;;; Inline markup: Markdown
;;; ------------------------------------------------------------------

(define (lx-word-char? c) (or (char-alphabetic? c) (char-numeric? c)))

;; The closing DELIM of emphasis opened at I (DELIM's length L), or #f:
;; after no blank, and for _ not inside a word
(define (lx-md-close s delim from)
  (let ((n (string-length s)) (l (string-length delim)))
    (let loop ((k from))
      (let ((e (lx-find s delim k)))
        (cond ((not e) #f)
              ((and (> e from) (not (lx-blank-char? (string-ref s (- e 1))))
                    (or (not (char=? (string-ref delim 0) #\_))
                        (>= (+ e l) n) (not (lx-word-char? (string-ref s (+ e l)))))
                    ;; ** is not the end of *
                    (or (> l 1) (>= (+ e 1) n) (not (char=? (string-ref s (+ e 1)) (string-ref delim 0)))))
               e)
              (else (loop (+ e 1))))))))

(define (lx-md-inline s)
  "A paragraph's Markdown text as LaTeX."
  (let ((p (open-output-string)) (n (string-length s)))
    (define (at k t) (and (<= (+ k (string-length t)) n) (string=? (substring s k (+ k (string-length t))) t)))
    (let loop ((i 0))
      (when (< i n)
        (let ((c (string-ref s i)))
          (cond
           ;; \* and the other escapes of Markdown: the character itself
           ((and (char=? c #\\) (< (+ i 1) n) (memv (string-ref s (+ i 1)) (string->list "\\`*_{}[]()#+-.!|~<>$")))
            (if (or (at i "\\(") (at i "\\[")) (lx-math-or-char p s i loop) (begin (display (lx-text-char (string-ref s (+ i 1))) p) (loop (+ i 2)))))
           ((or (char=? c #\$) (at i "\\[")) (lx-math-or-char p s i loop))
           ((char=? c #\`)
            (let* ((ticks (let count ((k i)) (if (and (< k n) (char=? (string-ref s k) #\`)) (count (+ k 1)) (- k i))))
                   (fence (make-string ticks #\`))
                   (e (lx-find s fence (+ i ticks))))
              (if e
                  (begin (display "\\texttt{" p) (display (lx-escape (trim (substring s (+ i ticks) e))) p) (display "}" p)
                         (loop (+ e ticks)))
                  (begin (display fence p) (loop (+ i ticks))))))
           ((and (at i "![") (lx-md-link s (+ i 1)))
            => (lambda (l)
                 (display "\\includegraphics[width=\\linewidth]{" p) (display (cadr l) p) (display "}" p)
                 (loop (car l))))
           ((and (char=? c #\[) (lx-md-link s i))
            => (lambda (l)
                 (display "\\href{" p) (display (lx-url (cadr l)) p) (display "}{" p)
                 (display (lx-md-inline (caddr l)) p) (display "}" p)
                 (loop (car l))))
           ((and (char=? c #\<) (or (at i "<http://") (at i "<https://")) (lx-find s ">" i))
            => (lambda (e)
                 (display "\\url{" p) (display (lx-url (substring s (+ i 1) e)) p) (display "}" p)
                 (loop (+ e 1))))
           ((or (at i "**") (at i "__") (at i "~~"))
            (let* ((d (substring s i (+ i 2)))
                   (ok (and (< (+ i 2) n) (not (lx-blank-char? (string-ref s (+ i 2))))
                            (or (not (char=? c #\_)) (= i 0) (not (lx-word-char? (string-ref s (- i 1)))))))
                   (e (and ok (lx-md-close s d (+ i 2)))))
              (if e
                  (begin (display (if (char=? c #\~) "\\sout{" "\\textbf{") p)
                         (display (lx-md-inline (substring s (+ i 2) e)) p) (display "}" p)
                         (loop (+ e 2)))
                  (begin (display (lx-escape d) p) (loop (+ i 2))))))
           ((memv c '(#\* #\_))
            (let* ((d (string c))
                   (ok (and (< (+ i 1) n) (not (lx-blank-char? (string-ref s (+ i 1))))
                            (or (char=? c #\*) (= i 0) (not (lx-word-char? (string-ref s (- i 1)))))))
                   (e (and ok (lx-md-close s d (+ i 1)))))
              (if e
                  (begin (display "\\emph{" p) (display (lx-md-inline (substring s (+ i 1) e)) p) (display "}" p)
                         (loop (+ e 1)))
                  (begin (display (lx-text-char c) p) (loop (+ i 1))))))
           (else (display (lx-text-char c) p) (loop (+ i 1)))))))
    (get-output-string p)))

;; math at I, or an escaped character: shared by both dialects
(define (lx-math-or-char p s i loop)
  (let ((e (lx-math-end s i)))
    (if e
        (begin (display (substring s i e) p) (loop e))
        (begin (display (lx-text-char (string-ref s i)) p) (loop (+ i 1))))))

(define (lx-text-char c) (or (lx-escape-char c) (string c)))

;; [text](url) at I: (end url text), or #f
(define (lx-md-link s i)
  (let ((close (let loop ((k (+ i 1)) (depth 0))
                 (cond ((>= k (string-length s)) #f)
                       ((char=? (string-ref s k) #\[) (loop (+ k 1) (+ depth 1)))
                       ((char=? (string-ref s k) #\]) (if (= depth 0) k (loop (+ k 1) (- depth 1))))
                       (else (loop (+ k 1) depth))))))
    (and close (< (+ close 1) (string-length s)) (char=? (string-ref s (+ close 1)) #\()
         (let ((e (lx-find s ")" (+ close 2))))
           (and e (let* ((target (trim (substring s (+ close 2) e)))
                         ;; [x](url "title"): the title goes
                         (sp (string-index target #\space)))
                    (list (+ e 1) (if sp (substring target 0 sp) target) (substring s (+ i 1) close))))))))

;;; ------------------------------------------------------------------
;;; Inline markup: Org
;;; ------------------------------------------------------------------

(define *lx-org-markers*
  '((#\* "\\textbf{" #f) (#\/ "\\emph{" #f) (#\_ "\\underline{" #f)
    (#\+ "\\sout{" #f) (#\= "\\texttt{" #t) (#\~ "\\texttt{" #t)))

(define (lx-org-pre? s i)
  (or (= i 0) (memv (string-ref s (- i 1)) '(#\space #\tab #\newline #\- #\( #\{ #\' #\"))))

(define (lx-org-close s c from)
  "The closing marker C of Org emphasis that opened before FROM, or #f."
  (let ((n (string-length s)))
    (let loop ((k from))
      (cond ((>= k n) #f)
            ((and (char=? (string-ref s k) c) (> k from)
                  (not (lx-blank-char? (string-ref s (- k 1))))
                  (or (= (+ k 1) n)
                      (memv (string-ref s (+ k 1)) '(#\space #\tab #\newline #\- #\. #\, #\; #\: #\! #\? #\' #\) #\} #\[ #\" #\\))))
             k)
            (else (loop (+ k 1)))))))

(define (lx-org-inline s)
  "A paragraph's Org text as LaTeX."
  (let ((p (open-output-string)) (n (string-length s)))
    (define (at k t) (and (<= (+ k (string-length t)) n) (string=? (substring s k (+ k (string-length t))) t)))
    (let loop ((i 0))
      (when (< i n)
        (let* ((c (string-ref s i)) (m (assv c *lx-org-markers*)))
          (cond
           ((or (char=? c #\$) (at i "\\(") (at i "\\[")) (lx-math-or-char p s i loop))
           ((and (at i "[[") (lx-find s "]]" i))
            => (lambda (e)
                 (let* ((inside (substring s (+ i 2) e))
                        (mid (lx-find inside "][" 0))
                        (target (if mid (substring inside 0 mid) inside))
                        (target (if (string-prefix? "file:" target) (substring target 5 (string-length target)) target))
                        (desc (and mid (substring inside (+ mid 2) (string-length inside)))))
                   (cond ((and (not desc) (lx-image? target))
                          (display "\\includegraphics[width=\\linewidth]{" p) (display target p) (display "}" p))
                         (desc (display "\\href{" p) (display (lx-url target) p) (display "}{" p)
                               (display (lx-org-inline desc) p) (display "}" p))
                         (else (display "\\url{" p) (display (lx-url target) p) (display "}" p)))
                   (loop (+ e 2)))))
           ((and m (lx-org-pre? s i) (< (+ i 1) n) (not (lx-blank-char? (string-ref s (+ i 1))))
                 (lx-org-close s c (+ i 1)))
            => (lambda (e)
                 (display (cadr m) p)
                 (display (if (caddr m) (lx-escape (substring s (+ i 1) e)) (lx-org-inline (substring s (+ i 1) e))) p)
                 (display "}" p)
                 (loop (+ e 1))))
           (else (display (lx-text-char c) p) (loop (+ i 1)))))))
    (get-output-string p)))

;;; ------------------------------------------------------------------
;;; Lines
;;; ------------------------------------------------------------------

(define (lx-indent line)
  (let loop ((i 0)) (if (and (< i (string-length line)) (memv (string-ref line i) '(#\space #\tab))) (loop (+ i 1)) i)))

(define (lx-blank? line) (= (lx-indent line) (string-length line)))

(define (lx-dedent line k)
  (substring line (min k (lx-indent line)) (string-length line)))

(define (lx-upcase-prefix? prefix line)
  (let ((l (trim line)))
    (and (>= (string-length l) (string-length prefix))
         (string=? (string-upcase (substring l 0 (string-length prefix))) prefix))))

(define (lx-stars line)
  "The level of an Org heading (* at the first column, then a blank), or #f."
  (let ((n (string-length line)))
    (let loop ((i 0))
      (cond ((and (< i n) (char=? (string-ref line i) #\*)) (loop (+ i 1)))
            ((and (> i 0) (< i n) (char=? (string-ref line i) #\space)) i)
            (else #f)))))

(define (lx-hashes line)
  "The level of a Markdown heading (# to ######, then a blank), or #f."
  (let ((n (string-length line)))
    (let loop ((i 0))
      (cond ((and (< i n) (< i 6) (char=? (string-ref line i) #\#)) (loop (+ i 1)))
            ((and (> i 0) (or (= i n) (char=? (string-ref line i) #\space))) i)
            (else #f)))))

;; A list item: (indent content-column kind marker-text), kind 'ul or 'ol
(define (lx-item line dialect)
  (let* ((k (lx-indent line)) (n (string-length line)))
    (and (< k n)
         (let ((c (string-ref line k)))
           (cond ((and (memv c (if (eq? dialect 'org) '(#\- #\+) '(#\- #\+ #\*)))
                       (or (= (+ k 1) n) (char=? (string-ref line (+ k 1)) #\space))
                       ;; Org: a * at the first column is a heading
                       (not (and (eq? dialect 'org) (char=? c #\*) (= k 0))))
                  (list k (min n (+ k 2)) 'ul))
                 ((char-numeric? c)
                  (let loop ((i k))
                    (cond ((and (< i n) (char-numeric? (string-ref line i))) (loop (+ i 1)))
                          ((and (< i n) (memv (string-ref line i) '(#\. #\)))
                                (or (= (+ i 1) n) (char=? (string-ref line (+ i 1)) #\space)))
                           (list k (min n (+ i 2)) 'ol))
                          (else #f))))
                 (else #f))))))

(define (lx-rule? line dialect)
  (let ((l (trim line)))
    (if (eq? dialect 'org)
        (and (>= (string-length l) 5) (string=? l (make-string (string-length l) #\-)))
        (and (>= (string-length l) 3)
             (let ((c (string-ref l 0)))
               (and (memv c '(#\- #\* #\_))
                    (string=? (list->string (filter (lambda (x) (not (char=? x #\space))) (string->list l)))
                              (make-string (string-count l c) c))
                    (>= (string-count l c) 3)))))))

(define (lx-table-line? line) (string-prefix? "|" (trim line)))

(define (lx-cells line)
  "The cells of a | table line, trimmed."
  (let* ((l (trim line))
         (l (if (string-prefix? "|" l) (substring l 1 (string-length l)) l))
         (l (if (string-suffix? "|" l) (substring l 0 (- (string-length l) 1)) l)))
    (map trim (string-split l #\|))))

(define (lx-table-rule? line)
  "|---+---| or |:--|--:|: a rule (a separator) line."
  (let ((l (trim line)))
    (and (string-prefix? "|" l)
         (string-index l #\-)
         (string=? l (list->string (filter (lambda (c) (memv c '(#\| #\- #\+ #\: #\space))) (string->list l)))))))

;;; ------------------------------------------------------------------
;;; Blocks
;;; ------------------------------------------------------------------

;; The state of an export: the dialect, and the output port
(define (lx-out st) (cdr st))
(define (lx-dialect st) (car st))
(define (lx-say st . parts) (for-each (lambda (x) (display x (lx-out st))) parts))
(define (lx-inline st s) (if (eq? (lx-dialect st) 'org) (lx-org-inline s) (lx-md-inline s)))

(define (lx-verbatim st lines)
  (lx-say st "\\begin{verbatim}\n")
  (for-each (lambda (l) (lx-say st l "\n")) lines)
  (lx-say st "\\end{verbatim}\n\n"))

(define (lx-numeric? s)
  (and (> (string-length s) 0)
       (string->number (list->string (filter (lambda (c) (not (memv c '(#\, #\%)))) (string->list s))))))

(define (lx-tabular st rows aligns caption)
  "ROWS: ('header . cells), ('row . cells), ('rule); ALIGNS: a string per
column, or #f to choose (r for columns of numbers)."
  (let* ((width (apply max 1 (map (lambda (r) (if (eq? (car r) 'rule) 0 (length (cdr r)))) rows)))
         (body (map cdr (filter (lambda (r) (eq? (car r) 'row)) rows)))
         (aligns (or aligns
                     (let loop ((k 0) (out '()))
                       (if (= k width) (reverse out)
                           (let* ((col (map (lambda (r) (if (< k (length r)) (list-ref r k) "")) body))
                                  (full (filter (lambda (x) (> (string-length x) 0)) col))
                                  (nums (filter lx-numeric? full)))
                             (loop (+ k 1) (cons (if (and (pair? full) (> (* 2 (length nums)) (length full))) "r" "l") out))))))))
    (lx-say st (if caption "\\begin{table}[htbp]\n\\centering\n" "\\begin{center}\n"))
    (when caption (lx-say st "\\caption{" (lx-inline st caption) "}\n"))
    (lx-say st "\\begin{tabular}{" (string-join aligns "") "}\n\\toprule\n")
    (let loop ((rs rows) (first #t))
      (unless (null? rs)
        (let ((r (car rs)))
          (if (eq? (car r) 'rule)
              (unless (or first (null? (cdr rs))) (lx-say st "\\midrule\n"))
              (let ((cells (append (cdr r) (make-list (max 0 (- width (length (cdr r)))) ""))))
                (lx-say st (string-join (map (lambda (c) (lx-inline st c)) cells) " & ") " \\\\\n")
                (when (and (eq? (car r) 'header) (or (null? (cdr rs)) (not (eq? (car (cadr rs)) 'rule))))
                  (lx-say st "\\midrule\n"))))
          (loop (cdr rs) #f))))
    (lx-say st "\\bottomrule\n\\end{tabular}\n" (if caption "\\end{table}\n\n" "\\end{center}\n\n"))))

(define (lx-pipe-table st lines)
  "A | table: in Markdown a rule after the first row is required; the
first row is the header when a rule follows it."
  (let* ((rows (map (lambda (l) (if (lx-table-rule? l) (list 'rule) (cons 'row (lx-cells l)))) lines))
         (rows (if (and (>= (length rows) 2) (eq? (car (cadr rows)) 'rule) (eq? (car (car rows)) 'row))
                   (cons (cons 'header (cdr (car rows))) (cdr rows))
                   rows))
         (aligns (and (eq? (lx-dialect st) 'md) (>= (length lines) 2) (lx-table-rule? (cadr lines))
                      (map (lambda (c)
                             (let ((l (string-prefix? ":" c)) (r (string-suffix? ":" c)))
                               (cond ((and l r) "c") (r "r") (else "l"))))
                           (lx-cells (cadr lines))))))
    (lx-tabular st rows (and aligns (pair? (filter (lambda (a) (not (string=? a "l"))) aligns)) aligns) #f)))

(define (lx-sexp-table st lines)
  "An Org sexp table (org-table.scm), its formulas computed."
  (let ((table (and (top-level-bound? 'org-table-parse)
                    ((top-level-value 'org-table-parse) (join-lines lines)))))
    (if (not (and table (not (string? table))))
        (lx-verbatim st lines)
        (let* ((table ((top-level-value 'org-table-compute) table))
               (text (top-level-value 'org-cell-text))
               (rows (map (lambda (i)
                            (case (car i)
                              ((rule) (list 'rule))
                              ((header) (cons 'header (map text (cdr i))))
                              (else (cons 'row (map text (cdr i))))))
                          ((top-level-value 'org-table-items) table))))
          (lx-tabular st rows #f ((top-level-value 'org-table-title) table))))))

(define (lx-heading st level text)
  (let ((command (case level
                   ((1) "section") ((2) "subsection") ((3) "subsubsection")
                   ((4) "paragraph") (else "subparagraph"))))
    (lx-say st "\\" command "{" (lx-inline st text) "}\n\n")))

(define (lx-org-heading-text text)
  "An Org heading without its tags (:a:b:); TODO and DONE in type."
  (let* ((t (trim text))
         (t (let ((sp (string-index-right t #\space)))
              (if (and sp (string-prefix? ":" (substring t (+ sp 1) (string-length t)))
                       (string-suffix? ":" t) (> (string-length t) (+ sp 2)))
                  (trim (substring t 0 sp))
                  (if (and (> (string-length t) 1) (string-prefix? ":" t) (string-suffix? ":" t) (not sp)) "" t)))))
    (cond ((string-prefix? "TODO " t) (string-append "=TODO= " (substring t 5 (string-length t))))
          ((string-prefix? "DONE " t) (string-append "=DONE= " (substring t 5 (string-length t))))
          (else t))))

(define (lx-block-end lines name)
  "The lines up to #+END_NAME: (inside . rest)."
  (let loop ((ls lines) (acc '()))
    (cond ((null? ls) (cons (reverse acc) '()))
          ((lx-upcase-prefix? (string-append "#+END_" name) (car ls)) (cons (reverse acc) (cdr ls)))
          (else (loop (cdr ls) (cons (car ls) acc))))))

(define (lx-take-while ok? lines)
  (let loop ((ls lines) (acc '()))
    (if (and (pair? ls) (ok? (car ls))) (loop (cdr ls) (cons (car ls) acc)) (cons (reverse acc) ls))))

(define (lx-starts-block? line dialect)
  "Does LINE begin something other than a paragraph's next line?"
  (let ((l (trim line)))
    (or (lx-blank? line)
        (if (eq? dialect 'org)
            (or (lx-stars line) (string-prefix? "#+" l) (and (string-prefix? "# " line)) (string=? l "#")
                (string-prefix? ": " l) (string=? l ":")
                (lx-org-drawer? l) (lx-table-line? line) (lx-rule? line dialect))
            (or (lx-hashes line) (string-prefix? "```" l) (string-prefix? "~~~" l) (string-prefix? ">" l)
                (lx-rule? line dialect) (string-prefix? "<!--" l)))
        (lx-item line dialect)
        (string-prefix? "\\begin{" l) (string=? l "$$") (string=? l "\\["))))

(define (lx-org-drawer? l)
  (and (> (string-length l) 2) (string-prefix? ":" l) (string-suffix? ":" l)
       (not (string-index (substring l 1 (- (string-length l) 1)) #\space))))

;; A list starting at LINES (whose first line is an item): (items . rest),
;; an item being (kind first-text body-lines)
(define (lx-list-lines lines dialect)
  (let* ((first (lx-item (car lines) dialect)) (indent (car first)))
    (let loop ((ls lines) (items '()) (prev-blank #f))
      (if (null? ls) (cons (reverse items) '())
          (let* ((line (car ls)) (it (lx-item line dialect)))
            (cond
             ((and it (= (car it) indent) (not (eq? (caddr it) (caddr first))))
              (cons (reverse items) ls))                    ; 1. after -: a new list
             ((and it (= (car it) indent))
              (loop (cdr ls)
                    (cons (list (caddr it) (substring line (cadr it) (string-length line)) '()) items)
                    #f))
             ((lx-blank? line)
              ;; a blank: the list goes on if an indented line follows
              (if (and (pair? (cdr ls)) (pair? items)
                       (or (> (lx-indent (cadr ls)) indent)
                           (let ((next (lx-item (cadr ls) dialect)))
                             (and next (= (car next) indent) (eq? (caddr next) (caddr first))))))
                  (loop (cdr ls) (lx-add-line items "") #t)
                  (cons (reverse items) ls)))
             ((and (> (lx-indent line) indent) (pair? items))
              (loop (cdr ls) (lx-add-line items (lx-dedent line (cadr first))) #f))
             ;; a lazy line, glued to the item's paragraph
             ((and (not prev-blank) (pair? items) (not (lx-starts-block? line dialect)))
              (loop (cdr ls) (lx-add-line items (trim line)) #f))
             (else (cons (reverse items) ls))))))))

(define (lx-add-line items line)
  (let ((it (car items)))
    (cons (list (car it) (cadr it) (append (caddr it) (list line))) (cdr items))))

(define (lx-list st items)
  (let* ((dialect (lx-dialect st))
         (description (and (eq? dialect 'org) (lx-find (cadr (car items)) " :: " 0)))
         (env (cond (description "description") ((eq? (car (car items)) 'ol) "enumerate") (else "itemize"))))
    (lx-say st "\\begin{" env "}\n")
    (for-each
     (lambda (it)
       (let* ((text (cadr it))
              (box (and (eq? dialect 'org)
                        (cond ((string-prefix? "[ ] " text) "[$\\square$] ")
                              ((or (string-prefix? "[X] " text) (string-prefix? "[x] " text)) "[$\\boxtimes$] ")
                              ((string-prefix? "[-] " text) "[$\\boxminus$] ")
                              (else #f))))
              (text (if box (substring text 4 (string-length text)) text))
              (term (and description (lx-find text " :: " 0))))
         (lx-say st "\\item")
         (cond (term (lx-say st "[" (lx-inline st (substring text 0 term)) "] ")
                     (set! text (substring text (+ term 4) (string-length text))))
               (box (lx-say st box))
               (else (lx-say st " ")))
         (lx-blocks st (cons text (caddr it)) #t)))
     items)
    (lx-say st "\\end{" env "}\n\n")))

(define (lx-paragraph-lines lines dialect)
  (let loop ((ls (cdr lines)) (acc (list (car lines))))
    (if (or (null? ls) (lx-starts-block? (car ls) dialect))
        (cons (reverse acc) ls)
        (loop (cdr ls) (cons (car ls) acc)))))

(define (lx-blocks st lines in-item)
  "Export LINES; IN-ITEM: the first paragraph follows \\item on its line."
  (let ((dialect (lx-dialect st)))
    (let loop ((ls lines) (first in-item))
      (unless (null? ls)
        (let* ((line (car ls)) (l (trim line)))
          (cond
           ((lx-blank? line) (loop (cdr ls) #f))
           ;; raw LaTeX environments and display math
           ((string-prefix? "\\begin{" l)
            (let* ((close (lx-find l "}" 7))
                   (name (if close (substring l 7 close) ""))
                   (end (string-append "\\end{" name "}"))
                   (r (if (lx-find l end 0) (cons '() (cdr ls))
                          (lx-take-while (lambda (x) (not (lx-find x end 0))) (cdr ls)))))
              (lx-say st line "\n")
              (for-each (lambda (x) (lx-say st x "\n")) (car r))
              (when (pair? (cdr r)) (lx-say st (cadr r) "\n"))
              (lx-say st "\n")
              (loop (if (pair? (cdr r)) (cddr r) '()) #f)))
           ((or (string=? l "$$") (string=? l "\\["))
            (let* ((close (if (string=? l "$$") "$$" "\\]"))
                   (r (lx-take-while (lambda (x) (not (string=? (trim x) close))) (cdr ls))))
              (lx-say st "\\[\n")
              (for-each (lambda (x) (lx-say st x "\n")) (car r))
              (lx-say st "\\]\n\n")
              (loop (if (pair? (cdr r)) (cddr r) '()) #f)))
           ((lx-rule? line dialect)
            (lx-say st "\\noindent\\rule{\\linewidth}{0.4pt}\n\n")
            (loop (cdr ls) #f))
           ((lx-item line dialect)
            (let ((r (lx-list-lines ls dialect)))
              (lx-list st (car r))
              (loop (cdr r) #f)))
           ((and (lx-table-line? line) (or (eq? dialect 'org) (and (pair? (cdr ls)) (lx-table-rule? (cadr ls)))))
            (let ((r (lx-take-while lx-table-line? ls)))
              (lx-pipe-table st (car r))
              (loop (cdr r) #f)))
           ((eq? dialect 'org) (lx-org-block st ls first loop))
           (else (lx-md-block st ls first loop))))))))

(define (lx-org-block st ls first loop)
  (let* ((line (car ls)) (l (trim line)))
    (cond
     ((lx-stars line)
      => (lambda (k) (lx-heading st k (lx-org-heading-text (substring line k (string-length line))))
                (loop (cdr ls) #f)))
     ((lx-upcase-prefix? "#+BEGIN_" line)
      (let* ((word (let ((w (substring l 8 (string-length l))))
                     (string-upcase (car (string-split (trim w) #\space)))))
             (args (string-downcase (trim (substring l (min (string-length l) (+ 8 (string-length word))) (string-length l)))))
             (r (lx-block-end (cdr ls) word))
             (inside (car r)))
        (cond ((member word '("SRC" "EXAMPLE")) (lx-verbatim st (lx-common-dedent inside)))
              ((string=? word "EXPORT")
               (when (string-prefix? "latex" args) (for-each (lambda (x) (lx-say st x "\n")) inside) (lx-say st "\n")))
              ((string=? word "SEXP_TABLE") (lx-sexp-table st inside))
              ((member word '("QUOTE" "CENTER" "VERSE"))
               (let ((env (string-downcase word)))
                 (lx-say st "\\begin{" env "}\n")
                 (lx-blocks st inside #f)
                 (lx-say st "\\end{" env "}\n\n")))
              (else (lx-blocks st inside #f)))
        (loop (cdr r) #f)))
     ((lx-upcase-prefix? "#+LATEX:" line)
      (lx-say st (trim (substring l 8 (string-length l))) "\n\n")
      (loop (cdr ls) #f))
     ((string-prefix? "#+" l) (loop (cdr ls) #f))               ; other keywords
     ((or (string-prefix? "# " line) (string=? l "#")) (loop (cdr ls) #f))   ; comments
     ((lx-org-drawer? l)
      (let ((r (lx-take-while (lambda (x) (not (string=? (string-upcase (trim x)) ":END:"))) (cdr ls))))
        (loop (if (pair? (cdr r)) (cddr r) '()) #f)))
     ((or (string-prefix? ": " l) (string=? l ":"))
      (let ((r (lx-take-while (lambda (x) (let ((t (trim x))) (or (string-prefix? ": " t) (string=? t ":")))) ls)))
        (lx-verbatim st (map (lambda (x) (let ((t (trim x))) (if (string=? t ":") "" (substring t 2 (string-length t))))) (car r)))
        (loop (cdr r) #f)))
     (else (lx-paragraph st ls first loop)))))

(define (lx-md-block st ls first loop)
  (let* ((line (car ls)) (l (trim line)))
    (cond
     ((lx-hashes line)
      => (lambda (k)
           (let* ((t (trim (substring line k (string-length line))))
                  ;; ## Title ## : the closing hashes go
                  (t (trim (string-trim-right t #\#))))
             (lx-heading st (- k (lx-md-shift st)) t)
             (loop (cdr ls) #f))))
     ((or (string-prefix? "```" l) (string-prefix? "~~~" l))
      (let* ((fence (substring l 0 3))
             (r (lx-take-while (lambda (x) (not (string-prefix? fence (trim x)))) (cdr ls))))
        (lx-verbatim st (lx-common-dedent (car r)))
        (loop (if (pair? (cdr r)) (cddr r) '()) #f)))
     ((string-prefix? "<!--" l)
      (let ((r (lx-take-while (lambda (x) (not (lx-find x "-->" 0))) ls)))
        (loop (if (pair? (cdr r)) (cddr r) '()) #f)))
     ((string-prefix? ">" l)
      (let ((r (lx-take-while (lambda (x) (string-prefix? ">" (trim x))) ls)))
        (lx-say st "\\begin{quote}\n")
        (lx-blocks st (map (lambda (x) (let* ((t (trim x)) (t (substring t 1 (string-length t))))
                                         (if (string-prefix? " " t) (substring t 1 (string-length t)) t)))
                           (car r))
                   #f)
        (lx-say st "\\end{quote}\n\n")
        (loop (cdr r) #f)))
     ;; four blanks after a blank: code
     ((and (>= (lx-indent line) 4) (not first))
      (let ((r (lx-take-while (lambda (x) (or (lx-blank? x) (>= (lx-indent x) 4))) ls)))
        (lx-verbatim st (lx-trim-blank-tail (map (lambda (x) (lx-dedent x 4)) (car r))))
        (loop (cdr r) #f)))
     (else (lx-paragraph st ls first loop)))))

(define (lx-trim-blank-tail lines)
  (reverse (let drop ((r (reverse lines))) (if (and (pair? r) (lx-blank? (car r))) (drop (cdr r)) r))))

(define (lx-common-dedent lines)
  (let ((k (apply min 1000 (map lx-indent (filter (lambda (x) (not (lx-blank? x))) lines)))))
    (map (lambda (x) (lx-dedent x k)) lines)))

(define (lx-paragraph st ls first loop)
  (let* ((r (lx-paragraph-lines ls (lx-dialect st)))
         (text (string-join (map trim (car r)) "\n")))
    (lx-say st (lx-inline st text) (if (and first (null? (cdr r))) "\n" "\n\n"))
    (loop (cdr r) #f)))

;;; ------------------------------------------------------------------
;;; The document
;;; ------------------------------------------------------------------

;; Markdown: how many levels the headings move up (1 when the first line
;; is the only # heading, the title)
(define *lx-md-shift* 0)
(define (lx-md-shift st) *lx-md-shift*)

(define (lx-scripts text)
  "Which scripts TEXT has: a list of 'greek 'hangul 'han."
  (let ((n (string-length text)))
    (let loop ((i 0) (greek #f) (hangul #f) (han #f))
      (if (= i n)
          (filter (lambda (x) x) (list (and greek 'greek) (and hangul 'hangul) (and han 'han)))
          (let ((c (char->integer (string-ref text i))))
            (loop (+ i 1)
                  (or greek (and (>= c #x370) (< c #x400)) (and (>= c #x1F00) (< c #x2000)))
                  (or hangul (and (>= c #xAC00) (< c #xD7A4)) (and (>= c #x1100) (< c #x1200)) (and (>= c #x3130) (< c #x3190)))
                  (or han (and (>= c #x4E00) (< c #xA000)) (and (>= c #x3000) (< c #x3040)) (and (>= c #xFF00) (< c #xFFF0)))))))))

(define (lx-preamble scripts title author date)
  (string-append
   "% Made by Chezweb (M-x latex-export).  Compile with xelatex.\n"
   "\\documentclass[11pt]{article}\n"
   "\\usepackage{fontspec}\n"
   (if (memq 'greek scripts)
       ;; Latin Modern has no Greek; Libertinus (TeX Live) has polytonic Greek
       "\\setmainfont{LibertinusSerif}[Extension=.otf, UprightFont=*-Regular, BoldFont=*-Bold, ItalicFont=*-Italic, BoldItalicFont=*-BoldItalic]\n"
       "")
   (cond ((memq 'hangul scripts) "\\usepackage{kotex}\n")
         ((memq 'han scripts) "\\usepackage{xeCJK}\n")
         (else ""))
   "\\usepackage{amsmath,amssymb}\n"
   "\\usepackage{graphicx}\n"
   "\\usepackage{booktabs}\n"
   "\\usepackage[normalem]{ulem}\n"
   "\\usepackage[hidelinks]{hyperref}\n"
   (if title (string-append "\\title{" title "}\n") "")
   (if author (string-append "\\author{" author "}\n") "")
   (if date (string-append "\\date{" date "}\n") "")
   "\n\\begin{document}\n"
   (if title "\\maketitle\n" "")
   "\n"))

(define (lx-org-keyword lines name)
  (let ((key (string-append "#+" name ":")))
    (let loop ((ls lines))
      (cond ((null? ls) #f)
            ((lx-upcase-prefix? key (car ls))
             (let ((l (trim (car ls)))) (trim (substring l (string-length key) (string-length l)))))
            (else (loop (cdr ls)))))))

(define (latex-from-text text dialect)
  "TEXT (Org when DIALECT is 'org, Markdown when 'md) as a LaTeX document."
  (let* ((lines (split-lines text))
         (p (open-output-string))
         (st (cons dialect p))
         (first-real (let loop ((ls lines)) (cond ((null? ls) #f) ((lx-blank? (car ls)) (loop (cdr ls))) (else (car ls)))))
         ;; Markdown's title: the first line, a # heading, the only one
         (md-title (and (eq? dialect 'md) first-real (eqv? (lx-hashes first-real) 1)
                        (= 1 (length (filter (lambda (l) (eqv? (lx-hashes l) 1)) lines)))
                        (trim (substring first-real 1 (string-length first-real)))))
         (title (if (eq? dialect 'org)
                    (let ((t (lx-org-keyword lines "TITLE"))) (and t (lx-org-inline t)))
                    (and md-title (lx-md-inline md-title))))
         (author (and (eq? dialect 'org) (let ((a (lx-org-keyword lines "AUTHOR"))) (and a (lx-org-inline a)))))
         (date (and (eq? dialect 'org) (let ((d (lx-org-keyword lines "DATE"))) (and d (lx-org-inline d)))))
         (body (if md-title
                   (let drop ((ls lines)) (if (eq? (car ls) first-real) (cdr ls) (drop (cdr ls))))
                   lines)))
    (set! *lx-md-shift* (if md-title 1 0))
    (lx-blocks st body #f)
    (string-append (lx-preamble (lx-scripts text) title author date)
                   (get-output-string p)
                   "\\end{document}\n")))

(define (latex-export-dialect)
  "'org, 'md, or #f: what the current buffer is, by its language."
  (let* ((lang (language-for-file (or (buffer-filename) (get-buffer-name))))
         (name (and lang (language-name lang))))
    (cond ((equal? name "Org") 'org) ((equal? name "Markdown") 'md) (else #f))))

(define (latex-export-name file)
  "paper.md -> paper.tex"
  (let ((dot (string-index-right file #\.)) (slash (string-index-right file #\/)))
    (string-append (if (and dot (or (not slash) (> dot slash))) (substring file 0 dot) file) ".tex")))

(defcommand (latex-export)
  "Export this Org or Markdown file to LaTeX, beside it (paper.md -> paper.tex)."
  (let ((dialect (latex-export-dialect)) (file (buffer-filename)))
    (cond
     ((not dialect) (message "latex-export: this is not an Org or a Markdown file"))
     ((or (not file) (string=? file ""))
      (message "latex-export: save the file first (C-x C-w), so that the .tex has a place"))
     (else
      (let* ((tex (latex-export-name file))
             (shown (let ((s (string-index-right tex #\/))) (if s (substring tex (+ s 1) (string-length tex)) tex))))
        (when (or (not (file-exists-p tex)) (yes-p (concat shown " exists; replace it?")))
          (let ((latex (latex-from-text (buffer-string) dialect)))
            (find-file tex)
            (delete-region 0 (buffer-size))
            (insert latex)
            (goto-char 0)
            (if (save-buffer (get-buffer-name))
                (message "Wrote " shown "; compile it with xelatex")
                (message "latex-export: " shown " could not be written; C-x C-w saves it elsewhere")))))))))

;; Org's key, as in Emacs: C-c C-e, then l l (org.scm binds C-c C-e in
;; Org files only)
(define (org-export-dispatch)
  (message "C-c C-e- (l l: export to a LaTeX file)")
  (let ((k1 (get-key)))
    (if (not (string=? k1 "l"))
        (message "C-c C-e " k1 " is not bound (l l: LaTeX)")
        (begin (message "C-c C-e l- (l: export to a LaTeX file)")
               (let ((k2 (get-key)))
                 (clear-message-line)
                 (if (string=? k2 "l")
                     (latex-export)
                     (message "C-c C-e l " k2 " is not bound (l: LaTeX file)")))))))
