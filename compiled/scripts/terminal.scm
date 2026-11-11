;;;; terminal.scm -- M-x term: a shell in a buffer (src/terminal.c)
;;;;
;;;; M-x term opens *terminal*, a shell ($SHELL) in a pseudo-terminal, as
;;;; Emacs's term and Neovim's :terminal do; full-screen programs (vim,
;;;; less, htop, claude) work in it.  If *terminal* is running, M-x term goes
;;;; to it; once its shell has exited, M-x term opens *terminal<2>*, and so
;;;; on.  The keys go to the shell, but for C-c, the escape:
;;;;
;;;;   C-c C-c    C-c to the shell (interrupt)
;;;;   C-c C-j    copy mode: the editor's keys in the terminal's text and
;;;;              history (C-s, C-SPC, M-w ...); the mode line shows Copy
;;;;   C-c C-k    back to the shell (the mode line shows Term)
;;;;   C-c KEY    the editor's C-x KEY: C-c b another buffer, C-c o the
;;;;              other window, C-c 2 two windows, C-c k kill the terminal
;;;;   C-c M-x    M-x
;;;;   C-c C-x    C-x: C-c C-x C-c quits the editor (asking, while a shell runs)
;;;;
;;;; The mouse stays the editor's.  In the browser there is no terminal: a
;;;; web page cannot start a shell.

(define (term-name k)
  (if (= k 1) "*terminal*" (string-append "*terminal<" (number->string k) ">*")))

(defcommand (term)
  "A shell in a buffer, *terminal* (terminal.c): C-c C-c interrupts, C-c C-j
copy mode, C-c KEY the editor's C-x KEY."
  (if (memv (fe-term-state) '(1 2))
      (begin (fe-term-copy-mode 0)
             (message "This is a terminal; C-c b goes to another buffer"))
      (let ((before (get-buffer-name)))
        ;; the first *terminal<k>* that runs, or is not a terminal yet
        (let loop ((k 1))
          (select-buffer (term-name k))
          (case (fe-term-state)
            ((1 2) (fe-term-copy-mode 0)
                   (update-display)
                   (message (term-name k) ": C-c C-c interrupts, C-c C-j copy mode, C-c KEY the editor's C-x KEY"))
            ((3) (loop (+ k 1)))
            (else
             (let ((why (fe-term-open)))
               (update-display)
               (if (string=? why "")
                   (message "Terminal: C-c C-c interrupts, C-c C-j copy mode, C-c b another buffer, C-c o the other window")
                   (begin (select-buffer before)
                          (kill-buffer (term-name k))
                          (update-display)
                          (message why))))))))))

(defcommand (term-char-mode)
  "Back from copy mode to the shell (C-c C-k in a terminal)."
  (if (= (fe-term-state) 2)
      (begin (fe-term-copy-mode 0) (message "Terminal: the keys go to the shell again"))
      (message "C-c C-k: not in a terminal's copy mode")))

(defcommand (term-copy-mode)
  "The editor's keys in a terminal's text (C-c C-j in a terminal)."
  (if (= (fe-term-state) 1)
      (begin (fe-term-copy-mode 1) (message "Copy mode: the editor's keys; M-w copies; C-c C-k: back to the shell"))
      (message "Not in a terminal")))

(global-set-key "C-c C-k" 'term-char-mode)
