;;;; shell.scm -- M-!: run a command of the operating system
;;;;
;;;; Port of SBEmacs's lisp/extensions/shell.lisp.
;;;;
;;;; M-! (or C-x @) opens a window below the file, *shell-command*, where the
;;;; command is written: one line, or several (Enter breaks the line).  C-c s
;;;; runs it; *output* then shows the command, as the shell got it, and
;;;; below it what the command printed, with its exit status when it
;;;; failed.  C-c q (or [CLOSE], or C-x 1 there) closes the window and
;;;; goes back to the file, with the other windows as they were; M-! again
;;;; writes another command.
;;;;
;;;; A command of several lines is one command: each line break becomes
;;;; " \" and a break, the shell's continuation.  The command runs in the
;;;; folder of the file it was called from and reads nothing (its input is
;;;; empty, so it cannot wait for the keyboard).

(define *shell-command-buffer* "*shell-command*")
(define *shell-output-buffer* "*output*")
(define *shell-timeout* 600)

(defvar *shell-directory* #f)
(defvar *shell-origin* #f)

(define (shell-command-line text)
  "TEXT, written on one or more lines, as the shell gets it: one command
whose line breaks are continuations."
  (let ((lines (filter (lambda (l) (not (string=? l "")))
                       (map (lambda (l) (string-trim-right (trim-bytes-right l " \t\r"))) (split-lines text)))))
    (let loop ((ls lines) (acc ""))
      (cond ((null? ls) acc)
            ((null? (cdr ls)) (string-append acc (car ls)))
            (else
             (let ((line (car ls)))
               (loop (cdr ls)
                     (string-append acc line
                                    ;; a line that already ends in \ is continued as it is
                                    (if (and (> (length line) 0) (= (aref line (- (length line) 1)) 92)) "" " \\")
                                    "\n"))))))))

(define (run-shell command directory)
  "Run COMMAND with /bin/sh in DIRECTORY: two values, what it printed (its
errors too) and its exit status (#f when it could not run)."
  (let* ((r (run-program "/bin/sh" (list "-c" (string-append "exec 2>&1\n" command)) "" *shell-timeout*
                         (and directory (directory-p directory) directory)))
         (out (remove-byte (car r) 13))
         (code (caddr r)))
    (if (< code 0)
        (values (string-append out (cadr r) "\n") #f)
        (values out code))))

(defcommand (shell-command-window)
  "M-!: a window below, to write a shell command (Enter: more lines);
C-c s runs it."
  (let ((origin (get-buffer-name)))
    (unless (member origin (list *shell-command-buffer* *shell-output-buffer*))
      (set! *shell-origin* origin)
      (set! *shell-directory*
            (let ((file (buffer-filename)))
              (if file (let ((d (file-name-directory (absolute-path file)))) (if (string=? d "") (path.cwd) d))
                  (path.cwd)))))
    ;; the shell's window, if it has one already (M-! again in *output*);
    ;; otherwise a new one below the file: the other windows stay
    (unless (or (shell-buffer-p (get-buffer-name))
                (select-window-showing *shell-command-buffer*)
                (select-window-showing *shell-output-buffer*))
      (open-window-below *shell-command-buffer*))
    (select-buffer *shell-command-buffer*)
    (erase-buffer)
    (message "Write the command (Enter for another line); [SEND] or C-c s runs it"))
  #t)

(define (shell-transcript command output code)
  "What *output* shows: the command, as the shell got it, then OUTPUT."
  (string-append
   (let loop ((ls (split-lines command)) (first #t) (acc ""))
     (if (null? ls) acc
         (loop (cdr ls) #f (string-append acc (if first "$ " "  ") (car ls) "\n"))))
   output
   (if (or (= (length output) 0) (= (aref output (- (length output) 1)) 10)) "" "\n")
   (if (and code (not (= code 0))) (concat "[exit status " code "]\n") "")))

(define (show-shell-output command output code)
  (select-buffer *shell-output-buffer*)
  (erase-buffer)
  (insert (shell-transcript command output code))
  (fe-set-modified 0)
  (goto-char 0))

(defcommand (shell-command-run)
  "C-c s: run the command written in the window M-! opened."
  (if (not (string=? (get-buffer-name) *shell-command-buffer*))
      (message "M-! opens a window for a command; C-c s there runs it")
      (let* ((text (trim (buffer-substring 0 (buffer-size))))
             (command (shell-command-line text)))
        (if (= (length command) 0)
            (message "Write a command first; C-c s runs it")
            (begin
              (message "Running: " (car (split-lines command)))
              (update-display)
              (let-values (((output code) (guard (e (#t (values (concat (describe-error e) "\n") #f)))
                                            (run-shell command *shell-directory*))))
                (fe-set-modified 0)
                (show-shell-output command output code)
                (if (and code (not (= code 0)))
                    (message "The command failed (exit status " code ")")
                    (message "Done")))))))
  #t)

(define (shell-command command)
  "For scripts: run COMMAND in the current folder and show *output* in this
window, with the command first."
  (let-values (((output code) (guard (e (#t (values (concat (describe-error e) "\n") #f)))
                                (run-shell command (path.cwd)))))
    (show-shell-output command output code))
  #t)

;;; Closing: C-c q (close-tool-window, menu.scm) or [CLOSE].  In these
;;; windows C-x 1 would keep the shell and close the file, so here it closes
;;; the shell too.  Elsewhere C-x 1 is what it always was.

(define (shell-buffer-p name) (and (member name (list *shell-command-buffer* *shell-output-buffer*)) #t))

(defcommand (shell-close)
  "C-c q or [CLOSE]: close the shell's windows and go back to the file it
was called from; the other windows are as they were before M-!."
  (let loop ((k 0))
    (when (and (< k (* 2 (window-count))) (> (window-count) 1))
      (if (shell-buffer-p (get-buffer-name)) (delete-window) (other-window))
      (loop (+ k 1))))
  (when (shell-buffer-p (get-buffer-name))
    (select-buffer (or *shell-origin* "*scratch*")))
  (when *shell-origin* (select-window-showing *shell-origin*))
  (clear-message-line)
  #t)

(defcommand (one-window)
  "C-x 1: keep only this window -- but in the shell windows, close them."
  (if (shell-buffer-p (get-buffer-name))
      (shell-close)
      (execute-builtin "delete-other-windows"))
  #t)

;;; The windows' own buttons (menu.scm), clicked or typed alike
(set-buffer-menu *shell-command-buffer* '(("SEND - C-c s" "C-c s") ("CLOSE - C-c q" "C-c q")))
(set-buffer-menu *shell-output-buffer* '(("NEW - M-!" "M-!") ("CLOSE - C-c q" "C-c q")))
(set-buffer-hint *shell-command-buffer* "")
(set-buffer-hint *shell-output-buffer* "")

(global-set-key "C-x 1" 'one-window)
(global-set-key "M-!" 'shell-command-window)
(global-set-key "C-x @" 'shell-command-window)
(global-set-key "C-c s" 'shell-command-run)

;;; Shell completion never evaluates the text being completed.
(define (shell-completion-context line)
  "(prefix decoded-token completed-words), respecting quotes and escapes."
  (let loop ((i 0) (start 0) (token "") (words '()) (quoting #f) (escaped #f))
    (if (= i (length line)) (list (byte-substring line 0 start) token (reverse words))
        (let ((b (aref line i)) (ch (byte-substring line i (+ i 1))))
          (cond (escaped (loop (+ i 1) start (concat token ch) words quoting #f))
                ((and (= b 92) (not (eqv? quoting 39))) (loop (+ i 1) start token words quoting #t))
                (quoting (loop (+ i 1) start (if (= b quoting) token (concat token ch)) words (if (= b quoting) #f quoting) #f))
                ((memv b '(34 39)) (loop (+ i 1) start token words b #f))
                ((memv b '(59 124 38)) (loop (+ i 1) (+ i 1) "" '() #f #f))
                ((memv b '(32 9 10)) (loop (+ i 1) (+ i 1) "" (if (string=? token "") words (cons token words)) #f #f))
                (else (loop (+ i 1) start (concat token ch) words #f #f)))))))

(define (shell-escape-token token)
  (let loop ((i 0) (out ""))
    (if (= i (length token)) out
        (let ((b (aref token i)))
          (loop (+ i 1) (concat out (if (memv b '(32 9 34 39 92 36 96 59 38 124 60 62 40 41 42 63 91 93 123 125 33 35)) "\\" "")
                               (byte-substring token i (+ i 1))))))))

(define (shell-working-directory)
  (or *shell-directory* (path.cwd)))

(define (shell-command-completions line)
  (if (and (bound? 'web-request) (bound? 'in-browser?) (in-browser?))
      (begin (web-request "command-context" (shell-working-directory))
             (filter (lambda (s) (not (string=? s ""))) (split-lines (web-request "command-complete" line))))
      (let* ((context (shell-completion-context line)) (prefix (car context))
             (token (cadr context)) (words (caddr context))
             (command-position (null? words))
             (paths (file-name-completions token (shell-working-directory)))
             (paths (if (and (pair? words) (string=? (car words) "cd"))
                        (filter (lambda (p) (ends-with-p "/" p)) paths) paths))
             (commands (if (and command-position (not (string-search "/" token)))
                           (append '("cd" "pwd" "exit" "export")
                             (apply append (map (lambda (folder)
                               (let ((folder (if (string=? folder "") (shell-working-directory) folder)))
                                 (filter (lambda (name) (and (starts-with-p token name) (file-executable? (concat folder "/" name))
                                                            (not (directory-p (concat folder "/" name)))))
                                         (guard (e (#t '())) (directory-files folder)))))
                               (string-split (or (os.getenv "PATH") "") ":")))) '()))
             (names (sort (delete-duplicates (append paths (filter (lambda (c) (starts-with-p token c)) commands))) string<?)))
        (map (lambda (name) (concat prefix (shell-escape-token name)))
             (filter (lambda (name) (not (string-search "\n" name))) names)))))

(define (shell-common-prefix names)
  (if (null? names) ""
      (let* ((first (car names)) (limit (apply min (map string-length names))))
        (let loop ((i 0))
          (if (and (< i limit) (every (lambda (s) (char=? (string-ref first i) (string-ref s i))) (cdr names)))
              (loop (+ i 1)) (substring first 0 i))))))

(defvar *shell-tab-last* #f)
(defvar *shell-tab-options* '())
(defvar *shell-tab-index* 0)
(define (shell-complete-input key)
  (and (string=? (get-buffer-name) *shell-command-buffer*)
       (if (not (string=? key "\t")) (begin (set! *shell-tab-last* #f) #f)
           (let* ((end (point)) (before (buffer-substring 0 end))
                  (again (and *shell-tab-last* (equal? *shell-tab-last* (list before end))))
                  (options (if again *shell-tab-options* (shell-command-completions before)))
                  (common (shell-common-prefix options))
                  (answer (cond ((null? options) #f)
                                ((or (= (length options) 1) (> (string-length common) (string-length before))) common)
                                (else (list-ref options (modulo (if again *shell-tab-index* 0) (length options)))))))
             (set! *shell-tab-options* options)
             (set! *shell-tab-index* (if again (+ *shell-tab-index* 1) 1))
             (if answer
                 (begin (replace-region 0 end answer)
                        ;; A completed directory is a fresh query on the next TAB.
                        (set! *shell-tab-last* (if (or (= (length options) 1) (> (string-length common) (string-length before))) #f (list answer (point)))))
                 (begin (set! *shell-tab-last* #f) (message "No command or path matches")))
             #t))))

;; Before indentation's TAB hook; C-q TAB still inserts a literal tab.
(set! *self-insert-hook* (cons 'shell-complete-input (filter (lambda (h) (not (eq? h 'shell-complete-input))) *self-insert-hook*)))

(defcommand (minibuffer-command)
  "C-c m: shell command in the minibuffer, with TAB completion."
  (let ((origin (get-buffer-name)))
    (unless (shell-buffer-p origin)
      (set! *shell-origin* origin)
      (unless *shell-directory*
        (set! *shell-directory* (let ((file (buffer-filename)))
                                 (if file (file-name-directory (absolute-path file)) (path.cwd))))))
    (let ((command (command-prompt)))
      (when (and command (not (string=? (trim command) "")))
        (let-values (((output code) (run-shell command (shell-working-directory))))
          (show-shell-output command output code))))))
(global-set-key "C-c m" 'minibuffer-command)
