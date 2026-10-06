;;;; ffi.lisp -- the editor API, a thin layer over the C core (src/interface.c)
;;;;
;;;; Every function here replaces one of the femtolisp builtins that used to
;;;; be registered in femtolisp/interface2editor.c.  The names are unchanged
;;;; where possible, so old extensions translate almost word for word.

(in-package #:sbemacs)

;;; ------------------------------------------------------------------
;;; Finding and loading libsbemacs
;;; ------------------------------------------------------------------

(defparameter *library-extension*
  #+darwin "dylib" #+win32 "dll" #-(or darwin win32) "so")

(defun library-name (backend)
  "libsbemacs-term or libsbemacs-gui, with this system's extension."
  (format nil "libsbemacs-~A.~A" (if (eq backend :gui) "gui" "term") *library-extension*))

(defvar *library-path* nil
  "Where the editor library was loaded from.")

(defvar *backend* nil
  "The library in use: :TERMINAL or :GUI.")

(defvar *source-directory*
  (let ((here (or *compile-file-truename* *load-truename*)))
    (when here
      (merge-pathnames "../" (make-pathname :name nil :type nil :defaults here))))
  "The lisp/ directory's parent when the sources were compiled.")

(defun library-candidates (backend)
  (let ((name (library-name backend))
        (env (sb-ext:posix-getenv (if (eq backend :gui) "SBEMACS_GUI_LIB" "SBEMACS_LIB")))
        (exe (ignore-errors (truename sb-ext:*runtime-pathname*))))
    (remove nil
            (list (and env (plusp (length env)) (pathname env))
                  (and exe (merge-pathnames name exe))
                  (and exe (merge-pathnames (concatenate 'string "../lib/sbemacs/" name) exe))
                  (and *source-directory* (merge-pathnames name *source-directory*))
                  (merge-pathnames name)))))

(defun load-core-library (&optional (backend :terminal))
  "Load the editor library for BACKEND (:TERMINAL or :GUI).  Both export
the same functions, so everything else is the same.  The library is not
saved in the image, so that the executable and the libraries can be
moved together."
  (unless *library-path*
    (let ((path (find-if #'probe-file (library-candidates backend))))
      (unless path
        (error "Cannot find ~A. Looked in:~%~{  ~A~%~}Set ~A to its full path."
               (library-name backend) (mapcar #'namestring (library-candidates backend))
               (if (eq backend :gui) "SBEMACS_GUI_LIB" "SBEMACS_LIB")))
      (sb-alien:load-shared-object (native (truename path)) :dont-save t)
      (setf *library-path* (truename path)
            *backend* backend)))
  *library-path*)

(defun unload-core-library ()
  (when *library-path*
    (sb-alien:unload-shared-object (native *library-path*))
    (setf *library-path* nil *backend* nil)))

(defun native (pathname)
  (sb-ext:native-namestring pathname))

;;; ------------------------------------------------------------------
;;; Raw foreign routines.  %name = fe_name in src/interface.c
;;; ------------------------------------------------------------------

(defmacro defcore (lisp-name c-name result &rest args)
  `(sb-alien:define-alien-routine (,c-name ,lisp-name) ,result ,@args))

(defcore %backward-char "fe_backward_char" sb-alien:void (n sb-alien:int))
(defcore %forward-char "fe_forward_char" sb-alien:void (n sb-alien:int))
(defcore %backward-word "fe_backward_word" sb-alien:void (n sb-alien:int))
(defcore %forward-word "fe_forward_word" sb-alien:void (n sb-alien:int))
(defcore %backward-page "fe_backward_page" sb-alien:void (n sb-alien:int))
(defcore %forward-page "fe_forward_page" sb-alien:void (n sb-alien:int))
(defcore %next-line "fe_next_line" sb-alien:void (n sb-alien:int))
(defcore %previous-line "fe_previous_line" sb-alien:void (n sb-alien:int))
(defcore %beginning-of-line "fe_beginning_of_line" sb-alien:void)
(defcore %end-of-line "fe_end_of_line" sb-alien:void)
(defcore %beginning-of-buffer "fe_beginning_of_buffer" sb-alien:void)
(defcore %end-of-buffer "fe_end_of_buffer" sb-alien:void)
(defcore %goto-line "fe_goto_line" sb-alien:void (n sb-alien:int))
(defcore %get-point "fe_get_point" sb-alien:long)
(defcore %get-mark "fe_get_mark" sb-alien:long)
(defcore %set-point "fe_set_point" sb-alien:void (p sb-alien:long))
(defcore %buffer-size "fe_buffer_size" sb-alien:long)
(defcore %set-mark "fe_set_mark" sb-alien:void)
(defcore %set-mark-at "fe_set_mark_at" sb-alien:void (p sb-alien:long))
(defcore %mark-active "fe_mark_active" sb-alien:int)
(defcore %set-mark-active "fe_set_mark_active" sb-alien:void (on sb-alien:int))
(defcore %char-at "fe_char_at" sb-alien:int (p sb-alien:long))
(defcore %line-start "fe_line_start" sb-alien:long (p sb-alien:long))
(defcore %copy-text "fe_copy_text" sb-alien:long
  (start sb-alien:long) (len sb-alien:long) (out sb-alien:system-area-pointer))

(defcore %insert "fe_insert" sb-alien:void (s sb-alien:c-string))
(defcore %backward-delete-char "fe_backward_delete_char" sb-alien:void (n sb-alien:int))
(defcore %delete-char "fe_delete_char" sb-alien:void (n sb-alien:int))
(defcore %kill-region "fe_kill_region" sb-alien:void)
(defcore %copy-region "fe_copy_region" sb-alien:void)
(defcore %yank "fe_yank" sb-alien:void)
(defcore %kill-line "fe_kill_line" sb-alien:void)
(defcore %undo "fe_undo" sb-alien:void)
(defcore %discard-undo-history "fe_discard_undo_history" sb-alien:void)
(defcore %get-clipboard "fe_get_clipboard" sb-alien:c-string)
(defcore %set-clipboard "fe_set_clipboard" sb-alien:void (s sb-alien:c-string))

(defcore %search-forward "fe_search_forward" sb-alien:int (s sb-alien:c-string))
(defcore %search-backward "fe_search_backward" sb-alien:int (s sb-alien:c-string))

(defcore %buffer-count "fe_buffer_count" sb-alien:int)
(defcore %buffer-name "fe_buffer_name" sb-alien:c-string)
(defcore %buffer-filename "fe_buffer_filename" sb-alien:c-string)
(defcore %buffer-modified "fe_buffer_modified" sb-alien:int)
(defcore %select-buffer "fe_select_buffer" sb-alien:int (s sb-alien:c-string))
(defcore %kill-buffer "fe_kill_buffer" sb-alien:int (s sb-alien:c-string))
(defcore %save-buffer "fe_save_buffer" sb-alien:int (s sb-alien:c-string))
(defcore %find-file "fe_find_file" sb-alien:void (s sb-alien:c-string))
(defcore %list-buffers "fe_list_buffers" sb-alien:void)
(defcore %rename-buffer "fe_rename_buffer" sb-alien:c-string (s sb-alien:c-string))

(defcore %delete-other-windows "fe_delete_other_windows" sb-alien:void)
(defcore %other-window "fe_other_window" sb-alien:void)
(defcore %split-window "fe_split_window" sb-alien:void)
(defcore %update-display "fe_update_display" sb-alien:void)
(defcore %refresh "fe_refresh" sb-alien:void)
(defcore %delete-window "fe_delete_window" sb-alien:void)
(defcore %window-count "fe_window_count" sb-alien:int)
(defcore %window-rows "fe_window_rows" sb-alien:int)
(defcore %recenter "fe_recenter" sb-alien:void)
(defcore %line-number "fe_line_number" sb-alien:int (p sb-alien:long))
(defcore %execute-command "fe_execute_command" sb-alien:int (name sb-alien:c-string))
(defcore %command-name "fe_command_name" sb-alien:c-string (i sb-alien:int))
(defcore %add-command-name "fe_add_command_name" sb-alien:void (name sb-alien:c-string))
(defcore %set-window-start "fe_set_window_start" sb-alien:void (p sb-alien:long))
(defcore %set-buffer-hint "fe_set_buffer_hint" sb-alien:void
  (name sb-alien:c-string) (hint sb-alien:c-string))
(defcore %set-modeline-hints "fe_set_modeline_hints" sb-alien:void
  (help sb-alien:c-string) (tail sb-alien:c-string))

(defcore %message "fe_message" sb-alien:void (s sb-alien:c-string))
(defcore %clear-message-line "fe_clear_message_line" sb-alien:void)
(defcore %log-debug "fe_log_debug" sb-alien:void (s sb-alien:c-string))
(defcore %log-message "fe_log_message" sb-alien:void (s sb-alien:c-string))

(defcore %get-key "fe_get_key" sb-alien:c-string)
(defcore %get-key-name "fe_get_key_name" sb-alien:c-string)
(defcore %get-key-binding "fe_get_key_binding" sb-alien:c-string)
(defcore %prompt "fe_prompt" sb-alien:c-string (p sb-alien:c-string) (initial sb-alien:c-string))

(defcore %shell-command "fe_shell_command" sb-alien:void (s sb-alien:c-string))
(defcore %add-mode-global "fe_add_mode_global" sb-alien:int (s sb-alien:c-string))
(defcore %version "fe_version" sb-alien:c-string)
(defcore %quit "fe_quit" sb-alien:void)
(defcore %screen-rows "fe_screen_rows" sb-alien:int)
(defcore %screen-cols "fe_screen_cols" sb-alien:int)
(defcore %set-color "fe_set_color" sb-alien:int
  (id sb-alien:int) (fg sb-alien:long) (bg sb-alien:long) (attr sb-alien:int))
(defcore %set-theme-face "fe_set_theme_face" sb-alien:int
  (id sb-alien:int) (fg sb-alien:long) (bg sb-alien:long) (attr sb-alien:int))
(defcore %reapply-colors "fe_reapply_colors" sb-alien:void)
(defcore %colors "fe_colors" sb-alien:int)

(defcore %set-hooks "fe_set_hooks" sb-alien:void
  (eval sb-alien:system-area-pointer)
  (event sb-alien:system-area-pointer)
  (highlight sb-alien:system-area-pointer))

(defcore %screen-probe "fe_screen_probe" sb-alien:int)
(defcore %backend-name "fe_backend" sb-alien:c-string)
(defcore %gui-set-font "fe_gui_set_font" sb-alien:void (path sb-alien:c-string) (points sb-alien:int))
(defcore %gui-set-colors "fe_gui_set_colors" sb-alien:void
  (fg sb-alien:long) (bg sb-alien:long) (cursor sb-alien:long))

(defcore %gui-set-option "fe_gui_set_option" sb-alien:void
  (name sb-alien:c-string) (value sb-alien:int))

(defcore %fe-main "fe_main" sb-alien:int (argc sb-alien:int) (argv (* sb-alien:c-string)))

;;; ------------------------------------------------------------------
;;; The public API
;;; ------------------------------------------------------------------

(defun count-arg (n)
  (check-type n (integer 0))
  n)

(defun text (x)
  "Anything printable becomes a string, as (insert 42) did in femtolisp."
  (if (stringp x) x (princ-to-string x)))

;; movement -- all take an optional repeat count, default 1
(defun forward-char (&optional (n 1)) (%forward-char (count-arg n)) t)
(defun backward-char (&optional (n 1)) (%backward-char (count-arg n)) t)
(defun forward-word (&optional (n 1)) (%forward-word (count-arg n)) t)
(defun backward-word (&optional (n 1)) (%backward-word (count-arg n)) t)
(defun forward-page (&optional (n 1)) (%forward-page (count-arg n)) t)
(defun backward-page (&optional (n 1)) (%backward-page (count-arg n)) t)
(defun next-line (&optional (n 1)) (%next-line (count-arg n)) t)
(defun previous-line (&optional (n 1)) (%previous-line (count-arg n)) t)
(defun beginning-of-line () (%beginning-of-line) t)
(defun end-of-line () (%end-of-line) t)
(defun beginning-of-buffer () (%beginning-of-buffer) t)
(defun end-of-buffer () (%end-of-buffer) t)
(defun goto-line (n) (%goto-line n) t)

(defun point () "Byte offset of the cursor." (%get-point))
(defun goto-char (p) "Move the cursor to byte offset P." (%set-point p) (%get-point))
(defun mark () "Byte offset of the mark, or NIL when no mark is set."
  (let ((m (%get-mark))) (if (minusp m) nil m)))
(defun set-mark (&optional (position (point)))
  "Set the mark at POSITION (default: the cursor) and activate the region,
which is shaded until the text changes or C-g."
  (%set-mark-at position)
  (%set-mark-active 1)
  t)
(defun push-mark (&optional (position (point)))
  "Set the mark at POSITION without activating the region."
  (%set-mark-at position)
  t)
(defun clear-mark () (%set-mark-at -1) (%set-mark-active 0) t)
(defun region-active-p () (= 1 (%mark-active)))
(defun activate-mark () (when (mark) (%set-mark-active 1)) t)
(defun deactivate-mark () (%set-mark-active 0) t)

(defun buffer-octets (start end)
  "The bytes of the current buffer from START to END, as an octet vector."
  (let* ((start (max 0 start))
         (end (min end (buffer-size)))
         (v (make-array (max 0 (- end start)) :element-type '(unsigned-byte 8))))
    (when (plusp (length v))
      (sb-sys:with-pinned-objects (v)
        (%copy-text start (length v) (sb-sys:vector-sap v))))
    v))

(defun line-start (&optional (p (point)))
  "Byte offset where the (logical) line containing P starts."
  (%line-start p))

(defun line-end (&optional (p (point)))
  "Byte offset of the newline ending the line containing P (or the end of
the buffer)."
  (let ((size (buffer-size)))
    (loop for start = p then end
          for end = (min size (+ start 4096))
          for chunk = (buffer-octets start end)
          for nl = (position 10 chunk)
          when nl return (+ start nl)
          when (>= end size) return size)))

(defun buffer-substring (start end)
  "The text of the current buffer between byte offsets START and END."
  (sb-ext:octets-to-string (buffer-octets start end)
                           :external-format '(:utf-8 :replacement #\?)))
(defun buffer-size () (%buffer-size))
(defun char-after (&optional (p (point)))
  "The character at byte offset P (ASCII view; NIL at end of buffer)."
  (let ((c (%char-at p))) (if (minusp c) nil (code-char c))))

;; editing
(defun insert (&rest things)
  "Insert each of THINGS at point.  Non-strings are printed with PRINC."
  (dolist (x things t)
    (let ((s (text x)))
      (when (plusp (length s)) (%insert s)))))
(defun backward-delete-char (&optional (n 1)) (%backward-delete-char (count-arg n)) t)
(defun backwards-delete-char (&optional (n 1)) (backward-delete-char n))
(defun delete-char (&optional (n 1)) (%delete-char (count-arg n)) t)
(defun kill-region () (%kill-region) t)
(defun copy-region () (%copy-region) t)
(defun yank () (%yank) t)
(defun kill-line () (%kill-line) t)
(defun undo () (%undo) t)
(defun discard-undo-history () (%discard-undo-history) t)
(defun get-clipboard () (or (%get-clipboard) ""))
(defun set-clipboard (s) (%set-clipboard (text s)) s)
(defun cut-region ()
  "Kill the region and return it as a string."
  (kill-region)
  (get-clipboard))

;; searching
(defun search-forward (s) (= 1 (%search-forward (text s))))
(defun search-backward (s) (= 1 (%search-backward (text s))))
(defun search-backwards (s) (search-backward s))

;; buffers
(defun get-buffer-count () (%buffer-count))
(defun get-buffer-name () (%buffer-name))
(defun buffer-filename ()
  (let ((f (%buffer-filename))) (if (or (null f) (string= f "")) nil f)))
(defun buffer-modified-p () (= 1 (%buffer-modified)))
(defun select-buffer (name) (= 1 (%select-buffer (text name))))
(defun kill-buffer (name) (= 1 (%kill-buffer (text name))))
(defun save-buffer (name) (= 1 (%save-buffer (text name))))
(defun find-file (filename) (%find-file (text filename)) t)
(defun list-buffers () (%list-buffers) t)
(defun rename-buffer (name) (%rename-buffer (text name)))

;; windows and display
(defun delete-other-windows () (%delete-other-windows) t)
(defun other-window () (%other-window) t)
(defun split-window () (%split-window) t)
(defun update-display () (%update-display) t)
(defun refresh-screen () (%refresh) t)
(defun delete-window () (%delete-window) t)
(defun window-count () (%window-count))
(defun window-rows () "Text lines in the selected window." (%window-rows))
(defun recenter () (%recenter) t)
(defun set-window-start (p)
  "Show the selected window from offset P, which should start a line."
  (%set-window-start p)
  t)
(defun line-number (&optional (p (point))) "1-based line of offset P." (%line-number p))
(defun set-mode-line-hints (help tail)
  "The two hints on the mode line, e.g. \"Ctrl-h for help\" and
\"Ctrl c r calls Claude; Ctrl c g calls GPT\"."
  (%set-modeline-hints (text help) (text tail))
  t)

(defvar *buffer-hints* (make-hash-table :test 'equal)
  "Buffer name -> its mode line hint; given to the C core at start-up.")

(defun set-buffer-hint (buffer hint)
  "Show HINT at the end of the mode line of BUFFER (a name) instead of the
usual hints; NIL or \"\" goes back to them."
  (let ((name (text buffer)) (hint (if hint (text hint) "")))
    (if (string= hint "")
        (remhash name *buffer-hints*)
        (setf (gethash name *buffer-hints*) hint))
    (when *library-path* (%set-buffer-hint name hint)))
  t)

(defun announce-buffer-hints ()
  "The scripts compiled into the image are not loaded again at start-up:
give their hints to the C core."
  (maphash (lambda (name hint) (%set-buffer-hint name hint)) *buffer-hints*))

(defun execute-builtin (name)
  "Run the C core's command NAME (\"query-replace\", \"exec-lisp-command\"...).
Returns NIL if there is no such command."
  (= 1 (%execute-command (text name))))

(defun builtin-command-names ()
  (loop for i from 0
        for name = (%command-name i)
        while name collect name))
(defun screen-rows () (%screen-rows))
(defun screen-columns () (%screen-cols))

;; message line and logging
(defun message (control &rest args)
  "Show a message.  With ARGS, CONTROL is a FORMAT string."
  (%message (if args (apply #'format nil control args) (text control)))
  t)
(defun clear-message-line () (%clear-message-line) t)
(defun log-debug (s) (%log-debug (text s)) t)
(defun log-message (s) (%log-message (text s)) t)

;; keyboard
(defun get-key ()
  "Wait for a key.  Returns the typed string, or \"\" for a bound key, in
which case GET-KEY-NAME and GET-KEY-BINDING describe it."
  (or (%get-key) ""))
(defun get-key-name () (or (%get-key-name) ""))
(defun get-key-binding () (or (%get-key-binding) ""))
(defun prompt (question &optional (initial ""))
  (or (%prompt (text question) (text initial)) ""))

;; misc
(defun shell-command (command) (%shell-command (text command)) t)
(defun add-mode-global (mode) (= 1 (%add-mode-global (text mode))))
(defun get-version-string () (%version))
(defun quit-editor () (%quit) t)
(defun trim (s) (string-trim '(#\Space #\Tab #\Newline #\Return) s))

(defun home (&optional (file ""))
  "A file in the user's home directory, as a string."
  (native (merge-pathnames file (user-homedir-pathname))))

(defun config-file (&optional (file ""))
  "A file in ~/.sbemacs/, as a string."
  (native (merge-pathnames file (merge-pathnames ".sbemacs/" (user-homedir-pathname)))))

;;; colours

(defparameter *color-ids*
  '((:symbol . 1) (:modeline . 2) (:brace . 3) (:keyword . 4) (:alpha . 5)
    (:digits . 6) (:comment . 7) (:block-comment . 8) (:string . 9)
    (:region . 10)))

;; the eight basic colours; :default is the terminal's own colour, and
;; an integer 0-255 picks from the 256-colour palette
(defparameter *curses-colors*
  '((:default . -1) (:black . 0) (:red . 1) (:green . 2) (:yellow . 3)
    (:blue . 4) (:magenta . 5) (:cyan . 6) (:white . 7)))

(defparameter *face-attributes*
  '((:bold . 1) (:underline . 2) (:reverse . 4) (:dim . 8) (:italic . 16)))

(defun color-id (face)
  (or (cdr (assoc face *color-ids*))
      (error "Unknown face ~S; expected one of ~{~S~^ ~}" face (mapcar #'car *color-ids*))))

(defconstant +rgb-flag+ #x1000000
  "Marks a 24-bit colour (SCR_RGB_FLAG in src/screen.h).")

(defun color-number (x)
  "A colour for the C side: -1 (default), 0-255, or a 24-bit \"#rrggbb\"."
  (cond ((cdr (assoc x *curses-colors*)))
        ((and (integerp x) (<= -1 x 255)) x)
        ((and (stringp x) (= (length x) 7) (char= (char x 0) #\#)
              (every (lambda (c) (digit-char-p c 16)) (subseq x 1)))
         (logior +rgb-flag+ (parse-integer x :start 1 :radix 16)))
        (t (error "Unknown colour ~S; use ~{~S~^ ~}, 0-255 or \"#rrggbb\""
                  x (mapcar #'car *curses-colors*)))))

(defun attribute-bits (attributes)
  (loop for a in attributes
        sum (or (cdr (assoc a *face-attributes*))
                (error "Unknown attribute ~S; use ~{~S~^ ~}" a (mapcar #'car *face-attributes*)))))

(defun set-color (face foreground &optional (background :default) &rest attributes)
  "Change how FACE is drawn; this overrides the colour theme.

  (set-color :keyword :red)
  (set-color :comment 244)                    ; grey, from the 256-colour palette
  (set-color :string :green :default :bold)   ; attributes: :bold :underline
                                              ; :reverse :dim :italic

Faces: :keyword :comment :block-comment :string :digits :alpha (identifiers)
:symbol (everything else) :brace (matching paren) :modeline :region
(the selected text)."
  (= 1 (%set-color (color-id face) (color-number foreground) (color-number background)
                   (attribute-bits attributes))))

(defun theme-face (face foreground &optional (background :default) &rest attributes)
  "Like SET-COLOR, for use inside a colour theme (see lisp/theme.lisp)."
  (= 1 (%set-theme-face (color-id face) (color-number foreground) (color-number background)
                        (attribute-bits attributes))))

(defun terminal-colors ()
  "How many colours the terminal has (0 before the screen is up)."
  (%colors))
