;;;; theme.scm -- the colour theme
;;;;
;;;; Port of SBEmacs's lisp/theme.lisp.  The theme is a procedure of the
;;;; number of colours: 8 or 256 in a terminal, 16777216 (24-bit) in the
;;;; window of chezemax --gui.  It runs when the screen starts, before your
;;;; own SET-COLOR calls are applied, so those always win.  To use a theme
;;;; of your own, define a procedure in ~/.chezemax/init.scm and
;;;; (set! *color-theme* 'my-theme).
;;;;
;;;; 'default means the terminal's own colour, which keeps the terminal's
;;;; cursor visible on light and dark backgrounds alike.
;;;;
;;;; M-x light-theme and M-x dark-theme switch the window's palette.

(defvar *color-theme* 'default-theme)
(defvar *gui-theme* 'dark)

(define (apply-color-theme colors)
  (let ((theme (command-procedure *color-theme*)))
    (when theme (theme colors))))

(define (default-theme colors)
  (if (>= colors 16777216) (gui-theme) (terminal-theme colors)))

;;; The window has 24-bit colour.  Two palettes, after Chris Kempson's
;;; "Tomorrow" themes; choose with *GUI-THEME*.

(define *gui-palettes*
  '((dark  (background . "#1d1f21") (foreground . "#c5c8c6") (cursor . "#f0c674")
           (selection . "#373b41") (region . "#3a5f94") (region-text . "#ffffff")
           (comment . "#969896") (keyword . "#b294bb")
           (string . "#b5bd68") (number . "#de935f") (brace . "#81a2be")
           (link . "#8abeb7"))
    (light (background . "#ffffff") (foreground . "#4d4d4c") (cursor . "#4271ae")
           (selection . "#d6d6d6") (region . "#9ec3f5") (region-text . "#1d1f21")
           (comment . "#8e908c") (keyword . "#8959a8")
           (string . "#718c00") (number . "#f5871f") (brace . "#4271ae")
           (link . "#3e999f"))))

(define (gui-theme)
  (let* ((p (cdr (or (assq *gui-theme* *gui-palettes*) (car *gui-palettes*))))
         (c (lambda (key) (cdr (assq key p)))))
    (set-gui-colors (c 'foreground) (c 'background) (c 'cursor))
    (theme-face 'symbol        'default)
    (theme-face 'alpha         'default)
    (theme-face 'modeline      (c 'foreground) (c 'selection))
    (theme-face 'brace         (c 'background) (c 'brace))
    (theme-face 'keyword       (c 'keyword) 'default 'bold)
    (theme-face 'digits        (c 'number))
    (theme-face 'comment       (c 'comment))
    (theme-face 'block-comment (c 'comment))
    (theme-face 'string        (c 'string))
    ;; the selected region (C-SPC): a clear blue, not the mode line's grey
    (theme-face 'region        (c 'region-text) (c 'region))
    (theme-face 'heading       (c 'brace) 'default 'bold)
    (theme-face 'emphasis      (c 'foreground) 'default 'italic)
    (theme-face 'strong        (c 'foreground) 'default 'bold)
    (theme-face 'link          (c 'link) 'default 'underline)
    ;; the mode line menu: yellow (dark) or blue (light) buttons, lit when clicked
    (theme-face 'menu          (c 'cursor) (c 'selection) 'bold)
    (theme-face 'menu-pressed  (c 'background) (c 'cursor) 'bold)))

(define (terminal-theme colors)
  (let ((many (>= colors 256)))
    (theme-face 'symbol   'default)
    (theme-face 'alpha    'default)
    (theme-face 'modeline 'default 'default 'reverse)
    (theme-face 'brace    'black 'cyan)
    ;; the selected region: black on light grey reads on any background
    (if many (theme-face 'region 16 252) (theme-face 'region 'default 'default 'reverse))
    ;; prose (Markdown)
    (theme-face 'heading  (if many 25 'blue) 'default 'bold)
    (theme-face 'emphasis 'default 'default 'italic)
    (theme-face 'strong   'default 'default 'bold)
    (theme-face 'link     (if many 30 'cyan) 'default 'underline)
    ;; the mode line menu: yellow on black, black on yellow when clicked
    (theme-face 'menu         (if many 226 'yellow) 'black 'bold)
    (theme-face 'menu-pressed 'black (if many 226 'yellow) 'bold)
    (if many
        (begin
          ;; picked to stay readable on both white and black backgrounds
          (theme-face 'keyword       127 'default 'bold)   ; purple
          (theme-face 'digits        166)                  ; orange
          (theme-face 'comment       244)                  ; grey
          (theme-face 'block-comment 244)
          (theme-face 'string         64))                 ; olive green
        (begin
          (theme-face 'keyword       'magenta 'default 'bold)
          (theme-face 'digits        'red)
          (theme-face 'comment       'blue)
          (theme-face 'block-comment 'blue)
          (theme-face 'string        'green)))))

(define (set-gui-theme theme)
  (set! *gui-theme* theme)
  (fe-reapply-colors)
  (message (if (eq? theme 'dark) "Dark theme" "Light theme")))

(defcommand (dark-theme) "The dark palette (yellow cursor)." (set-gui-theme 'dark))
(defcommand (light-theme) "The light palette (blue cursor)." (set-gui-theme 'light))
