;;; oracle.el -- what Emacs's Org shows after TABs (maintainers only:
;;; tests/org-fold.sh compares Chezemax's TAB with this, recorded in
;;; expected.txt).  Run in this folder:
;;;   emacs --batch -Q -l oracle.el > expected.txt
;;; Each line of sequences.txt: a file, then the headings TAB is pressed
;;; on, in order (a different heading means the cursor moved there).
(require 'org)
(defun oracle-visible ()
  (let (out)
    (save-excursion
      (goto-char (point-min))
      (while (not (eobp))
        (unless (invisible-p (point))
          (let* ((e (line-end-position))
                 (folded (and (< e (point-max)) (invisible-p e))))
            (push (concat (buffer-substring-no-properties (point) e) (if folded "..." "")) out)))
        (forward-line 1)))
    (mapconcat 'identity (nreverse out) "|")))
(defun oracle-run (file headings)
  (with-current-buffer (find-file-noselect (expand-file-name file))
    (revert-buffer t t) (org-mode) (org-show-all)
    (let ((previous nil))
      (dolist (h headings)
        (goto-char (point-min))
        (re-search-forward (concat "^" (regexp-quote h) "$"))
        (beginning-of-line)
        (setq last-command (if (equal h previous) 'org-cycle nil)
              this-command 'org-cycle)
        (org-cycle)
        (setq previous h)
        (princ (format "%s %s: %s\n" file h (oracle-visible)))))))
(with-temp-buffer
  (insert-file-contents "sequences.txt")
  (dolist (line (split-string (buffer-string) "\n" t))
    (let* ((space (string-match " " line)))
      (oracle-run (substring line 0 space) (split-string (substring line (1+ space)) ",")))))
