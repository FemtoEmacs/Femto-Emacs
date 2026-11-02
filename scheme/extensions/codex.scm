;;;; codex.scm -- ask OpenAI Codex (ChatGPT) from a lower editor window
;;;;
;;;; Port of SBEmacs's lisp/extensions/codex.lisp.
;;;;
;;;;   C-c g       a menu: h hints, q question, d discussion
;;;;   C-c g       in a question or discussion window, sends the request
;;;;   C-c y       in a question answer, insert every fenced code block
;;;;               into the source and close the help window, or create
;;;;               the new buffer the answer proposes
;;;;   C-c t       in a discussion, insert the snippet under the cursor
;;;;
;;;; Codex receives a bounded copy of the source around point.  It runs with
;;;; the read-only sandbox and an ephemeral session: it may inspect and test,
;;;; but cannot edit the project.  Only the user can insert proposed text.

(defvar *codex-program* #f)     ; an executable path, or #f to find it
(defvar *codex-model* #f)       ; #f: the CLI's default
(defvar *codex-timeout* 300)    ; seconds
(defvar *codex-context-bytes* 400000)

(define *codex-request-buffer* "*codex-request*")
(define *codex-answer-buffer* "*codex*")
;; The C core stores at most 16 buffer-name characters (NBUFN is 17).
(define *codex-discussion-buffer* "*codex-chat*")
(defvar *codex-origin-buffer* #f)
(defvar *codex-saved-context* #f)
(defvar *codex-working-directory* #f)
(defvar *codex-discussion-origin* #f)

(define *codex-instructions*
  (string-append
   "You are the Codex assistant inside Chezemax.  The user is editing a
file and has written a request in a separate editor window.  Answer that
request using the supplied source context.

Do not modify any file.  Do not propose changes to the editor's C sources.
Concentrate on the user's current text.  You may use read-only inspection
and run non-destructive tests when useful.  For a translation or
explanation, return the requested prose directly.  When you propose text or
code for insertion, place exactly the insertable text in one fenced code
block.  Keep explanations short and use plain text suitable for an editor
window.

"
   *new-buffer-instructions*))

(define (codex-source-directory)
  "Absolute directory of the current file, or the editor's directory."
  (let ((file (buffer-filename)))
    (if (and file (> (length file) 0))
        (let ((d (file-name-directory (absolute-path file)))) (if (string=? d "") (path.cwd) d))
        (path.cwd))))

(define (codex-effective-working-directory)
  "A nonempty directory for `codex exec --cd'."
  (let ((d (trim (or *codex-working-directory* ""))))
    (if (> (length d) 0) d (path.cwd))))

(define (codex-compose (context #f) (origin #f))
  "Open the lower Codex request window and save the source context."
  (set! *codex-origin-buffer* (or origin (get-buffer-name)))
  (set! *codex-saved-context* (or context (buffer-context)))
  (set! *codex-working-directory* (codex-source-directory))
  (go-to-file-window *codex-origin-buffer*)
  (open-assistant-window *codex-request-buffer*)
  (set-buffer-menu *codex-request-buffer*
                   '(("SEND" "C-c g") ("TANGLE" "C-c y") ("CLOSE" close-assistant-windows)))
  (erase-buffer)
  (fe-set-modified 0)
  (message "Describe the task, then press C-c g again to send it to Codex")
  #t)

(define (codex-prompt request)
  (string-append *codex-instructions* "\n\nUSER REQUEST\n============\n" request
                 "\n\nSOURCE CONTEXT\n==============\n" (or *codex-saved-context* "")))

(define (codex-installation-candidates)
  "Likely Codex executables not already on the PATH."
  (let ((home (home-directory)))
    (list "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
          (string-append home "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex")
          "/Applications/Codex.app/Contents/Resources/codex"
          (string-append home "/Applications/Codex.app/Contents/Resources/codex")
          "/Applications/ChatGPT.app/Contents/Resources/codex"
          (string-append home "/Applications/ChatGPT.app/Contents/Resources/codex")
          (string-append home "/.local/bin/codex"))))

(define (find-codex-program)
  "An explicit, PATH, standalone or ChatGPT-bundled Codex."
  (or (let ((name (or *codex-program* (os.getenv "CHEZEMAX_CODEX") (os.getenv "SBEMACS_CODEX_PROGRAM")
                      (os.getenv "SBEMACS_CODEX"))))
        (and name (> (length name) 0) (find-program name)))
      (find-program "codex")
      (find file-executable? (codex-installation-candidates))))

(define (codex-exec-arguments)
  (append (list "exec" "--sandbox" "read-only" "--ephemeral" "--ignore-rules"
                "--skip-git-repo-check" "--color" "never"
                (string-append "--cd=" (codex-effective-working-directory)))
          (if *codex-model* (list "--model" *codex-model*) '())
          (list "-")))

(define (codex-report-exit-error out err code)
  (let* ((detail (string-downcase (if (> (length err) 0) err out)))
         (authentication (any (lambda (term) (string-search term detail))
                              '("unauthorized" "authentication" "not logged in" "401" "sign in" "codex login"))))
    (error (if authentication
               (concat "Codex exited with code " code ": authentication failed. Run codex login and sign in with ChatGPT.")
               (concat "Codex exited with code " code ": " (one-line (trim (if (> (length err) 0) err out))))))))

(define (codex-cli-ask request (context #f))
  "The final response of `codex exec`."
  (when context (set! *codex-saved-context* context))
  (let ((program (or (find-codex-program)
                     (error "Codex was not found. Install the official Codex CLI or the ChatGPT desktop app, then sign in with ChatGPT."))))
    (let-values (((out err code) (run-with-input program (codex-exec-arguments) (codex-prompt request) *codex-timeout*)))
      (unless (= code 0) (codex-report-exit-error out err code))
      (let ((answer (trim out)))
        (when (= 0 (length answer))
          (error (concat "Codex exited successfully but returned no answer (" (length err) " bytes of messages).")))
        answer))))

(define (codex-ask question context) (codex-cli-ask question context))

(define-assistant 'codex "Codex" codex-ask)

(define (codex-submit)
  "Send the text in *codex-request* to Codex."
  (if (not (string=? (get-buffer-name) *codex-request-buffer*))
      (message "C-c g sends only after opening the *codex-request* window")
      (let ((request (trim (buffer-substring 0 (buffer-size)))))
        (if (= 0 (length request))
            (message "Write a request before sending it")
            (run-assistant 'codex request *codex-saved-context* (or *codex-origin-buffer* "*scratch*"))))))

(define (codex-menu)
  "Choose Hints, Question or Discussion with the mouse or h/q/d."
  (let ((context (buffer-context)) (origin (get-buffer-name)))
    (set! *codex-working-directory* (codex-source-directory))
    (let ((key (choose-assistant-menu "Ask Codex (ChatGPT)")))
      (cond ((equal? key "h") (set! *codex-saved-context* context) (run-assistant 'codex "" context origin))
            ((equal? key "q") (codex-compose context origin))
            ((equal? key "d") (codex-discussion origin))))))

(defcommand (ask-codex)
  "C-c g: menu; in a question or discussion window, send the request."
  (cond ((string=? (get-buffer-name) *codex-request-buffer*) (codex-submit))
        ((string=? (get-buffer-name) *codex-discussion-buffer*) (codex-discussion-send))
        (else (codex-menu))))

(define (codex-status-text)
  (let ((program (find-codex-program)))
    (string-append
     "Codex CLI: " (or program "NOT FOUND") "\n"
     "Model: " (or *codex-model* "CLI default") "\n"
     "Sandbox: read-only\nSession: ephemeral\n\n"
     "Chezemax checks the PATH, the standalone-install folder and the\n"
     "macOS ChatGPT app.  Set *codex-program* in ~/.chezemax/init.scm, or\n"
     "the CHEZEMAX_CODEX environment variable, to choose another.\n"
     "If authentication is needed, run codex once in a terminal and choose\n"
     "Sign in with ChatGPT.")))

(defcommand (codex-status)
  "Show Codex's set-up in the lower window."
  (show-in-assistant-window "Codex status" (codex-status-text))
  (set-buffer-hint *assistant-buffer* "C-c q close")
  #t)

;;; ------------------------------------------------------------------
;;; A Codex discussion: kept separate from a question
;;; ------------------------------------------------------------------

(define *codex-you-marker* "You:")
(define *codex-marker* "Codex:")

(define (codex-discussion origin)
  "Open (or return to) the persistent Codex discussion about ORIGIN."
  (go-to-file-window origin)
  (set! *codex-discussion-origin* origin)
  (set! *codex-working-directory* (codex-source-directory))
  (unless (select-window-showing *codex-discussion-buffer*)
    (open-window-below *codex-discussion-buffer*))
  (set-buffer-menu *codex-discussion-buffer*
                   '(("SEND" "C-c g") ("TANGLE" "C-c t") ("CLOSE" close-discussion-window)))
  (when (= 0 (buffer-size))
    (insert (discussion-header "Codex" origin *codex-you-marker* "C-c g")))
  (end-of-buffer)
  (message "Write to Codex after \"" *codex-you-marker* "\", then C-c g")
  #t)

(define (codex-discussion-send)
  "Send the latest user turn, the transcript and the source to Codex."
  (let* ((text (buffer-substring 0 (buffer-size)))
         (start (last-marker-position text *codex-you-marker*))
         (message-text (and start (trim (byte-substring text start)))))
    (cond ((or (not message-text) (= 0 (length message-text)))
           (message "Write after the last \"" *codex-you-marker* "\", then C-c g"))
          ((not *codex-discussion-origin*)
           (message "The file is unknown; start from it with C-c g, then d"))
          (else
           (let ((context (call-in-window-of *codex-discussion-origin* buffer-context))
                 (question (string-append "This is a continuing discussion. Reply to the user's last message.\n\n" text)))
             (message "Codex is thinking ... (up to " *codex-timeout* " s)")
             (update-display)
             (let ((answer (guard (e (#t (string-append "(Codex could not be reached: " (describe-error e) ")")))
                             (codex-ask question context))))
               (set! *assistant-last-answer* answer)
               (set! *assistant-origin* *codex-discussion-origin*)
               (end-of-buffer)
               (insert (discussion-turn text *codex-marker* answer *codex-you-marker*))
               (message "Codex answered. C-c t on a snippet inserts it into " *codex-discussion-origin*)))))))

(define (codex-discussion-tangle) (tangle-from-discussion *codex-discussion-origin*))

(defcommand (assistant-discussion-tangle)
  "C-c t: insert the snippet under the cursor of a discussion into its file."
  (cond ((string=? (get-buffer-name) *claude-discussion-buffer*) (discussion-tangle))
        ((string=? (get-buffer-name) *codex-discussion-buffer*) (codex-discussion-tangle))
        (else (message "C-c t works in a Claude or Codex discussion window"))))

(global-unset-key "C-c x")
(global-set-key "C-c g" 'ask-codex)
(global-set-key "C-c t" 'assistant-discussion-tangle)

(set-buffer-hint *codex-request-buffer* "C-c g ask; C-x o back to file")
(set-buffer-hint *codex-discussion-buffer* "C-c g send; C-c t code-tangle")
