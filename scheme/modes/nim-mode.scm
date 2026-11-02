;;;; nim-mode.scm -- Nim editing mode
;;;;
;;;; Port of SBEmacs's lisp/modes/nim-mode.lisp (its Lisp implementation;
;;;; the optional native library is not used).  The pm-* token helpers come
;;;; from python-mode.scm.  Active from the start; M-x nim-mode reloads it.
;;;;
;;;;   menu  [#] comment; in [MORE]: BUILD, RUN, DEF>, <DEF

(define *nim-keywords*
  '("addr" "and" "as" "asm" "bind" "block" "break" "case" "cast" "concept"
    "const" "continue" "converter" "defer" "discard" "distinct" "div" "do"
    "elif" "else" "end" "enum" "except" "export" "finally" "for" "from"
    "func" "if" "import" "in" "include" "interface" "is" "isnot" "iterator"
    "let" "macro" "method" "mixin" "mod" "nil" "not" "notin" "object"
    "of" "or" "out" "proc" "ptr" "raise" "ref" "return" "shl" "shr"
    "static" "template" "try" "tuple" "type" "using" "var" "when" "while"
    "xor" "yield"))
(define *nim-definers* '("proc" "func" "method" "iterator" "converter" "macro" "template"))

(define (nim-normalize word)
  ;; Nim keeps the case of the first letter; later letters ignore case and _
  (if (= 0 (length word)) word
      (string-append (byte-substring word 0 1) (string-downcase (remove-byte (byte-substring word 1) 95)))))

(define (nim-lex source)
  "Tolerant lexer: nested comments, raw/triple strings, backtick names."
  (let ((n (length source)))
    (let loop ((i 0) (tokens '()))
      (if (>= i n) (reverse tokens)
          (let* ((start i) (c (aref source i))
                 (emit (lambda (kind end (closed #t) (delim ""))
                         (cons (make-pm-token kind start end (byte-substring source start end) "" delim closed) tokens)))
                 (at (lambda (text) (pm-at source text i))))
            (cond
              ((memv c '(32 9 13)) (loop (+ i 1) tokens))
              ((= c 10) (loop (+ i 1) (emit 'newline (+ i 1))))
              ((or (at "#[") (at "##["))
               (let comment ((j (if (at "##[") (+ i 3) (+ i 2))) (stack (list (if (at "##[") "]##" "]#"))))
                 (cond ((or (>= j n) (null? stack)) (loop j (emit 'comment j (null? stack))))
                       ((pm-at source "##[" j) (comment (+ j 3) (cons "]##" stack)))
                       ((pm-at source "#[" j) (comment (+ j 2) (cons "]#" stack)))
                       ((pm-at source (car stack) j) (comment (+ j (length (car stack))) (cdr stack)))
                       (else (comment (+ j 1) stack)))))
              ((= c 35) (let ((e (or (byte-position source 10 i) n))) (loop e (emit 'comment e))))
              ((= c 96) (let* ((p (byte-position source 96 (+ i 1))) (e (if p (+ p 1) n))) (loop e (emit 'name e))))
              ((pm-digit c)
               (let num ((j (+ i 1)))
                 (if (and (< j n)
                          (let ((b (aref source j)))
                            (or (pm-name-part b) (= b 39)
                                (and (= b 46) (not (pm-at source ".." j)))
                                (and (memv b '(43 45)) (memv (aref source (- j 1)) '(101 69))))))
                     (num (+ j 1))
                     (loop j (emit 'number j)))))
              (else
               (let* ((word-end (and (pm-name-start c)
                                     (let w ((j (+ i 1))) (if (and (< j n) (pm-name-part (aref source j))) (w (+ j 1)) j))))
                      (raw (and word-end (< word-end n) (= (aref source word-end) 34)))
                      (opening (cond (raw word-end) (word-end #f) (else i))))
                 (cond
                   ((not opening) (loop word-end (emit 'name word-end)))
                   ((memv (aref source opening) '(34 39))
                    (let* ((q (aref source opening))
                           (delimiter (if (and (= q 34) (pm-at source "\"\"\"" opening)) "\"\"\"" (string (integer->char q)))))
                      (let str ((j (+ opening (length delimiter))))
                        (cond ((>= j n) (loop j (emit 'string j #f delimiter)))
                              ((and raw (= (length delimiter) 1) (pm-at source "\"\"" j)) (str (+ j 2)))
                              ((pm-at source delimiter j)
                               (let ((e (+ j (length delimiter)))) (loop e (emit 'string e #t delimiter))))
                              ((and (not raw) (= (length delimiter) 1) (= (aref source j) 92)) (str (min n (+ j 2))))
                              ((and (= (length delimiter) 1) (= (aref source j) 10)) (loop j (emit 'string j #f delimiter)))
                              (else (str (+ j 1)))))))
                   (else (let ((e (char-end (octets-get source) n i))) (loop e (emit 'operator e)))))))))))))

;; The painter runs at every redisplay, so it is in C (src/highlight.c,
;; fe-highlight-nim), with the same lexer and keywords as NIM-LEX.
(define (nim-highlight language text len colors)
  (fe-highlight-nim (if (= len (length text)) text (byte-substring text 0 len)) colors)
  colors)

(define (nim-indentation context)
  (let* ((source (ictx-text context))
         (pos (ictx-line context))
         (before (byte-substring source 0 pos))
         (width (ictx-width context))
         (tokens (nim-lex before))
         (current (nim-lex (byte-substring source pos))))
    (if (and (pair? tokens) (not (pm-token-closed (car (last-pair tokens)))))
        #f
        (let-values (((statements pending brackets in-string) (pm-statements tokens)))
          (cond
            ((pair? brackets)
             (let ((opener (car brackets)))
               (if (and (pair? current) (equal? (pm-token-value (car current)) (pm-closing (pm-token-value opener))))
                   (pm-indentation before (pm-token-start opener))
                   (+ (pm-indentation before (pm-token-start opener)) width))))
            (else
             (let ((statements (if (pair? pending) (append statements (list pending)) statements)))
               (if (null? statements) 0
                   (let* ((previous (car (last-pair statements)))
                          (head (pm-token-value (car previous)))
                          (tail (pm-token-value (car (last-pair previous))))
                          (base (pm-indentation before (pm-token-start (car previous))))
                          (first (and (pair? current) (pm-token-value (car current))))
                          (partners (let ((e (assoc first '(("elif" "if" "when" "elif")
                                                            ("else" "if" "when" "elif" "case" "of" "for" "while" "try" "except")
                                                            ("of" "case" "of") ("except" "try" "except")
                                                            ("finally" "try" "except")))))
                                      (and e (cdr e))))
                          (found (and partners
                                      (let loop ((ss (reverse statements)) (limit (+ base width)))
                                        (if (null? ss) #f
                                            (let ((level (pm-indentation before (pm-token-start (caar ss))))
                                                  (word (pm-token-value (caar ss))))
                                              (if (and (<= level limit) (member word partners))
                                                  (if (equal? word "case") (+ level width) level)
                                                  (loop (cdr ss) (min level limit)))))))))
                     (or found
                         (cond ((or (member tail '(":" "=")) (member head '("case" "type" "var" "let" "const"))
                                    (member tail '("object" "enum" "tuple")))
                                ;; a declaration with an initializer is not a section header
                                (if (and (member head '("let" "var" "const" "type"))
                                         (not (member tail '("=" "object" "enum" "tuple")))
                                         (pair? (cdr previous)))
                                    base (+ base width)))
                               ((member tail '("+" "-" "*" "/" "," "and" "or" "&")) (+ base width))
                               (else base))))))))))))

(define (nim-levels context)
  (let ((col (nim-indentation context)) (width (ictx-width context)))
    (and col (sort (delete-duplicates (cons col (let loop ((i 0) (acc '()))
                                                  (if (> i (+ col width)) acc (loop (+ i width) (cons i acc))))))
                   <))))

(define (nim-file-p name) (and name (member (file-extension name) '(".nim" ".nims" ".nimble")) #t))

(define (nim-navigate direction)
  (let* ((positions (filter-map (lambda (token)
                                  (and (eq? (pm-token-kind token) 'name) (member (pm-token-value token) *nim-definers*)
                                       (pm-token-start token)))
                                (nim-lex (buffer-substring 0 (buffer-size)))))
         (here (point))
         (target (if (> direction 0) (find (lambda (p) (> p here)) positions)
                     (find (lambda (p) (< p here)) (reverse positions)))))
    (if target (goto-char target) (message "No further Nim definition"))))

(defcommand (nim-next-definition) (nim-navigate 1))
(defcommand (nim-previous-definition) (nim-navigate -1))

(define (nim-shell-quote text)
  (string-append "'" (string-join (string-split text "'") "'\"'\"'") "'"))

(define (nim-command-line file run arguments)
  (string-append "nim c " (if run "-r " "") "--hints:off " (nim-shell-quote file)
                 (if (and run (> (length arguments) 0)) (string-append " " arguments) "")))

(define (nim-execute run)
  (guard (e (#t (message "Nim: " (describe-error e))))
    (let ((file (buffer-filename)))
      (cond ((not (and file (string=? (file-extension file) ".nim"))) (message "Open and save a .nim source file first."))
            ((or (not (save-buffer (get-buffer-name))) (buffer-modified-p)) (message "Save failed; compilation cancelled."))
            (else
             (let* ((arguments (if run (prompt "Nim program arguments: " "") ""))
                    (command (nim-command-line (file-name-nondirectory file) run arguments)))
               (shell-command-window) (insert command) (shell-command-run)))))))

(defcommand (nim-build) (nim-execute #f))
(defcommand (nim-run) (nim-execute #t))
(defcommand (nim-native-status) (message "Nim mode: Scheme implementation"))

(define (nim-menu buffer buttons)
  (if (if *menu-rendering* (nim-file-p *menu-filename*)
          (and (> (window-count) 0) (call-in-window-of buffer (lambda () (nim-file-p (buffer-filename))))))
      (if *menu-full*
          (append (filter (lambda (b) (not (equal? (car b) "QUIT"))) buttons)
                  '(("#" "M-;") ("BUILD" nim-build) ("RUN" nim-run)
                    ("DEF>" nim-next-definition) ("<DEF" nim-previous-definition) ("QUIT" "C-x C-c")))
          (apply append (map (lambda (b) (if (equal? (car b) "?") (list b '("#" "M-;")) (list b))) buttons)))
      buttons))

(define (install-nim-mode)
  (define-language "Nim" 'extensions '(".nim" ".nims" ".nimble") 'line-comment "#" 'highlighter nim-highlight)
  (define-indent-style 'nim-smart nim-indentation (lambda (text start) #f))
  (define-indentation "Nim" 'style 'nim-smart 'width 2 'tabs #f 'cycle #t 'levels 'nim-levels
    'electric-keys ":" 'electric-words '("elif" "else" "of" "except" "finally"))
  (install-mode-menu "nim" nim-menu))

(register-editing-mode "nim" install-nim-mode)
