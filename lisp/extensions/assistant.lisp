;;;; assistant.lisp -- ask Claude for hints, from inside the editor
;;;;
;;;; A script: edit and press C-x C-r, no rebuild.
;;;;
;;;;   C-c r   a small menu: h for hints about the code at the cursor,
;;;;           q to write a question (C-c r again sends it), s for the
;;;;           set-up; the answer appears in a window below (C-x 1 closes it)
;;;;   C-c y   insert the code the assistant proposed, at the cursor,
;;;;           after you confirm (undo with C-u)
;;;;   C-c g   Codex (ChatGPT), see codex.lisp
;;;;
;;;; The keys follow Isaac Asimov's Three Laws of Robotics.  C-c r is "R."
;;;; for robot, the title Asimov gives his robots (R. Daneel Olivaw,
;;;; R. Giskard).
;;;;
;;;;   First Law:  "A robot may not injure a human being or, through
;;;;               inaction, allow a human being to come to harm."
;;;;               The assistant never changes your text by itself.  It
;;;;               sees only what C-c r sends (this buffer, around the
;;;;               cursor), and the Claude Code CLI runs with every tool
;;;;               disabled, so it cannot touch your files.
;;;;   Second Law: "A robot must obey the orders given it by human beings
;;;;               except where such orders would conflict with the First
;;;;               Law."  C-c y types into the buffer only on your order,
;;;;               asks first, and C-u takes it back.
;;;;   Third Law:  "A robot must protect its own existence as long as such
;;;;               protection does not conflict with the First or Second
;;;;               Law."  A missing program, a network error or a timeout
;;;;               ends in a message, never in a crash or a lost buffer.
;;;;
;;;; How Claude is reached (*CLAUDE-TRANSPORT*):
;;;;
;;;;   :cli   the Claude Code program, `claude -p`, with your usual login
;;;;          (a Claude subscription works; no API key needed)
;;;;   :api   the Messages API through curl, with ANTHROPIC_API_KEY or the
;;;;          first line of ~/.sbemacs/anthropic-api-key
;;;;   :auto  (default) :cli when `claude` is installed, otherwise :api
;;;;
;;;; The editor waits while the assistant thinks (up to *ASSISTANT-TIMEOUT*
;;;; seconds); the message line says so.

(in-package #:sbemacs)

;;; ------------------------------------------------------------------
;;; Settings
;;; ------------------------------------------------------------------

(defvar *claude-transport* :auto
  ":cli, :api or :auto.")

(defvar *claude-model* nil
  "Model for :cli (an alias such as \"sonnet\" or \"opus\"; NIL = your
Claude Code default) and for :api (NIL = *CLAUDE-API-MODEL*).")

(defvar *claude-api-model* "claude-sonnet-5-5"
  "Default model for the Messages API (see docs.claude.com for the list).")

(defvar *assistant-timeout* 180
  "Seconds to wait for an answer.")

(defvar *assistant-context-bytes* 60000
  "How much of the buffer, around the cursor, is sent with a question.")

(defvar *assistant-buffer* "*assistant*"
  "The buffer where answers are shown.")

(defvar *claude-request-buffer* "*claude-request*"
  "The buffer where a question for Claude is written (C-c r, then q).")

(defparameter *assistant-instructions*
  "You are the assistant built into SBEmacs, a small Emacs-like text editor.
The user pressed a key to ask for help while editing.  You receive the
file name, the language, and the text around the cursor; the cursor is
marked <<CURSOR>>.  Answer the user's question, or, when there is no
question, give short, concrete hints about the code at the cursor: bugs,
simplifications, what to write next.

Your answer is shown as plain text in an editor window about 80 columns
wide, so keep it brief and do not use Markdown headings or tables.  When
you propose code to insert at the cursor, put exactly that code in ONE
fenced block (``` ... ```); the user can insert it with a key.  Never
rewrite the whole file."
  "System instructions sent with every question.")

;;; ------------------------------------------------------------------
;;; Assistants
;;; ------------------------------------------------------------------

(defstruct assistant
  key            ; :claude, :codex ...
  name           ; "Claude"
  ask)           ; function (question context) -> answer string, or signals

(defvar *assistants* '())

(defun define-assistant (key name ask)
  "Register an assistant.  ASK is called with the user's question (a
string, maybe empty) and the context (a string describing the buffer);
it returns the answer as a string or signals an error."
  (setf *assistants* (cons (make-assistant :key key :name name :ask ask)
                           (remove key *assistants* :key #'assistant-key)))
  key)

(defun find-assistant (key)
  (or (find key *assistants* :key #'assistant-key)
      (error "No assistant ~S" key)))

;;; ------------------------------------------------------------------
;;; Running programs (with a timeout, without deadlocking on big output)
;;; ------------------------------------------------------------------

(defun path-directories ()
  (let ((path (or (sb-ext:posix-getenv "PATH") ""))
        (sep #+win32 #\; #-win32 #\:)
        (home (user-homedir-pathname)))
    (append
     (loop with start = 0
           for pos = (position sep path :start start)
           for dir = (subseq path start pos)
           when (plusp (length dir))
             collect (pathname (concatenate 'string (string-right-trim "/\\" dir) "/"))
           while pos do (setf start (1+ pos)))
     ;; programs started from the Dock or Finder get a short PATH
     (list (merge-pathnames ".local/bin/" home)
           (merge-pathnames ".claude/local/" home)
           (merge-pathnames ".npm-global/bin/" home)
           #p"/opt/homebrew/bin/" #p"/usr/local/bin/" #p"/usr/bin/"))))

(defun find-program (name)
  "Full path of the executable NAME on the PATH, or NIL."
  (dolist (dir (path-directories))
    (dolist (ext '("" #+win32 ".exe" #+win32 ".cmd" #+win32 ".bat"))
      (let ((p (probe-file (merge-pathnames (concatenate 'string name ext) dir))))
        (when (and p (pathname-name p)) (return-from find-program p))))))

(defun child-environment ()
  "This process's environment, with the PATH extended by the directories
FIND-PROGRAM looks in (an editor started from the Dock or Finder gets a
short PATH, and programs like claude may need to find others)."
  (let ((path (format nil "~{~A~^~A~}"
                      (loop for (d . more) on (path-directories)
                            collect (string-right-trim "/\\" (native d))
                            when more collect #+win32 ";" #-win32 ":"))))
    (cons (concatenate 'string "PATH=" path)
          (remove-if (lambda (e) (starts-with-p "PATH=" e)) (sb-ext:posix-environ)))))

(defun run-with-input (program args input &key (timeout *assistant-timeout*))
  "Run PROGRAM with ARGS, feed it the string INPUT on stdin, and return
its standard output, its standard error and its exit code.  Kill it after
TIMEOUT seconds."
  (let* ((proc (sb-ext:run-program program args
                                   :input :stream :output :stream :error :stream
                                   :wait nil :search nil
                                   :environment (child-environment)
                                   :external-format :utf-8))
         (out (make-string-output-stream))
         (err (make-string-output-stream))
         (deadline (+ (get-universal-time) timeout)))
    (unwind-protect
         (progn
           (when input
             (ignore-errors
              (write-string input (sb-ext:process-input proc))
              (finish-output (sb-ext:process-input proc))))
           (ignore-errors (close (sb-ext:process-input proc)))
           (flet ((drain ()
                    (loop for s in (list (sb-ext:process-output proc) (sb-ext:process-error proc))
                          for dest in (list out err)
                          do (loop for c = (ignore-errors (read-char-no-hang s nil :eof))
                                   while (and c (not (eq c :eof)))
                                   do (write-char c dest)))))
             (loop while (sb-ext:process-alive-p proc)
                   do (drain)
                      (when (> (get-universal-time) deadline)
                        (sb-ext:process-kill proc 15)
                        (error "no answer after ~D seconds" timeout))
                      (sleep 0.05))
             (drain)
             ;; whatever is left after the process exited
             (loop for s in (list (sb-ext:process-output proc) (sb-ext:process-error proc))
                   for dest in (list out err)
                   do (loop for line = (read-line s nil nil)
                            while line do (write-line line dest)))))
      (ignore-errors (sb-ext:process-close proc)))
    (values (get-output-stream-string out)
            (get-output-stream-string err)
            (sb-ext:process-exit-code proc))))

;;; ------------------------------------------------------------------
;;; A little JSON, for the Messages API
;;; ------------------------------------------------------------------

(defun json-string (s)
  (with-output-to-string (o)
    (write-char #\" o)
    (loop for c across s
          do (case c
               (#\" (write-string "\\\"" o))
               (#\\ (write-string "\\\\" o))
               (#\Newline (write-string "\\n" o))
               (#\Return (write-string "\\r" o))
               (#\Tab (write-string "\\t" o))
               (t (if (< (char-code c) 32)
                      (format o "\\u~4,'0X" (char-code c))
                      (write-char c o)))))
    (write-char #\" o)))

(defun json-read (string)
  "Parse JSON: objects become alists with string keys, arrays lists,
true/false/null T/NIL/:NULL."
  (let ((i 0) (n (length string)))
    (labels ((peek () (and (< i n) (char string i)))
             (skip () (loop while (and (< i n) (member (char string i) '(#\Space #\Tab #\Newline #\Return)))
                            do (incf i)))
             (expect (c) (skip)
               (unless (eql (peek) c) (error "JSON: expected ~C at ~D" c i))
               (incf i))
             (value ()
               (skip)
               (let ((c (peek)))
                 (cond ((eql c #\{) (object))
                       ((eql c #\[) (array))
                       ((eql c #\") (str))
                       ((and c (or (digit-char-p c) (char= c #\-))) (num))
                       ((string= "true" string :start2 i :end2 (min n (+ i 4))) (incf i 4) t)
                       ((string= "false" string :start2 i :end2 (min n (+ i 5))) (incf i 5) nil)
                       ((string= "null" string :start2 i :end2 (min n (+ i 4))) (incf i 4) :null)
                       (t (error "JSON: unexpected ~S at ~D" c i)))))
             (object ()
               (incf i) (skip)
               (if (eql (peek) #\})
                   (progn (incf i) '())
                   (loop collect (let ((k (progn (skip) (str))))
                                   (expect #\:)
                                   (cons k (value)))
                         do (skip)
                         until (eql (peek) #\})
                         do (expect #\,)
                         finally (incf i))))
             (array ()
               (incf i) (skip)
               (if (eql (peek) #\])
                   (progn (incf i) '())
                   (loop collect (value)
                         do (skip)
                         until (eql (peek) #\])
                         do (expect #\,)
                         finally (incf i))))
             (str ()
               (incf i)
               (with-output-to-string (o)
                 (loop (let ((c (char string i)))
                         (incf i)
                         (cond ((char= c #\") (return))
                               ((char= c #\\)
                                (let ((e (char string i)))
                                  (incf i)
                                  (case e
                                    (#\n (write-char #\Newline o))
                                    (#\t (write-char #\Tab o))
                                    (#\r (write-char #\Return o))
                                    (#\b (write-char #\Backspace o))
                                    (#\f (write-char #\Page o))
                                    (#\u (let ((code (parse-integer string :start i :end (+ i 4) :radix 16)))
                                           (incf i 4)
                                           ;; a surrogate pair
                                           (when (and (<= #xD800 code #xDBFF)
                                                      (< (+ i 5) n) (char= (char string i) #\\))
                                             (let ((low (parse-integer string :start (+ i 2) :end (+ i 6) :radix 16)))
                                               (incf i 6)
                                               (setf code (+ #x10000 (ash (- code #xD800) 10) (- low #xDC00)))))
                                           (write-char (code-char code) o)))
                                    (t (write-char e o)))))
                               (t (write-char c o)))))))
             (num ()
               (let ((start i))
                 (loop while (and (< i n) (find (char string i) "+-0123456789.eE")) do (incf i))
                 (let ((*read-eval* nil))
                   (read-from-string string t nil :start start :end i)))))
      (value))))

(defun json-get (object &rest keys)
  (dolist (k keys object)
    (setf object (cdr (assoc k object :test #'equal)))))

;;; ------------------------------------------------------------------
;;; Claude
;;; ------------------------------------------------------------------

(defun anthropic-api-key ()
  (let ((env (sb-ext:posix-getenv "ANTHROPIC_API_KEY")))
    (if (and env (plusp (length env)))
        env
        (let ((file (merge-pathnames ".sbemacs/anthropic-api-key" (user-homedir-pathname))))
          (when (probe-file file)
            (with-open-file (in file) (trim (or (read-line in nil) ""))))))))

(defun claude-transport ()
  (ecase *claude-transport*
    ((:cli :api) *claude-transport*)
    (:auto (cond ((find-program "claude") :cli)
                 ((anthropic-api-key) :api)
                 (t (error "neither the claude program nor an API key was found.  ~
                            Install Claude Code (claude.com/claude-code) or set ANTHROPIC_API_KEY"))))))

(defun full-prompt (question context)
  (format nil "~A~%~%~A"
          context
          (if (plusp (length (trim question)))
              (format nil "Question: ~A" question)
              "Give hints about the code at the cursor.")))

(defun claude-cli-ask (question context)
  (let ((claude (or (find-program "claude") (error "the claude program is not installed"))))
    (multiple-value-bind (out err code)
        (run-with-input (native claude)
                        (append (list "-p"
                                      "--tools" ""          ; First Law: no tools, no files
                                      "--no-session-persistence"
                                      "--append-system-prompt" *assistant-instructions*)
                                (when *claude-model* (list "--model" *claude-model*))
                                (list (if (plusp (length (trim question)))
                                          question
                                          "Give hints about the code at the cursor.")))
                        context)
      (if (and code (zerop code) (plusp (length (trim out))))
          out
          (error "claude exited with code ~A: ~A" code
                 (trim (if (plusp (length (trim err))) err out)))))))

(defun claude-api-ask (question context)
  (let ((key (or (anthropic-api-key) (error "no API key: set ANTHROPIC_API_KEY")))
        (curl (or (find-program "curl") (error "curl is not installed")))
        (body (format nil "{\"model\":~A,\"max_tokens\":4096,\"system\":~A,~
                           \"messages\":[{\"role\":\"user\",\"content\":~A}]}"
                      (json-string (or *claude-model* *claude-api-model*))
                      (json-string *assistant-instructions*)
                      (json-string (full-prompt question context)))))
    ;; the key goes through stdin (curl -K -), never on the command line
    ;; or on disk; the body goes through a temporary file
    (let ((body-file (merge-pathnames (format nil "sbemacs-request-~D.json" (random 1000000000))
                                      (temporary-directory))))
      (unwind-protect
           (progn
             (with-open-file (o body-file :direction :output :if-exists :supersede
                                          :external-format :utf-8)
               (write-string body o))
             (multiple-value-bind (out err code)
                 (run-with-input (native curl)
                                 (list "-sS" "-K" "-" "--data-binary"
                                       (concatenate 'string "@" (native body-file))
                                       "https://api.anthropic.com/v1/messages")
                                 (format nil "header = \"x-api-key: ~A\"~%~
                                              header = \"anthropic-version: 2023-06-01\"~%~
                                              header = \"content-type: application/json\"~%"
                                         key))
               (unless (and code (zerop code))
                 (error "curl failed (~A): ~A" code (trim err)))
               (let ((json (json-read out)))
                 (if (equal (json-get json "type") "error")
                     (error "API: ~A" (json-get json "error" "message"))
                     (format nil "~{~A~}"
                             (loop for block in (json-get json "content")
                                   when (equal (json-get block "type") "text")
                                     collect (json-get block "text")))))))
        (ignore-errors (delete-file body-file))))))

(defun temporary-directory ()
  (let ((tmp (or (sb-ext:posix-getenv "TMPDIR") (sb-ext:posix-getenv "TEMP")
                 (sb-ext:posix-getenv "TMP") "/tmp")))
    (pathname (concatenate 'string (string-right-trim "/\\" tmp) "/"))))

(defun claude-ask (question context)
  (ecase (claude-transport)
    (:cli (claude-cli-ask question context))
    (:api (claude-api-ask question context))))

(define-assistant :claude "Claude" 'claude-ask)

;;; ------------------------------------------------------------------
;;; What is sent: the buffer around the cursor
;;; ------------------------------------------------------------------

(defun buffer-context ()
  "A description of the current buffer for the assistant, with the
cursor marked <<CURSOR>>."
  (let* ((p (point))
         (size (buffer-size))
         (half (floor *assistant-context-bytes* 2))
         (start (if (<= size *assistant-context-bytes*) 0 (line-start (max 0 (- p half)))))
         (end (if (<= size *assistant-context-bytes*) size (line-end (min size (+ p half)))))
         (before (buffer-substring start p))
         (after (buffer-substring p end))
         (line (1+ (count #\Newline (buffer-substring 0 p))))
         (file (or (buffer-filename) (get-buffer-name)))
         (lang (language-for-file file))
         (region (let ((m (mark)))
                   (when (and m (/= m p) (< (abs (- m p)) *assistant-context-bytes*))
                     (buffer-substring (min m p) (max m p))))))
    (format nil "File: ~A~%Language: ~A~%Cursor: line ~D~:[~;, the text shown is part of the file~]~%~
                 ~@[~%Selected region:~%```~%~A~%```~%~]~%Text:~%```~%~A<<CURSOR>>~A~%```"
            file (if lang (language-name lang) "unknown") line
            (or (> start 0) (< end size))
            region before after)))

;;; ------------------------------------------------------------------
;;; The window with the answer
;;; ------------------------------------------------------------------

(defvar *assistant-last-answer* nil)
(defvar *assistant-origin* nil "The buffer the question was asked from.")

(defun show-in-assistant-window (title text)
  "Show TEXT in *ASSISTANT-BUFFER* in the lower half of the screen; the
cursor stays where it was."
  (let ((origin (get-buffer-name)))
    (delete-other-windows)
    (split-window)
    (other-window)
    (select-buffer *assistant-buffer*)
    (goto-char 0)
    (delete-char (buffer-size))
    (insert (format nil "~A~%~A~%~%" title (make-string (min 70 (length title)) :initial-element #\-)))
    (insert (substitute #\Newline #\Return text))
    (beginning-of-buffer)
    (other-window)
    (select-buffer origin)))

(defun run-assistant (key question context origin)
  "Send QUESTION (\"\" for hints) and CONTEXT to the assistant KEY and show
the answer below the buffer ORIGIN."
  (let* ((assistant (find-assistant key))
         (name (assistant-name assistant)))
    (setf *assistant-origin* origin)
    (unless (string= (get-buffer-name) origin)
      (select-buffer origin))
    (message "~A is thinking ... (up to ~D s)" name *assistant-timeout*)
    (update-display)
    (handler-case
        (let ((answer (funcall (assistant-ask assistant) question context)))
          (setf *assistant-last-answer* answer)
          (show-in-assistant-window
           (format nil "~A~@[ -- ~A~]" name
                   (let ((q (trim question)))
                     (and (plusp (length q))
                          (if (> (length q) 60)
                              (concatenate 'string (substitute #\Space #\Newline (subseq q 0 57)) "...")
                              (substitute #\Space #\Newline q)))))
           answer)
          (message "~A answered.  ~:[C-x 1 closes the window~;C-c y inserts the code, C-x 1 closes the window~]"
                   name (proposed-code answer)))
      ;; Third Law: whatever happens, the editor and the buffer survive.
      ;; The explanation goes in the window, where it can be read.
      (error (e)
        (show-in-assistant-window
         (format nil "~A could not be reached" name)
         (format nil "~A~%~%~A" (princ-to-string e) (assistant-status-text)))
        (message "~A could not be reached; see the window below" name)))))

(defun ask-assistant (key)
  "Ask on the message line, then answer (kept for scripts that use it)."
  (let* ((name (assistant-name (find-assistant key)))
         (question (prompt (format nil "Ask ~A (RET for hints): " name) "")))
    (run-assistant key question (buffer-context) (get-buffer-name))))

;;; ------------------------------------------------------------------
;;; C-c r: the menu
;;; ------------------------------------------------------------------

(defparameter *claude-menu*
  "  h   Hints: Claude reads the code at the cursor (and the selected
      region) and suggests fixes and next steps.
  q   Question: write it in a window of its own, as many lines as
      you like; C-c r sends it.
  s   Set-up: is Claude installed and logged in?

  Any other key closes this menu.  Claude only reads: C-c y inserts
  the code it proposes, after you confirm."
  "The text of the C-c r menu.")

(defvar *assistant-saved-context* nil
  "The buffer around the cursor when the question window was opened.")

(defun claude-compose (context origin)
  "Open *claude-request* below ORIGIN, for a question of any length."
  (setf *assistant-saved-context* context
        *assistant-origin* origin)
  (unless (string= (get-buffer-name) origin) (select-buffer origin))
  (delete-other-windows)
  (split-window)
  (other-window)
  (select-buffer *claude-request-buffer*)
  (goto-char 0)
  (delete-char (buffer-size))
  (message "Write your question for Claude, then C-c r sends it (C-x o: back to ~A)" origin)
  t)

(defun claude-send-request ()
  "Send the question written in *claude-request*."
  (let ((question (trim (buffer-substring 0 (buffer-size)))))
    (cond ((zerop (length question))
           (message "Write a question first, then C-c r sends it"))
          ((null *assistant-saved-context*)
           (message "The file to ask about is unknown; start again from it with C-c r"))
          (t (run-assistant :claude question *assistant-saved-context*
                            (or *assistant-origin* "*scratch*"))))))

(defun claude-menu ()
  (let ((context (buffer-context))
        (origin (get-buffer-name)))
    (show-in-assistant-window "Ask Claude" *claude-menu*)
    (message "Claude: h hints, q question, s set-up; any other key closes the menu")
    (update-display)
    (let* ((k (get-key))
           (choice (and (= (length k) 1) (char-downcase (char k 0)))))
      (case choice
        (#\h (run-assistant :claude "" context origin))
        (#\q (claude-compose context origin))
        (#\s (assistant-status))
        (t (close-assistant-windows)
           (clear-message-line))))))

(defun ask-claude ()
  "C-c r: the menu; in *claude-request*, send the question."
  (if (string= (get-buffer-name) *claude-request-buffer*)
      (claude-send-request)
      (claude-menu)))



;;; ------------------------------------------------------------------
;;; Closing the assistants' windows (C-h and the menu use it)
;;; ------------------------------------------------------------------

(defparameter *assistant-buffer-names*
  '("*assistant*" "*claude-request*" "*codex*" "*codex-request*")
  "Buffers that belong to the assistants; help (C-h) closes their windows.")

(defun assistant-buffer-p (name)
  (member name *assistant-buffer-names* :test #'string=))

(defun file-behind-assistant ()
  "The buffer an assistant was asked from, if we know it."
  (or (and (boundp '*assistant-origin*) (symbol-value '*assistant-origin*))
      (and (boundp '*codex-origin-buffer*) (symbol-value '*codex-origin-buffer*))
      "*scratch*"))

(defcommand close-assistant-windows ()
  "Close every window showing a Claude or Codex buffer."
  (let ((origin (get-buffer-name)))
    (loop repeat (* 2 (window-count))
          while (> (window-count) 1)
          do (if (assistant-buffer-p (get-buffer-name))
                 (delete-window)
                 (other-window)))
    (when (assistant-buffer-p (get-buffer-name))
      (select-buffer (file-behind-assistant)))
    ;; back to the window that was selected, if it is still there
    (loop repeat (window-count)
          until (string= (get-buffer-name) origin)
          do (other-window))
    t))


;;; ------------------------------------------------------------------
;;; What is set up, and how to fix it
;;; ------------------------------------------------------------------

(defun assistant-status-text ()
  (let ((claude (find-program "claude"))
        (curl (find-program "curl"))
        (key (anthropic-api-key)))
    (format nil "Set-up~%------~%~
                 transport (*claude-transport*): ~S~%~
                 claude program: ~:[NOT FOUND~;~:*~A~]~%~
                 curl:           ~:[NOT FOUND~;~:*~A~]~%~
                 API key:        ~:[none~;found~]~%~%~
                 To use your Claude subscription, install Claude Code and log in~%~
                 once in a terminal:~%~%    ~
                 curl -fsSL https://claude.ai/install.sh | bash~%    ~
                 claude~%~%~
                 (or: brew install --cask claude-code).  Claude Code needs a Pro,~%~
                 Max, Team or Enterprise plan.  To use an API key instead, put it~%~
                 in ~~/.sbemacs/anthropic-api-key or in ANTHROPIC_API_KEY.~%~%~
                 Programs are looked for on the PATH and in:~%~{  ~A~%~}"
            *claude-transport*
            (and claude (native claude))
            (and curl (native curl))
            key
            (mapcar #'native (last (path-directories) 6)))))

(defun assistant-status ()
  "Show how the assistant would reach Claude (Esc-; (assistant-status))."
  (show-in-assistant-window "Assistant status" (assistant-status-text))
  t)

;;; ------------------------------------------------------------------
;;; Second Law: insert the proposed code, when told to
;;; ------------------------------------------------------------------

(defun proposed-code (answer)
  "The first fenced code block in ANSWER, without the fences, or NIL."
  (when answer
    (let* ((open (search "```" answer))
           (body-start (and open (position #\Newline answer :start open)))
           (close (and body-start (search "```" answer :start2 (1+ body-start)))))
      (when close
        (string-right-trim '(#\Newline #\Return) (subseq answer (1+ body-start) close))))))

(defun assistant-insert ()
  "Insert the code the assistant proposed at the cursor, after asking."
  (let ((code (proposed-code *assistant-last-answer*)))
    (cond ((null code)
           (message "The last answer has no code to insert"))
          ((string-equal (get-buffer-name) *assistant-buffer*)
           (message "Go back to your buffer first (C-x o)"))
          (t
           (let* ((lines (1+ (count #\Newline code)))
                  (yes (prompt (format nil "Insert ~D line~:P at the cursor? (y/n) " lines) "")))
             (if (string-equal (trim yes) "y")
                 (progn (insert code)
                        (message "Inserted ~D line~:P (C-u undoes it)" lines))
                 (message "Nothing inserted")))))))

;;; ------------------------------------------------------------------
;;; Keys
;;; ------------------------------------------------------------------

(global-set-key "C-c r" 'ask-claude)
(global-set-key "C-c y" 'assistant-insert)
