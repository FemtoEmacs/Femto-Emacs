;;;; ttfy.scm -- C-c f: textify a PDF into Markdown, with ChatGPT or Claude
;;;;
;;;; In Chez Scheme, compiled by Schemer: the port of scheme/extensions/
;;;; ttfy.scm.  Column widths in the layout of the tables count bytes, as
;;;; femtoscheme's did.
;;;;
;;;; Chezemax's own extension (not in SBEmacs).  C-c f (or TTFY in the
;;;; [MORE] window) offers 1 ChatGPT or 2 Claude, then asks for the PDF and
;;;; the pages (all, N or N-M).  The pages are rendered as images in C
;;;; (src/pdf-pages.c) and sent with the guidelines of
;;;; ttfy/plots-guidelines.md; the Markdown answer opens in a new buffer
;;;; for review (C-x C-s saves it).  Failures are shown in *ttfy-errors*.
;;;; Every table in the answer is an S-expression: a Markdown pipe table is
;;;; sent back to the same provider to be rewritten (see below).

(define *ttfy-errors-buffer* "*ttfy-errors*")
(defvar *ttfy-sequence* 0)

(define (ttfy-read-guidelines)
  (or (file-contents (string-append *install-dir* "/ttfy/plots-guidelines.md")) ""))

(define (ttfy-failed? text)
  (or (string-prefix? "Assistant failed" text)
      (string-prefix? "TTFY failed" text)
      (string=? (trim text) "")))

(define (ttfy-error-text e) (describe-error e))

(define (ttfy-choice-provider choice) (if (= choice 1) "codex" "claude"))

;;; ------------------------------------------------------------------
;;; Tables are S-expressions (ttfy/plots-guidelines.md, section 2)
;;; ------------------------------------------------------------------
;;; Both providers are told so in the prompt.  A model can still answer
;;; with a Markdown pipe table, so the answer is checked: each pipe table
;;; is sent back to the same provider, alone, to be rewritten as one
;;; S-expression, and every lisp block must read as exactly one form.
;;; Then every lisp block is laid out by the same fixed rules.
;;; What cannot be repaired is listed at the top of the answer.

(define (ttfy-fence? line) (string-prefix? "```" (trim line)))

(define (ttfy-pipe-row? line)
  (let ((s (trim line))) (and (> (string-length s) 1) (string-prefix? "|" s))))

(define (ttfy-pipe-separator? line)
  "A Markdown table rule such as |---|:--:|."
  (let ((s (trim line)))
    (and (string-prefix? "|" s) (string-search "-" s)
         (let loop ((i 0))
           (or (>= i (string-length s))
               (and (memv (string-ref s i) '(#\| #\- #\: #\space)) (loop (+ i 1))))))))

(define (ttfy-pipe-tables lines)
  "The (FIRST . LAST) line indices of the Markdown pipe tables in LINES,
outside fenced blocks.  A table is a run of | rows with a rule line."
  (let loop ((l lines) (i 0) (fenced #f) (start #f) (rule #f) (acc '()))
    (define (close) (if (and start rule) (cons (cons start (- i 1)) acc) acc))
    (cond ((null? l) (reverse (close)))
          ((ttfy-fence? (car l)) (loop (cdr l) (+ i 1) (not fenced) #f #f (close)))
          (fenced (loop (cdr l) (+ i 1) #t #f #f acc))
          ((ttfy-pipe-row? (car l))
           (loop (cdr l) (+ i 1) #f (or start i) (or rule (ttfy-pipe-separator? (car l))) acc))
          (else (loop (cdr l) (+ i 1) #f #f #f (close))))))

(define (ttfy-read-one text)
  "The one list that TEXT holds, or #f when TEXT does not read as exactly
one list."
  (guard (e (#t #f))
    (let* ((p (open-input-string text)) (x (read p)))
      (and (pair? x) (eof-object? (read p)) x))))

(define (ttfy-lisp-blocks lines)
  "The (LINE . TEXT) of each ```lisp block in LINES; LINE is its fence."
  (let loop ((l lines) (i 0) (open #f) (body '()) (acc '()))
    (cond ((null? l) (reverse acc))
          ((and (not open) (string-prefix? "```lisp" (trim (car l))))
           (loop (cdr l) (+ i 1) i '() acc))
          ((and open (ttfy-fence? (car l)))
           (loop (cdr l) (+ i 1) #f '() (cons (cons open (join-lines (reverse body))) acc)))
          (open (loop (cdr l) (+ i 1) open (cons (car l) body) acc))
          (else (loop (cdr l) (+ i 1) #f '() acc)))))

(define (ttfy-unreadable-blocks lines)
  "Problems for the lisp blocks that do not read as one S-expression."
  (map (lambda (b) (concat "the lisp block at line " (+ (car b) 1)
                           " does not read as one S-expression"))
       (filter (lambda (b) (not (ttfy-read-one (cdr b)))) (ttfy-lisp-blocks lines))))

(define (ttfy-sexpr-rules guidelines)
  "Section 2 of the guidelines: how a table is written."
  (let* ((a (string-search "## 2." guidelines))
         (z (and a (string-search "## 3." guidelines a))))
    (if a (substring guidelines a (or z (string-length guidelines))) guidelines)))

(define (ttfy-slice lines from to)
  "Lines FROM (inclusive) to TO (exclusive), clipped to LINES."
  (let ((from (max 0 from)) (to (min (length lines) to)))
    (if (>= from to) '() (list-head (list-tail lines from) (- to from)))))

(define (ttfy-table-prompt lines table guidelines)
  (concat "Rewrite the Markdown table below as ONE data-table S-expression, using the "
          "schema in the rules at the end exactly: the same fields in the same order, "
          "columns c1, c2 ..., one cell per column, and only the listed cell forms. "
          "Output only that S-expression in a fenced ```lisp block: no prose, no other "
          "table. Keep every printed value and every printed label in full; add nothing "
          "that the table does not show. Take the caption, notes and abbreviations from "
          "the surrounding text.\n\n"
          "Text before the table:\n"
          (join-lines (ttfy-slice lines (- (car table) 20) (car table)))
          "\n\nTable:\n"
          (join-lines (ttfy-slice lines (car table) (+ (cdr table) 1)))
          "\n\nText after the table:\n"
          (join-lines (ttfy-slice lines (+ (cdr table) 1) (+ (cdr table) 8)))
          "\n\nRules:\n" (ttfy-sexpr-rules guidelines)))

(define (ttfy-answer-sexpr answer)
  "The S-expression text in ANSWER (inside its ```lisp fence when it has
one), or #f when it does not read as exactly one list."
  (let* ((a (string-search "```lisp" answer))
         (b (and a (string-search "\n" answer a)))
         (z (and b (string-search "```" answer b)))
         (text (trim (if z (substring answer (+ b 1) z) answer))))
    (and (ttfy-read-one text) text)))

(define (ttfy-replace-lines lines table new)
  "LINES with the lines of TABLE replaced by the list NEW."
  (append (ttfy-slice lines 0 (car table)) new
          (ttfy-slice lines (+ (cdr table) 1) (length lines))))

(define (ttfy-fix-tables convert text guidelines)
  "TEXT with each pipe table rewritten by (CONVERT prompt), which returns
the provider's answer.  Returns (TEXT . PROBLEMS)."
  (let* ((lines (split-lines text))
         (tables (ttfy-pipe-tables lines)))
    (let loop ((ts (reverse tables)) (lines lines) (problems '()) (k (length tables)))
      (if (null? ts)
          (cons (ttfy-canonical-blocks (join-lines lines))
                (append problems (ttfy-unreadable-blocks lines)))
          (let* ((table (car ts))
                 (_ (begin (message "Textify: rewriting table " k " of " (length tables)
                                    " as an S-expression; please wait...")
                           (update-display)))
                 (answer (guard (e (#t "")) (convert (ttfy-table-prompt lines table guidelines))))
                 (sexpr (and (not (ttfy-failed? answer)) (ttfy-answer-sexpr answer))))
            (if sexpr
                (loop (cdr ts)
                      (ttfy-replace-lines lines table (append '("```lisp") (split-lines sexpr) '("```")))
                      problems (- k 1))
                (loop (cdr ts) lines
                      (cons (concat "the pipe table at line " (+ (car table) 1)
                                    " could not be rewritten as an S-expression")
                            problems)
                      (- k 1))))))))

;;; ------------------------------------------------------------------
;;; One layout for every table, whichever model wrote it
;;; ------------------------------------------------------------------
;;; The S-expression is split into tokens and laid out again by fixed
;;; rules, so Codex and Claude give the same text for the same table.
;;; Atoms keep their printed text (33.0 stays 33.0): nothing is read
;;; back as a float and printed again.

(define *ttfy-width* 88)

(define (ttfy-tokens text)
  "The tokens of TEXT: \"(\", \")\" and atom strings (strings keep their
quotes).  Comments are dropped."
  (let ((n (string-length text)))
    (define (aref s k) (char->integer (string-ref s k)))
    (define (delim? b) (or (= b 40) (= b 41) (= b 34) (= b 59) (<= b 32)))
    (let loop ((i 0) (acc '()))
      (if (>= i n) (reverse acc)
          (let ((b (aref text i)))
            (cond ((<= b 32) (loop (+ i 1) acc))
                  ((= b 40) (loop (+ i 1) (cons "(" acc)))
                  ((= b 41) (loop (+ i 1) (cons ")" acc)))
                  ((= b 59) (let skip ((j i))
                              (if (or (>= j n) (= (aref text j) 10)) (loop j acc) (skip (+ j 1)))))
                  ((= b 34) (let str ((j (+ i 1)))
                              (cond ((>= j n) (loop n (cons (substring text i n) acc)))
                                    ((= (aref text j) 92) (str (+ j 2)))
                                    ((= (aref text j) 34)
                                     (loop (+ j 1) (cons (substring text i (+ j 1)) acc)))
                                    (else (str (+ j 1))))))
                  (else (let atom ((j i))
                          (if (or (>= j n) (delim? (aref text j)))
                              (loop j (cons (substring text i j) acc))
                              (atom (+ j 1)))))))))))

(define (ttfy-tree tokens)
  "The first list in TOKENS as a tree of atom strings."
  (define (node ts)
    (if (string=? (car ts) "(")
        (let loop ((ts (cdr ts)) (acc '()))
          (cond ((null? ts) (cons (reverse acc) '()))
                ((string=? (car ts) ")") (cons (reverse acc) (cdr ts)))
                (else (let ((r (node ts))) (loop (cdr r) (cons (car r) acc))))))
        (cons (car ts) (cdr ts))))
  (car (node tokens)))

(define (ttfy-flat x)
  (if (string? x) x (concat "(" (string-join (map ttfy-flat x) " ") ")")))

(define (ttfy-keyword? x) (and (string? x) (string-prefix? ":" x)))

(define (ttfy-records? x)
  "A list of two or more lists: the rows, columns, steps or cohorts."
  (and (pair? x) (pair? (cdr x)) (every pair? x)))

(define (ttfy-pairs l)
  (if (or (null? l) (null? (cdr l))) (if (null? l) '() (list l))
      (cons (list (car l) (cadr l)) (ttfy-pairs (cddr l)))))

(define (ttfy-last-line s)
  (let ((i (string-search-back "\n" s))) (if i (substring s (+ i 1) (string-length s)) s)))

(define (ttfy-layout x col)
  "X laid out, starting at column COL (the first line is not indented)."
  (define (pad c) (make-spaces c))
  (define (pair-text p c)
    (if (null? (cdr p)) (ttfy-layout (car p) c)
        (concat (car p) " " (ttfy-layout (cadr p) (+ c (bytes-length (car p)) 1)))))
  (cond ((string? x) x)
        ((null? x) "()")
        ;; (data-table :key value ...): always one key per line.
        ((and (string? (car x)) (not (ttfy-keyword? (car x))) (pair? (cdr x))
              (ttfy-keyword? (cadr x)))
         (concat "(" (car x)
                 (apply concat (map (lambda (p) (concat "\n" (pad (+ col 2)) (pair-text p (+ col 2))))
                                    (ttfy-pairs (cdr x))))
                 ")"))
        ((ttfy-records? x)
         (concat "(" (string-join (map (lambda (r) (ttfy-layout r (+ col 1))) x)
                                  (concat "\n" (pad (+ col 1))))
                 ")"))
        ((<= (+ col (bytes-length (ttfy-flat x))) *ttfy-width*) (ttfy-flat x))
        ;; a record (:key value ...) too long for one line: as many pairs per
        ;; line as fit; a pair that needs several lines starts its own line.
        ((ttfy-keyword? (car x))
         (let* ((ps (ttfy-pairs x))
                (first (pair-text (car ps) (+ col 1))))
           (let loop ((ps (cdr ps)) (out (concat "(" first))
                      (c (+ col 1 (bytes-length (ttfy-last-line first))))
                      (broke (string-search "\n" first)))
             (if (null? ps) (concat out ")")
                 (let ((t (pair-text (car ps) (+ c 1))))
                   (if (and (not broke) (not (string-search "\n" t))
                            (<= (+ c 1 (bytes-length t)) *ttfy-width*))
                       (loop (cdr ps) (concat out " " t) (+ c 1 (bytes-length t)) #f)
                       (let ((t (pair-text (car ps) (+ col 1))))
                         (loop (cdr ps) (concat out "\n" (pad (+ col 1)) t)
                               (+ col 1 (bytes-length (ttfy-last-line t)))
                               (string-search "\n" t)))))))))
        ;; any other long list: as many items per line as fit.
        (else
         (let loop ((items (cdr x)) (line (ttfy-layout (car x) (+ col 1))) (c (+ col 1 (bytes-length (ttfy-flat (car x))))) (out "("))
           (if (null? items) (concat out line ")")
               (let ((t (ttfy-layout (car items) (+ c 1))))
                 (if (<= (+ c 1 (bytes-length t)) *ttfy-width*)
                     (loop (cdr items) (concat line " " t) (+ c 1 (bytes-length t)) out)
                     (loop (cdr items) (ttfy-layout (car items) (+ col 1))
                           (+ col 1 (bytes-length (ttfy-flat (car items))))
                           (concat out line "\n" (pad (+ col 1)))))))))))

(define (ttfy-canonical text)
  "TEXT laid out by the fixed rules, or TEXT itself when the new layout
would not read as the same S-expression."
  (let* ((old (ttfy-read-one text))
         (new (and old (ttfy-layout (ttfy-tree (ttfy-tokens text)) 0))))
    (if (and new (equal? (ttfy-read-one new) old)) new text)))

(define (ttfy-canonical-blocks text)
  "TEXT with every ```lisp block in the canonical layout."
  (let loop ((lines (split-lines text)) (open #f) (body '()) (acc '()))
    (cond ((null? lines)
           (join-lines (reverse (if open (append body (list open) acc) acc))))
          ((and (not open) (string-prefix? "```lisp" (trim (car lines))))
           (loop (cdr lines) (car lines) '() acc))
          ((and open (ttfy-fence? (car lines)))
           (let ((form (ttfy-canonical (join-lines (reverse body)))))
             (loop (cdr lines) #f '()
                   (append (list (car lines)) (reverse (split-lines form)) (list open) acc))))
          (open (loop (cdr lines) open (cons (car lines) body) acc))
          (else (loop (cdr lines) #f '() (cons (car lines) acc))))))

(define (ttfy-problems-comment problems)
  (if (null? problems) ""
      (concat "<!-- TTFY table check: " (string-join problems "; ") ". -->\n\n")))

(define (ttfy-show-errors text)
  (show-in-assistant-window "Textify failed" text)
  (set-buffer-hint *assistant-buffer* "C-x 1 close")
  (message "Textify failed; see the window below"))

(define (ttfy-convert provider path range)
  (message "Textifying PDF with " (if (string=? provider "codex") "ChatGPT" "Claude") "; please wait...")
  (update-display)
  (let* ((guidelines (ttfy-read-guidelines))
         (text (guard (e (#t (string-append "TTFY failed: " (ttfy-error-text e))))
                 (ttfy-request provider path range guidelines))))
    (if (ttfy-failed? text)
        (ttfy-show-errors text)
        (let* ((fixed (ttfy-fix-tables (lambda (prompt) (assistant-request provider prompt))
                                       text guidelines))
               (text (car fixed)))
          (set! *ttfy-sequence* (+ *ttfy-sequence* 1))
          (delete-other-windows)
          (split-window)
          (other-window)
          (select-buffer (concat "*ttfy-" *ttfy-sequence* ".md*"))
          (erase-buffer)
          (insert "<!-- TTFY provider: " (if (string=? provider "codex") "ChatGPT" "Claude")
                  "; review plot estimates before reuse. -->\n\n"
                  (ttfy-problems-comment (cdr fixed)) text)
          (goto-char 0)
          (message (if (null? (cdr fixed))
                       "Textify complete. Review/edit Markdown; C-x C-w saves it."
                       "Textify complete, with table problems listed at the top."))))))

(defcommand (ttfy-menu)
  "C-c f: textify a PDF into Markdown with ChatGPT or Claude."
  (let ((saved (list *more-menu-buffer* *menu-title* *menu-number-keys*)))
    (set! *more-menu-buffer* "*ttfy-menu*")
    (set! *menu-title* "Textify PDF")
    (set! *menu-number-keys* #t)
    (let ((choice (dynamic-wind (lambda () #f)
                                (lambda () (choose-menu '(("Textify with ChatGPT" "1") ("Textify with Claude" "2"))))
                                (lambda ()
                                  (set! *more-menu-buffer* (car saved))
                                  (set! *menu-title* (cadr saved))
                                  (set! *menu-number-keys* (caddr saved))))))
      (if (not choice)
          (message "Textify cancelled")
          (let ((path (ttfy-file-prompt)))
            (if (string=? path "")
                (message "Textify cancelled")
                (let ((range (prompt "PDF pages (all, N or N-M; C-g cancels): " "all")))
                  (if (string=? range "")
                      (message "Textify cancelled")
                      (ttfy-convert (ttfy-choice-provider (string->number choice)) path
                                    (if (string-ci=? (trim range) "all") "" range))))))))))

(global-set-key "C-c f" 'ttfy-menu)
