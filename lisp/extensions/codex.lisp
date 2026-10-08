;;;; codex.lisp -- ask OpenAI Codex from a lower editor window
;;;;
;;;; This is a script: edit it and press C-x C-r; no editor rebuild.
;;;;
;;;;   C-c g       a menu: h hints, q question, d discussion, s set-up
;;;;   C-c g       in a question or discussion window, sends the request
;;;;   C-c y       in a question answer, insert every fenced code block
;;;;               into the source and close the help window
;;;;   C-c t       in a discussion, insert the snippet under the cursor
;;;;
;;;; Codex receives a bounded copy of the source around point.  It runs with
;;;; the read-only sandbox and an ephemeral session: it may inspect and test,
;;;; but cannot edit the project.  Only the user can insert proposed text.

(in-package #:sbemacs)

(declaim (optimize (safety 3) (debug 2)))

(defvar *codex-program* nil
  "Codex executable override, or NIL to discover it automatically.")

(defvar *codex-model* nil
  "Codex model name, or NIL to use the CLI default.")

(defvar *codex-timeout* 300
  "Seconds to wait for Codex.")

(defvar *codex-context-bytes* 60000
  "Maximum source bytes sent to Codex around point.")

(defvar *codex-request-buffer* "*codex-request*")
(defvar *codex-answer-buffer* "*codex*")
;; The C core stores at most 16 buffer-name characters (NBUFN is 17).
;; A longer name is silently truncated and cannot be recognized afterward.
(defparameter *codex-discussion-buffer* "*codex-chat*")
(defvar *codex-origin-buffer* nil)
(defvar *codex-saved-context* nil)
(defvar *codex-working-directory* nil)
(defvar *codex-discussion-origin* nil)

(defparameter *codex-menu*
  "  h   Hints: Codex reads the code at the cursor (and the selected
      region) and suggests fixes and next steps.
  q   Question: write it in a window of its own, as many lines as
      you like; C-c g sends it.
  d   Discussion: a conversation in a window that stays open; C-c t
      there inserts the snippet under the cursor into your file.
  s   Set-up: is Codex installed and signed in with ChatGPT?

  Any other key closes this menu.  Codex only reads: C-c y inserts
  the code it proposes, after you confirm.")

(defparameter *codex-instructions*
  "You are the Codex assistant inside SBEmacs.  The user is editing a
file and has written a request in a separate editor window.  Answer that
request using the supplied source context.

Do not modify any file.  Do not propose changes to the editor's C sources.
Concentrate on Common Lisp and on the user's current text.  You may use
read-only inspection and run non-destructive tests when useful.  For a
translation or explanation, return the requested prose directly.  When you
propose text or code for insertion, place exactly the insertable text in one
fenced code block.  Keep explanations short and use plain text suitable for
an editor window."
  "Instructions prepended to every Codex request.")

(declaim (ftype (function () (values string &optional)) codex-source-context))
(defun codex-source-context ()
  "Describe a bounded part of the current source buffer, marking point."
  (let* ((p (point))
         (size (buffer-size))
         (half (floor *codex-context-bytes* 2))
         (start (if (<= size *codex-context-bytes*)
                    0
                    (line-start (max 0 (- p half)))))
         (end (if (<= size *codex-context-bytes*)
                  size
                  (line-end (min size (+ p half)))))
         (before (buffer-substring start p))
         (after (buffer-substring p end))
         (file (or (buffer-filename) (get-buffer-name)))
         (language (language-for-file file))
         (line (1+ (count #\Newline (buffer-substring 0 p))))
         (m (mark))
         (region (and m (/= m p)
                      (< (abs (- m p)) *codex-context-bytes*)
                      (buffer-substring (min m p) (max m p)))))
    (with-output-to-string (out)
      (format out "File: ~A~%Language: ~A~%Cursor line: ~D~%"
              file (if language (language-name language) "unknown") line)
      (format out "Context truncated: ~A~%"
              (if (or (> start 0) (< end size)) "yes" "no"))
      (when region
        (format out "Selected text:~%```~%~A~%```~%" region))
      (format out "Source around the cursor:~%```~%~A<<CURSOR>>~A~%```"
              before after))))

(declaim (ftype (function () (values string &optional)) codex-source-directory))
(defun codex-source-directory ()
  "Absolute directory of the current file, or the editor's directory.
A relative buffer name such as teste.lisp must not become the empty string."
  (let* ((file (buffer-filename))
         (absolute (and file (plusp (length file))
                        (merge-pathnames (pathname file)
                                         *default-pathname-defaults*)))
         (directory (if absolute
                        (make-pathname :name nil :type nil :version nil
                                       :defaults absolute)
                        *default-pathname-defaults*)))
    (native directory)))

(declaim (ftype (function () (values string &optional)) codex-effective-working-directory))
(defun codex-effective-working-directory ()
  "A nonempty directory for `codex exec --cd'."
  (let ((directory (trim (or *codex-working-directory* ""))))
    (if (plusp (length directory))
        directory
        (native (truename *default-pathname-defaults*)))))

(defun codex-clear-current-buffer ()
  (goto-char 0)
  (delete-char (buffer-size)))

(defun codex-compose (&optional context origin)
  "Open the lower Codex request window and save the source context."
  (setf *codex-origin-buffer* (or origin (get-buffer-name))
        *codex-saved-context* (or context (buffer-context))
        *codex-working-directory* (codex-source-directory))
  (delete-other-windows)
  (split-window)
  (other-window)
  (select-buffer *codex-request-buffer*)
  (codex-clear-current-buffer)
  (message "Describe the task, then press C-c g again to send it to Codex")
  t)

(declaim (ftype (function (string) (values string &optional)) codex-prompt))
(defun codex-prompt (request)
  (format nil "~A~%~%USER REQUEST~%============~%~A~%~%SOURCE CONTEXT~%==============~%~A"
          *codex-instructions* request *codex-saved-context*))

(declaim (ftype (function () (values list &optional)) codex-installation-candidates))
(defun codex-installation-candidates ()
  "Likely Codex executables not already covered by PATH."
  (remove
   nil
   (list
    ;; Current ChatGPT bundles keep the CLI inside a nested application.
    ;; Keep the legacy locations too: GUI launches need not inherit shell PATH.
    #+darwin #p"/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
    #+darwin (merge-pathnames
              "Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
              (user-homedir-pathname))
    #+darwin #p"/Applications/Codex.app/Contents/Resources/codex"
    #+darwin (merge-pathnames
              "Applications/Codex.app/Contents/Resources/codex"
              (user-homedir-pathname))
    ;; Codex bundled with older ChatGPT desktop applications on macOS.
    #+darwin #p"/Applications/ChatGPT.app/Contents/Resources/codex"
    #+darwin (merge-pathnames
              "Applications/ChatGPT.app/Contents/Resources/codex"
              (user-homedir-pathname))
    ;; Defaults used by the official standalone installers.
    #-win32 (merge-pathnames ".local/bin/codex" (user-homedir-pathname))
    #+win32 (let ((local (sb-ext:posix-getenv "LOCALAPPDATA")))
              (and local
                   (merge-pathnames "Programs/OpenAI/Codex/bin/codex.exe"
                                    (pathname (concatenate 'string
                                                           (string-right-trim "/\\" local)
                                                           "/")))))
    ;; npm's usual per-user command shim on Windows.
    #+win32 (let ((appdata (sb-ext:posix-getenv "APPDATA")))
              (and appdata
                   (merge-pathnames "npm/codex.cmd"
                                    (pathname (concatenate 'string
                                                           (string-right-trim "/\\" appdata)
                                                           "/"))))))))

(defun codex-windows-program (program)
  "Resolve npm's Unix shim to its Windows sibling; never execute a .ps1 directly."
  (let* ((path (pathname program))
         (type (string-downcase (or (pathname-type path) ""))))
    (cond ((member type '("exe" "cmd" "bat") :test #'string=) (probe-file path))
          ((member type '("" "ps1") :test #'string=)
           (or (probe-file (make-pathname :type "exe" :defaults path))
               (probe-file (make-pathname :type "cmd" :defaults path))))
          (t (probe-file path)))))

(defun codex-find-windows-program (name)
  "Search Windows executable extensions before npm's extensionless shell shim."
  (or (find-program (concatenate 'string name ".exe"))
      (find-program (concatenate 'string name ".cmd"))
      (find-program (concatenate 'string name ".bat"))))

(declaim (ftype (function ((or null string)) (values (or null pathname) &optional))
                codex-explicit-program))
(defun codex-explicit-program (name)
  "Resolve NAME as a path or as a command on PATH."
  (when (and name (plusp (length name)))
    #+win32
    (if (find-if (lambda (character) (find character "/\\")) name)
        (codex-windows-program name)
        (if (pathname-type (pathname name))
            (let ((found (find-program name)))
              (and found (codex-windows-program found)))
            (codex-find-windows-program name)))
    #-win32
    (if (find-if (lambda (character) (find character "/\\")) name)
        (probe-file (pathname name))
        (find-program name))))

(declaim (ftype (function () (values (or null pathname) &optional)) find-codex-program))
(defun find-codex-program ()
  "Find an explicit, PATH, standalone, npm, or ChatGPT-bundled Codex."
  (or (codex-explicit-program (or *codex-program*
                                  (sb-ext:posix-getenv "SBEMACS_CODEX_PROGRAM")))
      #+win32 (codex-find-windows-program "codex")
      #-win32 (find-program "codex")
      (find-if #'probe-file (codex-installation-candidates))))

(declaim (ftype (function () (values list &optional)) codex-exec-arguments))
(defun codex-exec-arguments ()
  (append (list "exec"
                "--sandbox" "read-only"
                "--ephemeral"
                "--ignore-rules"
                "--skip-git-repo-check"
                "--color" "never"
                (concatenate 'string "--cd="
                             (codex-effective-working-directory)))
          (when *codex-model* (list "--model" *codex-model*))
          (list "-")))

(defun codex-npm-native-program (program)
  "Find the Windows binary in npm's optional platform package or older vendor tree."
  (let ((root (make-pathname :name nil :type nil :defaults (pathname program))))
    (loop for package in '("codex-win32-x64" "codex-win32-arm64")
          for target in '("x86_64-pc-windows-msvc" "aarch64-pc-windows-msvc")
          append (list (format nil "node_modules/@openai/~A/vendor/~A/codex/codex.exe" package target)
                       (format nil "node_modules/@openai/codex/node_modules/@openai/~A/vendor/~A/codex/codex.exe" package target)
                       (format nil "node_modules/@openai/codex/vendor/~A/codex/codex.exe" target))
          into candidates
          finally (return (loop for relative in candidates
                                for path = (probe-file (merge-pathnames relative root))
                                when path return path)))))

(defun codex-cmd-quoted-argument (text)
  "Quote a cmd.exe argument. Refuse expansion characters instead of executing them."
  (when (find-if (lambda (c) (find c '(#\" #\% #\! #\Return #\Newline #\Null))) text)
    (error "Codex: this batch launcher cannot safely pass this path/argument; use a native codex.exe."))
  (format nil "\"~A\"" text))

(declaim (ftype (function ((or pathname string) list)
                          (values (or pathname string) list &optional))
                codex-windows-command))
(defun codex-windows-command (program arguments)
  "Prefer native Codex or Node, passing separate arguments without a command shell."
  #+win32
  (if (member (string-downcase (or (pathname-type (pathname program)) ""))
              '("cmd" "bat") :test #'string=)
      (let* ((root (make-pathname :name nil :type nil :defaults (pathname program)))
             (binary (codex-npm-native-program program))
             (script (probe-file (merge-pathnames "node_modules/@openai/codex/bin/codex.js" root)))
             (node (or (probe-file (merge-pathnames "node.exe" root))
                       (find-program "node.exe"))))
        (cond (binary (values binary arguments))
              ((and script node) (values node (cons (native script) arguments)))
              (t (values (windows-command-interpreter)
                         (list "/d" "/s" "/c"
                               ;; /s strips the outer pair; preserve the executable's quotes.
                               (format nil "\"~A~{ ~A~}\""
                                       (codex-cmd-quoted-argument (native (pathname program)))
                                       (mapcar #'codex-cmd-quoted-argument arguments)))))))
      (values program arguments))
  #-win32
  (values program arguments))

(defvar *codex-last-capture* nil
  "Last stdout/stderr octets and exit status, kept in memory for diagnosis only.")

(defun codex-new-capture-file ()
  "Reserve a temporary file without overwriting an existing one."
  (loop for path = (merge-pathnames
                    (format nil "sbemacs-codex-~36R-~36R.tmp" (get-universal-time) (random (expt 2 64)))
                    (temporary-directory))
        for stream = (open path :direction :output :element-type '(unsigned-byte 8)
                                :if-exists nil :if-does-not-exist :create)
        when stream do (close stream)
                       #-win32
                       (progn
                         (require :sb-posix)
                         (funcall (find-symbol "CHMOD" "SB-POSIX") (native path) #o600))
                       (return path)))

(defun codex-read-octets (path)
  (with-open-file (stream path :element-type '(unsigned-byte 8))
    (let ((octets (make-array (file-length stream) :element-type '(unsigned-byte 8))))
      (read-sequence octets stream)
      octets)))

(defun codex-capture-process (program arguments input &key (timeout *codex-timeout*))
  "Capture each child output as bytes. No console/OEM encoding is guessed.
File redirection avoids pipe deadlocks; stdin is explicitly encoded as UTF-8."
  (let ((files nil) (process nil))
    (setf *codex-last-capture* nil)
    (unwind-protect
         (let* ((in (car (push (codex-new-capture-file) files)))
                (out (car (push (codex-new-capture-file) files)))
                (err (car (push (codex-new-capture-file) files))))
           (with-open-file (stream in :direction :output :element-type '(unsigned-byte 8)
                                     :if-exists :overwrite)
             (write-sequence (sb-ext:string-to-octets input :external-format :utf-8) stream))
           (setf process (sb-ext:run-program program arguments
                                           :input in :output out :error err
                                           :if-output-exists :overwrite :if-error-exists :overwrite
                                           :search nil :wait nil :environment (child-environment)
                                           #+win32 :window #+win32 :hide))
           (let ((deadline (+ (get-internal-real-time)
                              (* timeout internal-time-units-per-second)))
                 (timed-out nil))
             (loop while (sb-ext:process-alive-p process)
                   do (when (>= (get-internal-real-time) deadline)
                        (setf timed-out t)
                        (sb-ext:process-kill process 9)
                        (return))
                      (sleep 0.05))
             (sb-ext:process-wait process)
             (let ((stdout (codex-read-octets out))
                   (stderr (codex-read-octets err))
                   (code (sb-ext:process-exit-code process)))
               (setf *codex-last-capture* (list :stdout stdout :stderr stderr :exit-code code
                                               :timed-out timed-out))
               (when timed-out (error "Codex: no answer after ~D seconds; raw streams captured separately." timeout))
               (values stdout stderr code))))
      (when process
        (when (sb-ext:process-alive-p process) (ignore-errors (sb-ext:process-kill process 9)))
        (ignore-errors (sb-ext:process-close process)))
      (dolist (file files) (ignore-errors (delete-file file))))))

(defun codex-decode-utf8 (octets stream-name)
  "Decode only proven-valid UTF-8; retain invalid data in the raw capture."
  (handler-case (sb-ext:octets-to-string octets :external-format :utf-8)
    (error () (error "Codex: ~A is not valid UTF-8 (~D bytes, byte 130 at offset ~A). Raw data retained in *codex-last-capture*; no bytes discarded."
                     stream-name (length octets) (position 130 octets)))))

(defun codex-capture-summary ()
  "Metadata only: never print the prompt, credential-bearing stderr, or raw bytes."
  (loop for name in '(:stdout :stderr)
        for octets = (getf *codex-last-capture* name)
        collect (list name :bytes (length octets) :byte-130-offset (position 130 octets)
                      :utf8-valid (handler-case
                                      (progn (sb-ext:octets-to-string octets :external-format :utf-8) t)
                                    (error () nil)))))

(defun codex-report-exit-error (out err code)
  "Report authentication distinctly without copying possible credentials to the panel."
  (let* ((bytes (if (plusp (length err)) err out))
         (detail (handler-case (sb-ext:octets-to-string bytes :external-format :utf-8)
                   (error () nil)))
         (authentication (and detail
                              (some (lambda (term) (search term (string-downcase detail)))
                                    '("unauthorized" "authentication" "not logged in" "401" "sign in" "codex login")))))
    (if authentication
        (error "Codex exited with code ~A: authentication failed. Run codex login and sign in with ChatGPT." code)
        (error "Codex exited with code ~A (~D stdout bytes, ~D stderr bytes; error output ~A). Raw streams retained in *codex-last-capture*; use codex-capture-summary for metadata."
               code (length out) (length err) (if detail "is UTF-8" "is not UTF-8")))))

(defun codex-cli-ask (request &optional context)
  "Return the final response, capturing transport diagnostics separately."
  (when context (setf *codex-saved-context* context))
  (let ((program (or (find-codex-program)
                     (error "Codex was not found. Install the official Codex CLI or the ChatGPT desktop app, then sign in with ChatGPT."))))
    (multiple-value-bind (launcher arguments)
        (codex-windows-command program (codex-exec-arguments))
      (multiple-value-bind (out err code)
          (codex-capture-process (if (pathnamep launcher) (native launcher) launcher)
                                 arguments (codex-prompt request))
        ;; A successful CLI may send progress to stderr. Keep it as raw diagnostic
        ;; data; only stdout is the response. Never transcode stderr as a guess.
        (unless (and code (zerop code))
          (codex-report-exit-error out err code))
        (let ((answer (trim (codex-decode-utf8 out "stdout"))))
          (when (zerop (length answer))
            (error "Codex exited successfully but returned empty stdout (~D stderr bytes captured)." (length err)))
          answer)))))

(defun codex-ask (question context)
  "ASK function used by the common assistant window machinery."
  (codex-cli-ask question context))

(define-assistant :codex "Codex" 'codex-ask)

(defun codex-show-answer (title text)
  "Replace the lower request window with a Codex answer."
  (select-buffer *codex-answer-buffer*)
  (codex-clear-current-buffer)
  (insert title #\Newline
          (make-string (min 70 (length title)) :initial-element #\-)
          #\Newline #\Newline
          (substitute #\Newline #\Return text))
  (beginning-of-buffer)
  (let ((hint (if (and (fboundp 'answer-hint) (proposed-code text))
                  (funcall 'answer-hint text)
                  "C-x o back to file")))
    (set-buffer-hint *codex-answer-buffer* hint)
    (message "Codex answered.  ~:[C-x o goes back to the file~;C-c y inserts the code and closes the window~]"
             (proposed-code text)))
  t)

(defun codex-submit ()
  "Send the text in *codex-request* to Codex."
  (unless (string= (get-buffer-name) *codex-request-buffer*)
    (message "C-c g sends only after opening the *codex-request* window")
    (return-from codex-submit nil))
  (let ((request (trim (buffer-substring 0 (buffer-size)))))
    (when (zerop (length request))
      (message "Write a request before sending it")
      (return-from codex-submit nil))
    (message "Codex is thinking ... (up to ~D seconds)" *codex-timeout*)
    (update-display)
    (run-assistant :codex request *codex-saved-context*
                   (or *codex-origin-buffer* "*scratch*"))))

(defun codex-menu ()
  "Show the Codex menu and perform its one-key choice."
  (let ((context (buffer-context))
        (origin (get-buffer-name)))
    (setf *codex-working-directory* (codex-source-directory))
    (show-in-assistant-window "Ask Codex (ChatGPT)" *codex-menu*)
    (set-buffer-hint *assistant-buffer* "h hints; q ask; d discuss; s set-up")
    (message "Codex: h hints, q question, d discussion, s set-up; any other key closes the menu")
    (update-display)
    (let* ((key (get-key))
           (choice (and (= (length key) 1) (char-downcase (char key 0)))))
      (case choice
        (#\h (run-assistant :codex "" context origin))
        (#\q (codex-compose context origin))
        (#\d (codex-discussion origin))
        (#\s (codex-status))
        (t (close-assistant-windows) (clear-message-line))))))

(defun ask-codex ()
  "C-c g: menu; in a question or discussion window, send the request."
  (cond ((string= (get-buffer-name) *codex-request-buffer*) (codex-submit))
        ((string= (get-buffer-name) *codex-discussion-buffer*)
         (codex-discussion-send))
        (t (codex-menu))))

(declaim (ftype (function () (values string &optional)) codex-status-text))
(defun codex-status-text ()
  (let ((program (find-codex-program)))
    (format nil "Codex CLI: ~:[NOT FOUND~;~:*~A~]~%~
                 Model: ~:[CLI default~;~:*~A~]~%~
                 Sandbox: read-only~%Session: ephemeral~%~%~
                 SBEmacs checks PATH, the official standalone-install~%~
                 directories, npm on Windows, and the macOS ChatGPT app.~%~
                 Override discovery with *codex-program* in init.lisp~%~
                 or the SBEMACS_CODEX_PROGRAM environment variable.~%~
                 If authentication is needed, run Codex once and choose~%~
                 Sign in with ChatGPT."
            (and program (native program)) *codex-model*)))

(defun codex-status ()
  "Show Codex setup in the lower window."
  (show-in-assistant-window "Codex status" (codex-status-text))
  (set-buffer-hint *assistant-buffer* "C-x 1 close")
  t)

;;; ------------------------------------------------------------------
;;; A Codex discussion: deliberately kept separate from a question
;;; ------------------------------------------------------------------

(defparameter *codex-you-marker* "You:")
(defparameter *codex-marker* "Codex:")

(defun codex-discussion (origin)
  "Open (or return to) the persistent Codex discussion about ORIGIN."
  (unless (string= (get-buffer-name) origin) (select-buffer origin))
  (setf *codex-discussion-origin* origin
        *codex-working-directory* (codex-source-directory))
  (delete-other-windows)
  (split-window)
  (other-window)
  (select-buffer *codex-discussion-buffer*)
  (when (zerop (buffer-size))
    (insert (format nil "Discussion with Codex about ~A~%~
                         C-c g sends what you write after the last ~A~%~
                         C-c t inserts the snippet under the cursor into ~A~%~
                         C-x 0 closes this window; C-c g, then d, brings it back~%~
                         ~A~%~%~A~%"
                    origin *codex-you-marker* origin
                    (make-string 70 :initial-element #\=) *codex-you-marker*)))
  (end-of-buffer)
  (message "Write to Codex after \"~A\", then C-c g" *codex-you-marker*)
  t)

(defun codex-discussion-send ()
  "Send the latest user turn, the transcript and current source to Codex."
  (let* ((text (buffer-substring 0 (buffer-size)))
         (start (last-marker-position text *codex-you-marker*))
         (message-text (and start (trim (subseq text start)))))
    (cond ((or (null message-text) (zerop (length message-text)))
           (message "Write after the last \"~A\", then C-c g" *codex-you-marker*))
          ((null *codex-discussion-origin*)
           (message "The file is unknown; start from it with C-c g, then d"))
          (t
           (let ((context (call-in-window-of *codex-discussion-origin* #'buffer-context))
                 (question (format nil "This is a continuing discussion. Reply to the ~
                                        user's last message.~%~%~A" text)))
             (message "Codex is thinking ... (up to ~D s)" *codex-timeout*)
             (update-display)
             (let ((answer (handler-case (codex-ask question context)
                             (error (condition)
                               (format nil "(Codex could not be reached: ~A)" condition)))))
               (setf *assistant-last-answer* answer
                     *assistant-origin* *codex-discussion-origin*)
               (end-of-buffer)
               (insert (format nil "~:[~%~;~]~%~A~%~A~%~%~A~%"
                               (and (plusp (length text))
                                    (char= (char text (1- (length text))) #\Newline))
                               *codex-marker* (trim (substitute #\Newline #\Return answer))
                               *codex-you-marker*))
               (message "Codex answered. C-c t on a snippet inserts it into ~A"
                        *codex-discussion-origin*)))))))

(defun codex-discussion-tangle ()
  "Insert the fenced snippet at point in the persistent Codex discussion."
  (let* ((octets (buffer-octets 0 (buffer-size)))
         (text (sb-ext:octets-to-string octets :external-format '(:utf-8 :replacement #\?)))
         (index (length (sb-ext:octets-to-string
                         (subseq octets 0 (point))
                         :external-format '(:utf-8 :replacement #\?))))
         (code (snippet-at text index)))
    (if (null code)
        (message "Put the cursor on a snippet (between its ``` lines) first")
        (call-in-window-of *codex-discussion-origin*
                           (lambda ()
                             (confirm-insert code
                               (format nil "into ~A at line ~D"
                                       *codex-discussion-origin* (line-number))))))))

(defun assistant-discussion-tangle ()
  "C-c t: dispatch to the discussion shown in the current buffer."
  (cond ((string= (get-buffer-name) *claude-discussion-buffer*)
         (discussion-tangle))
        ((string= (get-buffer-name) *codex-discussion-buffer*)
         (codex-discussion-tangle))
        (t (message "C-c t works in a Claude or Codex discussion window"))))

;; Remove the old stub binding when this script is reloaded in a running editor.
(global-unset-key "C-c x")
(global-set-key "C-c g" 'ask-codex)
(global-set-key "C-c t" 'assistant-discussion-tangle)

(set-buffer-hint *codex-request-buffer* "C-c g ask; C-x o back to file")
(set-buffer-hint *codex-discussion-buffer* "C-c g send; C-c t code-tangle")
