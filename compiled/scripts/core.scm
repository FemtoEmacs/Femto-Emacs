;;;; core.scm -- key bindings, commands, events from C, the kill ring
;;;;
;;;; In Chez Scheme, compiled by Schemer (PORT-TO-SCHEMER.md, step 4): the
;;;; port of scheme/core.scm, which femtoscheme runs until all the scripts
;;;; are compiled.  The C core owns the screen and the command loop; it
;;;; offers every key, typed character, click and change to Scheme through
;;;; EDITOR-EVENT.  A binding made here takes precedence over the C core's
;;;; own.
;;;;
;;;; Strings are Chez strings, of characters.  The buffer's offsets are
;;;; bytes of UTF-8 text, so the byte- procedures below count bytes: on a
;;;; string they count the bytes of its UTF-8, and they take bytevectors
;;;; too.  The other string procedures count characters.

;;; ------------------------------------------------------------------
;;; Small helpers used everywhere
;;; ------------------------------------------------------------------

(define (%utf8 s) (if (bytevector? s) s (string->utf8 s)))

(define (bytes-length s) (if (bytevector? s) (bytevector-length s) (bytevector-length (string->utf8 s))))
(define (byte-ref s i) (bytevector-u8-ref (%utf8 s) i))
(define byte-substring
  (case-lambda
    ((s start) (byte-substring s start (bytes-length s)))
    ((s start end)
     (let ((b (%utf8 s)))
       (if (bytevector? s)
           (bytevector-copy b start end)
           (utf8->string (bytevector-copy b start end)))))))

(define (->string x)
  (cond ((string? x) x)
        ((symbol? x) (symbol->string x))
        ((number? x) (number->string x))
        ((char? x) (string x))
        ((bytevector? x) (utf8->string x))
        (else (let ((p (open-output-string))) (display x p) (get-output-string p)))))

(define (concat . parts) (apply string-append (map ->string parts)))

(define (trim s) (trim-chars s " \t\n\r"))
(define (%in-chars? chars) (lambda (c) (string-index chars c)))
(define (trim-chars s chars)
  "S without the CHARS at either end."
  (string-trim-both s (%in-chars? chars)))
(define (trim-chars-right s chars)
  "S without the CHARS at its end."
  (string-trim-right s (%in-chars? chars)))
;; femtoscheme's names: the characters cut are ASCII, so bytes and
;; characters agree
(define (trim-bytes s chars) (trim-chars s chars))
(define (trim-bytes-right s chars) (trim-chars-right s chars))

(define (starts-with-p prefix s) (string-prefix? prefix s))
(define (ends-with-p suffix s) (string-suffix? suffix s))

(define (split-lines s)
  "The lines of S, split at newlines (a final newline gives a last \"\")."
  (string-split s #\newline))

(define (join-lines lines) (string-join lines "\n"))

;;; Bytes of S (a string's UTF-8, or a bytevector): B is a byte, offsets
;;; are bytes
(define count-byte
  (case-lambda
    ((s b) (count-byte s b 0 #f))
    ((s b start) (count-byte s b start #f))
    ((s b start end)
     (let* ((v (%utf8 s)) (end (or end (bytevector-length v))))
       (let loop ((i start) (n 0))
         (if (>= i end) n (loop (+ i 1) (if (= (bytevector-u8-ref v i) b) (+ n 1) n))))))))

(define byte-position
  (case-lambda
    ((s b) (byte-position s b 0 #f))
    ((s b start) (byte-position s b start #f))
    ((s b start end)
     (let* ((v (%utf8 s)) (end (or end (bytevector-length v))))
       (let loop ((i start))
         (cond ((>= i end) #f) ((= (bytevector-u8-ref v i) b) i) (else (loop (+ i 1)))))))))

(define byte-position-back
  (case-lambda
    ((s b) (byte-position-back s b #f 0))
    ((s b end) (byte-position-back s b end 0))
    ((s b end start)
     "The last index of byte B in S before END."
     (let ((v (%utf8 s)))
       (let loop ((i (- (or end (bytevector-length v)) 1)))
         (cond ((< i start) #f) ((= (bytevector-u8-ref v i) b) i) (else (loop (- i 1)))))))))

;;; Characters of S
(define string-search
  (case-lambda
    ((needle s) (string-search-forward needle s 0))
    ((needle s start) (string-search-forward needle s start))))

(define (string-search-back needle s)
  (let loop ((i (string-search-forward needle s 0)) (last #f))
    (if i (loop (string-search-forward needle s (+ i 1)) i) last)))

(define (make-spaces n) (make-string (max 0 n) #\space))

(define (pad-right s width)
  (let ((n (string-length s))) (if (>= n width) s (string-append s (make-spaces (- width n))))))

(define (pad-left s width)
  (let ((n (string-length s))) (if (>= n width) s (string-append (make-spaces (- width n)) s))))

(define (plural n word) (concat n " " word (if (= n 1) "" "s")))

;;; FROM and TO are bytes, as in femtoscheme; the characters of the same codes
(define (substitute-byte s from to)
  (let ((f (integer->char from)) (t (integer->char to)))
    (string-map (lambda (c) (if (char=? c f) t c)) s)))

(define (remove-byte s b)
  (let ((c (integer->char b)))
    (list->string (filter (lambda (x) (not (char=? x c))) (string->list s)))))

(define (one-line s)
  "S with every run of blanks and line breaks as one space."
  (string-join (filter (lambda (w) (not (string=? w ""))) (string-split s " \t\n\r")) " "))

(define (%write-string x) (let ((p (open-output-string))) (write x p) (get-output-string p)))

(define (%error-text e)
  (let ((irritants (error-object-irritants e)))
    (apply string-append (->string (error-object-message e))
           (map (lambda (x) (string-append " " (if (string? x) x (%write-string x)))) irritants))))

(define (describe-error e)
  "One line for the message line."
  (concat "Error: "
          (one-line (cond ((and (pair? e) (eq? (car e) 'error) (pair? (cdr e)) (string? (cadr e)))
                           (apply string-append (cadr e)
                                  (map (lambda (x) (string-append " " (if (string? x) x (%write-string x))))
                                       (cddr e))))
                          ((error-object? e) (%error-text e))
                          ((string? e) e)
                          (else (%write-string e))))))

(define (home-directory) (or (getenv "HOME") "."))
(define config-file
  (case-lambda
    (() (config-file ""))
    ((file) (concat (home-directory) "/.chezemax/" file))))

(define (file-name-nondirectory path)
  (let ((slash (string-index-right path #\/)))
    (if slash (substring path (+ slash 1) (string-length path)) path)))

(define (file-name-directory path)
  "The folder part of PATH, ending in /; \"\" when it has none."
  (let ((slash (string-index-right path #\/)))
    (if slash (substring path 0 (+ slash 1)) "")))

(define (file-exists-p path) (and (file-attributes path) #t))
(define (directory-p path) (let ((i (file-attributes path))) (and i (car i))))

(define (absolute-path path)
  (cond ((starts-with-p "/" path) path)
        ((starts-with-p "~/" path) (concat (home-directory) (substring path 1 (string-length path))))
        (else (concat (current-directory) "/" path))))

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
           (substring k 1 (- (string-length k) 1)))
          ((and (= (string-length k) 3) (string-prefix? "C-" k)
                (char-upper-case? (string-ref k 2)))
           (string #\C #\- (char-downcase (string-ref k 2))))
          (else k)))
  (let ((n (string-length token)))
    (cond ((and (> n 4) (or (string-prefix? "C-M-" token) (string-prefix? "M-C-" token)))
           (list "esc" (simple (string-append "C-" (substring token 4 n)))))
          ((and (> n 2) (string-prefix? "M-" token))
           (list "esc" (simple (substring token 2 n))))
          (else (list (simple token))))))

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
                                      ((and (> (string-length next) 2) (string-prefix? "C-" next))
                                       (string-append "C-M-" (substring next 2 (string-length next))))
                                      (else (string-append "M-" next)))
                                out))))
                 ((string=? (car tokens) "C-space") (loop (cdr tokens) (cons "C-SPC" out)))
                 ((string=? (car tokens) "C-i") (loop (cdr tokens) (cons "TAB" out)))
                 (else (loop (cdr tokens) (cons (car tokens) out))))))))

;;; ------------------------------------------------------------------
;;; Commands and the keymap
;;; ------------------------------------------------------------------

(defvar *keymap* (make-hashtable string-hash string=?))      ; core key name -> symbol or procedure
(defvar *commands* (make-hashtable string-hash string=?))    ; command name -> symbol, for M-x

(define (register-command symbol)
  (let ((name (symbol->string symbol)))
    (hashtable-set! *commands* name symbol)
    (fe-add-command-name name)
    symbol))

;; (defcommand (name) body ...) is in compiled/syntax.scm

(define (define-command name procedure)
  "Older form: offer PROCEDURE to M-x as NAME (a string)."
  (hashtable-set! *commands* name procedure)
  (fe-add-command-name name)
  name)

(define (command-procedure fn)
  (cond ((procedure? fn) fn)
        ((and (symbol? fn) (top-level-bound? fn) (procedure? (top-level-value fn))) (top-level-value fn))
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
  (hashtable-set! *keymap* (normalize-key key) function)
  function)

(define (table-remove! t key) (hashtable-delete! t key))
(define (global-unset-key key) (table-remove! *keymap* (normalize-key key)) #t)
(define (key-binding key) (hashtable-ref *keymap* (normalize-key key) #f))

(define *last-key* "")
(define *this-key* "")
(define *last-command* #f)
(define *this-command* #f)
(defvar *command-usage* (make-hashtable string-hash string=?))

(define (note-command-use command)
  (let ((name (cond ((symbol? command) (symbol->string command))
                    ((string? command) command)
                    (else #f))))
    (when name (hashtable-update! *command-usage* name (lambda (n) (+ n 1)) 0))))

(define (call-command fn)
  (let ((p (command-procedure fn)))
    (if p (p) (message (concat (command-name fn) " is not defined")))))

(define (run-key key)
  "Run the Scheme binding of KEY (a core key name); #f when it has none."
  (let ((fn (hashtable-ref *keymap* key #f)))
    (and fn (begin (call-command fn) #t))))

(define command-boundary
  (case-lambda
    (() (command-boundary #t))
    ((key)
     "Before each key: the changes a command makes undo together."
     (when (top-level-bound? 'undo-boundary)
       (guard (e (#t #f)) ((top-level-value 'undo-boundary) key))))))

(define (%after-command key)
  (note-command-use *this-command*)
  (set! *last-key* key)
  (set! *last-command* *this-command*))

(define (run-key-as-typed key)
  "Do what typing KEY (Emacs notation) does: its Scheme binding, or else
the C core's.  For buttons and menus.  #f when KEY is bound to nothing."
  (let* ((k (normalize-key key))
         (fn (hashtable-ref *keymap* k #f)))
    (command-boundary k)
    (set! *this-key* k)
    (set! *this-command* (or fn k))
    (dynamic-wind
     (lambda () #f)
     (lambda () (if fn (begin (call-command fn) #t) (= 1 (fe-run-c-key k))))
     (lambda () (%after-command k)))))

(define (command key-or-name)
  "Run a command by name (M-x): Scheme's, or the C core's."
  (let ((fn (hashtable-ref *commands* key-or-name #f)))
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
          (((command-procedure (car hooks)) key) #t)
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
    (when (> (string-length text) 0) (push-kill text))))

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
  (let* ((out (open-output-string))
         (value (%with-port (list out) thunk)))
    (cons value (get-output-string out))))

;; EVAL-STRING (M-:, C-x C-e) is compiled/eval-compiled.scm's

(define (value->string v)
  (if (and (procedure? v) (not (foreign-procedure? v)))
      (let ((name (procedure-name v)))
        (if (symbol? name) (string-append "#<procedure " (symbol->string name) ">") "#<procedure>"))
      (%write-string v)))

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
  (let ((fn (hashtable-ref *keymap* arg #f)))
    (set! *this-key* arg)
    (set! *this-command* (or fn arg))
    (and fn
         (begin
           (dynamic-wind
            (lambda () #f)
            (lambda () (call-command fn))
            (lambda () (%after-command arg)))
           #t))))

(define (event-command arg)
  (let ((fn (hashtable-ref *commands* arg #f)))
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

;;; The procedures of scripts not compiled yet, by name (compiled/scripts/
;;; pending.scm defines what is missing)
(define (%call name . args) (apply (top-level-value name) args))

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
                      (%call 'run-mode-line-button (string->number arg)))
                     ((string=? kind "select") (run-hook '*select-hook*))
                     ((string=? kind "complete-file")
                      (fe-set-completions (string-join (%call 'file-name-completions arg) "\n")))
                     ((string=? kind "complete-command")
                      (fe-set-completions (string-join (%call 'shell-command-completions arg) "\n")))
                     ((string=? kind "kill") (run-hook '*kill-hook* arg))
                     ((string=? kind "startup") (run-startup))
                     ((string=? kind "colors") (%call 'apply-color-theme (string->number arg))))
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
