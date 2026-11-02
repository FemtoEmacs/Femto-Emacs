;;;; eval-compiled.scm -- M-:, C-x C-e, --eval and your files, compiled
;;;;
;;;; Everything you evaluate is compiled by Schemer into a program of its
;;;; own and run at full speed (src/compiled-eval.c: the compiler runs in
;;;; the editor's process, from its saved machine code, in under a second).
;;;; There is no interpreter.
;;;;
;;;; The program cannot change the editor: it calls the editor's procedures
;;;; by name, with data ((insert "Hello"), (goto-char 0), (message ...)), and
;;;; reads its variables; defining one of the editor's names is refused, and
;;;; so is setting one -- except from your own files (~/.chezemax/init.scm,
;;;; languages/, extensions/), which exist to set the editor's variables and
;;;; bind its keys.  A procedure cannot be given to the editor: new commands
;;;; go in a script (~/.chezemax/users, chezemax --compile-scripts).
;;;;
;;;; What M-: and C-x C-e define makes a session: each later evaluation is
;;;; compiled with it, so (define (fib n) ...) with C-x C-e, then
;;;; (time (fib 34)), works; a variable keeps its value from one evaluation
;;;; to the next when the value is data.  The session lasts until the editor
;;;; stops (M-x scheme-reset forgets it).

(define eval-compiled (foreign-procedure "eval-compiled" (string scheme-object boolean) scheme-object))

;;; ------------------------------------------------------------------
;;; The forms
;;; ------------------------------------------------------------------

(define (%defined-names form)           ; the names a top-level FORM defines
  (if (not (pair? form)) '()
      (case (car form)
        ((define define-syntax define-macro defvar)
         (if (pair? (cdr form))
             (let loop ((t (cadr form))) (if (pair? t) (loop (car t)) (if (symbol? t) (list t) '())))
             '()))
        ((define-values)
         (if (pair? (cdr form))
             (let loop ((f (cadr form)) (acc '()))
               (cond ((pair? f) (loop (cdr f) (if (symbol? (car f)) (cons (car f) acc) acc)))
                     ((symbol? f) (cons f acc))
                     (else acc)))
             '()))
        ((define-record-type)
         (if (and (list? form) (>= (length form) 4))
             (append (if (pair? (caddr form)) (list (car (caddr form))) '())
                     (if (symbol? (cadddr form)) (list (cadddr form)) '())
                     (apply append (map (lambda (f) (if (pair? f) (filter symbol? (cdr f)) '())) (cddddr form))))
             '()))
        ((defcommand) (if (and (pair? (cdr form)) (pair? (cadr form))) (list (car (cadr form))) '()))
        ((begin) (apply append (map %defined-names (cdr form))))
        (else '()))))

(define (%symbols-in x acc)             ; the symbols of X, outside quotes
  (cond ((symbol? x) (if (memq x acc) acc (cons x acc)))
        ((pair? x) (if (eq? (car x) 'quote) acc (%symbols-in (cdr x) (%symbols-in (car x) acc))))
        ((vector? x) (%symbols-in (vector->list x) acc))
        (else acc)))

(define (%loops? x)                     ; does X define, make procedures or loop?
  (and (pair? x)
       (not (eq? (car x) 'quote))
       (or (memq (car x) '(define define-values define-record-type define-syntax define-macro defvar defcommand
                           lambda case-lambda do letrec letrec* named-lambda))
           (and (eq? (car x) 'let) (pair? (cdr x)) (symbol? (cadr x)))
           (let loop ((l x)) (and (pair? l) (or (%loops? (car l)) (loop (cdr l))))))
       #t))

;;; ------------------------------------------------------------------
;;; The session
;;; ------------------------------------------------------------------

(define *eval-session* '())             ; ((name . form) ...), oldest first

(define (%session-names) (map car *eval-session*))

(define (%session-add! form)
  (for-each (lambda (name)
              (let ((e (assq name *eval-session*)))
                (if e (set-cdr! e form)
                    (set! *eval-session* (append *eval-session* (list (cons name form)))))))
            (%defined-names form)))

(define (%session-forms)                ; each form once, in order
  (let loop ((l *eval-session*) (acc '()))
    (cond ((null? l) (reverse acc))
          ((memq (cdar l) acc) (loop (cdr l) acc))
          (else (loop (cdr l) (cons (cdar l) acc))))))

(define (%session-variables)            ; names whose form is (define name data-expression)
  (filter-map (lambda (e)
                (let ((f (cdr e)))
                  (and (pair? f) (eq? (car f) 'define) (symbol? (cadr f)) (eq? (cadr f) (car e))
                       (not (and (pair? (cddr f)) (pair? (caddr f)) (memq (car (caddr f)) '(lambda case-lambda))))
                       (car e))))
            *eval-session*))

(defcommand (scheme-reset)
  "Forget the definitions of M-: and C-x C-e (the session)."
  (set! *eval-session* '())
  (message "The session's definitions are forgotten"))

;;; ------------------------------------------------------------------
;;; Evaluating
;;; ------------------------------------------------------------------

;;; A value that cannot be read back (a procedure): its written text
(define-record-type %opaque (%make-opaque text) %opaque? (text %opaque-text))

(define (value->string v)
  (cond ((%opaque? v) (%opaque-text v))
        ((and (procedure? v) (not (foreign-procedure? v)))
         (let ((name (procedure-name v)))
           (if (symbol? name) (string-append "#<procedure " (symbol->string name) ">") "#<procedure>")))
        (else (%write-string v))))

(define (%datum text)                   ; TEXT read, or #f when it is not data
  (and (not (string-search "#<" text))
       (guard (e (#t #f))
         (let ((p (open-input-string text)))
           (let ((v (read p))) (and (not (eof-object? v)) (eof-object? (read p)) (list v)))))))

(define (%write-text x) (let ((p (open-output-string))) (write x p) (get-output-string p)))

(define (%program-text forms)
  ;; the session, the new forms, then a report: the last form's value, then
  ;; each session variable's, one a line
  (let* ((last (car (last-pair forms)))
         (front (reverse (cdr (reverse forms))))
         (result (if (pair? (%defined-names last)) (list 'quote (car (%defined-names last))) last))
         (vars (%session-variables))
         (p (open-output-string)))
    ;; the scripts' forms that make sense in a program of its own
    (display %program-preamble p)
    ;; each definition once: the session's earlier ones, then FORMS in their
    ;; order (a name defined twice would not be called directly, link.scm)
    (for-each (lambda (f) (write f p) (newline p))
              (append (filter (lambda (f) (not (memq f forms))) (%session-forms)) front))
    (when (pair? (%defined-names last)) (write last p) (newline p))
    (write `(let ((%%eval-r ,result) (%%eval-p (open-output-string)))
              (write %%eval-r %%eval-p)
              ,@(map (lambda (v) `(begin (newline %%eval-p) (write ',v %%eval-p) (write-string "\t" %%eval-p) (write ,v %%eval-p)))
                     vars)
              (get-output-string %%eval-p))
           p)
    (get-output-string p)))

(define %program-preamble
  "(define-syntax defvar (syntax-rules () ((_ n v) (define n v)) ((_ n) (define n #f))))
(define-syntax trycatch (syntax-rules () ((_ e h) (guard (x (#t (h x))) e))))
(define (describe-error e)
  (if (error-object? e)
      (let ((p (open-output-string)))
        (display (error-object-message e) p)
        (for-each (lambda (x) (display \" \" p) (write x p)) (error-object-irritants e))
        (get-output-string p))
      (let ((p (open-output-string))) (write e p) (get-output-string p))))
")

;;; While a program runs, may it set the editor's variables?  Only one of
;;; your files may (LOAD)
(define *editor-settable* #f)

(define (%refuse-editor-name name)
  (error (string-append (symbol->string name) " is the editor's: change it in a script")))

;;; FORMS compiled and run; SESSION? : with the session (M-:, C-x C-e)
(define (%compiled-eval forms session?)
  (when (any (lambda (f) (and (pair? f) (memq (car f) '(defcommand define-macro)))) forms)
    (error "a command belongs in a script (~/.chezemax/users, then M-x compile-scripts): evaluated code cannot give the editor a procedure"))
  (for-each (lambda (name)
              (when (top-level-bound? name) (%refuse-editor-name name)))
            (apply append (map %defined-names forms)))
  (let ((before *eval-session*) (outside *eval-session*))
    (unless session? (set! *eval-session* '()))
    (for-each (lambda (f) (when (pair? (%defined-names f)) (%session-add! f))) forms)
    (let* ((own (%session-names))
           ;; the editor's variables the code reads (its procedures are
           ;; called by name, link.scm)
           (globals (filter (lambda (s) (and (not (memq s own)) (top-level-bound? s)
                                             (not (procedure? (top-level-value s)))))
                            (%symbols-in (append (%session-forms) forms) '())))
           (r (eval-compiled (%program-text forms) (map symbol->string globals) (not session?)))
           (ok (car r)) (text (cadr r)) (output (caddr r)))
      (unless session? (set! *eval-session* outside))
      (unless ok
        (set! *eval-session* before)
        ;; what it printed before the error, then the error alone
        (let* ((i (string-search "Error: " output))
               (message (if i (trim (substring output (+ i 7) (string-length output))) text))
               (j (string-search "schemer-global-set!: " message)))
          (when i (display (substring output 0 i)))
          (error (if j (substring message (+ j 21) (string-length message)) message))))
      (display output)
      ;; the report: the value, then "name<TAB>value" lines
      (let* ((report (let ((d (guard (e (#t #f)) (read (open-input-string text)))))   ; a string, which may hold #<...>
                       (if (string? d) d "")))
             (lines (string-split report #\newline))
             (value-text (if (pair? lines) (car lines) "")))
        (for-each (lambda (line)
                    (let ((tab (string-index line #\tab)))
                      (when tab
                        (let ((name (string->symbol (substring line 0 tab)))
                              (d (%datum (substring line (+ tab 1) (string-length line)))))
                          (let ((e (assq name *eval-session*)))
                            (when (and e d)
                              (set-cdr! e (list 'define name (list 'quote (car d))))))))))
                  (if (pair? lines) (cdr lines) '()))
        (let ((d (%datum value-text)))
          (cond ((string=? value-text "") (if #f #f))
                (d (car d))
                (else (%make-opaque value-text))))))))

(define (%read-all port)
  (let loop ((acc '()))
    (let ((x (read port)))
      (if (eof-object? x) (reverse acc) (loop (cons x acc))))))

(define (eval-string string)
  "M-:, C-x C-e, --eval: compile the forms of STRING, with the session, and
run them; the value of the last.  The editor's names cannot be redefined
or set."
  (let ((forms (%read-all (open-input-string string))))
    (if (null? forms) (if #f #f) (%compiled-eval forms #t))))

(define (eval x . environment)
  "The datum X compiled and run, with the session."
  (%compiled-eval (list x) #t))

(define (load file . environment)
  "Your file FILE compiled and run: it may set the editor's variables and
bind keys, not redefine them.  Not part of the session."
  (let ((text (file-contents file)))
    (unless (string? text) (error "load: cannot read" file))
    (let ((forms (%read-all (open-input-string text))))
      (unless (null? forms)
        (dynamic-wind
         (lambda () (set! *editor-settable* #t))
         (lambda () (%compiled-eval forms #f))
         (lambda () (set! *editor-settable* #f)))))
    (if #f #f)))

(define (load-script file)
  "Load FILE; an error is reported, not raised (the other files still load)."
  (guard (e (#t (let ((text (concat (file-name-nondirectory file) ": " (describe-error e))))
                  (set! *init-errors* (cons text *init-errors*))
                  #f)))
    (load file)
    #t))

;;; ------------------------------------------------------------------
;;; The compiled code calls the editor: "(name argument ...)", answered
;;; "ok VALUE" or "error MESSAGE" (src/compiled-eval.c)
;;; ------------------------------------------------------------------

(define hook-request 7)
(compiled-hook! hook-request (lambda (text) (%editor-request text)))

(define (%editor-request text)
  (guard (e (#t (string-append "error " (%bridge-error-text e))))
    (let ((request (guard (e (#t (error "only data (numbers, strings, symbols, lists ...) can be given to the editor")))
                     (read (open-input-string text)))))
      (let ((name (car request)) (args (cdr request)))
        (case name
          ((schemer-global-get)
           (string-append "ok " (%write-text (top-level-value (car args)))))
          ((schemer-global-set!)
           (if *editor-settable*
               (begin (set-top-level-value! (car args) (cadr args)) "ok #t")
               (%refuse-editor-name (car args))))
          (else
           (let ((p (and (symbol? name) (top-level-bound? name) (top-level-value name))))
             (unless (procedure? p) (error "unbound variable" name))
             (string-append "ok " (%write-text (apply p args))))))))))
