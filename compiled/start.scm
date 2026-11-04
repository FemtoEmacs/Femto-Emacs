;;;; start.scm -- the compiled program runs the editor
;;;;
;;;; The last file of chezemax.wasm (make; PORT-TO-SCHEMER.md, step 4).  The
;;;; scripts are compiled before it; here the C core's hooks are given to
;;;; them, and what scheme/init.scm did when femtoscheme ran the scripts is
;;;; done: the user's own files (~/.chezemax) are loaded, by EVAL
;;;; (eval.scm).  From now on femtoscheme runs no script: Chezemax starts
;;;; with CHEZEMAX_SCHEME=femtoscheme to have them run as before.

;;; CHEZEMAX_SCHEME=femtoscheme (or legacy): the scripts run there, as
;;; before; this program then takes no hook and loads no file
(define *compiled-scripts*
  (let ((mode (getenv "CHEZEMAX_SCHEME")))
    (or (not mode) (string=? mode "") (string=? mode "compiled"))))

(define (start-hook! n procedure) (when *compiled-scripts* (compiled-hook! n procedure)))

;;; why your own compiled scripts were not used, if they were not
;;; (compiled-program.c)
(define startup-notice (foreign-procedure "startup-notice" () string))

;;; Every event: a key bound in compiled Scheme for the tests first
;;; (compiled-key!, editor.scm), then the scripts' EDITOR-EVENT
(start-hook! hook-event
  (lambda (kind arg)
    ;; A key command might immediately replace the completion message.
    ;; Deliver it at an idle boundary instead, outside prompts.
    (when (and *compile-scripts-log* (string=? kind "idle")) (compile-scripts-check))
    (cond ((string=? kind "init") (start-up) #t)
          (else (or (compiled-editor-event kind arg)
                    (editor-event kind arg))))))

;;; Colours: one face a byte of the text C gives (HOOK-TEXT)
(start-hook! hook-highlight
  (lambda (file buffer start count)
    (let ((colors (make-bytevector count +alpha+)))
      (highlight-buffer-text file (hook-text) colors buffer start)
      colors)))

;;; Each window's mode line
(start-hook! hook-mode-line
  (lambda (name file buffer line flags cols)
    (let ((line-text (mode-line-pieces name file buffer line flags cols)))
      (and (string? line-text) line-text))))

;;; Every change to a text, for undo
(start-hook! hook-change
  (lambda (id kind offset text)
    (record-change id kind offset text)
    #t))

;;; Word wrap: a length below 0 asks whether FILE wraps
(start-hook! hook-wrap
  (lambda (file length cols)
    (markdown-wrap-row file (if (< length 0) #f (hook-text)) cols)))

;;; Evaluation (M-] and --eval): (ok? text output).  TEXT is the value
;;; written, or the error, as "Error: ..." says it.
(define hook-eval 6)
(define (%eval-hook text)
  (let* ((out (open-output-string))
         (r (%bridge-try (lambda () (%with-port (list out) (lambda () (eval-string text)))))))
    (if (car r)
        (list #t (if (eq? (cdr r) (if #f #f)) "" (value->string (cdr r))) (get-output-string out))
        (list #f (%bridge-error-text (cdr r)) (get-output-string out)))))
(start-hook! hook-eval %eval-hook)

;;; ------------------------------------------------------------------
;;; The user's files: ~/.chezemax/languages, extensions, init.scm
;;; ------------------------------------------------------------------

(define (scheme-files directory)
  "The .scm files of DIRECTORY, sorted; none when it does not exist."
  (guard (e (#t '()))
    (map (lambda (name) (string-append directory "/" name))
         (sort (filter (lambda (name)
                         (and (ends-with-p ".scm" name) (> (string-length name) 4)
                              (not (char=? (string-ref name 0) #\.))))
                       (or (directory-files directory) '()))
               string<?))))

(define (user-script-files)
  (append (scheme-files (config-file "languages"))
          (scheme-files (config-file "extensions"))
          (let ((init (config-file "init.scm"))) (if (path.exists? init) (list init) '()))))

(define *load-user-scripts* (not (getenv "CHEZEMAX_NO_INIT")))

(define (load-user-scripts)
  "Load the user's files; the number that failed."
  (let ((before (length *init-errors*)))
    (when *load-user-scripts* (for-each load-script (user-script-files)))
    (- (length *init-errors*) before)))

(defcommand (reload-scripts)
  "C-x C-r: load your own files (~/.chezemax) again, after editing them.
The editor's scripts are compiled: make compiles them again."
  (set! *init-errors* '())
  (let ((failed (load-user-scripts)))
    (fe-reapply-colors)
    (if (= failed 0)
        (message "Your files reloaded (~/.chezemax)")
        (message (string-join (reverse *init-errors*) "; ")))
    failed))

;;; ------------------------------------------------------------------
;;; M-x compile-scripts: the scripts, and your code under ~/.chezemax/users,
;;; compiled again, for the next start
;;; ------------------------------------------------------------------
;;; Schemer compiles the whole program at once: a few minutes.  It runs in
;;; the background (chezemax --compile-scripts LOG, src/compile-scripts.c);
;;; the editor looks for LOG.status at each key and says how it went.

(define *compile-scripts-log* #f)

(define (compile-scripts-check)
  (let ((status (file-contents (string-append *compile-scripts-log* ".status"))))
    (when (string? status)
      (let ((log *compile-scripts-log*))
        (set! *compile-scripts-log* #f)
        (if (string-prefix? "ok" status)
            (message "Scripts compiled: restart Chezemax to use them")
            (begin
              (find-file log)
              (message "The scripts were not compiled: the messages are in " log)))))))

(defcommand (compile-scripts)
  "Compile Chezemax's scripts, and your own code under ~/.chezemax/users,
into ~/.chezemax/chezemax.wasm, in the background (a few minutes).  They
take effect when Chezemax starts again."
  (if *compile-scripts-log*
      (message "The scripts are being compiled already")
      (let ((log (config-file "compile-scripts.log")))
        (guard (e (#t #f)) (delete-file (string-append log ".status")))
        (let ((r (spawn-program (fe-program-path) (list "--compile-scripts" log))))
          (if (eq? r #t)
              (begin (set! *compile-scripts-log* log)
                     (message "Compiling the scripts in the background (a few minutes); keep editing"))
              (message "compile-scripts could not start: " (->string r)))))))

(define (script-installer-default-name)
  (let* ((file (buffer-filename))
         (base (if file (file-name-nondirectory file) "my-script.scm"))
         (dot (string-index-right base #\.)))
    (cond ((or (string=? base "") (char=? (string-ref base 0) #\.)) "my-script.scm")
          ((ends-with-p ".scm" base) base)
          (else (string-append (if dot (substring base 0 dot) base) ".scm")))))

(define (script-installer-name destination)
  "A visible .scm filename directly under ~/.chezemax/users, or #f."
  (let* ((root (config-file "users/")) (path (absolute-path destination)))
    (and (starts-with-p root path)
         (let ((name (substring path (string-length root) (string-length path))))
           (and (> (string-length name) 4) (ends-with-p ".scm" name)
                (not (char=? (string-ref name 0) #\.))
                (not (string-index name #\/)) (not (string-index name #\\)) name)))))

(defcommand (script-installer)
  "Install this buffer, including unsaved edits, in ~/.chezemax/users/.
The source file, buffer filename and modified flag stay as they were.
Then use M-x compile-scripts and restart to load the installed script."
  (let ((destination (fe-file-prompt-default "Install script as: "
                       (config-file (string-append "users/" (script-installer-default-name))))))
    (if (string=? destination "")
        (message "Script installation cancelled")
        (let* ((name (script-installer-name destination))
               (exists (and name (path.exists? (config-file (string-append "users/" name))))))
          (cond ((not name) (message "Choose a visible .scm file directly in ~/.chezemax/users/"))
                ((and exists
                      (not (string-ci=? "y" (trim (prompt (string-append "Replace " name "? (y/n) ") "")))))
                 (message "Script installation cancelled"))
                (else
                 (let ((error (fe-install-script name (if exists 1 0))))
                   (if (string=? error "")
                       (message "Installed " name "; M-x compile-scripts, then restart")
                       (message "Script installation failed: " error)))))))))

;;; After the program has started, before the screen does (fe_main): the
;;; C core sends the event "init" (flcall.c).  Your files are compiled
;;; programs that call this one, which cannot happen while it is still
;;; starting.
(define (start-up)
  (let ((notice (startup-notice)))
    (unless (string=? notice "") (set! *init-errors* (cons notice *init-errors*))))
  (load-user-scripts)
  (when *undo-mode* (fe-add-mode-global "undo"))
  (when (string=? (fe-backend) "gui")
    (guard (e (#t #f)) (apply-gui-settings))))
