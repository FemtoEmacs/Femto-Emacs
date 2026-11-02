; -*- scheme -*-
; femtoscheme <-> JavaScript glue for the WebAssembly build.

(define (%json-string s)
  (let ((b (buffer)))
    (io.write b "\"")
    (string-for-each
     (lambda (c)
       (let ((n (char->integer c)))
         (cond ((eqv? c #\") (io.write b "\\\""))
               ((eqv? c #\\) (io.write b "\\\\"))
               ((< n 32) (io.write b (string "\\u" (string.lpad (number->string n 16) 4 #\0))))
               (else (io.write b (string c))))))
     s)
    (io.write b "\"")
    (io.tostring! b)))

; Scheme values as JSON: lists and vectors become arrays.
(define (%json x)
  (cond ((eq? x #t) "true")
        ((eq? x #f) "false")
        ((null? x) "[]")
        ((number? x) (if (finite? x) (number->string x) "null"))
        ((string? x) (%json-string x))
        ((symbol? x) (%json-string (symbol->string x)))
        ((char? x) (%json-string (string x)))
        ((list? x) (string "[" (string-join (map %json x) ",") "]"))
        ((vector? x) (%json (vector->list x)))
        (else (%json-string (%write-string x)))))

; Call the page: answers arrive as Scheme datum text.
(define (%host-call op . args)
  (let ((answer (read (open-input-string (%host (symbol->string op) (%json args))))))
    (if (and (pair? answer) (eq? (car answer) '%host-error))
        (error (string "browser: " (cadr answer)))
        answer)))

(define *last-value* #f)

(define (%web-eval source)
  (let ((out (buffer)) (value #f) (has-value #f) (failure #f))
    (trycatch
     (with-output-to out
       (let ((in (open-input-string source)))
         (let loop ()
           (let ((form (read in)))
             (if (not (eof-object? form))
                 (begin (set! value (eval form))
                        (set! has-value #t)
                        (loop)))))))
     (lambda (e) (set! failure e)))
    (if has-value (set! *last-value* value))
    (string "{\"ok\":" (if failure "false" "true")
            ",\"output\":" (%json-string (io.tostring! out))
            ",\"value\":" (if (and has-value (not failure))
                              (%json-string (%write-string value))
                              "null")
            ",\"error\":" (if failure (%json-string (error-message failure)) "null")
            "}")))
