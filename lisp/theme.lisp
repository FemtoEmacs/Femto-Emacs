;;;; theme.lisp -- the default colour theme
;;;;
;;;; Loaded at start-up, like every script in this directory: edit it and
;;;; press C-x C-r (reload-scripts) to see the change, no rebuild needed.
;;;;
;;;; The theme is a function of the number of colours the terminal has.  It
;;;; is called when the screen starts, before your own SET-COLOR calls are
;;;; applied, so those always win.  To use your own theme, define a
;;;; function in ~/.sbemacs/init.lisp and (setf *color-theme* 'my-theme).
;;;;
;;;; :default means the terminal's own colour.  Using the terminal's
;;;; background keeps its cursor visible on light and dark themes alike.

(in-package #:sbemacs)

(defun default-theme (colors)
  (theme-face :symbol   :default)
  (theme-face :alpha    :default)
  (theme-face :modeline :default :default :reverse)
  (theme-face :brace    :black :cyan)
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
