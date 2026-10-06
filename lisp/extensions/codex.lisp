;;;; codex.lisp -- ask OpenAI Codex from a lower editor window
;;;;
;;;; This is a script: edit it and press C-x C-r; no editor rebuild.
;;;;
;;;;   C-c g       open *codex-request* below the source window
;;;;   C-c g       again, from that buffer, sends the request
;;;;   C-c y       after returning to the source window, insert the first
;;;;               fenced code block from the answer, with confirmation
;;;;
;;;; Codex receives a bounded copy of the source around point.  It runs with
;;;; the read-only sandbox and an ephemeral session: it may inspect and test,
;;;; but cannot edit the project.  Only the user can insert proposed text.

(in-package #:sbemacs)

(defvar *codex-program* "codex"
  "Name of the OpenAI Codex CLI executable.")

(defvar *codex-model* nil
  "Codex model name, or NIL to use the CLI default.")

(defvar *codex-timeout* 300
  "Seconds to wait for Codex.")

(defvar *codex-context-bytes* 60000
  "Maximum source bytes sent to Codex around point.")

(defvar *codex-request-buffer* "*codex-request*")
(defvar *codex-answer-buffer* "*codex*")
(defvar *codex-origin-buffer* nil)
(defvar *codex-saved-context* nil)
(defvar *codex-working-directory* nil)

(defparameter *codex-instructions*
  "You are the Codex assistant inside Femto Emacs.  The user is editing a
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
    (format nil "File: ~A~%Language: ~A~%Cursor line: ~D~%~
                 Context truncated: ~:[no~;yes~]~%~
                 ~@[Selected text:~%```~%~A~%```~%~]~%~
                 Source around the cursor:~%```~%~A<<CURSOR>>~A~%```"
            file (if language (language-name language) "unknown") line
            (or (> start 0) (< end size)) region before after)))

(defun codex-source-directory ()
  "Directory of the current file, or the editor's working directory."
  (let ((file (buffer-filename)))
    (if file
        (native (make-pathname :name nil :type nil :version nil
                               :defaults (pathname file)))
        (native *default-pathname-defaults*))))

(defun codex-clear-current-buffer ()
  (goto-char 0)
  (delete-char (buffer-size)))

(defun codex-compose ()
  "Open the lower Codex request window and save the source context."
  (setf *codex-origin-buffer* (get-buffer-name)
        *codex-saved-context* (codex-source-context)
        *codex-working-directory* (codex-source-directory))
  (delete-other-windows)
  (split-window)
  (other-window)
  (select-buffer *codex-request-buffer*)
  (codex-clear-current-buffer)
  (message "Describe the task, then press C-c g again to send it to Codex")
  t)

(defun codex-prompt (request)
  (format nil "~A~%~%USER REQUEST~%============~%~A~%~%SOURCE CONTEXT~%==============~%~A"
          *codex-instructions* request *codex-saved-context*))

(defun codex-exec-arguments ()
  (append (list "exec"
                "--sandbox" "read-only"
                "--ephemeral"
                "--ignore-rules"
                "--skip-git-repo-check"
                "--color" "never"
                "-C" *codex-working-directory*)
          (when *codex-model* (list "--model" *codex-model*))
          (list "-")))

(defun codex-windows-command (program arguments)
  "On Windows, run npm's codex.cmd through cmd.exe.  Native executables
are returned unchanged.  Elsewhere this is a no-op."
  #+win32
  (if (member (string-downcase (or (pathname-type program) ""))
              '("cmd" "bat") :test #'string=)
      (let ((cmd (or (find-program "cmd")
                     #p"C:/Windows/System32/cmd.exe")))
        (values cmd
                (list "/d" "/s" "/c"
                      (format nil "\"~A\" ~{\"~A\"~^ ~}"
                              (native program) arguments))))
      (values program arguments))
  #-win32
  (values program arguments))

(defun codex-cli-ask (request)
  "Return the final response from a read-only, ephemeral Codex CLI run."
  (let ((program (or (find-program *codex-program*)
                     (error "the Codex CLI was not found; install @openai/codex and run codex login"))))
    (multiple-value-bind (launcher arguments)
        (codex-windows-command program (codex-exec-arguments))
      (multiple-value-bind (out err code)
          (run-with-input (native launcher) arguments (codex-prompt request)
                          :timeout *codex-timeout*)
        (if (and code (zerop code) (plusp (length (trim out))))
            (trim out)
            (error "codex exited with code ~A: ~A"
                   code (trim (if (plusp (length (trim err))) err out))))))))

(defun codex-show-answer (title text)
  "Replace the lower request window with a Codex answer."
  (select-buffer *codex-answer-buffer*)
  (codex-clear-current-buffer)
  (insert title #\Newline
          (make-string (min 70 (length title)) :initial-element #\-)
          #\Newline #\Newline
          (substitute #\Newline #\Return text))
  (beginning-of-buffer)
  (message "Codex answered; C-x o returns to the source, C-c y inserts proposed code")
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
    (handler-case
        (let ((answer (codex-cli-ask request)))
          ;; Keep compatibility with C-c y while assistant.lisp is evolving.
          (when (boundp '*assistant-last-answer*)
            (setf *assistant-last-answer* answer))
          (when (boundp '*assistant-origin*)
            (setf *assistant-origin* *codex-origin-buffer*))
          (codex-show-answer (format nil "Codex -- ~A" request) answer))
      (error (condition)
        (codex-show-answer
         "Codex could not be reached"
         (format nil "~A~%~%~A" condition (codex-status-text)))))))

(defun ask-codex ()
  "C-c g: compose a request, or send it when already composing."
  (if (string= (get-buffer-name) *codex-request-buffer*)
      (codex-submit)
      (codex-compose)))

(defun codex-status-text ()
  (let ((program (find-program *codex-program*)))
    (format nil "Codex CLI: ~:[NOT FOUND~;~:*~A~]~%~
                 Model: ~:[CLI default~;~:*~A~]~%~
                 Sandbox: read-only~%Session: ephemeral~%~%~
                 Install on Windows:~%  npm install -g @openai/codex@latest~%~
                 Then authenticate once in a terminal:~%  codex login"
            (and program (native program)) *codex-model*)))

(defun codex-status ()
  "Show Codex setup in the lower window."
  (let ((origin (get-buffer-name)))
    (delete-other-windows)
    (split-window)
    (other-window)
    (codex-show-answer "Codex status" (codex-status-text))
    (other-window)
    (select-buffer origin))
  t)

;; Remove the old stub binding when this script is reloaded in a running editor.
(global-unset-key "C-c x")
(global-set-key "C-c g" 'ask-codex)
