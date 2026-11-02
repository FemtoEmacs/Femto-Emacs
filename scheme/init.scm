;;;; init.scm -- loading the Scheme scripts at start-up
;;;;
;;;; The C core owns the screen and the command loop; everything else is a
;;;; script in this folder, loaded in this order:
;;;;
;;;;   core.scm            keys, commands, events from C, the kill ring
;;;;   api.scm             the editor as scripts see it (point, insert ...)
;;;;   highlight.scm       the tokenizer and DEFINE-LANGUAGE
;;;;   indent.scm          automatic indentation and DEFINE-INDENTATION
;;;;   theme.scm           the colour theme
;;;;   undo.scm            undo and redo
;;;;   gui.scm             font and options for the window
;;;;   languages/*.scm     one file per language
;;;;   defaults.scm        commands and key bindings from FemtoEmacs's init.lsp
;;;;   extensions/*.scm    menus, help, shell, dired, grep, assistants ...
;;;;
;;;; followed by your own ~/.chezemax/languages/*.scm and
;;;; ~/.chezemax/extensions/*.scm, then ~/.chezemax/init.scm.  Edit any of
;;;; them and press C-x C-r (reload-scripts): no rebuild.  A script that
;;;; fails to load is reported on the message line; the others still load.

(define *scheme-dir* (string-append *install-dir* "/scheme"))

;; (defvar name value): define NAME only the first time, so that C-x C-r
;; keeps state (the kill ring, undo histories, key bindings) as it is.
(define-macro (defvar name value)
  `(if (not (bound? ',name)) (set-top-level-value! ',name ,value)))
(define *script-errors* '())

;; Embedded, the VM's standard streams and line ends are not set up by
;; femtoscheme's own start-up; set them as it would.  (Once the screen is
;; up, commands print into a string instead: CALL-QUIETLY in core.scm.)
(__init_globals)

(define (script-error-text e)
  (let ((e (if (and (pair? e) (eq? (car e) 'load-error) (pair? (cdr e)) (pair? (cddr e))) (caddr e) e)))
    (if (error-object? e) (%exception->string e)
        (let ((p (buffer))) (write e p) (io.tostring! p)))))

(define (load-script path)
  "Load one script; an error is remembered instead of stopping start-up."
  (trycatch (begin (load path) #t)
            (lambda (e)
              (let ((slash (let loop ((i (- (length path) 1)))
                             (cond ((< i 0) #f) ((= (aref path i) 47) i) (else (loop (- i 1)))))))
                (set! *script-errors*
                      (cons (string-append (if slash (string.sub path (+ slash 1) (length path)) path)
                                           ": " (script-error-text e))
                            *script-errors*)))
              #f)))

(define (scheme-files directory)
  "The .scm files of DIRECTORY, sorted; none when it does not exist."
  (trycatch
   (map (lambda (name) (string-append directory "/" name))
        (sort (filter (lambda (name)
                        (let ((n (length name)))
                          (and (> n 4) (string=? (string.sub name (- n 4) n) ".scm")
                               (not (= (aref name 0) 46)))))
                      (directory-files directory))
              string<?))
   (lambda (e) '())))

(define (script-files)
  (append (map (lambda (f) (string-append *scheme-dir* "/" f))
               '("core.scm" "api.scm" "highlight.scm" "indent.scm" "theme.scm"
                 "undo.scm" "gui.scm"))
          (scheme-files (string-append *scheme-dir* "/languages"))
          (list (string-append *scheme-dir* "/defaults.scm"))
          (scheme-files (string-append *scheme-dir* "/extensions"))))

(define (user-script-files)
  (let ((home (string-append (or (os.getenv "HOME") ".") "/.chezemax")))
    (append (scheme-files (string-append home "/languages"))
            (scheme-files (string-append home "/extensions"))
            (let ((init (string-append home "/init.scm")))
              (if (path.exists? init) (list init) '())))))

(define *load-user-scripts* (not (os.getenv "CHEZEMAX_NO_INIT")))

(define (load-scripts)
  "Load every script; the number that failed."
  (set! *script-errors* '())
  (for-each load-script (script-files))
  (when *load-user-scripts* (for-each load-script (user-script-files)))
  (when (and (bound? '*init-errors*))
    (set! *init-errors* *script-errors*))
  (length *script-errors*))

(define (reload-scripts)
  "C-x C-r: load the scripts again (after editing them); no rebuild."
  (let ((failed (load-scripts)))
    (when (bound? 'fe-reapply-colors) (fe-reapply-colors))
    (when (bound? 'message)
      (if (= failed 0)
          (message "Scripts reloaded")
          (message (string-join (reverse *script-errors*) "; "))))
    failed))

(load-scripts)

;; before the screen starts (fe_main)
(when (and (bound? '*undo-mode*) *undo-mode*) (fe-add-mode-global "undo"))
(when (and (string=? (fe-backend) "gui") (bound? 'apply-gui-settings))
  (trycatch (apply-gui-settings) (lambda (e) #f)))
