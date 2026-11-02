;;; compiled-editor.scm -- keys bound in compiled Scheme, in the real editor
;;; (tests/run-bridge.sh)
(compiled-key! "C-c 9" (lambda () (fe-insert "compiled ✓ ") (fe-insert (fe-buffer-name))))
(compiled-key! "C-c 8" (lambda () (error "a compiled command failed on purpose")))

;;; The other hooks (tests/run-bridge.sh)
(define (ends-with? s suffix)
  (let ((n (string-length s)) (k (string-length suffix)))
    (and (>= n k) (string=? (substring s (- n k) n) suffix))))
;; colours: "!" is face 4 (a keyword), the rest 5
(compiled-highlighter! (lambda (file) (ends-with? file ".shout"))
  (lambda (text)
    (let* ((n (bytevector-length text)) (colors (make-bytevector n 5)))
      (let loop ((i 0))
        (when (< i n)
          (when (= (bytevector-u8-ref text i) 33) (bytevector-u8-set! colors i 4))
          (loop (+ i 1))))
      colors)))
;; the mode line of a buffer called "special"
(compiled-mode-line!
  (lambda (name file buffer line flags cols)
    (and (string=? buffer "special")
         (mode-line-pieces (list (list 0 0 (string-append "compiled: " buffer " L. " (number->string line))))))))
;; undo: changes whose text is "record-me" are recorded here
(define *changes* '())
(compiled-change!
  (lambda (id kind offset text)
    (let ((s (utf8->string text)))
      (set! *changes* (cons s *changes*))
      (string=? s "record-me"))))
;; word wrap at 10 columns for files ending in .wrap
(compiled-wrapper! (lambda (file) (ends-with? file ".wrap"))
  (lambda (text cols) (min 10 cols (bytevector-length text))))
