;;;; syntax.scm -- the scripts' own forms, as syntax-rules
;;;;
;;;; In femtoscheme these were macros (define-macro, scheme/core.scm and
;;;; init.scm).  Compiled, the program is built once, so DEFVAR defines its
;;;; variable as DEFINE does: C-x C-r, which reloads the scripts without
;;;; losing their state, will recompile the user's own files instead.

;;; (defcommand (name arg ...) body ...): define NAME and offer it to M-x
;;; (REGISTER-COMMAND, scheme/core.scm)
(define-syntax defcommand
  (syntax-rules ()
    ((_ (name . args) body ...)
     (begin (define (name . args) body ...)
            (register-command 'name)
            'name))))

;;; (defvar name value): a variable of the scripts' state
(define-syntax defvar
  (syntax-rules ()
    ((_ name value) (define name value))
    ((_ name) (define name #f))))
