;;
;; Dired extension for FemtoEmacs, written in Femtolisp with FemtoEmacs bindings
;;
;; 
;; use the arrow keys to move up or down the list
;; then select one of the following letters
;;
;; Suggested first implementation does the following
;; o - if a directory change to that directory and reload the ls output
;; f - open the file in the editor
;; x - exit dired
;;
;;
;; This is just a start. Completion of this DIRED is left as challenge for the
;; reader.  For an example see the dired.cmd sample that was written for MicroEMACS
;;
;;
;;
;; (load "samples/dired.scm")
;; (dired)
;;
;;


(define dired-dir "$HOME")
(define dired-ls-cmd "ls -la ")

(define (dired)
  (delete-other-windows)
  (shell-command (string-append dired-ls-cmd dired-dir))
  (beginning-of-buffer)
  (set-mark)
  (goto-line 3)
  (kill-region))


