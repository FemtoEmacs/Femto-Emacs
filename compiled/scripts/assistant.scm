;;;; assistant.scm -- ask Claude for hints, from inside the editor
;;;;
;;;; In Chez Scheme, compiled by Schemer: the port of scheme/extensions/
;;;; assistant.scm (itself a port of SBEmacs's lisp/extensions/
;;;; assistant.lisp).
;;;;
;;;;   C-c r   a small menu: h for hints about the code at the cursor, q to
;;;;           write a question (C-c r again sends it), d for a discussion;
;;;;           the answer appears in a window below
;;;;   C-c y   insert the code the assistant proposed, at the cursor, after
;;;;           you confirm (undo with C-/); or create the buffer it proposed
;;;;           (```new-buffer NAME, with <<FILE>> for the whole file)
;;;;   C-c t   in a discussion, insert the snippet under the cursor
;;;;   C-c g   Codex (ChatGPT), see codex.scm
;;;;
;;;; The keys follow Isaac Asimov's Three Laws of Robotics.  C-c r is "R."
;;;; for robot, the title Asimov gives his robots (R. Daneel Olivaw).
;;;;
;;;;   First Law:  the assistant never changes your text by itself.  It sees
;;;;               only what C-c r sends, and the Claude Code CLI runs with
;;;;               every tool disabled, so it cannot touch your files.
;;;;   Second Law: C-c y types into the buffer only on your order, asks
;;;;               first, and C-/ takes it back.
;;;;   Third Law:  a missing program, a network error or a timeout ends in
;;;;               a message, never in a crash or a lost buffer.
;;;;
;;;; How Claude is reached (*CLAUDE-TRANSPORT*):
;;;;
;;;;   'cli   the Claude Code program, `claude -p`, with your usual login
;;;;   'api   the Messages API through curl, with ANTHROPIC_API_KEY or the
;;;;          first line of ~/.chezemax/anthropic-api-key
;;;;   'auto  (default) 'cli when `claude` is installed, otherwise 'api
;;;;
;;;; Offsets into an answer that meet the buffer's (the fenced blocks of a
;;;; discussion) are bytes, as the buffer's are.

;;; ------------------------------------------------------------------
;;; Settings
;;; ------------------------------------------------------------------

(defvar *claude-transport* 'auto)
(defvar *claude-model* #f)            ; e.g. "sonnet" or "opus"; #f: your default
(defvar *claude-api-model* "claude-sonnet-5-5")
(defvar *assistant-timeout* 180)      ; seconds
(defvar *assistant-context-bytes* 400000) ; a whole paper fits
(define *assistant-buffer* "*assistant*")
(define *claude-request-buffer* "*claude-request*")
(define *claude-discussion-buffer* "*discussion*")
(defvar *discussion-origin* #f)

(define *new-buffer-instructions*
  "You cannot open buffers or files, but you can propose a new buffer for
the user to create with one key.  Write its whole text in ONE fenced block
whose opening line is ```new-buffer NAME (NAME: at most 16 characters, no
spaces).  Inside that block, a line that is exactly <<FILE>> stands for
the whole text of the user's file: Chezemax pastes the file there.  Use
it whenever the new buffer should contain the file or the paper; never
retype the file and never ask the user to copy it.  Put nothing else in
that block that the user did not ask for.")

(define *assistant-instructions*
  (string-append
   "You are the assistant built into Chezemax, a small Emacs-like text editor.
The user pressed a key to ask for help while editing.  You receive the
file name, the language, and its text, with the cursor marked <<CURSOR>>;
then the other buffers open in the editor, each under its name, so a
question about \"the answers buffer\" or \"the paper\" can be answered.  Answer the user's question, or, when there is no
question, give short, concrete hints about the code at the cursor: bugs,
simplifications, what to write next.

Your answer is shown as plain text in an editor window about 80 columns
wide, so keep it brief and do not use Markdown headings or tables.  Put
code to insert at the cursor in fenced blocks (``` ... ```): the user can
insert them with a key, so fence only code meant to be inserted, and show
code you are not proposing (the old version, say) indented, without
fences.  Never rewrite the whole file.

"
   *new-buffer-instructions*))

;;; ------------------------------------------------------------------
;;; Assistants
;;; ------------------------------------------------------------------

;; an assistant: #(key name ask), ASK a procedure (question context) -> answer
(define (assistant-key a) (vector-ref a 0))
(define (assistant-name a) (vector-ref a 1))
(define (assistant-ask a) (vector-ref a 2))

(defvar *assistants* '())

(define (define-assistant key name ask)
  "Register an assistant.  ASK is called with the user's question (maybe
empty) and the context; it returns the answer or raises an error."
  (set! *assistants* (cons (vector key name ask)
                           (filter (lambda (a) (not (eq? (assistant-key a) key))) *assistants*)))
  key)

(define (find-assistant key)
  (or (find (lambda (a) (eq? (assistant-key a) key)) *assistants*)
      (error "No assistant" key)))

;;; ------------------------------------------------------------------
;;; Finding and running programs
;;; ------------------------------------------------------------------

(define (path-directories)
  "The PATH, and the folders where installers put programs: an editor
started from the Dock or Finder gets a short PATH."
  (let ((home (home-directory)))
    (delete-duplicates
     (append (filter (lambda (d) (> (string-length d) 0)) (string-split (or (os.getenv "PATH") "") ":"))
             (list (string-append home "/.local/bin") (string-append home "/.claude/local")
                   (string-append home "/.npm-global/bin")
                   "/opt/homebrew/bin" "/usr/local/bin" "/usr/bin" "/bin")))))

(define (find-program name)
  "Full path of the executable NAME, or #f."
  (if (byte-position name 47)
      (and (file-executable? name) name)
      (find file-executable? (map (lambda (d) (string-append d "/" name)) (path-directories)))))

;; programs run from here (claude needs node, say) find what the PATH and
;; the usual installation folders hold
(os.setenv "PATH" (string-join (path-directories) ":"))

(define run-with-input
  (case-lambda
    ((program args input) (run-with-input program args input *assistant-timeout*))
    ((program args input timeout)
     "Run PROGRAM with ARGS and INPUT on its standard input: three values,
its output, its errors and its exit status (-1: it did not finish)."
     (let ((r (run-program program args input timeout #f)))
       (values (car r) (cadr r) (caddr r))))))

;;; ------------------------------------------------------------------
;;; A little JSON, for the Messages API
;;; ------------------------------------------------------------------

(define (hex4 n)
  (let ((s (number->string n 16))) (string-append (make-string (- 4 (string-length s)) #\0) s)))

(define (json-string s)
  (let ((out (open-output-string)))
    (write-string "\"" out)
    (string-for-each
     (lambda (c)
       (write-string
        (case c
          ((#\") "\\\"")
          ((#\\) "\\\\")
          ((#\newline) "\\n")
          ((#\return) "\\r")
          ((#\tab) "\\t")
          (else (if (< (char->integer c) 32)
                    (string-append "\\u" (hex4 (char->integer c)))
                    (string c))))
        out))
     s)
    (write-string "\"" out)
    (get-output-string out)))

(define (json-read json)
  "Parse JSON: objects become alists with string keys, arrays lists,
true/false/null #t/#f/'null."
  (let* ((text (%utf8 json)) (i 0) (n (bytevector-length text)))
    (define (at k) (bytevector-u8-ref text k))
    (define (piece a b) (utf8->string (bytevector-copy text a b)))
    (define (peek) (and (< i n) (at i)))
    (define (skip) (let loop () (when (and (< i n) (memv (at i) '(32 9 10 13))) (set! i (+ i 1)) (loop))))
    (define (expect b)
      (skip)
      (unless (eqv? (peek) b) (error "JSON: unexpected text at" i))
      (set! i (+ i 1)))
    (define (literal word value)
      (if (match-at text n i word) (begin (set! i (+ i (string-length word))) value) (error "JSON: unexpected text at" i)))
    (define (value)
      (skip)
      (let ((b (peek)))
        (cond ((eqv? b 123) (object))
              ((eqv? b 91) (array))
              ((eqv? b 34) (str))
              ((and b (or (= b 45) (and (<= 48 b) (<= b 57)))) (num))
              ((eqv? b 116) (literal "true" #t))
              ((eqv? b 102) (literal "false" #f))
              ((eqv? b 110) (literal "null" 'null))
              (else (error "JSON: unexpected text at" i)))))
    (define (object)
      (set! i (+ i 1)) (skip)
      (if (eqv? (peek) 125) (begin (set! i (+ i 1)) '())
          (let loop ((acc '()))
            (skip)
            (let* ((k (str)) (_ (expect 58)) (v (value)) (acc (cons (cons k v) acc)))
              (skip)
              (if (eqv? (peek) 125) (begin (set! i (+ i 1)) (reverse acc))
                  (begin (expect 44) (loop acc)))))))
    (define (array)
      (set! i (+ i 1)) (skip)
      (if (eqv? (peek) 93) (begin (set! i (+ i 1)) '())
          (let loop ((acc '()))
            (let ((acc (cons (value) acc)))
              (skip)
              (if (eqv? (peek) 93) (begin (set! i (+ i 1)) (reverse acc))
                  (begin (expect 44) (loop acc)))))))
    (define (hex-at k) (string->number (piece k (+ k 4)) 16))
    (define (str)
      (set! i (+ i 1))
      (let ((out (open-output-string)))
        (let loop ()
          (when (>= i n) (error "JSON: a string without its end"))
          (let ((b (at i)))
            (set! i (+ i 1))
            (cond ((= b 34) (get-output-string out))
                  ((= b 92)
                   (let ((e (at i)))
                     (set! i (+ i 1))
                     (case e
                       ((110) (write-string "\n" out))
                       ((116) (write-string "\t" out))
                       ((114) (write-string "\r" out))
                       ((98) (write-char (integer->char 8) out))
                       ((102) (write-char (integer->char 12) out))
                       ((117)
                        (let ((code (hex-at i)))
                          (set! i (+ i 4))
                          ;; a surrogate pair
                          (when (and (<= #xD800 code) (<= code #xDBFF) (< (+ i 5) n) (= (at i) 92))
                            (let ((low (hex-at (+ i 2))))
                              (set! i (+ i 6))
                              (set! code (+ #x10000 (* (- code #xD800) 1024) (- low #xDC00)))))
                          (write-char (integer->char code) out)))
                       (else (write-char (integer->char e) out)))
                     (loop)))
                  (else
                   ;; the bytes up to the next quote or backslash, whole characters
                   (let run ((j i))
                     (if (and (< j n) (not (memv (at j) '(34 92))))
                         (run (+ j 1))
                         (begin (write-string (piece (- i 1) j) out) (set! i j))))
                   (loop)))))))
    (define (num)
      (let ((start i))
        (let loop () (when (and (< i n) (memv (at i) '(43 45 48 49 50 51 52 53 54 55 56 57 46 101 69))) (set! i (+ i 1)) (loop)))
        (string->number (piece start i))))
    (value)))

(define (json-get object . keys)
  (let loop ((o object) (ks keys))
    (if (null? ks) o
        (let ((e (and (pair? o) (assoc (car ks) o))))
          (loop (and e (cdr e)) (cdr ks))))))

;;; ------------------------------------------------------------------
;;; Claude
;;; ------------------------------------------------------------------

(define (anthropic-api-key)
  (let ((env (os.getenv "ANTHROPIC_API_KEY")))
    (if (and env (> (string-length env) 0)) env
        (let ((text (file-contents (config-file "anthropic-api-key"))))
          (and text (let ((line (trim (car (split-lines text))))) (and (> (string-length line) 0) line)))))))

(define (claude-program)
  (find-program (or (os.getenv "CHEZEMAX_CLAUDE") (os.getenv "SBEMACS_CLAUDE") "claude")))

(define (claude-transport)
  (case *claude-transport*
    ((cli api) *claude-transport*)
    (else (cond ((claude-program) 'cli)
                ((anthropic-api-key) 'api)
                (else (error "neither the claude program nor an API key was found.  Install Claude Code (claude.com/claude-code) or set ANTHROPIC_API_KEY"))))))

(define (full-prompt question context)
  (string-append context "\n\n"
                 (if (> (string-length (trim question)) 0)
                     (string-append "Question: " question)
                     "Give hints about the code at the cursor.")))

(define (claude-cli-ask question context)
  (let ((claude (or (claude-program) (error "the claude program is not installed"))))
    (let-values (((out err code)
                  (run-with-input claude
                                  (append (list "-p"
                                                "--tools" ""          ; First Law: no tools, no files
                                                "--no-session-persistence"
                                                "--append-system-prompt" *assistant-instructions*)
                                          (if *claude-model* (list "--model" *claude-model*) '())
                                          (list (if (> (string-length (trim question)) 0)
                                                    question
                                                    "Give hints about the code at the cursor.")))
                                  context)))
      (if (and (= code 0) (> (string-length (trim out)) 0))
          out
          (error (concat "claude exited with code " code ": "
                         (trim (if (> (string-length (trim err)) 0) err out))))))))

(define (temporary-directory)
  (let ((tmp (or (os.getenv "TMPDIR") (os.getenv "TEMP") (os.getenv "TMP") "/tmp")))
    (trim-bytes-right tmp "/")))

(define (claude-api-ask question context)
  (let* ((key (or (anthropic-api-key) (error "no API key: set ANTHROPIC_API_KEY")))
         (curl (or (find-program "curl") (error "curl is not installed")))
         (body (string-append "{\"model\":" (json-string (or *claude-model* *claude-api-model*))
                              ",\"max_tokens\":4096,\"system\":" (json-string *assistant-instructions*)
                              ",\"messages\":[{\"role\":\"user\",\"content\":"
                              (json-string (full-prompt question context)) "}]}"))
         (body-file (concat (temporary-directory) "/chezemax-request-" (random 1000000000) ".json")))
    ;; the key goes through stdin (curl -K -), never on the command line or
    ;; on disk; the body goes through a temporary file
    (dynamic-wind
     (lambda () (call-with-output-file body-file (lambda (p) (write-string body p))))
     (lambda ()
       (let-values (((out err code)
                     (run-with-input curl
                                     (list "-sS" "-K" "-" "--data-binary" (string-append "@" body-file)
                                           "https://api.anthropic.com/v1/messages")
                                     (string-append "header = \"x-api-key: " key "\"\n"
                                                    "header = \"anthropic-version: 2023-06-01\"\n"
                                                    "header = \"content-type: application/json\"\n"))))
         (unless (= code 0) (error (concat "curl failed (" code "): " (trim err))))
         (let ((json (json-read out)))
           (if (equal? (json-get json "type") "error")
               (error (concat "API: " (json-get json "error" "message")))
               (apply string-append
                      (filter-map (lambda (block) (and (equal? (json-get block "type") "text") (json-get block "text")))
                                  (or (json-get json "content") '())))))))
     (lambda () (guard (e (#t #f)) (delete-file body-file))))))

(define (claude-ask question context)
  (case (claude-transport)
    ((cli) (claude-cli-ask question context))
    ((api) (claude-api-ask question context))))

(define-assistant 'claude "Claude" claude-ask)

;;; ------------------------------------------------------------------
;;; What is sent: the buffer around the cursor
;;; ------------------------------------------------------------------

(define (buffer-context)
  "A description of the current buffer, with the cursor marked <<CURSOR>>,
then of the other buffers open in the editor."
  (let* ((this (this-buffer-context *assistant-context-bytes*))
         (others (other-buffers-context (- *assistant-context-bytes* (bytes-length this)))))
    (string-append this others)))

;; buffers of the editor's own windows: never sent
(define *private-buffer-names*
  '("*assistant*" "*claude-request*" "*discussion*" "*codex*" "*codex-request*" "*codex-chat*"
    "*chezemax-help*" "*help-options*" "*ai-options*" "*more-actions*" "*ttfy-menu*" "*ttfy-errors*"
    "*completions*" "*buffers*" "*buffer-pick*" "*plot*" "*tags-hidden*"))

;; the buffer's text up to END, cut back to a whole character
(define (%text-before end)
  (let loop ((e end))
    (if (and (> e 0) (< e (buffer-size)) (= (quotient (buffer-get e) 64) 2))
        (loop (- e 1))
        (buffer-substring 0 e))))

(define (other-buffers-context budget)
  "The other buffers, each under its name and file, while BUDGET bytes last;
a buffer that does not fit is cut, and the cut is said."
  (let* ((here (get-buffer-name))
         (names (filter (lambda (n) (not (or (string=? n here) (member n *private-buffer-names*))))
                        (buffer-names))))
    (if (null? names) ""
        (let loop ((names names) (left budget) (parts '()))
          (if (or (null? names) (<= left 200))
              (string-append
               "\n\nOther buffers open in the editor (the cursor is not in them):"
               (apply string-append (reverse parts))
               (if (pair? names)
                   (concat "\n\n(Not sent, for lack of room: " (string-join names ", ") ")")
                   ""))
              (let* ((name (car names))
                     (info (call-in-window-of name
                                              (lambda () (cons (buffer-filename)
                                                               (%text-before (min (buffer-size) left))))))
                     (cut (>= (bytes-length (cdr info)) left))
                     (part (string-append "\n\nBuffer: " name
                                          (if (car info) (concat " (file " (car info) ")") "")
                                          (if cut ", only its beginning" "")
                                          "\n```\n" (cdr info) "\n```")))
                (loop (cdr names) (- left (bytes-length part)) (cons part parts))))))))

(define (this-buffer-context limit)
  "The current buffer, with the cursor marked <<CURSOR>>: all of it when it
is under LIMIT bytes, otherwise the part around the cursor."
  (let* ((p (point))
         (size (buffer-size))
         (half (quotient limit 2))
         (start (if (<= size limit) 0 (line-start (max 0 (- p half)))))
         (end (if (<= size limit) size (line-end (min size (+ p half)))))
         (before (buffer-substring start p))
         (after (buffer-substring p end))
         (line (line-number p))
         (file (or (buffer-filename) (get-buffer-name)))
         (lang (language-for-file file))
         (m (mark))
         (region (and m (not (= m p)) (< (abs (- m p)) limit)
                      (buffer-substring (min m p) (max m p)))))
    (string-append "File: " file "\nLanguage: " (if lang (language-name lang) "unknown")
                   "\nCursor: line " (number->string line)
                   (if (or (> start 0) (< end size)) ", the text shown is part of the file" "") "\n"
                   (if region (string-append "\nSelected region:\n```\n" region "\n```\n") "")
                   "\nText:\n```\n" before "<<CURSOR>>" after "\n```")))

;;; ------------------------------------------------------------------
;;; The window with the answer
;;; ------------------------------------------------------------------

(defvar *assistant-last-answer* #f)
(defvar *assistant-origin* #f)

;;; The assistants' windows leave the others alone.  A window for an answer,
;;; a question or a discussion is made by splitting the window of the file
;;; asked about; closing it ([CLOSE], C-c q, C-c y) deletes it, and its rows
;;; go back to the window above, so the screen is as it was before: two
;;; windows stay two.

(define (shown-assistant-buffer)
  "The name of an assistant buffer (answer or question) some window shows, or #f."
  (let loop ((names *assistant-buffer-names*))
    (cond ((null? names) #f)
          ((buffer-shown-p (car names)) (car names))
          (else (loop (cdr names))))))

(define (open-assistant-window buffer)
  "Select a window for BUFFER: the one an answer or a question already
has (the answer replaces the question), or a new one below."
  (let ((shown (shown-assistant-buffer)))
    (if shown
        (begin (select-window-showing shown) (select-buffer buffer))
        (open-window-below buffer))))

(define (show-in-assistant-window title text)
  "Show TEXT in *ASSISTANT-BUFFER* in a window below; the cursor stays
where it was.  The other windows stay as they are."
  (let ((fill (lambda ()
                (erase-buffer)
                (insert title "\n" (make-string (min 70 (string-length title)) #\-) "\n\n")
                (insert (remove-byte text 13))
                (fe-set-modified 0)
                (beginning-of-buffer))))
    (if (buffer-shown-p *assistant-buffer*)
        (call-in-window-of *assistant-buffer* fill)
        (let ((origin (get-buffer-name)))
          (open-assistant-window *assistant-buffer*)
          ;; [TANGLE] inserts the answer's code (or makes the buffer it
          ;; proposes) in the file asked about, as C-c y does
          (set-buffer-menu *assistant-buffer*
                           '(("TANGLE" "C-c y") ("CLOSE" close-assistant-windows)))
          (fill)
          ;; back to the file's window
          (go-to-file-window origin)))))

(define (one-line-question q)
  (let ((q (trim q)))
    (and (> (string-length q) 0)
         (if (> (string-length q) 60)
             (string-append (substitute-byte (substring q 0 57) 10 32) "...")
             (substitute-byte q 10 32)))))

(define (answer-hint answer)
  (cond ((pair? (proposed-buffers answer)) "C-c y create buffer & close")
        ((proposed-code answer) "C-c y insert code & close")
        (else "C-c q close")))

(define (run-assistant key question context origin)
  "Send QUESTION (\"\" for hints) and CONTEXT to the assistant KEY and show
the answer below the buffer ORIGIN."
  (let* ((assistant (find-assistant key))
         (name (assistant-name assistant)))
    (set! *assistant-origin* origin)
    (go-to-file-window origin)
    (message name " is thinking ... (up to " (if (eq? key 'codex) *codex-timeout* *assistant-timeout*) " s)")
    (update-display)
    (guard (e (#t
               ;; Third Law: whatever happens, the editor and the buffer
               ;; survive; the explanation goes in the window
               (show-in-assistant-window
                (string-append name " could not be reached")
                (string-append (describe-error e) "\n\n"
                               (if (eq? key 'codex) (codex-status-text) (assistant-status-text))))
               (set-buffer-hint *assistant-buffer* "C-c q close")
               (message name " could not be reached; see the window below")))
      (let ((answer ((assistant-ask assistant) question context)))
        (set! *assistant-last-answer* answer)
        (show-in-assistant-window
         (let ((q (one-line-question question))) (if q (string-append name " -- " q) name))
         answer)
        (set-buffer-hint *assistant-buffer* (answer-hint answer))
        (message name " answered.  "
                 (cond ((pair? (proposed-buffers answer))
                        "C-c y creates the buffer it proposes and closes the window")
                       ((proposed-code answer) "C-c y inserts the code and closes the window")
                       (else "C-c q closes the window")))))))

;;; ------------------------------------------------------------------
;;; C-c r: the menu
;;; ------------------------------------------------------------------

(defvar *assistant-saved-context* #f)

(define (claude-compose context origin)
  "Open *claude-request* below ORIGIN, for a question of any length."
  (set! *assistant-saved-context* context)
  (set! *assistant-origin* origin)
  (go-to-file-window origin)
  (open-assistant-window *claude-request-buffer*)
  (set-buffer-menu *claude-request-buffer*
                   '(("SEND" "C-c r") ("TANGLE" "C-c y") ("CLOSE" close-assistant-windows)))
  (erase-buffer)
  (fe-set-modified 0)
  (message "Write your question for Claude, then C-c r sends it (C-x o: back to " origin ")")
  #t)

(define (claude-send-request)
  (let ((question (trim (buffer-substring 0 (buffer-size)))))
    (cond ((= (string-length question) 0) (message "Write a question first, then C-c r sends it"))
          ((not *assistant-saved-context*)
           (message "The file to ask about is unknown; start again from it with C-c r"))
          (else (run-assistant 'claude question *assistant-saved-context* (or *assistant-origin* "*scratch*"))))))

(define (claude-menu)
  "Choose Hints, Question or Discussion with the mouse or h/q/d."
  (let* ((context (buffer-context)) (origin (get-buffer-name))
         (key (choose-assistant-menu "Ask Claude")))
    (cond ((equal? key "h") (run-assistant 'claude "" context origin))
          ((equal? key "q") (claude-compose context origin))
          ((equal? key "d") (claude-discussion origin)))))

(defcommand (ask-claude)
  "C-c r: the menu; in *claude-request*, send the question; in the
discussion, send what was written since the last answer."
  (cond ((string=? (get-buffer-name) *claude-request-buffer*) (claude-send-request))
        ((string=? (get-buffer-name) *claude-discussion-buffer*) (discussion-send))
        (else (claude-menu))))

;;; ------------------------------------------------------------------
;;; Closing the assistants' windows (C-h and the menu use it)
;;; ------------------------------------------------------------------

(define *assistant-buffer-names* '("*assistant*" "*claude-request*" "*codex*" "*codex-request*"))

(define (assistant-buffer-p name) (and (member name *assistant-buffer-names*) #t))

(define (file-behind-assistant)
  (or *assistant-origin* *codex-origin-buffer* "*scratch*"))

(defcommand (close-assistant-windows)
  "Close every window showing a Claude or Codex answer or question; the
other windows are as they were before it opened."
  (let ((origin (get-buffer-name)))
    (let loop ((k 0))
      (when (and (< k (* 2 (window-count))) (> (window-count) 1))
        (if (assistant-buffer-p (get-buffer-name)) (delete-window) (other-window))
        (loop (+ k 1))))
    (when (assistant-buffer-p (get-buffer-name)) (select-buffer (file-behind-assistant)))
    ;; back to the window that was selected, or to the file asked about
    (unless (select-window-showing origin) (select-window-showing (file-behind-assistant)))
    #t))

(defcommand (assistant-close)
  "C-c q: close the assistant's window, as its [CLOSE] does: the answer or
question, or, from the discussion, the discussion.  The other windows stay."
  (cond ((discussion-buffer-p (get-buffer-name)) (close-discussion-window))
        ((shown-assistant-buffer) (close-assistant-windows))
        (else (close-discussion-window))))

;;; ------------------------------------------------------------------
;;; What is set up, and how to fix it
;;; ------------------------------------------------------------------

(define (assistant-status-text)
  (let ((claude (claude-program)) (curl (find-program "curl")) (key (anthropic-api-key)))
    (string-append
     "Set-up\n------\n"
     "transport (*claude-transport*): " (->string *claude-transport*) "\n"
     "claude program: " (or claude "NOT FOUND") "\n"
     "curl:           " (or curl "NOT FOUND") "\n"
     "API key:        " (if key "found" "none") "\n\n"
     "To use your Claude subscription, install Claude Code and log in\n"
     "once in a terminal:\n\n"
     "    curl -fsSL https://claude.ai/install.sh | bash\n"
     "    claude\n\n"
     "(or: brew install --cask claude-code).  Claude Code needs a Pro,\n"
     "Max, Team or Enterprise plan.  To use an API key instead, put it\n"
     "in ~/.chezemax/anthropic-api-key or in ANTHROPIC_API_KEY.\n\n"
     "Programs are looked for on the PATH and in:\n"
     (apply string-append (map (lambda (d) (string-append "  " d "\n")) (list-tail (path-directories) (max 0 (- (length (path-directories)) 7))))))))

(defcommand (assistant-status)
  "How the assistant would reach Claude."
  (show-in-assistant-window "Assistant status" (assistant-status-text))
  (set-buffer-hint *assistant-buffer* "C-c q close")
  #t)

;;; ------------------------------------------------------------------
;;; Second Law: insert the proposed code, when told to
;;; ------------------------------------------------------------------

(define (fence-line-p line)
  (starts-with-p "```" (left-trim-blanks line)))

(define (fenced-blocks text)
  "The fenced code blocks of TEXT, as (start end body): START and END are
the byte offsets of the opening fence line and of the end of the closing
one; BODY is the code without the fences."
  (let ((text (or text "")))
    (let loop ((lines (split-lines text)) (pos 0) (open #f) (blocks '()))
      (if (null? lines) (reverse blocks)
          (let* ((line (car lines)) (end (+ pos (bytes-length line))))
            (if (fence-line-p line)
                (if open
                    (loop (cdr lines) (+ end 1) #f
                          (cons (list (car open) end
                                      (trim-bytes-right (byte-substring text (min (bytes-length text) (+ 1 (cdr open)))
                                                                        (max (+ 1 (cdr open)) pos))
                                                        "\n\r"))
                                blocks))
                    (loop (cdr lines) (+ end 1) (cons pos end) blocks))
                (loop (cdr lines) (+ end 1) open blocks)))))))

(define (proposed-snippets answer)
  "The code blocks to insert: every fenced block but a proposed buffer."
  (let ((text (or answer "")))
    (map caddr (filter (lambda (b) (not (new-buffer-block? text b))) (fenced-blocks text)))))

(define (proposed-code answer)
  (let ((s (proposed-snippets answer))) (and (pair? s) (car s))))

(define (snippet-at text index)
  "The body of the fenced block of TEXT around byte INDEX, or #f."
  (let ((b (find (lambda (b) (and (<= (car b) index) (<= index (cadr b)))) (fenced-blocks text))))
    (and b (caddr b))))

(define (confirm-insert code where)
  "Ask, then insert CODE at the cursor.  True when inserted."
  (let* ((lines (+ 1 (count-byte code 10)))
         (yes (prompt (concat "Insert " (plural lines "line") " " where "? (y/n) ") "")))
    (if (string-ci=? (trim yes) "y")
        (begin (insert code) (message "Inserted " (plural lines "line") " (C-/ undoes it)") #t)
        (begin (message "Nothing inserted") #f))))

(defcommand (assistant-insert)
  "C-c y: insert every snippet the last answer proposed at the cursor,
after asking, and close the answer window."
  (let ((snippets (proposed-snippets *assistant-last-answer*)))
    (cond ((pair? (proposed-buffers *assistant-last-answer*))
           (create-proposed-buffers *assistant-last-answer* (file-behind-assistant)))
          ((null? snippets) (message "The last answer has no code to insert"))
          ((member (get-buffer-name) (list *claude-discussion-buffer* *codex-discussion-buffer*))
           (message "In the discussion, C-c t inserts the snippet under the cursor"))
          (else
           ;; from the answer window too: the code goes into the file
           (let* ((file (if (assistant-buffer-p (get-buffer-name)) (file-behind-assistant) (get-buffer-name)))
                  (code (string-join snippets "\n\n"))
                  (done #f) (here 0))
             (call-in-window-of file
                                (lambda ()
                                  (set! done (confirm-insert code
                                                             (concat (if (pair? (cdr snippets))
                                                                         (concat "(" (length snippets) " snippets) ") "")
                                                                     "into " file " at line " (line-number))))
                                  (set! here (point))))
             (when done
               (close-assistant-windows)
               (let loop ((k 0))
                 (when (and (< k (window-count)) (not (string=? (get-buffer-name) file)))
                   (other-window) (loop (+ k 1))))
               (unless (string=? (get-buffer-name) file) (select-buffer file))
               (goto-char here)))))))

;;; ------------------------------------------------------------------
;;; Second Law: a new buffer, when told to
;;; ------------------------------------------------------------------
;;; Neither assistant can open a buffer, and neither should retype a long
;;; file.  So an answer may PROPOSE a buffer: a fenced block whose opening
;;; line is ```new-buffer NAME.  A line that is exactly <<FILE>> stands for
;;; the whole text of the file the question was asked about.  C-c y (or
;;; C-c t on the block, in a discussion) asks, then makes the buffer.

(define *file-placeholder* "<<FILE>>")

(define (fence-info text block)
  "The words after ``` on the opening line of BLOCK, from FENCED-BLOCKS."
  (let* ((start (car block))
         (nl (or (byte-position text 10 start) (bytes-length text)))
         (line (trim (byte-substring text start nl))))
    (trim (byte-substring line (min 3 (bytes-length line))))))

(define (new-buffer-block? text block)
  (string-prefix? "new-buffer" (fence-info text block)))

(define (new-buffer-name info)
  "The buffer name in the fence words \"new-buffer NAME\": its first word,
cut to the 16 characters a buffer name can hold."
  (let* ((words (filter (lambda (w) (> (string-length w) 0))
                        (string-split (byte-substring info (min 10 (bytes-length info))) " ")))
         (name (if (pair? words) (car words) "*new*")))
    (if (> (string-length name) 16) (substring name 0 16) name)))

(define (proposed-buffers answer)
  "The buffers ANSWER proposes, as (NAME . TEXT)."
  (let ((text (or answer "")))
    (map (lambda (b) (cons (new-buffer-name (fence-info text b)) (caddr b)))
         (filter (lambda (b) (new-buffer-block? text b)) (fenced-blocks text)))))

(define (expand-file-placeholder body file-text)
  "BODY with each line that is exactly <<FILE>> replaced by FILE-TEXT."
  (string-join (map (lambda (line) (if (string=? (trim line) *file-placeholder*) file-text line))
                    (split-lines body))
               "\n"))

(define (free-buffer-name name)
  "NAME, or NAME<2>, NAME<3> ... : the first that is not a buffer with text
or a file in it.  Selects that buffer."
  (let loop ((k 1))
    (let* ((suffix (if (= k 1) "" (concat "<" k ">")))
           (base (if (> (+ (string-length name) (string-length suffix)) 16)
                     (substring name 0 (- 16 (string-length suffix)))
                     name))
           (candidate (concat base suffix)))
      (select-buffer candidate)
      (if (and (= (buffer-size) 0) (not (buffer-filename)) (< k 50))
          candidate
          (loop (+ k 1))))))

(define (create-proposed-buffer name body origin)
  "Ask, then make the buffer NAME from BODY, the file ORIGIN pasted for
<<FILE>>, in the window of ORIGIN.  True when made."
  (let* ((needs-file (any (lambda (l) (string=? (trim l) *file-placeholder*)) (split-lines body)))
         (file-text (if needs-file
                        (call-in-window-of origin (lambda () (buffer-substring 0 (buffer-size))))
                        ""))
         (text (expand-file-placeholder body file-text))
         (lines (+ 1 (count-byte text 10)))
         (yes (prompt (concat "Create buffer " name " (" (plural lines "line")
                              (if needs-file (concat ", with the text of " origin) "") ")? (y/n) ")
                      "")))
    (if (not (string-ci=? (trim yes) "y"))
        (begin (message "No buffer created") #f)
        (begin
          (when (assistant-buffer-p (get-buffer-name)) (close-assistant-windows))
          (let loop ((k 0))             ; to the window of the file asked about
            (when (and (< k (window-count)) (not (string=? (get-buffer-name) origin)))
              (other-window) (loop (+ k 1))))
          (let ((made (free-buffer-name name)))
            (insert text)
            (goto-char 0)
            (message "Buffer " made " created (" (plural lines "line") "); C-x C-w saves it to a file")
            #t)))))

(define (create-proposed-buffers answer origin)
  (for-each (lambda (b) (create-proposed-buffer (car b) (cdr b) origin))
            (proposed-buffers answer)))

;;; ------------------------------------------------------------------
;;; A discussion: a window that stays open
;;; ------------------------------------------------------------------

(define *you-marker* "You:")
(define *claude-marker* "Claude:")

(define (discussion-header who origin marker key)
  (string-append "Discussion with " who " about " origin "\n"
                 key " sends what you write after the last " marker "\n"
                 "C-c t inserts the snippet under the cursor into " origin "\n"
                 "C-c q closes this window; " key ", then d, brings it back\n"
                 (make-string 70 #\=) "\n\n" marker "\n"))

(define (claude-discussion origin)
  "Open (or go back to) the discussion about ORIGIN, below it."
  (go-to-file-window origin)
  (set! *discussion-origin* origin)
  (unless (select-window-showing *claude-discussion-buffer*)
    (open-window-below *claude-discussion-buffer*))
  (set-buffer-menu *claude-discussion-buffer*
                   '(("SEND" "C-c r") ("TANGLE" "C-c t") ("CLOSE" close-discussion-window)))
  (when (= 0 (buffer-size))
    (insert (discussion-header "Claude" origin *you-marker* "C-c r")))
  (end-of-buffer)
  (message "Write to Claude after \"" *you-marker* "\", then C-c r")
  #t)

(define (last-marker-position text marker)
  "Index (a character's) just after the last line that is exactly MARKER, or #f."
  (let ((pos (string-search-back (string-append "\n" marker "\n") text)))
    (and pos (+ pos (string-length marker) 2))))

(define (discussion-turn text marker answer you)
  (string-append (if (and (> (string-length text) 0)
                          (char=? (string-ref text (- (string-length text) 1)) #\newline))
                     "" "\n")
                 "\n" marker "\n" (trim (remove-byte answer 13)) "\n\n" you "\n"))

(define (discussion-send)
  "Send what was written after the last You: to Claude, with the whole
discussion and the file around its cursor."
  (let* ((text (buffer-substring 0 (buffer-size)))
         (start (last-marker-position text *you-marker*))
         (message-text (and start (trim (substring text start (string-length text))))))
    (cond ((or (not message-text) (= 0 (string-length message-text)))
           (message "Write after the last \"" *you-marker* "\", then C-c r"))
          ((not *discussion-origin*)
           (message "The file is unknown; start the discussion from it (C-c r, then d)"))
          (else
           (let ((context (call-in-window-of *discussion-origin* buffer-context))
                 (question (string-append "This is a discussion that continues; reply to the user's last message.\n\n" text)))
             (message "Claude is thinking ... (up to " *assistant-timeout* " s)")
             (update-display)
             (let ((answer (guard (e (#t (string-append "(Claude could not be reached: " (describe-error e) ")")))
                             (claude-ask question context))))
               (set! *assistant-last-answer* answer)
               (set! *assistant-origin* *discussion-origin*)
               (end-of-buffer)
               (insert (discussion-turn text *claude-marker* answer *you-marker*))
               (message "Claude answered.  C-c t on a snippet inserts it into " *discussion-origin*)))))))

(define (tangle-from-discussion origin)
  "Insert the snippet under the cursor into ORIGIN, at its cursor, after
asking; on a proposed buffer, make that buffer."
  (let* ((text (buffer-substring 0 (buffer-size)))
         (block (find (lambda (b) (and (<= (car b) (point)) (<= (point) (cadr b)))) (fenced-blocks text)))
         (code (snippet-at text (point))))
    (cond
     ((and block (new-buffer-block? text block))
      (create-proposed-buffer (new-buffer-name (fence-info text block)) (caddr block) origin))
     ((not code)
      (message "Put the cursor on a snippet (between its ``` lines) first"))
     (else
      (call-in-window-of origin
                         (lambda () (confirm-insert code (concat "into " origin " at line " (line-number)))))))))

(define (discussion-tangle)
  "C-c t in the Claude discussion."
  (cond ((not (string=? (get-buffer-name) *claude-discussion-buffer*))
         (message "C-c t works in the discussion window (C-c r, then d)"))
        ((not *discussion-origin*) (message "The file is unknown"))
        (else (tangle-from-discussion *discussion-origin*))))

;;; ------------------------------------------------------------------
;;; Closing a discussion window ([CLOSE] in it)
;;; ------------------------------------------------------------------

(define (discussion-buffer-p name)
  (member name (list *claude-discussion-buffer* *codex-discussion-buffer*)))

(defcommand (close-discussion-window)
  "Close the windows showing a Claude or Codex discussion; the discussion
is kept, and C-c r d (or C-c g d) brings it back."
  (let loop ((k 0))
    (when (and (< k (* 2 (window-count))) (> (window-count) 1))
      (if (discussion-buffer-p (get-buffer-name)) (delete-window) (other-window))
      (loop (+ k 1))))
  (when (discussion-buffer-p (get-buffer-name))
    (select-buffer (or *discussion-origin* *codex-discussion-origin* "*scratch*")))
  (select-window-showing (or *discussion-origin* *codex-discussion-origin* "*scratch*"))
  #t)

;;; ------------------------------------------------------------------
;;; Keys
;;; ------------------------------------------------------------------

(global-set-key "C-c r" 'ask-claude)
(global-set-key "C-c y" 'assistant-insert)

;;; What the mode line of each assistant window says
(set-buffer-hint *claude-request-buffer* "C-c r ask; C-x o back to file")
(set-buffer-hint *claude-discussion-buffer* "C-c r send; C-c t code-tangle")
