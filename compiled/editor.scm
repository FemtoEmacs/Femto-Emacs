;;;; editor.scm -- the compiled side of Chezemax's scripts
;;;;
;;;; The program `make` builds (chezemax.wasm) is bridge.scm, the C core's
;;;; functions (editor-functions.scm), then this file.  While the scripts are
;;;; ported (PORT-TO-SCHEMER.md), the C core gives every event to this program
;;;; first: what it handles is done here; everything else goes on to the
;;;; femtoscheme scripts as before.

;;; Keys bound in compiled Scheme, by the C core's key names ("C-c a",
;;; "esc x" for M-x): key -> procedure of no arguments
(define *compiled-keys* (make-hashtable string-hash string=?))

(define (compiled-key! key procedure)
  (hashtable-set! *compiled-keys* key procedure))

;;; editor-event, the C core's hook for keys, commands and clicks: #t when
;;; handled here
(define (compiled-editor-event kind arg)
  (if (string=? kind "key")
      (let ((procedure (hashtable-ref *compiled-keys* arg #f)))
        (if procedure
            (begin (procedure) #t)
            #f))
      #f))

;;; ------------------------------------------------------------------
;;; The C core's hooks (src/hooks.c).  C calls a hook only when this program
;;; has registered it: COMPILED-HOOK! tells C.  A hook answers #f to leave
;;; the work to the femtoscheme scripts, as while they are being ported.
;;; ------------------------------------------------------------------

;;; The hooks' numbers (src/bridge.h)
(define hook-event 1)
(define hook-highlight 2)
(define hook-mode-line 3)
(define hook-change 4)
(define hook-wrap 5)

(define %hook-set! (foreign-procedure "bridge-hook-set!" (int boolean) void))
;;; The text of the hook running now, as a bytevector: only fetched by a
;;; hook that does handle the file
(define hook-text (foreign-procedure "hook-text" () u8*))

(define (compiled-hook! n procedure)
  (bridge-hook! n procedure)
  (%hook-set! n (if procedure #t #f)))

(compiled-hook! hook-event compiled-editor-event)

;;; The first (predicate . procedure) of ALIST whose predicate accepts FILE
(define (%for-file alist file)
  (cond ((null? alist) #f)
        (((caar alist) file) (cdar alist))
        (else (%for-file (cdr alist) file))))

;;; Colours.  (compiled-highlighter! predicate procedure): PREDICATE takes a
;;; file name (or a buffer name, for a buffer without a file); PROCEDURE takes
;;; the text, a bytevector of UTF-8 bytes, and returns a bytevector of as
;;; many colours (faces), one a byte.
(define *compiled-highlighters* '())
(define (compiled-highlighter! predicate procedure)
  (set! *compiled-highlighters* (append *compiled-highlighters* (list (cons predicate procedure))))
  (compiled-hook! hook-highlight compiled-highlight))
(define (compiled-highlight file buffer start count)
  (let ((procedure (%for-file *compiled-highlighters* (if (string=? file "") buffer file))))
    (and procedure
         (let ((colors (procedure (hook-text))))
           (and (bytevector? colors) (= (bytevector-length colors) count) colors)))))

;;; Mode lines.  (compiled-mode-line! procedure): PROCEDURE takes the name
;;; shown, the file, the buffer's name, the line, the flags and the columns,
;;; and returns the line, or #f for the usual one.  The line is made of
;;; pieces (src/display.c, paint_pieces): (mode-line-pieces (list face id
;;; text) ...), where face 0 is the mode line's own and an id above 0 makes
;;; the piece a button.
(define (mode-line-piece face id text)
  (string-append (number->string face) (string (integer->char 31))
                 (number->string id) (string (integer->char 31)) text))
(define (mode-line-pieces pieces)
  (let loop ((pieces pieces) (out ""))
    (if (null? pieces)
        out
        (loop (cdr pieces)
              (string-append out (if (string=? out "") "" (string (integer->char 30)))
                             (mode-line-piece (car (car pieces)) (cadr (car pieces)) (caddr (car pieces))))))))
(define *compiled-mode-line* #f)
(define (compiled-mode-line! procedure)
  (set! *compiled-mode-line* procedure)
  (compiled-hook! hook-mode-line (and procedure compiled-mode-line)))
(define (compiled-mode-line name file buffer line flags cols)
  (*compiled-mode-line* name file buffer line flags cols))

;;; Undo.  (compiled-change! procedure): PROCEDURE takes the buffer's id, the
;;; kind of change, the offset and the text (a bytevector), and returns #t
;;; when it recorded the change.
(define *compiled-change* #f)
(define (compiled-change! procedure)
  (set! *compiled-change* procedure)
  (compiled-hook! hook-change (and procedure compiled-change)))
(define (compiled-change id kind offset text)
  (*compiled-change* id kind offset text))

;;; Word wrap.  (compiled-wrapper! predicate procedure): PROCEDURE takes the
;;; text of a row and more (a bytevector) and the columns, and returns how
;;; many bytes go in the row.  C first asks whether a file wraps at all.
(define *compiled-wrappers* '())
(define (compiled-wrapper! predicate procedure)
  (set! *compiled-wrappers* (append *compiled-wrappers* (list (cons predicate procedure))))
  (compiled-hook! hook-wrap compiled-wrap))
(define (compiled-wrap file length cols)
  (let ((procedure (%for-file *compiled-wrappers* file)))
    (cond ((not procedure) #f)
          ((< length 0) -1)                   ; "does this file wrap?": yes
          (else (procedure (hook-text) cols)))))
