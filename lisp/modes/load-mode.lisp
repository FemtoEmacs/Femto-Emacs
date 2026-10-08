;;;; Optional editing modes. Definitions are bundled; activation is explicit.
(in-package #:sbemacs)
(declaim (optimize (safety 3) (debug 2)))
(defvar *editing-mode-directory* nil
  "Absolute directory containing load-mode.lisp and the optional mode files.")
;; Direct source loading can discover its directory here. Cached FASLs live
;; elsewhere; their startup entry point supplies the original source directory.
(when (and *load-truename* (equal (pathname-type *load-truename*) "lisp"))
  (setf *editing-mode-directory*
        (make-pathname :name nil :type nil :defaults *load-truename*)))
(defvar *editing-modes* (make-hash-table :test 'equal))
(defvar *active-editing-modes* nil)
(defvar *mode-menu-providers* nil)
(defvar *mode-base-menu-provider* nil)

(defun editing-mode-name (name)
  (let ((s (string-downcase (string-trim '(#\Space #\Tab) name))))
    (when (ends-with-p "-mode" s) (setf s (subseq s 0 (- (length s) 5))))
    (unless (and (plusp (length s))
                 (every (lambda (c) (or (alpha-char-p c) (digit-char-p c) (find c "-_"))) s))
      (error "Invalid mode name: ~S" name))
    s))

(defun register-editing-mode (name installer)
  "Register definitions without changing the startup language. INSTALLER activates them."
  (setf (gethash (editing-mode-name name) *editing-modes*) installer))

(defun editing-mode-path (name)
  "Find a mode beside the loader, independently of the shell directory.
User modes in ~/.sbemacs/modes/ keep precedence over shipped modes."
  (let ((filename (format nil "~A-mode.lisp" (editing-mode-name name))))
    (or (probe-file (merge-pathnames filename (merge-pathnames ".sbemacs/modes/" (user-homedir-pathname))))
        (and *editing-mode-directory* (probe-file (merge-pathnames filename *editing-mode-directory*)))
        (and *script-directory* (probe-file (merge-pathnames filename (merge-pathnames "modes/" *script-directory*)))))))

(defun mode-menu-buttons (buffer-name)
  (let ((buttons (funcall *mode-base-menu-provider* buffer-name)))
    (dolist (provider *mode-menu-providers* buttons)
      (setf buttons (funcall (cdr provider) buffer-name buttons)))))

(defun install-mode-menu (owner provider)
  "Replace an owner's menu contribution; reloading never stacks copies."
  (unless (eq *mode-line-buttons-function* 'mode-menu-buttons)
    (setf *mode-base-menu-provider* *mode-line-buttons-function*
          *mode-line-buttons-function* 'mode-menu-buttons))
  (setf *mode-menu-providers*
        (append (remove owner *mode-menu-providers* :key #'car :test #'equal)
                (list (cons owner provider)))))

(defun activate-editing-mode (name)
  "Load updated definitions when available, then activate a registered mode.
Registrations currently apply to every file claimed by the language, not just
one buffer. Errors are signalled to callers; no buffer text is changed."
  (let* ((key (editing-mode-name name)) (path (editing-mode-path key)))
    (when path
      (let ((*default-pathname-defaults* (make-pathname :name nil :type nil :defaults path)))
        (load-script path)))
    (let ((installer (gethash key *editing-modes*)))
      (unless installer (error "Unknown mode ~A; available: ~{~A~^, ~}" key
                               (sort (loop for k being the hash-keys of *editing-modes* collect k) #'string<)))
      (funcall installer)
      (pushnew key *active-editing-modes* :test #'equal)
      key)))

(declaim (ftype (function () list) available-editing-mode-names)
         (ftype (function (string list) (values string list &optional)) complete-editing-mode-name))
(defun available-editing-mode-names ()
  "Sorted completion names, including bundled registrations and source files."
  (let ((names (loop for name being the hash-keys of *editing-modes*
                     collect (concatenate 'string name "-mode"))))
    (dolist (directory (remove-duplicates
                       (remove nil (list (merge-pathnames ".sbemacs/modes/" (user-homedir-pathname))
                                         *editing-mode-directory*
                                         (and *script-directory* (merge-pathnames "modes/" *script-directory*))))
                       :test #'equal))
      (dolist (path (directory (merge-pathnames "*-mode.lisp" directory)))
        (let ((name (pathname-name path)))
          (when (and name (not (string-equal name "load-mode"))
                     (ignore-errors (editing-mode-name name)))
            (push (string-downcase name) names)))))
    (sort (remove-duplicates names :test #'equal) #'string<)))

(defun complete-editing-mode-name (typed candidates)
  "Return the common completion and all matching mode names."
  (declare (type string typed) (type list candidates))
  (let* ((prefix (string-downcase typed))
         (matches (remove-if-not (lambda (name) (starts-with-p prefix name)) candidates)))
    (if (null matches)
        (values typed nil)
        (let ((length (length (first matches))))
          (dolist (name (rest matches))
            (setf length (loop for i below (min length (length name))
                               while (char= (char name i) (char (first matches) i)) count t)))
          (values (subseq (first matches) 0 length) matches)))))

;; Existing screen functions, shared by terminal and GUI backends.
;; Keep these bindings local to the mode loader; the editor API is unchanged.
(sb-alien:define-alien-routine ("display_prompt_and_response" %mode-prompt-display) sb-alien:void
  (prompt sb-alien:c-string) (response sb-alien:c-string))
(sb-alien:define-alien-routine ("screen_move" %mode-prompt-move) sb-alien:void
  (row sb-alien:int) (column sb-alien:int))
(sb-alien:define-alien-routine ("screen_refresh" %mode-prompt-refresh) sb-alien:void)

(defun editing-mode-prompt-column (typed columns)
  (max 0 (min (1- columns) (+ (length "Load mode: ") (length typed)))))

(defun display-editing-mode-prompt (typed status)
  "Redraw first, then leave the visible cursor at the mode input position."
  (message "Load mode: ~A~@[  [~A]~]" typed status)
  (update-display)
  (%mode-prompt-display "Load mode: " (format nil "~A~@[  [~A]~]" typed status))
  (%mode-prompt-move (max 0 (1- (screen-rows)))
                     (editing-mode-prompt-column typed (screen-columns)))
  (%mode-prompt-refresh))

(defun read-editing-mode-name ()
  "Mode minibuffer: TAB completes, repeated TAB cycles ambiguous matches."
  (let ((typed "") (candidates (available-editing-mode-names))
        (matches nil) (cycle 0) (last-tab nil) (status nil))
    (loop
      (display-editing-mode-prompt typed status)
      (let* ((key (get-key)) (name (if (equal key "") (get-key-name) ""))
             (char (and (= (length key) 1) (char key 0))))
        (cond
          ((or (member char '(#\Return #\Newline)) (member name '("RET" "return" "C-m" "C-j") :test #'equal))
           (return (and (plusp (length typed)) typed)))
          ((or (eql char #\Tab) (member name '("TAB" "tab" "C-i") :test #'equal))
           (if (and last-tab matches (> (length matches) 1))
               (progn (setf typed (nth cycle matches)) (setf cycle (mod (1+ cycle) (length matches))))
               (multiple-value-bind (completion found) (complete-editing-mode-name typed candidates)
                 (setf typed completion matches found cycle 0)))
           (setf last-tab t status (cond ((null matches) "No matching mode")
                                        ((rest matches) (format nil "~{~A~^, ~}" matches)))))
          ((or (eql char (code-char 7)) (equal name "C-g")) (return nil))
          ((or (member char (list (code-char 8) (code-char 127)))
               (member name '("backspace" "C-h" "DEL") :test #'equal))
           (when (plusp (length typed)) (setf typed (subseq typed 0 (1- (length typed))))))
          ((or (eql char (code-char 21)) (equal name "C-u")) (setf typed ""))
          ((and (plusp (length key))
                (every (lambda (c) (or (alpha-char-p c) (digit-char-p c) (find c "-_"))) key))
           (setf typed (concatenate 'string typed key))))
        (unless (or (eql char #\Tab) (member name '("TAB" "tab" "C-i") :test #'equal))
          (setf last-tab nil matches nil status nil))))))

(defcommand load-mode (&optional name)
  "M-x load-mode: TAB completes a mode name; C-g cancels."
  (handler-case
      (let ((selection (or name (read-editing-mode-name))))
        (if selection
            (let ((key (activate-editing-mode selection)))
              (%reapply-colors)
              (message "Loaded ~A-mode" key))
            (message "Mode loading cancelled")))
    (error (e) (message "Mode not loaded: ~A" e))))

(defcommand reload-mode ()
  "Reload the active modes from their source files, keeping common menus."
  (handler-case
      (if *active-editing-modes*
          (progn
            (dolist (name (copy-list *active-editing-modes*)) (activate-editing-mode name))
            (%reapply-colors)
            (message "Reloaded ~{~A-mode~^, ~}" *active-editing-modes*))
          (message "No optional mode is active; use M-x load-mode"))
    (error (e) (message "Mode reload failed: ~A" e))))

(defcommand python-mode ()
  "Activate the optional Python coloring, indentation and menu."
  (load-mode "python"))

;; During a build these definitions become part of the saved image, so an
;; installed executable can activate Python even without the source directory.
;; Optional modes register an installer; they must not activate at file load.
(let ((path (and *editing-mode-directory* (probe-file (merge-pathnames "python-mode.lisp" *editing-mode-directory*)))))
  (when path
    (let ((*default-pathname-defaults* *editing-mode-directory*)) (load-script path))))
;; Reapply active installers after a forced script reload restores defaults.
(dolist (name *active-editing-modes*)
  (let ((installer (gethash name *editing-modes*)))
    (when installer (funcall installer))))
