;;;; shell.lisp -- M-!: run a command of the operating system
;;;;
;;;; A script: edit and press C-x C-r, no rebuild.
;;;;
;;;; M-! (or C-x @) opens a window below the file, *shell-command*, where
;;;; the command is written: one line, or several (Enter breaks the line).
;;;; C-c s runs it; *output* then shows the command, as the shell got it,
;;;; and below it what the command printed, with its exit status when it
;;;; failed.  C-x 1 closes the window; M-! again writes another command.
;;;;
;;;; A command of several lines is one command: the line breaks are
;;;; continuations.  The shell of Linux and macOS (sh) continues a line
;;;; that ends in \, so each break becomes " \" and a break; cmd.exe, on
;;;; Windows, joins the lines (what its ^ continuation does), so each break
;;;; becomes a space.
;;;;
;;;; The command runs in the folder of the file it was called from, reads
;;;; nothing (its input is empty, so it cannot wait for the keyboard), and
;;;; on Windows its console window is hidden: no flicker.

(in-package #:sbemacs)

(declaim (optimize (safety 3) (debug 2)))

(defparameter *shell-command-buffer* "*shell-command*")
(defparameter *shell-output-buffer* "*output*")

(defvar *shell-directory* nil
  "The folder the command runs in: that of the file M-! was pressed in.")

(defvar *shell-origin* nil
  "The buffer M-! was pressed in: it stays in the window above.")

(declaim (ftype (function (string) (values string &optional)) shell-command-line))
(defun shell-command-line (text)
  "TEXT, written on one or more lines, as the shell gets it: one command
whose line breaks are continuations (see the top of this file)."
  (let ((lines (remove "" (mapcar (lambda (l) (string-right-trim '(#\Space #\Tab #\Return) l))
                                  (split-lines text))
                       :test #'string=)))
    #-win32
    (with-output-to-string (out)
      (loop for (line . more) on lines
            do (write-string line out)
               (when more
                 ;; a line that already ends in \ is continued as it is
                 (unless (and (plusp (length line))
                              (char= (char line (1- (length line))) #\\))
                   (write-string " \\" out))
                 (terpri out))))
    #+win32
    (format nil "~{~A~^ ~}" lines)))

(declaim (ftype (function (string (or null pathname string))
                          (values string (or null integer) &optional))
                run-shell))
(defun run-shell (command directory)
  "Run COMMAND with the system's shell in DIRECTORY; what it printed (its
errors too) and its exit status."
  (let ((out (make-string-output-stream))
        (dir (and directory (probe-file directory) (native directory))))
    (let ((process
            #-win32
            (sb-ext:run-program "/bin/sh" (list "-c" command)
                                :directory dir :input nil
                                :output out :error :output :wait t
                                :external-format '(:utf-8 :replacement #\?))
            #+win32
            ;; /s /c "...": cmd.exe drops the outer quotes and runs the rest
            ;; as written; :window :hide keeps its console window hidden
            (sb-ext:run-program (or (ignore-errors (native (find-program "cmd")))
                                    "C:\\Windows\\System32\\cmd.exe")
                                (list "/d" "/s" "/c" (format nil "\"~A\"" command))
                                :escape-arguments nil :window :hide
                                :directory dir :input nil
                                :output out :error :output :wait t
                                :external-format '(:utf-8 :replacement #\?))))
      (values (get-output-stream-string out)
              (sb-ext:process-exit-code process)))))

(defcommand shell-command-window ()
  "M-!: a window below, to write a shell command (Enter: more lines);
C-c s runs it."
  (let ((origin (get-buffer-name)))
    (unless (member origin (list *shell-command-buffer* *shell-output-buffer*)
                    :test #'string=)
      (setf *shell-origin* origin)
      (setf *shell-directory*
            (let ((file (buffer-filename)))
              (if file
                  (make-pathname :name nil :type nil
                                 :defaults (merge-pathnames file))
                  *default-pathname-defaults*))))
    (delete-other-windows)
    ;; pressed again in *output*: the file goes back above
    (when (and *shell-origin*
               (member (get-buffer-name) (list *shell-command-buffer* *shell-output-buffer*)
                       :test #'string=))
      (select-buffer *shell-origin*))
    (split-window)
    (other-window)
    (select-buffer *shell-command-buffer*)
    (goto-char 0)
    (delete-char (buffer-size))
    (message "Write the command (Enter for another line); C-c s runs it; C-x 1 closes"))
  t)

(declaim (ftype (function (string string (or null integer)) (values string &optional))
                shell-transcript))
(defun shell-transcript (command output code)
  "What *output* shows: the command, as the shell got it, then OUTPUT."
  (with-output-to-string (s)
    (loop for line in (split-lines command)
          for first = t then nil
          do (write-string (if first #-win32 "$ " #+win32 "> " "  ") s)
             (write-line line s))
    (write-string output s)
    (unless (or (zerop (length output))
                (char= (char output (1- (length output))) #\Newline))
      (terpri s))
    (when (and code (/= code 0))
      (format s "[exit status ~D]~%" code))))

(defcommand shell-command-run ()
  "C-c s: run the command written in the window M-! opened."
  (if (string/= (get-buffer-name) *shell-command-buffer*)
      (message "M-! opens a window for a command; C-c s there runs it")
      (let* ((text (string-trim '(#\Space #\Tab #\Newline #\Return)
                                (buffer-substring 0 (buffer-size))))
             (command (shell-command-line text)))
        (if (zerop (length command))
            (message "Write a command first; C-c s runs it")
            (progn
              (message "Running: ~A" (first (split-lines command)))
              (update-display)
              (multiple-value-bind (output code)
                  (handler-case (run-shell command *shell-directory*)
                    (error (e) (values (format nil "~A~%" e) nil)))
                (select-buffer *shell-output-buffer*)
                (goto-char 0)
                (delete-char (buffer-size))
                (insert (shell-transcript command output code))
                (goto-char 0)
                (message "~:[Done~;~:*The command failed (exit status ~D)~]; M-! another command, C-x 1 closes"
                         (and code (/= code 0) code)))))))
  t)

(declaim (ftype (function (string) (values (eql t) &optional)) shell-command-to-output))
(defun shell-command-to-output (command)
  "For scripts (SHELL-COMMAND): run COMMAND in the current folder and show
*output* in this window, with the command first."
  (multiple-value-bind (output code)
      (handler-case (run-shell command *default-pathname-defaults*)
        (error (e) (values (format nil "~A~%" e) nil)))
    (select-buffer *shell-output-buffer*)
    (goto-char 0)
    (delete-char (buffer-size))
    (insert (shell-transcript command output code))
    (goto-char 0))
  t)

(set-buffer-hint *shell-command-buffer* "C-c s run; C-x 1 close")
(set-buffer-hint *shell-output-buffer* "M-! another; C-x 1 close")

(global-set-key "M-!" 'shell-command-window)
(global-set-key "C-x @" 'shell-command-window)
(global-set-key "C-c s" 'shell-command-run)
