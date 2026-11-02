;;;; load-mode.scm -- optional editing modes: definitions are bundled,
;;;; activation is explicit.
;;;;
;;;; In Chez Scheme, compiled by Schemer: the port of scheme/modes/
;;;; load-mode.scm (itself a port of SBEmacs's lisp/modes/load-mode.lisp).
;;;; A mode file NAME-mode.scm registers an installer with
;;;; REGISTER-EDITING-MODE; M-x load-mode (TAB completes, repeated TAB
;;;; cycles, C-g cancels) runs the installer.  The modes shipped with
;;;; Chezemax are compiled into the program (python-mode.scm, nim-mode.scm);
;;;; a mode of your own in ~/.chezemax/modes/ is loaded (EVAL, eval.scm) each
;;;; time it is activated, and takes precedence.  python-mode and nim-mode
;;;; are active from the start (modes.scm).

(defvar *editing-modes* (make-hashtable string-hash string=?))   ; name -> installer
(defvar *active-editing-modes* '())
(defvar *mode-menu-providers* '())         ; (owner . provider)
(defvar *mode-base-menu-provider* #f)

(define (editing-mode-name name)
  (let* ((s (string-downcase (trim name)))
         (s (if (ends-with-p "-mode" s) (substring s 0 (- (string-length s) 5)) s)))
    (unless (and (> (string-length s) 0)
                 (let loop ((i 0))
                   (or (= i (string-length s))
                       (let ((b (char->integer (string-ref s i))))
                         (and (or (and (<= 97 b) (<= b 122)) (and (<= 48 b) (<= b 57)) (= b 45) (= b 95))
                              (loop (+ i 1)))))))
      (error "Invalid mode name" name))
    s))

(define (register-editing-mode name installer)
  "Register definitions without activating them; INSTALLER activates them."
  (hashtable-set! *editing-modes* (editing-mode-name name) installer))

(define (editing-mode-directories)
  (list (config-file "modes") (string-append *install-dir* "/scheme/modes")))

;; only your own modes are loaded from files: the bundled ones are compiled
(define (editing-mode-path name)
  (let ((file (string-append (editing-mode-name name) "-mode.scm")))
    (find path.exists? (list (string-append (config-file "modes") "/" file)))))

(define (mode-menu-buttons buffer-name)
  (let loop ((ps *mode-menu-providers*)
             (buttons ((command-procedure *mode-base-menu-provider*) buffer-name)))
    (if (null? ps) buttons (loop (cdr ps) ((cdar ps) buffer-name buttons)))))

(define (install-mode-menu owner provider)
  "Replace an owner's menu contribution; reloading never stacks copies."
  (unless (eq? *mode-line-buttons-function* 'mode-menu-buttons)
    (set! *mode-base-menu-provider* *mode-line-buttons-function*)
    (set! *mode-line-buttons-function* 'mode-menu-buttons))
  (set! *mode-menu-providers*
        (append (filter (lambda (p) (not (equal? (car p) owner))) *mode-menu-providers*)
                (list (cons owner provider)))))

(define (%editing-mode-names)
  (let-values (((keys values) (hashtable-entries *editing-modes*)))
    (vector->list keys)))

(define (activate-editing-mode name)
  "Load the newest definitions when available, then activate a mode."
  (let* ((key (editing-mode-name name)) (path (editing-mode-path key)))
    (when path (load path))
    (let ((installer (hashtable-ref *editing-modes* key #f)))
      (unless installer
        (error (concat "Unknown mode " key "; available: "
                       (string-join (sort (%editing-mode-names) string<?) ", "))))
      (installer)
      (unless (member key *active-editing-modes*)
        (set! *active-editing-modes* (cons key *active-editing-modes*)))
      key)))

(define (available-editing-mode-names)
  "Sorted completion names: bundled registrations and mode files."
  (let ((names (append (map (lambda (k) (string-append k "-mode")) (%editing-mode-names))
                       (apply append
                              (map (lambda (d)
                                     (filter-map (lambda (f)
                                                   (and (ends-with-p "-mode.scm" f) (not (string=? f "load-mode.scm"))
                                                        (substring f 0 (- (string-length f) 4))))
                                                 (guard (e (#t '())) (or (directory-files d) '()))))
                                   (editing-mode-directories))))))
    (sort (delete-duplicates names) string<?)))

(define (complete-editing-mode-name typed candidates)
  "Two values: the common completion and every matching name."
  (let* ((prefix (string-downcase typed))
         (matches (filter (lambda (name) (starts-with-p prefix name)) candidates)))
    (if (null? matches)
        (values typed '())
        (values (fold (lambda (name common)
                        (let loop ((i 0))
                          (if (and (< i (string-length common)) (< i (string-length name))
                                   (char=? (string-ref common i) (string-ref name i)))
                              (loop (+ i 1))
                              (substring common 0 i))))
                      (car matches) (cdr matches))
                matches))))

(define (read-editing-mode-name)
  "Mode minibuffer: TAB completes, repeated TAB cycles ambiguous matches."
  (let ((candidates (available-editing-mode-names)))
    (let loop ((typed "") (matches '()) (cycle 0) (last-tab #f) (status #f))
      (message "Load mode: " typed (if status (string-append "  [" status "]") ""))
      (update-display)
      (let* ((key (get-key))
             (name (if (string=? key "") (get-key-name) ""))
             (b (and (= (string-length key) 1) (char->integer (string-ref key 0))))
             (tab (or (eqv? b 9) (member name '("TAB" "C-i")))))
        (cond
          ((or (memv b '(10 13)) (member name '("RET" "C-m" "C-j")))
           (and (> (string-length typed) 0) typed))
          (tab
           (if (and last-tab (pair? matches) (pair? (cdr matches)))
               (loop (list-ref matches cycle) matches (modulo (+ cycle 1) (length matches)) #t
                     (string-join matches ", "))
               (let-values (((completion found) (complete-editing-mode-name typed candidates)))
                 (loop completion found 0 #t
                       (cond ((null? found) "No matching mode")
                             ((pair? (cdr found)) (string-join found ", "))
                             (else #f))))))
          ((or (eqv? b 7) (string=? name "C-g")) #f)
          ((or (memv b '(8 127)) (member name '("backspace" "C-h" "DEL")))
           (loop (if (> (string-length typed) 0) (substring typed 0 (- (string-length typed) 1)) typed) '() 0 #f #f))
          ((or (eqv? b 21) (string=? name "C-u")) (loop "" '() 0 #f #f))
          ((and b (or (and (<= 97 b) (<= b 122)) (and (<= 65 b) (<= b 90)) (and (<= 48 b) (<= b 57)) (= b 45) (= b 95)))
           (loop (string-append typed key) '() 0 #f #f))
          (else (loop typed '() 0 #f #f)))))))

(define load-mode
  (case-lambda
    (() (load-mode #f))
    ((name)
     "M-x load-mode: TAB completes a mode name; C-g cancels."
     (guard (e (#t (message "Mode not loaded: " (describe-error e))))
       (let ((selection (or name (read-editing-mode-name))))
         (if selection
             (let ((key (activate-editing-mode selection)))
               (fe-reapply-colors)
               (message "Loaded " key "-mode"))
             (message "Mode loading cancelled")))))))
(register-command 'load-mode)

(defcommand (reload-mode)
  "Reload the active modes from their files."
  (guard (e (#t (message "Mode reload failed: " (describe-error e))))
    (if (pair? *active-editing-modes*)
        (begin (for-each activate-editing-mode *active-editing-modes*)
               (fe-reapply-colors)
               (message "Reloaded " (string-join (map (lambda (m) (string-append m "-mode")) *active-editing-modes*) ", ")))
        (message "No optional mode is active; use M-x load-mode"))))

(defcommand (python-mode) "Activate the Python coloring, indentation and menu." (load-mode "python"))
(defcommand (nim-mode) "Activate the Nim coloring, indentation and menu." (load-mode "nim"))
