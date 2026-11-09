;;;; Shared commands: the browser is another view; AI stays native.
(define %chezweb-open (foreign-procedure "chezweb-open" () string))
(define (in-browser?) (string=? (fe-backend) "browser"))
(defcommand (browser-editor)
  "C-c d: open the current text in Chrome, leaving this editor running."
  (message (%chezweb-open)))
(global-set-key "C-c d" 'browser-editor)
(defcommand (browser-ai-advice)
  "AI assistance uses the native window."
  (message "For Codex or Claude, use the terminal or SDL window. No AI login or API key is used here."))
(when (in-browser?)
  (set! ask-codex browser-ai-advice)
  (set! ask-claude browser-ai-advice)
  ;; The command registry keeps procedure values: update it too.
  (global-set-key "C-c g" 'browser-ai-advice)
  (global-set-key "C-c r" 'browser-ai-advice))

;;; Browser shell services use only the in-memory/granted filesystem.
(define %browser-request (foreign-procedure "chezweb-browser-request" (string string) string))
(define (web-request name arg) (%browser-request name arg))

;;; Grammarly edits use byte positions, as does the C editor.
(define (web-layer-edit buffer page offset old new)
  (let* ((from (+ page offset)) (to (+ from (bytes-length old))))
    (when (and (string=? buffer (get-buffer-name))
               (not (buffer-read-only?)) (>= from 0) (<= to (buffer-size))
               (or (= from (buffer-size))
                   (not (= (bitwise-and (buffer-get from) #xC0) #x80)))
               (string=? (buffer-substring from to) old))
      (let ((here (point)))
        (undo-boundary "grammarly")
        (replace-region from to new)
        (goto-char (cond ((< here from) here)
                         ((>= here to) (+ here (- (bytes-length new) (bytes-length old))))
                         (else (+ from (min (- here from) (bytes-length new))))))))))
(defcommand (toggle-grammarly)
  (if (in-browser?)
      (begin (web-request "grammarly-toggle" "") (update-display))
      (message "Grammarly is available in the browser editor.")))

;;; M-x native-window-update: when a browser C-x C-s is refused because the
;;; native buffer was edited, closed or saved under another name, send the
;;; browser's text to the native buffer (the native text, if it is on no
;;; disk, goes to a *native-N* buffer there); then C-x C-s saves.
(defcommand (native-window-update)
  "In the browser: put this text in the native window's buffer."
  (if (in-browser?)
      (message (web-request "native-update"
                            (string-append (or (buffer-filename) "") "\n"
                                           (buffer-substring 0 (buffer-size)))))
      (message "M-x native-window-update runs in the browser editor (C-c d).")))

;;; Your ~/.chezemax files: the page fetched them at start-up (web/page.js),
;;; read-only, from the native window's server.  C-x C-r fetches them again,
;;; so it loads what you last saved there, then reloads them as natively.
(define %native-reload-scripts reload-scripts)
(defcommand (browser-reload-scripts)
  "C-x C-r in the browser: fetch your ~/.chezemax files again, then load them."
  (web-request "settings-reload" "")
  (%native-reload-scripts))
(when (in-browser?)
  (set! reload-scripts browser-reload-scripts)
  (global-set-key "C-x C-r" 'browser-reload-scripts))

;;; ------------------------------------------------------------------
;;; What the browser editor leaves to the terminal and SDL windows
;;; ------------------------------------------------------------------
;;; The assistants (C-c r, C-c g and what works on their answers), TTFY
;;; (textify a PDF), the plots (C-c p) and compile-scripts need programs
;;; on your computer: in the browser they say where they are.  TTFY and the
;;; plots leave the mode line, the keys and the help page.  Done here, so
;;; the scripts stay Chezemax's own.

;; M-x chinese-input reads its tables from the installation's Chinese/
;; folder, which the page does not carry (it would weigh on every page);
;; the browser's own text field takes the system's Chinese input instead.
(defcommand (browser-chinese-input)
  "Chinese input in the browser: the system's input method."
  (message "Chinese input: in the browser, use your system's pinyin input method; M-x chinese-input works in the terminal and SDL window"))

(defcommand (browser-native-only)
  "TTFY, plots and compile-scripts run in the terminal or SDL window."
  (message "Not in the browser editor: TTFY, plots (C-c p) and compile-scripts run in the terminal or SDL window."))

(define (%without-labels labels buttons)
  (filter (lambda (b) (not (member (car b) labels))) buttons))
(define (%without-entries names entries)
  (filter (lambda (e) (not (member (car e) names))) entries))
(define (%browser-help-entry e)
  (let ((says (assoc (car e)
                     '(("C-c r" "Claude: in the terminal or SDL window, not here")
                       ("C-c g" "ChatGPT (Codex): in the terminal or SDL window, not here")
                       ("C-c y" "(assistants) in the terminal or SDL window")
                       ("C-c t" "(assistants) in the terminal or SDL window")
                       ("C-c q" "close the help menu or page, or the command window")
                       ("M-!" "command window: only ls, cd and pwd here (TAB completes)")
                       ("C-c m" "command in the minibuffer: only ls, cd and pwd here")
                       ("C-c s" "in the command window: run ls, cd or pwd")
                       ("C-x C-r" "reload your ~/.chezemax files")))))
    (if says (list (car e) (cadr says)) e)))

(when (in-browser?)
  ;; what works on the assistants' answers, and their set-up pages
  (set! assistant-insert browser-ai-advice)
  (set! assistant-discussion-tangle browser-ai-advice)
  (set! ai-help browser-ai-advice)
  (set! assistant-status browser-ai-advice)
  (set! codex-status browser-ai-advice)
  (global-set-key "C-c y" 'browser-ai-advice)
  (global-set-key "C-c t" 'browser-ai-advice)
  ;; TTFY, the plots and compiling: gone from the keys, the mode line and M-x
  (set! ttfy-menu browser-native-only)
  (set! plot-at-point browser-native-only)
  (set! plot-save browser-native-only)
  (set! compile-scripts browser-native-only)
  (set! chinese-input browser-chinese-input)
  (global-unset-key "C-c f")
  (global-unset-key "C-c p")
  (set! *mode-line-menu* (%without-labels '("TTFY") *mode-line-menu*))
  (set! *full-menu* (%without-labels '("TTFY") *full-menu*))
  (set! *mode-line-kept-buttons* (filter (lambda (l) (not (string=? l "TTFY"))) *mode-line-kept-buttons*))
  ;; the help page says what the browser does
  (set! *help-header*
        "PRESS i (OR CLICK [CLOSE]) TO CLOSE THIS PAGE and return to your file.
This page is read-only: j and k (or the arrows) move down and up, Ctrl-d
and Ctrl-u a page, gg and G to the top and the end, / searches (n: again).
Ctrl-c h shows this page.  This is the browser editor: Claude (Ctrl-c r),
ChatGPT (Ctrl-c g), TTFY, the plots and a full shell are in the terminal or
SDL window; here M-! and Ctrl-c m run only ls, cd and pwd.")
  (set! *help-sections*
        (map (lambda (section)
               (cons (car section)
                     (map %browser-help-entry (%without-entries '("C-c f" "C-c p") (cdr section)))))
             *help-sections*))
  (set! *help-commands*
        (cons (car *help-commands*)
              (%without-entries '("plot-at-point" "plot-save" "ai-help" "assistant-status" "codex-status")
                                (cdr *help-commands*)))))
