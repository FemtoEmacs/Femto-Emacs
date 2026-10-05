;;;; run-tests.lisp -- non-interactive tests (make test)
;;;;
;;;; Loads the Lisp side without starting curses and checks the parts that
;;;; do not need a terminal: the highlighter, the init.lsp ports, the
;;;; evaluator used by Esc-; and Esc-], and string passing to C.

(setf sb-impl::*default-external-format* :utf-8)

(defparameter *root*
  (merge-pathnames "../" (make-pathname :name nil :type nil :defaults *load-truename*)))

(sb-alien:load-shared-object
 (sb-ext:native-namestring
  (merge-pathnames #+darwin "libsbemacs.dylib" #+win32 "libsbemacs.dll"
                   #-(or darwin win32) "libsbemacs.so"
                   *root*))
 :dont-save t)

(handler-bind ((warning #'muffle-warning))
  (dolist (f '("lisp/package" "lisp/ffi" "lisp/highlight" "lisp/languages" "lisp/core"
               "lisp/defaults" "lisp/extensions/buffer-menu" "lisp/extensions/kill-ring"
               "lisp/extensions/dired" "lisp/extensions/grep"))
    (load (merge-pathnames (concatenate 'string f ".lisp") *root*))))

(in-package #:sbemacs)

(defvar *failures* 0)
(defvar *count* 0)

(defmacro check (name form expected)
  `(let ((got (handler-case ,form (error (e) (list :error (princ-to-string e)))))
         (want ,expected))
     (incf *count*)
     (unless (equal got want)
       (incf *failures*)
       (format t "~&FAIL ~A~%  expected ~S~%  got      ~S~%" ,name want got))))

(defun faces (string file)
  "Runs as (face . text), keeping only the interesting faces."
  (remove-if (lambda (run) (member (car run) (list +alpha+ +symbol+)))
             (highlight-string string file)))

;;; highlighting
(check "C keywords, numbers, comments"
       (faces "int x = 42; // hi" "a.c")
       '((4 . "int") (6 . "42") (7 . "// hi")))
(check "C block comment and string"
       (faces "/* a */ \"s\\\"q\"" "a.c")
       '((8 . "/* a */") (9 . "\"s\\\"q\"")))
(check "C char literal with a double quote does not open a string"
       (faces "c = '\"'; return" "a.c")
       '((9 . "'\"'") (4 . "return")))
(check "identifiers containing digits are not numbers"
       (faces "x1 utf8 1.5e3" "a.c")
       '((6 . "1.5e3")))
(check "Lisp: hyphenated words are not keywords"
       (faces "(defun define-x (let) #\\\" 1)" "a.lisp")
       '((4 . "defun") (4 . "let") (6 . "1")))
(check "Lisp is case-insensitive"
       (faces "(DEFUN f ())" "a.lisp")
       '((4 . "DEFUN")))
(check "Lisp block comment"
       (faces "#| x |# ; y" "a.lisp")
       '((8 . "#| x |#") (7 . "; y")))
(check "Python triple quotes and single quotes"
       (faces "def f(): '''doc''' + 'x'" "a.py")
       '((4 . "def") (9 . "'''doc'''") (9 . "'x'")))
(check "TeX commands"
       (faces "\\section{A} % c" "a.tex")
       '((4 . "\\section") (7 . "% c")))
(check "#include is a keyword"
       (faces "#include <x.h>" "a.h")
       '((4 . "#include")))
(check "UTF-8 text keeps byte alignment"
       (faces "/* café */ 7" "a.c")
       '((8 . "/* café */") (6 . "7")))
(check "unknown extension: numbers and strings only"
       (faces "if 3 \"q\"" "README")
       '((6 . "3") (9 . "\"q\"")))
(check "unterminated block comment runs to the end"
       (faces "/* open" "a.c")
       '((8 . "/* open")))
(check "a later define-language wins"
       (progn (define-language "Test" :extensions ".zz" :keywords '("foo"))
              (faces "foo bar" "x.zz"))
       '((4 . "foo")))

;;; init.lsp ports
(check "what-day" (what-day '(2016 9 3)) "Saturday")
(check "what-day 2026-10-05" (what-day '(2026 10 5)) "Monday")
(check "read-string" (read-string "(2016 8 31)") '(2016 8 31))
(check "trim" (trim "  buf  ") "buf")
(check "summarize-kill" (summarize-kill (format nil "line one~%line two")) "line one")

;;; the evaluator used by Esc-; and Esc-]
(check "eval-string evaluates every form"
       (let ((*package* (find-package '#:sbemacs-user)))
         (eval-string "(defun sq (x) (* x x)) (sq 12)"))
       144)
(check "errors become one-line messages"
       (with-editor-environment () (error "boom~%   bang"))
       "Error: boom bang")

;;; strings handed to C are UTF-8 and truncated on character boundaries
(check "write-c-string truncation"
       (let ((buf (make-array 6 :element-type '(unsigned-byte 8) :initial-element 255)))
         (sb-sys:with-pinned-objects (buf)
           (write-c-string "aéé" (sb-sys:vector-sap buf) 5))
         (coerce buf 'list))
       ;; "aé" = 61 C3 A9, the second é does not fit in 4 bytes + NUL
       '(#x61 #xC3 #xA9 0 255 255))

(format t "~&~D/~D tests passed~%" (- *count* *failures*) *count*)
(sb-ext:exit :code (if (zerop *failures*) 0 1))
