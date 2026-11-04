;;;; core.scm -- key bindings, commands, events from C, the kill ring
;;;;
;;;; Port of SBEmacs's lisp/core.lisp.  The C core owns the screen and the
;;;; command loop; it offers every key, typed character, click and change to
;;;; Scheme through EDITOR-EVENT (src/hooks.c).  A binding made here takes
;;;; precedence over the C core's own.

;;; ------------------------------------------------------------------
;;; Small helpers used everywhere
;;; ------------------------------------------------------------------

;; femtoscheme strings are UTF-8 byte arrays: AREF reads a byte, LENGTH
;; counts bytes and STRING.SUB cuts at byte offsets.  Buffer offsets are
;; bytes too, so the scanners below work on bytes.
(define (bytes-length s) (length s))
(define (byte-ref s i) (aref s i))
(define (byte-substring s start (end #f)) (string.sub s start (or end (length s))))

(define (->string x)
  (cond ((string? x) x)
        ((symbol? x) (symbol->string x))
        ((number? x) (number->string x))
        ((char? x) (string x))
        (else (let ((p (open-output-string))) (display x p) (get-output-string p)))))

(define (concat . parts) (apply string-append (map ->string parts)))

(define (trim s) (trim-bytes s " \t\n\r"))

(define (trim-bytes s chars)
  "S without the ASCII CHARS at either end."
  (let* ((in? (lambda (b) (and (< b 128) (string.find chars (string (integer->char b)) 0))))
         (n (length s))
         (a (let loop ((a 0)) (if (and (< a n) (in? (aref s a))) (loop (+ a 1)) a)))
         (z (let loop ((z n)) (if (and (> z a) (in? (aref s (- z 1)))) (loop (- z 1)) z))))
    (string.sub s a z)))
(define (trim-bytes-right s chars)
  "S without the ASCII CHARS at its end."
  (let loop ((z (length s)))
    (if (and (> z 0) (< (aref s (- z 1)) 128) (string.find chars (string.sub s (- z 1) z) 0))
        (loop (- z 1))
        (string.sub s 0 z))))

(define (starts-with-p prefix s) (string-prefix? prefix s))
(define (ends-with-p suffix s) (string-suffix? suffix s))

(define (split-lines s)
  "The lines of S, split at newlines (a final newline gives a last \"\")."
  (let loop ((start 0) (acc '()))
    (let ((nl (string.find s "\n" start)))
      (if nl
          (loop (+ nl 1) (cons (string.sub s start nl) acc))
          (reverse (cons (string.sub s start (length s)) acc))))))

(define (join-lines lines) (string-join lines "\n"))

(define (count-byte s b (start 0) (end #f))
  (let ((end (or end (length s))))
    (let loop ((i start) (n 0))
      (if (>= i end) n (loop (+ i 1) (if (= (aref s i) b) (+ n 1) n))))))

(define (byte-position s b (start 0) (end #f))
  (let ((end (or end (length s))))
    (let loop ((i start))
      (cond ((>= i end) #f) ((= (aref s i) b) i) (else (loop (+ i 1)))))))

(define (byte-position-back s b (end #f) (start 0))
  "The last index of byte B in S before END."
  (let loop ((i (- (or end (length s)) 1)))
    (cond ((< i start) #f) ((= (aref s i) b) i) (else (loop (- i 1))))))

(define (string-search needle s (start 0))
  "Byte index of NEEDLE in S, or #f."
  (string.find s needle start))

(define (string-search-back needle s)
  (let loop ((i (string.find s needle 0)) (last #f))
    (if i (loop (string.find s needle (+ i 1)) i) last)))

(define (make-spaces n) (make-string (max 0 n) #\space))

(define (pad-right s width)
  (let ((n (string-length s))) (if (>= n width) s (string-append s (make-spaces (- width n))))))

(define (pad-left s width)
  (let ((n (string-length s))) (if (>= n width) s (string-append (make-spaces (- width n)) s))))

(define (plural n word) (concat n " " word (if (= n 1) "" "s")))

(define (substitute-byte s from to)
  (if (not (byte-position s from)) s
      (let ((out (buffer)))
        (let loop ((i 0))
          (when (< i (length s))
            (let ((b (aref s i)))
              (io.write out (if (= b from) (string (integer->char to)) (string.sub s i (+ i 1))))
              (loop (+ i 1)))))
        (io.tostring! out))))

(define (remove-byte s b)
  (if (not (byte-position s b)) s
      (string-join (string-split s (string (integer->char b))) "")))

(define (one-line s)
  "S with every run of blanks and line breaks as one space."
  (string-join (filter (lambda (w) (not (string=? w "")))
                       (string-split (substitute-byte (substitute-byte (substitute-byte s 10 32) 9 32) 13 32) " "))
               " "))

(define (describe-error e)
  "One line for the message line."
  (concat "Error: "
          (one-line (cond ((and (pair? e) (eq? (car e) 'error) (pair? (cdr e)) (string? (cadr e)))
                           (apply string-append (cadr e)
                                  (map (lambda (x) (string-append " " (if (string? x) x (%write-string x))))
                                       (cddr e))))
                          ((error-object? e) (%exception->string e))
                          ((string? e) e)
                          (else (%write-string e))))))

(define (home-directory) (or (os.getenv "HOME") "."))
(define (config-file (file "")) (concat (home-directory) "/.chezemax/" file))

(define (file-name-nondirectory path)
  (let ((slash (byte-position-back path 47)))
    (if slash (byte-substring path (+ slash 1)) path)))

(define (file-name-directory path)
  "The folder part of PATH, ending in /; \"\" when it has none."
  (let ((slash (byte-position-back path 47)))
    (if slash (byte-substring path 0 (+ slash 1)) "")))

(define (file-exists-p path) (and (file-attributes path) #t))
(define (directory-p path) (let ((i (file-attributes path))) (and i (car i))))

(define (absolute-path path)
  (cond ((starts-with-p "/" path) path)
        ((starts-with-p "~/" path) (concat (home-directory) (byte-substring path 1)))
        (else (concat (path.cwd) "/" path))))

;;; ------------------------------------------------------------------
;;; Key names
;;; ------------------------------------------------------------------

(define (normalize-key-token token)
  "One key in Emacs notation (M-d, C-M-f, M-DEL, C-/ ...) -> the C core's
names (esc d, esc C-f, esc backspace, C-_ ...); a list of one or two."
  (define (simple k)
    (cond ((member k '("DEL" "<backspace>" "BS")) "backspace")
          ((string=? k "<delete>") "DEL")
          ((string=? k "TAB") "C-i")
          ((string=? k "RET") "C-m")
          ((string=? k "ESC") "esc")
          ((member k '("C-SPC" "C-@")) "C-space")
          ((member k '("C-/" "C--")) "C-_")
          ((string=? k "<f1>") "F1")
          ((member k '("<left>" "<right>" "<up>" "<down>"))      ; C-x <left>
           (byte-substring k 1 (- (length k) 1)))
          ((and (= (length k) 3) (string-prefix? "C-" k)
                (char-upper-case? (string-ref k 2)))
           (string "C-" (char-downcase (string-ref k 2))))
          (else k)))
  (cond ((and (> (length token) 4)
              (or (string-prefix? "C-M-" token) (string-prefix? "M-C-" token)))
         (list "esc" (simple (string-append "C-" (byte-substring token 4)))))
        ((and (> (length token) 2) (string-prefix? "M-" token))
         (list "esc" (simple (byte-substring token 2))))
        (else (list (simple token)))))

(define (key-tokens key)
  (filter (lambda (t) (not (string=? t ""))) (string-split key " ")))

(define (normalize-key key)
  "KEY in Emacs notation (\"M-d\", \"C-x C-f\", \"C-M-\\\\\") or as the C core
names it (\"esc d\") -> the core's name."
  (string-join (apply append (map normalize-key-token (key-tokens key))) " "))

(define (display-key name)
  "The core's key name in Emacs notation, for help: esc C-f -> C-M-f."
  (cond ((string=? name "esc [1;5C") "C-right")
        ((string=? name "esc [1;5D") "C-left")
        (else
         (let loop ((tokens (string-split name " ")) (out '()))
           (cond ((null? tokens) (string-join (reverse out) " "))
                 ((and (string=? (car tokens) "esc") (pair? (cdr tokens)))
                  (let ((next (cadr tokens)))
                    (loop (cddr tokens)
                          (cons (cond ((string=? next "backspace") "M-DEL")
                                      ((and (> (length next) 2) (string-prefix? "C-" next))
                                       (string-append "C-M-" (byte-substring next 2)))
                                      (else (string-append "M-" next)))
                                out))))
                 ((string=? (car tokens) "C-space") (loop (cdr tokens) (cons "C-SPC" out)))
                 ((string=? (car tokens) "C-i") (loop (cdr tokens) (cons "TAB" out)))
                 (else (loop (cdr tokens) (cons (car tokens) out))))))))

;;; ------------------------------------------------------------------
;;; Commands and the keymap
;;; ------------------------------------------------------------------

(defvar *keymap* (table))      ; core key name -> symbol or procedure
(defvar *commands* (table))    ; command name -> symbol, for M-x

(define (register-command symbol)
  (let ((name (symbol->string symbol)))
    (put! *commands* name symbol)
    (fe-add-command-name name)
    symbol))

;; (defcommand (name) body ...): define NAME and offer it to M-x
(define-macro (defcommand head . body)
  `(begin (define ,head ,@body)
          (register-command ',(car head))
          ',(car head)))

(define (define-command name procedure)
  "Older form: offer PROCEDURE to M-x as NAME (a string)."
  (put! *commands* name procedure)
  (fe-add-command-name name)
  name)

(define (command-procedure fn)
  (cond ((procedure? fn) fn)
        ((and (symbol? fn) (bound? fn) (procedure? (top-level-value fn))) (top-level-value fn))
        (else #f)))

(define (command-name fn)
  (cond ((symbol? fn) (symbol->string fn))
        ((string? fn) fn)
        (else "a function")))

(define (global-set-key key function)
  "Bind KEY to FUNCTION (a symbol naming a procedure of no arguments, or
the procedure).  Any key can be bound, in Emacs notation: \"C-c a\",
\"C-x h\", \"M-d\", \"C-M-f\", \"M-DEL\", \"F1\"."
  (when (symbol? function) (register-command function))
  (put! *keymap* (normalize-key key) function)
  function)

(define (table-remove! t key) (when (has? t key) (del! t key)))
(define (global-unset-key key) (table-remove! *keymap* (normalize-key key)) #t)
(define (key-binding key) (get *keymap* (normalize-key key) #f))

(define (key-command-name key)
  "The live Scheme binding, or the C command behind KEY; #f if unbound."
  (let* ((name (normalize-key key)) (fn (key-binding key))
         (builtin (if fn "" (fe-key-command name)))
         (builtin (if (and (not fn) (string=? builtin "")) (fe-key-command key) builtin)))
    (cond (fn (command-name fn))
          ((or (string=? builtin "") (string=? builtin "user-defined-function")) #f)
          (else builtin))))

(define *last-key* "")
(define *this-key* "")
(define *last-command* #f)
(define *this-command* #f)
(defvar *command-usage* (table))

(define (note-command-use command)
  (let ((name (cond ((symbol? command) (symbol->string command))
                    ((string? command) command)
                    (else #f))))
    (when name (put! *command-usage* name (+ 1 (get *command-usage* name 0))))))

(define (call-command fn)
  (let ((p (command-procedure fn)))
    (if p (p) (message (concat (command-name fn) " is not defined")))))

(define (run-key key)
  "Run the Scheme binding of KEY (a core key name); #f when it has none."
  (let ((fn (get *keymap* key #f)))
    (and fn (begin (call-command fn) #t))))

(define (command-boundary (key #t))
  "Before each key: the changes a command makes undo together."
  (when (bound? 'undo-boundary)
    (guard (e (#t #f)) (undo-boundary key))))

(define (run-key-as-typed key)
  "Do what typing KEY (Emacs notation) does: its Scheme binding, or else
the C core's.  For buttons and menus.  #f when KEY is bound to nothing."
  (let* ((k (normalize-key key))
         (fn (get *keymap* k #f)))
    (command-boundary k)
    (set! *this-key* k)
    (set! *this-command* (or fn k))
    (let ((result (dynamic-wind
                   (lambda () #f)
                   (lambda () (if fn (begin (call-command fn) #t) (= 1 (fe-run-c-key k))))
                   (lambda ()
                     (note-command-use *this-command*)
                     (set! *last-key* k)
                     (set! *last-command* *this-command*)))))
      result)))

(define (command key-or-name)
  "Run a command by name (M-x): Scheme's, or the C core's."
  (let ((fn (get *commands* key-or-name #f)))
    (cond (fn (set! *this-command* fn) (call-command fn) #t)
          (else (= 1 (fe-execute-command key-or-name))))))

;;; ------------------------------------------------------------------
;;; Hooks
;;; ------------------------------------------------------------------

(define *kill-hook* '())          ; called with the buffer name after a kill
(define *startup-hook* '())       ; called once the screen is up
(define *select-hook* '())        ; called after a mouse drag selected text
(define *self-insert-hook* '())   ; called with "x", "\t", "\n": true = handled

(define (add-hook! name fn)
  "Add FN (a symbol, so that reloading replaces it) to the hook NAME."
  (let ((hook (top-level-value name)))
    (unless (memq fn hook)
      (set-top-level-value! name (append hook (list fn))))))

(define (run-hook name . args)
  (for-each (lambda (f) (apply (command-procedure f) args)) (top-level-value name)))

(define (run-self-insert key)
  (let loop ((hooks *self-insert-hook*))
    (cond ((null? hooks) #f)
          ((apply (command-procedure (car hooks)) (list key)) #t)
          (else (loop (cdr hooks))))))

;;; ------------------------------------------------------------------
;;; The kill ring and the system clipboard
;;; ------------------------------------------------------------------

(defvar *kill-ring* '())
(define *kill-ring-max* 60)

(define (push-kill text)
  (set! *kill-ring* (cons text *kill-ring*))
  (when (> (length *kill-ring*) *kill-ring-max*)
    (set! *kill-ring* (list-head *kill-ring* *kill-ring-max*))))

(define (remember-kill buffer-name)
  (let ((text (get-clipboard)))
    (when (> (length text) 0) (push-kill text))))

(add-hook! '*kill-hook* 'remember-kill)

(define *use-system-clipboard* #t)
(defvar *clipboard-notice-shown* #f)

(define (clipboard-helper-missing-notice)
  (let ((tool (fe-clipboard-tool)))
    (when (and (not *clipboard-notice-shown*) (equal? tool ""))
      (set! *clipboard-notice-shown* #t)
      (message "To paste what other programs copy, install xclip (X11) or wl-clipboard (Wayland)")
      #t)))

(define (adopt-system-clipboard)
  "If the system clipboard holds text that is not the newest kill, push it
on the kill ring and make it what C-y inserts."
  (let ((text (and *use-system-clipboard* (system-clipboard))))
    (when (and text (not (and (pair? *kill-ring*) (string=? text (car *kill-ring*)))))
      (push-kill text)
      (fe-set-scrap text)
      text)))

(define *undo-mode* #t)
(defvar *init-errors* '())

;;; ------------------------------------------------------------------
;;; Running Scheme safely from inside C
;;; ------------------------------------------------------------------

;; Output printed by a command must not reach the terminal (curses owns
;; it): CALL-QUIETLY captures it.
(define (call-quietly thunk)
  (let ((out (buffer)))
    (let ((value (with-bindings ((*output-stream* out)) (thunk))))
      (cons value (io.tostring! out)))))

(define (eval-string string)
  "Read and evaluate every form in STRING; the last value."
  (let ((in (open-input-string string)))
    (let loop ((value #f))
      (let ((form (read in)))
        (if (eof-object? form) value (loop (eval form)))))))

(define (value->string v)
  (if (and (procedure? v) (not (builtin? v)))
      (let ((name (function:name v)))
        (if (symbol? name) (string-append "#<procedure " (symbol->string name) ">") "#<procedure>"))
      (let ((p (open-output-string))) (write v p) (get-output-string p))))

(define (eval-for-message string)
  "Evaluate STRING; what it printed and its value, on one line."
  (guard (e (#t (describe-error e)))
    (let* ((r (call-quietly (lambda () (eval-string string))))
           (printed (cdr r)))
      (one-line (if (string=? printed "")
                    (value->string (car r))
                    (concat printed " => " (value->string (car r))))))))

;; A modal key handler (the vim-like normal mode of read-only.scm) sees
;; every key first; it returns true when it took the key.
(defvar *modal-key-handler* #f)

(define (modal-key? kind key)
  (and *modal-key-handler*
       ((command-procedure *modal-key-handler*) kind key)))

(define (event-key arg)
  (if (modal-key? 'key arg) #t (event-key-normally arg)))

(define (event-key-normally arg)
  (command-boundary arg)
  (let ((fn (get *keymap* arg #f)))
    (set! *this-key* arg)
    (set! *this-command* (or fn arg))
    (if (not fn)
        #f
        (begin
          (dynamic-wind
           (lambda () #f)
           (lambda () (call-command fn))
           (lambda ()
             (note-command-use *this-command*)
             (set! *last-key* arg)
             (set! *last-command* *this-command*)))
          #t))))

(define (event-command arg)
  (let ((fn (get *commands* arg #f)))
    (and fn (command-procedure fn)
         (begin
           (set! *this-command* fn)
           (dynamic-wind (lambda () #f)
                         (lambda () (call-command fn))
                         (lambda () (set! *last-command* *this-command*)))
           #t))))

(define (event-self-insert arg)
  (if (modal-key? 'char arg) #t (event-self-insert-normally arg)))

(define (event-self-insert-normally arg)
  (command-boundary #t)
  (set! *last-key* "self-insert")
  (set! *last-command* 'self-insert)
  (run-self-insert arg))

(define (editor-event kind arg)
  "Every event from the C core.  True when Scheme handled it."
  (let* ((key-like (member kind '("key" "command" "menu")))
         (handled #f)
         (result
          (guard (e (#t (if key-like (set! handled #t)) (describe-error e)))
            (call-quietly
             (lambda ()
               (cond ((string=? kind "key") (set! handled (event-key arg)))
                     ((string=? kind "command") (set! handled (event-command arg)))
                     ((string=? kind "self-insert") (set! handled (event-self-insert arg)))
                     ((string=? kind "menu")
                      (set! handled #t)
                      (command-boundary "menu")
                      (run-mode-line-button (string->number arg)))
                     ((string=? kind "menu-hover")
                      (set! handled #t)
                      (describe-mode-line-button (string->number arg)))
                     ((string=? kind "select") (run-hook '*select-hook*))
                     ((string=? kind "complete-file")
                      (fe-set-completions (string-join (file-name-completions arg) "\n")))
                     ((string=? kind "complete-command")
                      (fe-set-completions (string-join (shell-command-completions arg) "\n")))
                     ((string=? kind "kill") (run-hook '*kill-hook* arg))
                     ((string=? kind "startup") (run-startup))
                     ((string=? kind "colors") (apply-color-theme (string->number arg))))
               #f)))))
    (when (string? result) (message result))
    handled))

;;; ------------------------------------------------------------------
;;; Start-up
;;; ------------------------------------------------------------------

(define *banner*
  '("                                     ____ _              "
    "                                    / ___| |__   ___ ____"
    "                                   | |   | '_ \\ / _ \\_  /"
    "                                   | |___| | | |  __// / "
    "                                    \\____|_| |_|\\___/___|"
    ""
    "                                       ___ _ __ ___   __ ___  __"
    "                                      / _ \\ '_ ` _ \\ / _` \\ \\/ /"
    "                                     |  __/ | | | | | (_| |>  < "
    "                                      \\___|_| |_| |_|\\__,_/_/\\_\\"))

(define *show-banner* #t)

(define (show-startup-message)
  (when (and *show-banner* (string=? "*scratch*" (fe-buffer-name)) (= 0 (fe-buffer-size)))
    (fe-insert "\n\n")
    (for-each (lambda (line) (fe-insert (string-trim-right line)) (fe-insert "\n")) *banner*)
    (fe-insert (concat "\n                 " (fe-version) "\n\n"))
    (fe-insert "                 C-h help;  C-c r Claude;  C-c g ChatGPT;  C-x C-c quit\n")
    (fe-set-point 0)
    (fe-set-modified 0)))

(add-hook! '*startup-hook* 'show-startup-message)

(define (run-startup)
  (run-hook '*startup-hook*)
  (if (pair? *init-errors*)
      (message (string-join (reverse *init-errors*) "; "))
      (message "Chezemax -- C-h help; C-c r Claude; C-c g ChatGPT")))
