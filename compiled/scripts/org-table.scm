;;;; org-table.scm -- Org's sexp tables (a module of org.scm)
;;;;
;;;; A table is an S-expression in a block, which Emacs's Org leaves alone:
;;;;
;;;;   #+BEGIN_SEXP_TABLE
;;;;   (
;;;;    ((Title: "Org table"))
;;;;    (( Name  ) ( Phone ) ( Age ) ( Age-24 ))
;;;;    (( ----- ) ( ----- ) ( --- ) ( ------ ))
;;;;    (( Peter ) ( 1234  ) ( 24  ) ( 0      ))
;;;;   )
;;;;   #+TBLFM: $4=(- $3 24)
;;;;   #+END_SEXP_TABLE
;;;;
;;;; A row is a list of cells, a cell a list of values: a number, a symbol
;;;; (Peter), a string ("Peter Pan"), or none: ( ) is empty.  A row whose
;;;; first value ends in : is a property (Title:).  A rule is a row of
;;;; runs of - = _ ~ or +, a cell holding one or several -- ( ----- ),
;;;; ( = ----- = ) -- with a run of two, or in every cell; it is written back
;;;; with the character of its longest run.  The row just above the first
;;;; rule names the columns; without a rule, a first row without a number
;;;; above rows with numbers does.  Long tables never break: a row is a
;;;; line, whatever its length, and its cells are found by the
;;;; parentheses, not by columns.
;;;;
;;;; C-c C-c in the block computes the formulas and aligns the columns.  A
;;;; formula sets a column in every row below the header, from the other
;;;; cells of the same row, by number or by name, several on a line
;;;; separated by :: or on several #+TBLFM: lines:
;;;;
;;;;   #+TBLFM: $4=(- $3 24)
;;;;   #+TBLFM: (set! Age-24 (- Age 24))
;;;;
;;;; Its language is a small, safe one, not Scheme: numbers; the cells $N
;;;; and column names; + - * / min max abs round floor ceiling truncate
;;;; sqrt expt quotient remainder modulo; < > = <= >= if and or not.  An
;;;; empty cell counts as 0, a cell that is not a number gives "#ERROR".  So
;;;; C-c C-c on a table someone sent you computes, and does nothing else.
;;;;
;;;; Inside, a table is a record (org-table-parse): its title, headers,
;;;; rows and formulas, ((column . expression) ...), columns from 1.

(define-record-type org-table
  (fields properties    ; the property rows, as read: ((Title: "Org table")) ...
          title         ; the Title: property, a string, or #f
          headers       ; the names of the columns, strings ("" none)
          items         ; the other rows in order: (above . cells), (header .
                        ; cells), (rule . character), (row . cells); the
                        ; formulas set the cells of the rows
          formulas      ; ((column . expression) ...)
          formula-lines ; the #+TBLFM: lines, as written
          errors))      ; formulas that could not be read, strings

(define (org-table-rows table)
  "The rows the formulas set: lists of cells."
  (map cdr (filter (lambda (i) (eq? (car i) 'row)) (org-table-items table))))

;;; ------------------------------------------------------------------
;;; The block around point
;;; ------------------------------------------------------------------

(define (org-table-block text p)
  "The block around offset P: (begin-line-end . end-line-start), the bytes
between its #+BEGIN_SEXP_TABLE and #+END_SEXP_TABLE lines; #f outside."
  (let up ((ls (org-line-start text p)))
    (let ((le (org-line-end text ls)))
      (cond ((org-keyword-line? text ls le "#+BEGIN_SEXP_TABLE")
             (let down ((s (min (+ le 1) (blen text))))
               (let ((e (org-line-end text s)))
                 (cond ((org-keyword-line? text s e "#+END_SEXP_TABLE")
                        (and (>= (org-line-end text p) ls) (<= p e) (cons (min (+ le 1) s) s)))
                       ((org-keyword-line? text s e "#+BEGIN_") #f)
                       ((>= e (blen text)) #f)
                       (else (down (+ e 1)))))))
            ((and (< ls (org-line-start text p)) (org-keyword-line? text ls le "#+END_")) #f)
            ((<= ls 0) #f)
            (else (up (org-line-start text (- ls 1))))))))

(define (org-in-sexp-table?)
  (and (org-table-block (org-buffer-bytes) (point)) #t))

;;; ------------------------------------------------------------------
;;; Reading
;;; ------------------------------------------------------------------

(define (org-every ok? xs) (or (null? xs) (and (ok? (car xs)) (org-every ok? (cdr xs)))))

(define (org-rule-symbol? x)
  "A run of - = _ ~ or + (a piece of a rule)?"
  (and (symbol? x)
       (let ((s (symbol->string x)))
         (and (> (string-length s) 0)
              (not (string-index s (lambda (c) (not (memv c '(#\- #\= #\_ #\~ #\+))))))))))

(define (org-rule-run? x)
  "A symbol with two of the same rule character in a row: --, ==, ..."
  (and (org-rule-symbol? x)
       (let ((s (symbol->string x)))
         (let loop ((i 1))
           (and (< i (string-length s))
                (or (and (char=? (string-ref s i) (string-ref s (- i 1)))
                         (not (char=? (string-ref s i) #\+)))
                    (loop (+ i 1))))))))

(define (org-rule-row? row)
  "Is ROW a rule: cells of rule pieces only, and either one at least a run
of two (( ----- ) ( )), or none empty (( - ) ( - ))?"
  (and (pair? row)
       (org-every (lambda (cell) (and (list? cell) (org-every org-rule-symbol? cell))) row)
       (or (org-every pair? row)
           (let any ((cells row))
             (and (pair? cells)
                  (or (let some ((vs (car cells))) (and (pair? vs) (or (org-rule-run? (car vs)) (some (cdr vs)))))
                      (any (cdr cells))))))))

(define (org-rule-character row)
  "The character of the longest run of the rule ROW."
  (let ((longest (fold-left (lambda (best v)
                              (if (> (string-length (symbol->string v)) (string-length best))
                                  (symbol->string v) best))
                            "" (apply append row))))
    (if (string=? longest "") #\-
        (let ((c (string-ref longest (quotient (string-length longest) 2))))
          (if (char=? c #\+) #\- c)))))

(define (org-has-number? row)
  (let any ((cells row))
    (and (pair? cells)
         (or (let some ((vs (car cells))) (and (pair? vs) (or (number? (car vs)) (some (cdr vs)))))
             (any (cdr cells))))))

(define (org-property-row? row)
  (and (pair? row) (pair? (car row)) (symbol? (caar row))
       (let ((s (symbol->string (caar row))))
         (and (> (string-length s) 1) (char=? (string-ref s (- (string-length s) 1)) #\:)))))

(define (org-cell-string values)
  "A cell's values as written: Peter, 1234, \"Peter Pan\", \"\"."
  (string-join (map (lambda (v)
                      (cond ((number? v) (number->string v))
                            ((symbol? v) (symbol->string v))
                            ((string? v) (%write-string v))
                            (else (%write-string v))))
                    values)
               " "))

(define (org-cell-text values)
  "A cell's values as text (a name, a title): strings without quotes."
  (string-join (map (lambda (v) (if (string? v) v (org-cell-string (list v)))) values) " "))

(define (org-formula-strings line)
  "The formulas of a #+TBLFM: line, split at ::."
  (let loop ((s line) (out '()))
    (let ((i (string-search-forward "::" s 0)))
      (if i
          (loop (substring s (+ i 2) (string-length s)) (cons (trim (substring s 0 i)) out))
          (reverse (cons (trim s) out))))))

(define (org-read-one s)
  (guard (e (#t #f))
    (let* ((p (open-input-string s)) (x (read p)))
      (and (not (eof-object? x)) (eof-object? (read p)) (list x)))))

(define (org-parse-formula s headers)
  "\"$4=(- $3 24)\" or \"(set! Age-24 (- Age 24))\" -> (column . expression);
#f if it cannot be read."
  (cond ((string=? s "") #f)
        ((char=? (string-ref s 0) #\()
         (let ((x (org-read-one s)))
           (and x (let ((f (car x)))
                    (and (list? f) (= (length f) 3) (eq? (car f) 'set!)
                         (let ((column (org-column-of (cadr f) headers)))
                           (and column (org-formula-ok? (caddr f) headers) (cons column (caddr f)))))))))
        (else
         (let ((eq (string-index s #\=)))
           (and eq
                (let ((column (org-column-of (string->symbol (trim (substring s 0 eq))) headers))
                      (x (org-read-one (substring s (+ eq 1) (string-length s)))))
                  (and column x (org-formula-ok? (car x) headers) (cons column (car x)))))))))

(define (org-formula-ok? x headers)
  "Does expression X use only the formula language's words and the
table's columns?  (A formula that does not is reported, not applied.)"
  (cond ((or (number? x) (boolean? x)) #t)
        ((symbol? x) (and (org-column-of x headers) #t))
        ((and (pair? x) (list? x) (symbol? (car x)))
         (and (or (memq (car x) '(if and or not)) (assq (car x) *org-formula-functions*))
              (org-every (lambda (a) (org-formula-ok? a headers)) (cdr x))))
        (else #f)))

(define (org-column-of name headers)
  "The column (from 1) NAME names: $3, or a header's name; #f if none."
  (and (symbol? name)
       (let ((s (symbol->string name)))
         (or (and (> (string-length s) 1) (char=? (string-ref s 0) #\$)
                  (let ((n (string->number (substring s 1 (string-length s)))))
                    (and (integer? n) (> n 0) n)))
             (let loop ((hs headers) (k 1))
               (cond ((null? hs) #f)
                     ((string=? (car hs) s) k)
                     (else (loop (cdr hs) (+ k 1)))))))))

(define (org-table-parse source)
  "SOURCE, the text between the block's lines (a string) -> an org-table,
or a string saying why it cannot be read."
  (let* ((lines (split-lines source))
         (formula? (lambda (l) (starts-with-p "#+TBLFM:" (string-upcase (trim l)))))
         (sexp-text (join-lines (filter (lambda (l) (not (formula? l))) lines)))
         (formula-lines (map trim (filter formula? lines)))
         (read (org-read-one sexp-text)))
    (cond
     ((not read) "the table is not one S-expression (are its parentheses balanced?)")
     ((not (and (list? (car read)) (org-every (lambda (r) (and (list? r) (org-every list? r))) (car read))))
      "a table is a list of rows, a row a list of cells, a cell a list: (( Name ) ( Age ))")
     (else
      (let* ((all (car read))
             (properties (filter org-property-row? all))
             (body (filter (lambda (r) (not (org-property-row? r))) all))
             (rule-at (let loop ((rs body) (k 0)) (cond ((null? rs) #f) ((org-rule-row? (car rs)) k) (else (loop (cdr rs) (+ k 1))))))
             ;; the header: the row above the first rule; without a rule, a
             ;; first row without numbers above rows with numbers
             (header-at (cond (rule-at (and (> rule-at 0) (- rule-at 1)))
                              ((and (pair? body) (not (org-has-number? (car body)))
                                    (find org-has-number? (cdr body)))
                               0)
                              (else #f)))
             (items (let loop ((rs body) (k 0) (out '()))
                      (if (null? rs) (reverse out)
                          (loop (cdr rs) (+ k 1)
                                (cons (cond ((org-rule-row? (car rs)) (cons 'rule (org-rule-character (car rs))))
                                            ((and header-at (= k header-at)) (cons 'header (car rs)))
                                            ((and header-at (< k header-at)) (cons 'above (car rs)))
                                            (else (cons 'row (car rs))))
                                      out)))))
             (headers (if header-at (map org-cell-text (list-ref body header-at)) '()))
             (title (let ((t (find (lambda (r) (string=? (symbol->string (caar r)) "Title:")) properties)))
                      (and t (org-cell-text (cdar t)))))
             (parsed (map (lambda (s) (cons s (org-parse-formula s headers)))
                          (apply append (map (lambda (l) (org-formula-strings (substring l 8 (string-length l))))
                                             formula-lines)))))
        (make-org-table properties title headers items
                        (filter (lambda (x) x) (map cdr parsed))
                        formula-lines
                        (map car (filter (lambda (p) (not (cdr p))) parsed))))))))

;;; ------------------------------------------------------------------
;;; Formulas
;;; ------------------------------------------------------------------

(define (org-cell-number row column)
  "The value of COLUMN (from 1) in ROW for a formula: a number, 0 if
empty; else raise."
  (let ((cell (if (<= column (length row)) (list-ref row (- column 1)) '())))
    (cond ((null? cell) 0)
          ((and (= (length cell) 1) (number? (car cell))) (car cell))
          ((and (= (length cell) 1) (equal? (car cell) "")) 0)
          (else (raise 'org-not-a-number)))))

(define *org-formula-functions*
  (list (cons '+ +) (cons '- -) (cons '* *) (cons '/ /) (cons 'min min) (cons 'max max)
        (cons 'abs abs) (cons 'round round) (cons 'floor floor) (cons 'ceiling ceiling)
        (cons 'truncate truncate) (cons 'sqrt sqrt) (cons 'expt expt)
        (cons 'quotient quotient) (cons 'remainder remainder) (cons 'modulo modulo)
        (cons '< <) (cons '> >) (cons '= =) (cons '<= <=) (cons '>= >=)))

(define (org-evaluate x row headers)
  "EXPRESSION X for ROW: the small language of formulas."
  (cond ((number? x) x)
        ((symbol? x)
         (let ((column (org-column-of x headers)))
           (cond (column (org-cell-number row column))
                 ((memq x '(true #t)) #t)
                 (else (raise 'org-unknown-name)))))
        ((boolean? x) x)
        ((and (pair? x) (eq? (car x) 'if) (= (length x) 4))
         (if (org-evaluate (cadr x) row headers)
             (org-evaluate (caddr x) row headers)
             (org-evaluate (cadddr x) row headers)))
        ((and (pair? x) (eq? (car x) 'and))
         (let loop ((xs (cdr x)) (v #t)) (if (null? xs) v (let ((v (org-evaluate (car xs) row headers))) (and v (loop (cdr xs) v))))))
        ((and (pair? x) (eq? (car x) 'or))
         (let loop ((xs (cdr x))) (and (pair? xs) (or (org-evaluate (car xs) row headers) (loop (cdr xs))))))
        ((and (pair? x) (eq? (car x) 'not) (= (length x) 2)) (not (org-evaluate (cadr x) row headers)))
        ((and (pair? x) (assq (car x) *org-formula-functions*))
         => (lambda (f) (apply (cdr f) (map (lambda (a) (org-evaluate a row headers)) (cdr x)))))
        (else (raise 'org-unknown-function))))

(define (org-number-value v)
  "A result as it goes into a cell: integers as integers, others with at
most 6 decimals."
  (cond ((not (number? v)) (if (boolean? v) (if v 't 'nil) v))
        ((and (integer? v) (exact? v)) v)
        ((integer? v) (exact v))
        (else (let ((r (/ (round (* v 1000000.0)) 1000000.0)))
                (if (integer? r) (exact r) r)))))

(define (org-table-compute table)
  "TABLE with its formulas applied to every row below the rule."
  (let ((headers (org-table-headers table))
        (formulas (org-table-formulas table)))
    (if (null? formulas) table
        (make-org-table
         (org-table-properties table) (org-table-title table) headers
         (map (lambda (item)
               (if (not (eq? (car item) 'row)) item
                (cons 'row
                (fold-left
                 (lambda (row f)
                   (let* ((column (car f))
                          (value (guard (e (#t "#ERROR"))
                                   (org-number-value (org-evaluate (cdr f) row headers))))
                          (row (if (< (length row) column)
                                   (append row (make-list (- column (length row)) '()))
                                   row)))
                     (let loop ((cells row) (k 1) (out '()))
                       (if (null? cells) (reverse out)
                           (loop (cdr cells) (+ k 1) (cons (if (= k column) (list value) (car cells)) out))))))
                 (cdr item) formulas))))
              (org-table-items table))
         formulas (org-table-formula-lines table) (org-table-errors table)))))

;;; ------------------------------------------------------------------
;;; Writing, aligned
;;; ------------------------------------------------------------------

(define (org-text-width s)
  "The columns S takes on the screen: wide characters two, accents none."
  (let loop ((i 0) (w 0))
    (if (= i (string-length s)) w
        (loop (+ i 1) (+ w (fe-char-width (char->integer (string-ref s i))))))))

(define (org-pad s width)
  (string-append s (make-spaces (- width (org-text-width s)))))

(define (org-table-format table)
  "TABLE as the text of its block (a string ending in a newline)."
  (let* ((items (org-table-items table))
         (cells (map cdr (filter (lambda (i) (not (eq? (car i) 'rule))) items)))
         (columns (fold-left max 0 (map length cells)))
         (strings (lambda (row)
                    (let ((cs (map org-cell-string row)))
                      (append cs (make-list (- columns (length cs)) "")))))
         (all (map strings cells))
         (widths (let loop ((k 0) (out '()))
                   (if (= k columns) (reverse out)
                       (loop (+ k 1) (cons (fold-left max 1 (map (lambda (r) (org-text-width (list-ref r k))) all)) out)))))
         (row-line (lambda (cs)
                     (string-append " (" (string-join (map (lambda (c w) (string-append "( " (org-pad c w) " )")) cs widths) " ") ")\n")))
         (rule-line (lambda (c)
                      (string-append " (" (string-join (map (lambda (w) (string-append "( " (make-string w c) " )")) widths) " ") ")\n"))))
    (string-append
     "(\n"
     (apply string-append
            (map (lambda (p) (string-append " (" (string-join (map (lambda (c) (string-append "(" (org-cell-string c) ")")) p) " ") ")\n"))
                 (org-table-properties table)))
     (apply string-append
            (map (lambda (i) (if (eq? (car i) 'rule) (rule-line (cdr i)) (row-line (strings (cdr i))))) items))
     ")\n"
     (apply string-append (map (lambda (l) (string-append l "\n")) (org-table-formula-lines table))))))

;;; ------------------------------------------------------------------
;;; C-c C-c
;;; ------------------------------------------------------------------

(define (org-table-redo source)
  "The text between the block's lines, SOURCE, computed and aligned; or
(error . why) when it cannot be read.  C-c C-c's work, without the buffer."
  (let ((table (org-table-parse source)))
    (if (string? table) (cons 'error table) (org-table-format (org-table-compute table)))))

(define (org-table-describe source)
  "For tests: (title headers formulas errors) of SOURCE, or the reason."
  (let ((table (org-table-parse source)))
    (if (string? table) table
        (list (org-table-title table) (org-table-headers table)
              (org-table-formulas table) (org-table-errors table)))))

(define (org-table-recompute)
  "C-c C-c in a #+BEGIN_SEXP_TABLE block: compute its formulas and align it."
  (let* ((text (org-buffer-bytes))
         (block (org-table-block text (point)))
         (from (car block)) (to (cdr block))
         (table (org-table-parse (bytes->string text from to))))
    (if (string? table)
        (message "Sexp table: " table)
        (let* ((new (org-table-format (org-table-compute table)))
               ;; point: the same line of the block, the same column, or
               ;; the line's end
               (here (point))
               (line (let count ((i from) (n 0)) (if (>= i (min here to)) n (count (+ i 1) (if (= (b@ text i) 10) (+ n 1) n)))))
               (column (- here (org-line-start text here)))
               (old (bytes->string text from to)))
          (if (string=? new old)
              (message "Sexp table: nothing to change"
                       (if (null? (org-table-errors table)) "" (string-append "; formulas not understood: " (string-join (org-table-errors table) " :: "))))
              (begin
                (fe-delete-region from to)
                (goto-char from)
                (insert new)
                (let* ((bytes (string->utf8 new))
                       (ls (let skip ((i 0) (n 0)) (cond ((= n line) i) ((>= i (blen bytes)) i) ((= (b@ bytes i) 10) (skip (+ i 1) (+ n 1))) (else (skip (+ i 1) n)))))
                       (le (org-line-end bytes ls))
                       (p (min (+ ls column) le))
                       (p (let back ((p p)) (if (and (> p ls) (< p (blen bytes)) (= (bitwise-and (b@ bytes p) #xC0) #x80)) (back (- p 1)) p))))
                  (goto-char (+ from p)))
                (message "Sexp table aligned"
                         (if (null? (org-table-formulas table)) "" ", formulas computed")
                         (if (null? (org-table-errors table)) "" (string-append "; formulas not understood: " (string-join (org-table-errors table) " :: "))))))))))

(org-c-c-c! "sexp table" org-in-sexp-table? org-table-recompute)
