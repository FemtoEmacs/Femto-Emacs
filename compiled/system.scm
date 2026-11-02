;;;; system.scm -- the scripts' C functions beyond src/native.c's table
;;;;
;;;; Buffer text in bulk, the command and hint tables, files, programs, the
;;;; system, the highlighters and the assistants (src/bridge-more.c, around
;;;; the same C as femtoscheme's builtins), with the signatures the scripts
;;;; know.  Text comes back as strings; colours as bytevectors.

(define buffer-substring (foreign-procedure "buffer-substring" (long long) string))
(define buffer-bytes (foreign-procedure "buffer-bytes" (long long) u8*))   ; the same text as bytes
(define buffer-string (foreign-procedure "buffer-string" () string))
(define fe-insert-bytes (foreign-procedure "fe-insert-bytes" (long u8*) boolean))
(define fe-add-command-name (foreign-procedure "fe-add-command-name" (string) boolean))
(define fe-set-buffer-hint (foreign-procedure "fe-set-buffer-hint" (string string) boolean))
(define fe-set-modeline-hints (foreign-procedure "fe-set-modeline-hints" (string string) boolean))
(define fe-mouse-event (foreign-procedure "fe-mouse-event" () boolean))
(define command-prompt (foreign-procedure "command-prompt" () string))
(define buffer-read-only? (foreign-procedure "buffer-read-only?" () boolean))
(define set-buffer-read-only! (foreign-procedure "set-buffer-read-only!" (boolean) boolean))
(define fe-set-completions (foreign-procedure "fe-set-completions" (string) boolean))
(define %file-prompt (foreign-procedure "file-prompt" (string) string))
(define (ttfy-file-prompt) (%file-prompt "Textify PDF: "))

;;; files
(define file-attributes (foreign-procedure "file-attributes" (string) scheme-object))  ; #f or (directory? size mtime)
(define file-executable? (foreign-procedure "file-executable?" (string) boolean))
(define path.exists? (foreign-procedure "path.exists?" (string) boolean))
(define real-path (foreign-procedure "real-path" (string) scheme-object))
(define format-time (foreign-procedure "format-time" (long) string))
(define file-contents (foreign-procedure "file-contents" (string) scheme-object))       ; a string or #f
(define directory-files (foreign-procedure "directory-files" (string) scheme-object))
(define file-completions (foreign-procedure "file-completions" (string) scheme-object))

;;; programs and the system
;;; (run-program program args input timeout directory): (stdout stderr status)
(define run-program (foreign-procedure "run-program" (string scheme-object scheme-object long scheme-object) scheme-object))
(define spawn-program (foreign-procedure "spawn-program" (string scheme-object) scheme-object))
(define os-name (foreign-procedure "os-name" () string))
(define getpid (foreign-procedure "getpid" () int))
;;; milliseconds since the editor started (R7RS's jiffies)
(define current-jiffy (foreign-procedure "current-jiffy" () int))
(define (jiffies-per-second) 1000)
(define os.getenv (foreign-procedure "os.getenv" (string) scheme-object))
(define os.setenv (foreign-procedure "os.setenv" (string scheme-object) boolean))
(define getenv os.getenv)
(define %cwd (foreign-procedure "path.cwd" () string))
(define %cd (foreign-procedure "path.cwd" (string) string))
(define (path.cwd . directory) (if (pair? directory) (%cd (car directory)) (%cwd)))
(define (current-directory . directory) (apply path.cwd directory))
(define fe-install-dir (foreign-procedure "fe-install-dir" () string))
(define *install-dir* (fe-install-dir))
(define fe-program-path (foreign-procedure "fe-program-path" () string))
(define (in-browser?) #f)
(define (web-request . what) (error "web-request: only in the browser" what))

;;; highlighters: they fill COLORS, a bytevector as long as the text's bytes
(define %define-token-language
  (foreign-procedure "fe-define-token-language"
                     (string scheme-object scheme-object scheme-object scheme-object scheme-object boolean boolean scheme-object) int))
(define (fe-define-token-language word-chars line-comments block-comments strings escape char-prefix
                                  backslash-commands case-insensitive keywords)
  (%define-token-language word-chars line-comments
                          (map (lambda (b) (list (car b) (cdr b))) block-comments)
                          strings escape char-prefix backslash-commands case-insensitive keywords))
(define %highlight-tokens (foreign-procedure "fe-highlight-tokens" (int u8*) u8*))
(define %highlight-python (foreign-procedure "fe-highlight-python" (u8*) u8*))
(define %highlight-nim (foreign-procedure "fe-highlight-nim" (u8*) u8*))
(define %highlight-markdown (foreign-procedure "fe-highlight-markdown" (u8*) scheme-object))
(define (%fill-colors! colors from)
  (bytevector-copy! colors 0 from 0 (min (bytevector-length colors) (bytevector-length from)))
  #t)
(define (fe-highlight-tokens id text colors) (%fill-colors! colors (%highlight-tokens id text)))
(define (fe-highlight-python text colors) (%fill-colors! colors (%highlight-python text)))
(define (fe-highlight-nim text colors) (%fill-colors! colors (%highlight-nim text)))
(define (fe-highlight-markdown text colors)   ; the blocks of code, (start end info) ...
  (let ((r (%highlight-markdown text)))
    (%fill-colors! colors (car r))
    (cadr r)))

;;; the assistants
(define assistant-request (foreign-procedure "assistant-request" (string string) string))
(define ttfy-request (foreign-procedure "ttfy-request" (string string string string) string))
