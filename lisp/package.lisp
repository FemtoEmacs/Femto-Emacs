;;;; package.lisp -- packages for SBEmacs
;;;;
;;;; SBEMACS       the editor API (everything that used to be a femtolisp
;;;;               builtin) plus the machinery that talks to the C core.
;;;; SBEMACS-USER  where the user's init file, Esc-; and Esc-] are evaluated.
;;;;               It uses COMMON-LISP and SBEMACS, so plain (insert "x") works.

(defpackage #:sbemacs
  (:use #:common-lisp)
  (:export
   ;; movement
   #:forward-char #:backward-char #:forward-word #:backward-word
   #:forward-page #:backward-page #:next-line #:previous-line
   #:beginning-of-line #:end-of-line #:beginning-of-buffer #:end-of-buffer
   #:goto-line #:point #:goto-char #:mark #:set-mark #:buffer-size
   #:char-after #:current-line-text #:buffer-octets #:buffer-substring
   #:line-start #:line-end #:line-number
   #:push-mark #:clear-mark #:region-active-p #:activate-mark #:deactivate-mark
   ;; editing
   #:insert #:backward-delete-char #:backwards-delete-char #:delete-char
   #:kill-region #:copy-region #:yank #:kill-line #:undo #:redo #:*undo-limit*
   #:discard-undo-history #:get-clipboard #:set-clipboard #:cut-region
   ;; searching
   #:search-forward #:search-backward #:search-backwards
   ;; buffers and files
   #:get-buffer-count #:get-buffer-name #:buffer-filename #:buffer-modified-p
   #:select-buffer #:kill-buffer #:save-buffer #:find-file #:list-buffers
   #:rename-buffer
   ;; windows and display
   #:delete-other-windows #:other-window #:split-window #:update-display
   #:refresh-screen #:screen-rows #:screen-columns
   #:delete-window #:window-count #:window-rows #:recenter #:set-mode-line-hints
   #:set-window-start #:set-buffer-hint
   ;; message line, keyboard, prompts
   #:message #:clear-message-line #:log-debug #:log-message
   #:get-key #:get-key-name #:get-key-binding #:prompt
   ;; misc
   #:shell-command #:add-mode-global #:get-version-string #:quit-editor
   #:trim #:home #:config-file
   ;; customisation
   #:global-set-key #:global-unset-key #:key-binding #:*keymap*
   #:normalize-key #:display-key #:*last-key* #:*this-key* #:*last-command* #:*this-command*
   #:defcommand #:register-command #:*commands* #:execute-builtin #:builtin-command-names
   #:*kill-hook* #:*startup-hook* #:*self-insert-hook* #:*kill-ring* #:*kill-ring-max*
   #:set-color #:terminal-colors #:show-startup-message
   #:theme-face #:*color-theme* #:default-theme
   ;; the window
   #:set-gui-font #:set-gui-colors #:*gui-font* #:*gui-font-size*
   #:*option-is-meta* #:*gui-theme* #:*gui-font-candidates*
   ;; indentation
   #:define-indentation #:define-indent-style #:indent-line #:indent-region
   #:indent-buffer #:newline-and-indent #:indentation-for
   ;; scripts
   #:reload-scripts #:*script-directory*
   ;; syntax highlighting
   #:define-language #:find-language #:language-for-file #:*languages*
   #:highlight-string
   ;; extensions
   #:buffer-menu #:kill-ring-menu #:insert-kill-ring #:dired
   #:grep-command #:next-grep
   #:ask-claude #:ask-codex #:codex-submit #:codex-status
   #:codex-discussion #:codex-discussion-send
   #:assistant-insert #:assistant-status
   #:*claude-transport* #:*claude-model* #:*assistant-timeout*
   #:*codex-program* #:*codex-model* #:*codex-timeout*
   ;; default user commands (formerly in init.lsp)
   #:*undo-mode* #:read-string #:weekday #:what-day #:insert-day
   #:html-p #:html-h1 #:html-pp #:indent-two #:deindent-two
   #:upcase-region #:downcase-region #:transform-region #:eval-last-sexp
   ;; entry point
   #:main))

(defpackage #:sbemacs-user
  (:use #:common-lisp #:sbemacs))
