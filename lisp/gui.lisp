;;;; gui.lisp -- settings for the window (sbemacs --gui, or sbemacs-gui)
;;;;
;;;; A script: edit and restart (the font is chosen when the window opens).
;;;; Colours for the window are in theme.lisp.  In ~/.sbemacs/init.lisp:
;;;;
;;;;   (set-gui-font "/path/to/MyFont.ttf" 15)   ; any TrueType/OpenType file
;;;;   (setf *gui-font-size* 16)                 ; keep the font, change size
;;;;   (setf *option-is-meta* nil)               ; Mac: Option types accents
;;;;   (setf *gui-theme* :light)                 ; or :dark (theme.lisp)
;;;;
;;;; In the window: Ctrl-+ / Ctrl-- (Cmd-+ / Cmd-- on a Mac) change the
;;;; font size, the mouse moves the cursor and scrolls, Shift-Insert or the
;;;; middle button pastes the system clipboard, and every kill or copy
;;;; also goes to the system clipboard (C-y takes in what other programs
;;;; copied: see ADOPT-SYSTEM-CLIPBOARD in core.lisp).  On a Mac,
;;;; Cmd-C, Cmd-X, Cmd-V, Cmd-Z, Cmd-S and Cmd-Q do what they usually do.

(in-package #:sbemacs)

(defvar *gui-font* nil
  "Path of the font for the window, or NIL to take the first of
*GUI-FONT-CANDIDATES* that exists.")

(defvar *gui-font-size* 14
  "Font size in points.")

(defvar *option-is-meta* t
  "When true, Alt (Option on a Mac) works as Meta: Option-x is Esc x.
Set to NIL to type accented characters with Option instead.")

(defvar *gui-theme* :dark
  "Colours of the window: :dark or :light (see theme.lisp).")

(defun font-directories ()
  (let ((home (user-homedir-pathname)))
    (append
     #+darwin (list #p"/System/Library/Fonts/" #p"/Library/Fonts/"
                    (merge-pathnames "Library/Fonts/" home))
     #+win32 (list (pathname (concatenate 'string (or (sb-ext:posix-getenv "WINDIR") "C:\\Windows")
                                          "\\Fonts\\"))
                   (merge-pathnames "AppData/Local/Microsoft/Windows/Fonts/" home))
     #-(or darwin win32) (list (merge-pathnames ".local/share/fonts/" home)
                               (merge-pathnames ".fonts/" home)
                               #p"/usr/share/fonts/truetype/" #p"/usr/share/fonts/"
                               #p"/usr/local/share/fonts/"))))

(defparameter *gui-font-candidates*
  ;; file names, looked for (recursively, one level) in the font directories
  '("JetBrainsMono-Regular.ttf" "FiraCode-Regular.ttf" "FiraMono-Regular.ttf"
    "CascadiaMono.ttf" "CascadiaCode.ttf" "SourceCodePro-Regular.ttf"
    "IBMPlexMono-Regular.ttf" "Hack-Regular.ttf"
    "SFMono-Regular.otf" "Menlo.ttc" "Monaco.ttf"
    "consola.ttf" "DejaVuSansMono.ttf" "LiberationMono-Regular.ttf"
    "NotoSansMono-Regular.ttf" "UbuntuMono-R.ttf" "cour.ttf")
  "Fonts tried in order when *GUI-FONT* is NIL.")

(defun find-font-file (name)
  (dolist (dir (font-directories))
    (let ((direct (probe-file (merge-pathnames name dir))))
      (when direct (return direct))
      ;; one level of subdirectories (e.g. /usr/share/fonts/truetype/dejavu/)
      (let ((hit (ignore-errors
                  (first (directory (merge-pathnames (make-pathname :directory '(:relative :wild)
                                                                    :name (pathname-name name)
                                                                    :type (pathname-type name))
                                                     dir))))))
        (when hit (return hit))))))

(defun choose-gui-font ()
  (or (and *gui-font* (probe-file *gui-font*))
      (some #'find-font-file *gui-font-candidates*)))

(defun set-gui-font (path &optional size)
  "Use the font file PATH (and SIZE in points) in the window.  Takes effect
at once in a running window, otherwise when it opens."
  (setf *gui-font* path)
  (when size (setf *gui-font-size* size))
  (when (eq *backend* :gui)
    (%gui-set-font (if path (native (merge-pathnames path)) "") *gui-font-size*))
  path)

(defun apply-gui-settings ()
  "Called by MAIN just before the window opens."
  (let ((font (choose-gui-font)))
    (%gui-set-font (if font (native font) "") *gui-font-size*))
  (%gui-set-option "option-is-meta" (if *option-is-meta* 1 0)))

(defun set-gui-colors (&key foreground background cursor)
  "The window's default text and background colours and the cursor colour,
as \"#rrggbb\" strings or palette numbers."
  (flet ((c (x) (if x (color-number x) -1)))
    (%gui-set-colors (c foreground) (c background) (c cursor))))
