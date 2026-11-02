;;;; gui.scm -- settings for the window (chezemax --gui, or Chezemax.app)
;;;;
;;;; Port of SBEmacs's lisp/gui.lisp.  Colours for the window are in
;;;; theme.scm.  In ~/.chezemax/init.scm:
;;;;
;;;;   (set-gui-font "/path/to/MyFont.ttf" 15)   ; any TrueType/OpenType file
;;;;   (set! *gui-font-size* 16)                 ; keep the font, change size
;;;;   (set! *option-is-meta* #f)                ; Mac: Option types accents
;;;;   (set! *gui-theme* 'light)                 ; or 'dark (theme.scm)
;;;;
;;;; In the window: Ctrl-+ / Ctrl-- (Cmd-+ / Cmd-- on a Mac) change the font
;;;; size, the mouse moves the cursor and scrolls, and every kill or copy
;;;; also goes to the system clipboard.  With no font set, the window tries
;;;; the usual monospace fonts of the system (src/gui.c).

(defvar *gui-font* #f)          ; path of a font file, or #f: the system's
(defvar *gui-font-size* 14)     ; points
(defvar *option-is-meta* #t)    ; Alt (Option) works as Meta

(define (set-gui-font path (size #f))
  "Use the font file PATH (and SIZE in points) in the window."
  (set! *gui-font* path)
  (when size (set! *gui-font-size* size))
  (when (string=? (fe-backend) "gui")
    (fe-gui-set-font (if path (absolute-path path) "") *gui-font-size*))
  path)

(define (apply-gui-settings)
  "Run at start-up in the window, before it opens."
  (fe-gui-set-font (if *gui-font* (absolute-path *gui-font*) "") *gui-font-size*)
  (fe-gui-set-option "option-is-meta" (if *option-is-meta* 1 0)))

(define (set-gui-colors foreground background cursor)
  "The window's default text, background and cursor colours."
  (let ((c (lambda (x) (if x (color-number x) -1))))
    (fe-gui-set-colors (c foreground) (c background) (c cursor))))
