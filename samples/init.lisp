;;;; Example ~/.sbemacs/init.lisp
;;;;
;;;; Copy this file to ~/.sbemacs/init.lisp (or ~/.sbemacs.lisp) and edit.
;;;; It is plain Common Lisp, loaded into the SBEMACS-USER package, which
;;;; uses COMMON-LISP and the editor API.  If it signals an error the editor
;;;; still starts and shows the error on the message line.  Start with
;;;; "sbemacs -q" to skip it.

;;; Keep unlimited undo (the default).  Set to NIL on low-memory machines.
(setf *undo-mode* t)

;;; Colours.  Faces: :keyword :comment :block-comment :string :digits
;;; :alpha (identifiers) :symbol (the rest) :brace :modeline.
;;; Colours: :default (the terminal's own), :black :red :green :yellow :blue
;;; :magenta :cyan :white, or 0-255 on 256-colour terminals.
;;; Attributes after the background: :bold :underline :reverse :dim :italic
;; (set-color :keyword :blue :default :bold)
;; (set-color :comment 244)                ; grey
;; (set-color :string 28)                  ; dark green, for light backgrounds

;;; A command of your own, bound to a free user key (see Esc-l for the
;;; keys shown as "user-defined-function").
(defun insert-date ()
  (multiple-value-bind (s m h day month year) (get-decoded-time)
    (declare (ignore s m h))
    (insert (format nil "~4D-~2,'0D-~2,'0D" year month day))))

(global-set-key "C-c d" 'insert-date)

;;; Syntax highlighting for another language.
(define-language "Markdown"
  :extensions '(".md" ".markdown")
  :strings '("`")
  :keywords '("#" "##" "###" "####" "-" "*"))

;;; Run something every time a region is killed.
;; (push (lambda (buffer) (log-message (format nil "kill in ~A" buffer))) *kill-hook*)

;;; Do something once the screen is up.
;; (push (lambda () (message "Welcome back, ~A" (sb-ext:posix-getenv "USER"))) *startup-hook*)
