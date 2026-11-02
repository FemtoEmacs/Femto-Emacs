;;;; python-mode.scm -- the standard Python mode
;;;;
;;;; In Chez Scheme, compiled by Schemer: the port of scheme/modes/
;;;; python-mode.scm (itself a port of SBEmacs's lisp/modes/python-mode.lisp,
;;;; the hand-written implementation of languages/python.synpy).  Active from
;;;; the start.  No Python runtime.  The text is scanned as bytes (a
;;;; bytevector), so positions are bytes of UTF-8 text, as everywhere in the
;;;; editor; a token's value is a string.
;;;;
;;;;   colours   keywords, definitions, decorators, builtins, f-strings
;;;;   TAB       indent; repeated TAB cycles through the possible levels
;;;;   RET       indent the new line
;;;;   menu      [#] comment, [INDENT] region, [DEF>] [<DEF] definitions

(define *pm-keywords*
  '("False" "None" "True" "and" "as" "assert" "async" "await" "break" "class"
    "continue" "def" "del" "elif" "else" "except" "finally" "for" "from" "global"
    "if" "import" "in" "is" "lambda" "nonlocal" "not" "or" "pass" "raise"
    "return" "try" "while" "with" "yield"))
(define *pm-builtins*
  '("abs" "all" "any" "ascii" "bin" "bool" "breakpoint" "bytearray" "bytes"
    "callable" "chr" "classmethod" "complex" "dict" "dir" "divmod" "enumerate"
    "eval" "exec" "filter" "float" "format" "frozenset" "getattr" "globals"
    "hasattr" "hash" "help" "hex" "id" "input" "int" "isinstance" "issubclass"
    "iter" "len" "list" "locals" "map" "max" "memoryview" "min" "next" "object"
    "oct" "open" "ord" "pow" "print" "property" "range" "repr" "reversed" "round"
    "set" "setattr" "slice" "sorted" "staticmethod" "str" "sum" "super" "tuple"
    "type" "vars" "zip" "__import__"))
(define *pm-prefixes* '("r" "u" "b" "f" "br" "rb" "fr" "rf" "t" "tr" "rt"))

;; a token: #(kind start end value prefix quote closed)
(define make-pm-token
  (case-lambda
    ((kind start end value) (make-pm-token kind start end value "" "" #t))
    ((kind start end value prefix) (make-pm-token kind start end value prefix "" #t))
    ((kind start end value prefix delim) (make-pm-token kind start end value prefix delim #t))
    ((kind start end value prefix delim closed) (vector kind start end value prefix delim closed))))

;;; the source's bytes
(define (pm-ref s i) (bytevector-u8-ref s i))
(define (pm-len s) (bytevector-length s))
(define (pm-str s a b) (utf8->string (bytevector-copy s a b)))
(define (pm-trim-left s)               ; without the blanks (space, tab) it starts with
  (let loop ((i 0)) (if (and (< i (pm-len s)) (memv (pm-ref s i) '(32 9))) (loop (+ i 1)) (bytevector-copy s i (pm-len s)))))
(define (pm-trim s bytes)              ; without BYTES at either end
  (let* ((n (pm-len s))
         (a (let loop ((a 0)) (if (and (< a n) (memv (pm-ref s a) bytes)) (loop (+ a 1)) a)))
         (z (let loop ((z n)) (if (and (> z a) (memv (pm-ref s (- z 1)) bytes)) (loop (- z 1)) z))))
    (bytevector-copy s a z)))
(define (pm-token-kind t) (vector-ref t 0))
(define (pm-token-start t) (vector-ref t 1))
(define (pm-token-end t) (vector-ref t 2))
(define (pm-token-value t) (vector-ref t 3))
(define (pm-token-prefix t) (vector-ref t 4))
(define (pm-token-quote t) (vector-ref t 5))
(define (pm-token-closed t) (vector-ref t 6))

(define (pm-name-start b) (or (= b 95) (and (<= 65 b) (<= b 90)) (and (<= 97 b) (<= b 122)) (>= b 128)))
(define (pm-name-part b) (or (pm-name-start b) (and (<= 48 b) (<= b 57))))
(define (pm-digit b) (and (<= 48 b) (<= b 57)))
(define (pm-at source delimiter position) (match-at source (pm-len source) position delimiter))
(define (pm-in b chars) (and (< b 128) (string-index chars (integer->char b)) #t))

(define (pm-string-end source opening)
  "Three values: the end of the string opened at OPENING, its delimiter and
whether it was closed."
  (let* ((q (pm-ref source opening))
         (triple (string (integer->char q) (integer->char q) (integer->char q)))
         (delimiter (if (pm-at source triple opening) triple (string (integer->char q))))
         (n (pm-len source)))
    (let loop ((cursor (+ opening (string-length delimiter))))
      (cond ((>= cursor n) (values n delimiter #f))
            ((= (pm-ref source cursor) 92) (loop (+ cursor 2)))
            ((pm-at source delimiter cursor) (values (+ cursor (string-length delimiter)) delimiter #t))
            ((and (= (string-length delimiter) 1) (memv (pm-ref source cursor) '(13 10))) (values cursor delimiter #f))
            (else (loop (+ cursor 1)))))))

(define (pm-number-end source start)
  (let* ((n (pm-len source))
         (in (lambda (i chars) (and (< i n) (pm-in (pm-ref source i) chars))))
         (digits (lambda (i) (let loop ((i i)) (if (in i "0123456789_") (loop (+ i 1)) i)))))
    (if (and (< (+ start 1) n) (= (pm-ref source start) 48) (in (+ start 1) "xobXOB"))
        (let ((set (case (pm-ref source (+ start 1))
                     ((120 88) "0123456789abcdefABCDEF_") ((111 79) "01234567_") (else "01_"))))
          (let loop ((i (+ start 2))) (if (in i set) (loop (+ i 1)) i)))
        (let* ((i (digits start))
               (i (if (in i ".") (digits (+ i 1)) i))
               (i (if (in i "eE")
                      (let* ((e (+ i 1)) (e (if (in e "+-") (+ e 1) e)))
                        (if (and (< e n) (pm-digit (pm-ref source e))) (digits (+ e 1)) i))
                      i)))
          (if (in i "jJ") (+ i 1) i)))))

(define (pm-lex source)
  "Tolerant lexer: a list of tokens (SOURCE: a bytevector or a string)."
  (let* ((source (%utf8 source)) (n (pm-len source)))
    (let loop ((i 0) (tokens '()))
      (if (>= i n) (reverse tokens)
          (let ((c (pm-ref source i)) (start i))
            (cond
              ((memv c '(32 9 13 12)) (loop (+ i 1) tokens))
              ((= c 10) (loop (+ i 1) (cons (make-pm-token 'newline start (+ i 1) "\n") tokens)))
              ((= c 35)
               (let ((e (or (byte-position source 10 i) n)))
                 (loop e (cons (make-pm-token 'comment start e (pm-str source start e)) tokens))))
              (else
               (let* ((word-end (and (pm-name-start c)
                                     (let w ((j (+ i 1))) (if (and (< j n) (pm-name-part (pm-ref source j))) (w (+ j 1)) j))))
                      (opening (cond ((not word-end) i)
                                     ((and (member (string-downcase (pm-str source start word-end)) *pm-prefixes*)
                                           (< word-end n) (memv (pm-ref source word-end) '(34 39)))
                                      word-end)
                                     (else #f)))
                      (prefix (if (and word-end opening) (string-downcase (pm-str source start word-end)) "")))
                 (cond
                   ((not opening)
                    (loop word-end (cons (make-pm-token 'name start word-end (pm-str source start word-end)) tokens)))
                   ((memv (pm-ref source opening) '(34 39))
                    (let-values (((end delim closed) (pm-string-end source opening)))
                      (loop end (cons (make-pm-token 'string start end (pm-str source start end) prefix delim closed)
                                      tokens))))
                   ((or (pm-digit c) (and (= c 46) (< (+ i 1) n) (pm-digit (pm-ref source (+ i 1)))))
                    (let ((e (pm-number-end source start)))
                      (loop e (cons (make-pm-token 'number start e (pm-str source start e)) tokens))))
                   (else
                    (let ((e (char-end (octets-get source) n start)))
                      (loop e (cons (make-pm-token 'operator start e (pm-str source start e)) tokens)))))))))))))

(define (pm-line-start source pos)
  (let ((p (byte-position-back source 10 pos))) (if p (+ p 1) 0)))

(define (pm-column source pos) (column-at source pos))

(define (pm-indentation source pos)
  (let ((i (let loop ((i (pm-line-start source pos)))
             (if (and (< i (pm-len source)) (memv (pm-ref source i) '(32 9))) (loop (+ i 1)) i))))
    (pm-column source i)))

(define (pm-closing value)
  (let ((e (assoc value '(("(" . ")") ("[" . "]") ("{" . "}"))))) (and e (cdr e))))

(define (pm-statements tokens)
  "Four values: complete statements (each a list of tokens), the pending
one, the open brackets (innermost first) and whether a string is open."
  (let loop ((ts tokens) (statements '()) (current '()) (brackets '()) (in-string #f))
    (if (null? ts)
        (values (reverse statements) (reverse current) brackets in-string)
        (let* ((token (car ts)) (value (pm-token-value token)))
          (case (pm-token-kind token)
            ((comment) (loop (cdr ts) statements current brackets in-string))
            ((newline)
             (cond ((and (pair? current) (null? brackets) (not (equal? (pm-token-value (car current)) "\\")))
                    (loop (cdr ts) (cons (reverse current) statements) '() brackets in-string))
                   ((and (pair? current) (equal? (pm-token-value (car current)) "\\"))
                    (loop (cdr ts) statements (cdr current) brackets in-string))
                   (else (loop (cdr ts) statements current brackets in-string))))
            (else
             (let ((current (cons token current)))
               (cond ((eq? (pm-token-kind token) 'string)
                      (loop (cdr ts) statements current brackets
                            (and (not (pm-token-closed token))
                                 (or (= (string-length (pm-token-quote token)) 3) (ends-with-p "\\" value)))))
                     ((pm-closing value) (loop (cdr ts) statements current (cons token brackets) in-string))
                     ((and (pair? brackets) (equal? value (pm-closing (pm-token-value (car brackets)))))
                      (loop (cdr ts) statements current (cdr brackets) in-string))
                     (else (loop (cdr ts) statements current brackets in-string))))))))))

(define (pm-paint start end face colors) (paint colors start end (color-id face)))

;; The painter runs at every redisplay, so it is in C (src/highlight.c,
;; fe-highlight-python): the same lexer, keywords, definitions, decorators,
;; builtins and f-string fields as below.
(define (python-mode-highlight language text len colors)
  (fe-highlight-python (if (= len (pm-len text)) text (bytevector-copy text 0 len)) colors)
  colors)

(define (python-mode-indentation context)
  (let* ((source (ictx-text context))
         (pos (ictx-line context))
         (before (bytevector-copy source 0 pos))
         (current-line (pm-trim-left (bytevector-copy source pos (or (byte-position source 10 pos) (pm-len source)))))
         (width (ictx-width context)))
    (let-values (((statements pending brackets in-string) (pm-statements (pm-lex before))))
      (cond
        (in-string #f)
        ((pair? brackets)
         (let* ((opener (car brackets)) (start (pm-token-start opener)) (end (pm-token-end opener))
                (content (bytevector-copy before end (or (byte-position before 10 end) (pm-len before))))
                (trimmed (pm-trim content '(32 9 13))))
           (cond ((and (> (pm-len current-line) 0)
                       (equal? (pm-str current-line 0 1) (pm-closing (pm-token-value opener))))
                  (pm-indentation before start))
                 ((and (> (pm-len trimmed) 0) (not (= (pm-ref trimmed 0) 35)))
                  (pm-column before (+ end (- (pm-len content) (pm-len (pm-trim-left content))))))
                 (else (+ (pm-indentation before start) width)))))
        ((pair? pending) (+ (pm-indentation before (pm-token-start (car pending))) width))
        ((null? statements) 0)
        (else
         (let* ((previous (car (last-pair statements)))
                (base (pm-indentation before (pm-token-start (car previous))))
                (tokens (pm-lex current-line))
                (first (if (and (pair? tokens) (eq? (pm-token-kind (car tokens)) 'name)) (pm-token-value (car tokens)) ""))
                (partners (let ((e (assoc first '(("elif" "if" "elif") ("else" "if" "elif" "for" "while" "try" "except")
                                                  ("except" "try" "except") ("finally" "try" "except" "else")
                                                  ("case" "match" "case")))))
                            (and e (cdr e))))
                (partners (if (and (pair? tokens) (pair? (cdr tokens)) (member (pm-token-value (cadr tokens)) '("=" "(" ".")))
                              #f partners))
                (last-value (lambda (s) (pm-token-value (car (last-pair s)))))
                (found (and partners
                            (let loop ((ss (reverse statements))
                                       (limit (if (equal? (last-value previous) ":") (+ base width) base)))
                              (if (null? ss) #f
                                  (let* ((statement (car ss))
                                         (level (pm-indentation before (pm-token-start (car statement))))
                                         (head (pm-token-value (car statement)))
                                         (head (if (and (equal? head "async") (pair? (cdr statement)))
                                                   (pm-token-value (cadr statement)) head)))
                                    (if (and (<= level limit) (member head partners) (equal? (last-value statement) ":"))
                                        (if (and (equal? first "case") (equal? head "match")) (+ level width) level)
                                        (loop (cdr ss) (if (< level limit) level limit)))))))))
           (or found
               (cond ((equal? (last-value previous) ":") (+ base width))
                     ((member (pm-token-value (car previous)) '("return" "raise" "break" "continue" "pass"))
                      (max 0 (- base width)))
                     (else base)))))))))

(define (python-mode-levels context)
  (let ((column (python-mode-indentation context)) (width (ictx-width context)))
    (and column
         (sort (delete-duplicates (cons column (let loop ((i 0) (acc '()))
                                                 (if (> i (+ column width)) acc (loop (+ i width) (cons i acc))))))
               <))))

(define (python-mode-definition-positions source)
  (let-values (((statements pending b s) (pm-statements (pm-lex source))))
    (filter-map (lambda (statement)
                  (let ((head (pm-token-value (car statement))))
                    (and (or (member head '("def" "class"))
                             (and (equal? head "async") (pair? (cdr statement))
                                  (equal? (pm-token-value (cadr statement)) "def")))
                         (pm-token-start (car statement)))))
                (append statements (if (pair? pending) (list pending) '())))))

(define (python-mode-navigate direction)
  (let* ((positions (python-mode-definition-positions (buffer-substring 0 (buffer-size))))
         (here (point))
         (target (if (> direction 0)
                     (find (lambda (p) (> p here)) positions)
                     (find (lambda (p) (< p here)) (reverse positions)))))
    (if target (goto-char target) (message "No further Python definition"))))

(defcommand (python-next-definition) (python-mode-navigate 1))
(defcommand (python-previous-definition) (python-mode-navigate -1))

(define (python-mode-file-p filename)
  (and filename (member (file-extension filename) '(".py" ".pyw" ".pyi" ".synpy")) #t))

(defcommand (menu-indent)
  (if (and (menu-region-p) (python-mode-file-p (buffer-filename)))
      (indent-region)
      (message "Select Python lines first.")))

(define (python-mode-menu buffer-name buttons)
  (if (if *menu-rendering*
          (python-mode-file-p *menu-filename*)
          (and (> (window-count) 0)
               (call-in-window-of buffer-name (lambda () (python-mode-file-p (buffer-filename))))))
      (if *menu-full*
          (append (filter (lambda (b) (not (equal? (car b) "QUIT"))) buttons)
                  '(("#" "M-;") ("INDENT" menu-indent) ("DEF>" python-next-definition)
                    ("<DEF" python-previous-definition) ("QUIT" "C-x C-c")))
          (apply append
                 (map (lambda (button)
                        (cond ((equal? (car button) "?") (list button '("#" "M-;")))
                              ((equal? (car button) "DELETE") (list button '("INDENT" menu-indent)))
                              ((equal? (car button) "Select") (list '("MORE" more-menu) button))
                              ((equal? (car button) "MORE") (if *menu-region* (list button) '()))
                              (else (list button))))
                      buttons)))
      buttons))

(define (install-python-mode)
  (define-language "Python" 'extensions '(".py" ".pyw" ".pyi" ".synpy") 'line-comment "#"
    'highlighter python-mode-highlight)
  (define-indent-style 'python-smart python-mode-indentation (lambda (text start) #f))
  (define-indentation "Python" 'style 'python-smart 'width 4 'tabs #f 'cycle #t
    'levels 'python-mode-levels
    'electric-keys ":" 'electric-words '("elif" "else" "except" "finally" "case"))
  (install-mode-menu "python" python-mode-menu))

(register-editing-mode "python" install-python-mode)
