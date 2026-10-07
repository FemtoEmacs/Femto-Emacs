;;;; theme.lisp -- the default colour theme
;;;;
;;;; Loaded at start-up, like every script in this directory: edit it and
;;;; press C-x C-r (reload-scripts) to see the change, no rebuild needed.
;;;;
;;;; The theme is a function of the number of colours: 8 or 256 in a
;;;; terminal, 16777216 (24-bit) in the window of sbemacs --gui.  It
;;;; is called when the screen starts, before your own SET-COLOR calls are
;;;; applied, so those always win.  To use your own theme, define a
;;;; function in ~/.sbemacs/init.lisp and (setf *color-theme* 'my-theme).
;;;;
;;;; :default means the terminal's own colour.  Using the terminal's
;;;; background keeps its cursor visible on light and dark themes alike.

(in-package #:sbemacs)

(defun default-theme (colors)
  (if (>= colors 16777216)
      (gui-theme)
      (terminal-theme colors)))

;;; The window (sbemacs --gui) has 24-bit colour.  Two palettes, after
;;; Chris Kempson's "Tomorrow" themes; choose with *GUI-THEME* (gui.lisp).

(defparameter *gui-palettes*
  '((:dark  :background "#1d1f21" :foreground "#c5c8c6" :cursor "#f0c674"
            :selection "#373b41" :comment "#969896" :keyword "#b294bb"
            :string "#b5bd68" :number "#de935f" :brace "#81a2be"
            :link "#8abeb7")
    (:light :background "#ffffff" :foreground "#4d4d4c" :cursor "#4271ae"
            :selection "#d6d6d6" :comment "#8e908c" :keyword "#8959a8"
            :string "#718c00" :number "#f5871f" :brace "#4271ae"
            :link "#3e999f")))

(defun gui-theme ()
  (let ((p (cdr (or (assoc (if (boundp '*gui-theme*) (symbol-value '*gui-theme*) :dark)
                           *gui-palettes*)
                    (first *gui-palettes*)))))
    (flet ((c (key) (getf p key)))
      (set-gui-colors :foreground (c :foreground) :background (c :background)
                      :cursor (c :cursor))
      (theme-face :symbol        :default)
      (theme-face :alpha         :default)
      (theme-face :modeline      (c :foreground) (c :selection))
      (theme-face :brace         (c :background) (c :brace))
      (theme-face :keyword       (c :keyword) :default :bold)
      (theme-face :digits        (c :number))
      (theme-face :comment       (c :comment))
      (theme-face :block-comment (c :comment))
      (theme-face :string        (c :string))
      (theme-face :region        (c :foreground) (c :selection))
      (theme-face :heading       (c :brace) :default :bold)
      (theme-face :emphasis      (c :foreground) :default :italic)
      (theme-face :strong        (c :foreground) :default :bold)
      (theme-face :link          (c :link) :default :underline)
      ;; the mode line menu: yellow buttons, lit when clicked
      (theme-face :menu          (c :cursor) (c :selection) :bold)
      (theme-face :menu-pressed  (c :background) (c :cursor) :bold))))

(defun terminal-theme (colors)
  (theme-face :symbol   :default)
  (theme-face :alpha    :default)
  (theme-face :modeline :default :default :reverse)
  (theme-face :brace    :black :cyan)
  ;; the selected region: black on light grey reads on any background
  (if (>= colors 256)
      (theme-face :region 16 252)
      (theme-face :region :default :default :reverse))
  ;; prose (Markdown)
  (theme-face :heading  (if (>= colors 256) 25 :blue) :default :bold)
  (theme-face :emphasis :default :default :italic)
  (theme-face :strong   :default :default :bold)
  (theme-face :link     (if (>= colors 256) 30 :cyan) :default :underline)
  ;; the mode line menu: yellow on black, black on yellow when clicked
  (theme-face :menu         (if (>= colors 256) 226 :yellow) :black :bold)
  (theme-face :menu-pressed :black (if (>= colors 256) 226 :yellow) :bold)
  (if (>= colors 256)
      (progn
        ;; picked to stay readable on both white and black backgrounds
        (theme-face :keyword       127 :default :bold) ; purple
        (theme-face :digits        166)                ; orange
        (theme-face :comment       244)                ; grey
        (theme-face :block-comment 244)
        (theme-face :string         64))               ; olive green
      (progn
        (theme-face :keyword       :magenta :default :bold)
        (theme-face :digits        :red)
        (theme-face :comment       :blue)
        (theme-face :block-comment :blue)
        (theme-face :string        :green))))
