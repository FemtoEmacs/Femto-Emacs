;;;; tex.scm -- colours and indentation for TeX and LaTeX, and LaTeX
;;;; without its commands
;;;;
;;;; In Chez Scheme, compiled by Schemer: the port of scheme/languages/
;;;; tex.scm.  TEXT is the buffer's UTF-8 bytes, a bytevector; command
;;;; names and arguments taken from it are strings.
;;;;
;;;; The colours (the faces of theme.scm):
;;;;
;;;;   \commands                 keyword     % comments          comment
;;;;   \section{Title} ...       heading     $x^2$ \[ \] \( \)    string
;;;;   \begin{env} \end{env}     the name in digits; math environments
;;;;                             (equation, align ...) as a string
;;;;   \emph{...} \textit{...}   emphasis    \textbf{...}        strong
;;;;   \cite{} \ref{} \label{} \url{} \href{} \input{} ...      link
;;;;   numbers                   digits      { } [ ] & ^ _ ~      symbol
;;;;
;;;; LATEX-STRIP gives the text without commands, for C-c l
;;;; (extensions/tag-view.scm): \section{Title} keeps the title on a line
;;;; of its own, \emph{word} keeps the word, \cite{key} shows [key],
;;;; \item a "- ", \\ a line break; comments, the preamble, \label and
;;;; the like go.  Math is kept as written.

;;; ------------------------------------------------------------------
;;; Reading bytes
;;; ------------------------------------------------------------------

(define (tex-letter? b) (or (and (<= 65 b) (<= b 90)) (and (<= 97 b) (<= b 122)) (= b 64)))
(define (tex-digit? b) (and (<= 48 b) (<= b 57)))

(define (tex-command-end text i len)
  "The index after the command whose backslash is at I: \\name (and a *),
or \\ and one other character."
  (cond ((>= (+ i 1) len) len)
        ((tex-letter? (b@ text (+ i 1)))
         (let loop ((j (+ i 1)))
           (cond ((and (< j len) (tex-letter? (b@ text j))) (loop (+ j 1)))
                 ((and (< j len) (= (b@ text j) 42)) (+ j 1))     ; \section*
                 (else j))))
        (else (+ i 2))))

(define (tex-group-end text i len)
  "The index after the group that opens at I with { or [, nested groups and
\\{ included; LEN when it is not closed."
  (let ((open (b@ text i)) (close (if (= (b@ text i) 123) 125 93)))
    (let loop ((j (+ i 1)) (depth 1))
      (cond ((>= j len) len)
            ((= (b@ text j) 92) (loop (+ j 2) depth))
            ((= (b@ text j) open) (loop (+ j 1) (+ depth 1)))
            ((= (b@ text j) close) (if (= depth 1) (+ j 1) (loop (+ j 1) (- depth 1))))
            (else (loop (+ j 1) depth))))))

(define (tex-skip-blanks text i len)
  (let loop ((i i)) (if (and (< i len) (memv (b@ text i) '(32 9))) (loop (+ i 1)) i)))

(define (tex-comment-end text i len)
  (let loop ((j i)) (if (and (< j len) (not (= (b@ text j) 10))) (loop (+ j 1)) j)))

(define (tex-math-end text i len closer)
  "The index after CLOSER ($, $$, \\], \\)) that ends math opened before I."
  (let loop ((j i))
    (cond ((>= j len) len)
          ((match-at text len j closer) (+ j (string-length closer)))
          ((= (b@ text j) 92) (loop (+ j 2)))
          (else (loop (+ j 1))))))

;;; ------------------------------------------------------------------
;;; Colours
;;; ------------------------------------------------------------------

(define *tex-heading-commands*
  '("\\part" "\\chapter" "\\section" "\\subsection" "\\subsubsection" "\\paragraph"
    "\\subparagraph" "\\title" "\\author" "\\caption" "\\frametitle"))
(define *tex-emphasis-commands* '("\\emph" "\\textit" "\\textsl" "\\mathit"))
(define *tex-strong-commands* '("\\textbf" "\\mathbf" "\\bm"))
(define *tex-link-commands*
  '("\\cite" "\\citep" "\\citet" "\\citeauthor" "\\citeyear" "\\nocite" "\\ref" "\\eqref"
    "\\pageref" "\\autoref" "\\cref" "\\Cref" "\\label" "\\url" "\\href" "\\input" "\\include"
    "\\includegraphics" "\\bibliography" "\\bibliographystyle" "\\usepackage"
    "\\documentclass"))
(define *tex-math-environments*
  '("equation" "equation*" "align" "align*" "gather" "gather*" "multline" "multline*"
    "eqnarray" "eqnarray*" "displaymath" "math" "flalign" "flalign*"))

(define (tex-base-command name)
  "\\section* -> \\section"
  (if (string-suffix? "*" name) (substring name 0 (- (string-length name) 1)) name))

(define (tex-argument-face name)
  "The face of the first {argument} of the command NAME, or #f."
  (let ((base (tex-base-command name)))
    (cond ((member base *tex-heading-commands*) +heading+)
          ((member base *tex-emphasis-commands*) +emphasis+)
          ((member base *tex-strong-commands*) +strong+)
          ((member base *tex-link-commands*) +link+)
          ((member base '("\\begin" "\\end")) +digits+)
          (else #f))))

(define (tex-paint-argument text i len colors face)
  "Colour the {argument} (after any [options]) at I with FACE; the index
after it."
  (let loop ((j (tex-skip-blanks text i len)))
    (cond ((>= j len) j)
          ((= (b@ text j) 91)
           (let ((e (tex-group-end text j len))) (paint colors j e +symbol+) (loop (tex-skip-blanks text e len))))
          ((= (b@ text j) 123)
           (let ((e (tex-group-end text j len)))
             (bytevector-u8-set! colors j +symbol+)
             (paint colors (+ j 1) (max (+ j 1) (- e 1)) face)
             (when (> e (+ j 1)) (bytevector-u8-set! colors (- e 1) +symbol+))
             e))
          (else j))))

(define (latex-highlight lang text len colors)
  (let loop ((i 0))
    (when (< i len)
      (let ((b (b@ text i)))
        (cond
         ;; % comment
         ((= b 37)
          (let ((e (tex-comment-end text i len))) (paint colors i e +comment+) (loop e)))
         ;; math: $$ $ \[ \(
         ((match-at text len i "$$")
          (let ((e (tex-math-end text (+ i 2) len "$$"))) (paint colors i e +string+) (loop e)))
         ((= b 36)
          (let ((e (tex-math-end text (+ i 1) len "$"))) (paint colors i e +string+) (loop e)))
         ((or (match-at text len i "\\[") (match-at text len i "\\("))
          (let ((e (tex-math-end text (+ i 2) len (if (= (b@ text (+ i 1)) 91) "\\]" "\\)"))))
            (paint colors i e +string+)
            (loop e)))
         ;; a command
         ((= b 92)
          (let* ((e (tex-command-end text i len))
                 (name (bytes->string text i e))
                 (face (and (> (- e i) 1) (tex-letter? (b@ text (+ i 1))) (tex-argument-face name))))
            (paint colors i e (if (tex-letter? (b@ text (min (+ i 1) (- len 1)))) +keyword+ +symbol+))
            (cond
             ((not face) (loop e))
             ((string=? name "\\begin")
              (let* ((a (tex-skip-blanks text e len))
                     (after (tex-paint-argument text e len colors face))
                     (env (if (and (< a len) (= (b@ text a) 123))
                              (bytes->string text (+ a 1) (max (+ a 1) (- after 1)))
                              "")))
                (if (member env *tex-math-environments*)
                    ;; the body of a math environment, up to its \end
                    (let* ((close (search-bytes (string-append "\\end{" env "}") text after len))
                           (stop (or close len)))
                      (paint colors after stop +string+)
                      (loop stop))
                    (loop after))))
             (else (loop (tex-paint-argument text e len colors face))))))
         ((tex-digit? b) (bytevector-u8-set! colors i +digits+) (loop (+ i 1)))
         ((memv b '(123 125 91 93 38 94 95 126)) (bytevector-u8-set! colors i +symbol+) (loop (+ i 1)))
         (else (bytevector-u8-set! colors i (if (memv b '(32 9 10 13)) +symbol+ +alpha+)) (loop (+ i 1))))))))

(define-language "TeX"
  'extensions '(".tex" ".latex" ".ltx" ".sty" ".cls" ".dtx" ".ins" ".bib")
  'highlighter latex-highlight)

(define-indentation "TeX"
  'style 'block 'width 2 'tabs #f
  'comment "%"
  'reindent-on-newline #t
  'open-anywhere '("\\begin{")
  'not-open-anywhere '("\\begin{document}" "\\end{")
  'close-words '("\\end")
  'electric-keys "}" 'electric-prefixes '("\\end"))

;;; ------------------------------------------------------------------
;;; The text without its commands (C-c l)
;;; ------------------------------------------------------------------

;; commands that go with their arguments
(define *tex-dropped-commands*
  '("\\label" "\\usepackage" "\\documentclass" "\\includegraphics" "\\input" "\\include"
    "\\bibliography" "\\bibliographystyle" "\\newcommand" "\\renewcommand"
    "\\providecommand" "\\newenvironment" "\\setlength" "\\addtolength" "\\vspace"
    "\\hspace" "\\vspace*" "\\hspace*" "\\pagestyle" "\\thispagestyle" "\\setcounter"
    "\\addcontentsline" "\\maketitle" "\\tableofcontents" "\\centering" "\\noindent"
    "\\newpage" "\\clearpage" "\\small" "\\large" "\\Large" "\\footnotesize"
    "\\nocite" "\\graphicspath" "\\hypersetup" "\\geometry"))
(define *tex-cite-commands* '("\\cite" "\\citep" "\\citet" "\\autocite" "\\parencite"))
(define *tex-ref-commands* '("\\ref" "\\eqref" "\\pageref" "\\autoref" "\\cref" "\\Cref"))
;; \% \& ... and the characters they stand for
(define *tex-escaped* '(("\\%" . "%") ("\\&" . "&") ("\\$" . "$") ("\\#" . "#") ("\\_" . "_")
                        ("\\{" . "{") ("\\}" . "}") ("\\ " . " ") ("\\," . " ") ("\\;" . " ")))

(define (tex-skip-arguments text i len)
  "The index after the [options] and {arguments} that follow I."
  (let loop ((j (tex-skip-blanks text i len)))
    (if (and (< j len) (memv (b@ text j) '(91 123)))
        (loop (tex-skip-blanks text (tex-group-end text j len) len))
        j)))

(define (latex-strip text out)
  "Write TEXT without its commands to OUT, a tag view (tag-view.scm)."
  (let* ((len (blen text))
         (doc (search-bytes "\\begin{document}" text 0 len))
         (from (if doc (+ doc (string-length "\\begin{document}")) 0)))
    ;; BREAKS: the closing braces of titles, where a line break goes
    (let loop ((i from) (start from) (breaks '()))
      (define (flush) (tag-view-copy out text start i))
      (if (>= i len)
          (flush)
          (let ((b (b@ text i)))
            (cond
             ((= b 37)                                   ; % comment
              (flush)
              (let ((e (tex-comment-end text i len))) (loop e e breaks)))
             ((or (= b 123) (= b 125))                   ; a lone brace
              (flush)
              (when (memv i breaks) (tag-view-emit out "\n" i))   ; after a title
              (loop (+ i 1) (+ i 1) breaks))
             ((= b 126)                                  ; ~ is a space
              (flush) (tag-view-emit out " " i) (loop (+ i 1) (+ i 1) breaks))
             ((= b 92)
              (flush)
              (let* ((e (tex-command-end text i len))
                     (name (bytes->string text i e))
                     (base (tex-base-command name)))
                (cond
                 ((string=? name "\\\\") (tag-view-emit out "\n" i) (loop e e breaks))
                 ((assoc name *tex-escaped*) => (lambda (p) (tag-view-emit out (cdr p) i) (loop e e breaks)))
                 ((member base '("\\begin" "\\end"))
                  (let* ((a (tex-skip-blanks text e len))
                         (env-end (if (and (< a len) (= (b@ text a) 123)) (tex-group-end text a len) a))
                         (env (if (> env-end a) (bytes->string text (+ a 1) (max (+ a 1) (- env-end 1))) "")))
                    (if (and (string=? base "\\end") (string=? env "document"))
                        (loop len len breaks)
                        (let ((after (if (string=? base "\\begin") (tex-skip-arguments text env-end len) env-end)))
                          (tag-view-emit out "\n" i)
                          (loop after after breaks)))))
                 ((string=? base "\\item")
                  (tag-view-emit out "\n" i)
                  (tag-view-emit out "- " i +symbol+)
                  (let ((after (let ((a (tex-skip-blanks text e len)))
                                 (if (and (< a len) (= (b@ text a) 91)) (tex-group-end text a len) a))))
                    (loop after after breaks)))
                 ((member base *tex-dropped-commands*)
                  (let ((after (tex-skip-arguments text e len))) (loop after after breaks)))
                 ((or (member base *tex-cite-commands*) (member base *tex-ref-commands*))
                  ;; AFTER: the end of the last argument; the blanks after it stay
                  (let* ((after (let back ((k (tex-skip-arguments text e len)))
                                  (if (and (> k e) (memv (b@ text (- k 1)) '(32 9))) (back (- k 1)) k)))
                         (brace (let find ((k (- after 1)))
                                  (cond ((< k e) #f) ((= (b@ text k) 123) k) (else (find (- k 1))))))
                         (key (if brace (bytes->string text (+ brace 1) (max (+ brace 1) (- after 1))) "")))
                    (tag-view-emit out (if (member base *tex-cite-commands*) (concat "[" key "]") key) i +link+)
                    (loop after after breaks)))
                 ((member base *tex-heading-commands*)
                  ;; the title on a line of its own: drop [short title], keep {title}
                  (let ((a (tex-skip-blanks text e len)))
                    (tag-view-emit out "\n" i)
                    (let* ((after (if (and (< a len) (= (b@ text a) 91)) (tex-group-end text a len) a))
                           (a2 (tex-skip-blanks text after len))
                           (close (and (< a2 len) (= (b@ text a2) 123) (- (tex-group-end text a2 len) 1))))
                      (loop after after (if close (cons close breaks) breaks)))))
                 (else (loop e e breaks)))))                    ; \emph and the like: only the name goes
             (else (loop (+ i 1) start breaks))))))))
