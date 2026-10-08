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
  (merge-pathnames #+darwin "libsbemacs-term.dylib" #+win32 "libsbemacs-term.dll"
                   #-(or darwin win32) "libsbemacs-term.so"
                   *root*))
 :dont-save t)

(handler-bind ((warning #'muffle-warning))
  (dolist (f '("lisp/package" "lisp/ffi" "lisp/loader" "lisp/core"))
    (load (merge-pathnames (concatenate 'string f ".lisp") *root*))))

(setf sbemacs::*script-directory* (truename (merge-pathnames "lisp/" *root*)))
(multiple-value-bind (loaded errors)
    (sbemacs::load-scripts :files (sbemacs::script-files sbemacs::*script-directory*)
                           :cache-directory (merge-pathnames "build/test-scripts/" *root*))
  (declare (ignore loaded))
  (when errors (format t "~&script errors: ~S~%" errors) (sb-ext:exit :code 1)))

(in-package #:sbemacs)

(defvar *failures* 0)
(defvar *count* 0)
(defmacro check (name form expected)
  `(progn (incf *count*) (unless (equalp ,form ,expected)
             (incf *failures*) (format t "FAIL ~A: ~S~%" ,name ,form))))
(defun nim-test-indent (text)
  (let* ((raw (octets text)) (line (1+ (or (position 10 raw :from-end t) -1))))
    (nim-indentation (make-indent-context :text raw :line line :spec (gethash "Nim" *indentation*)))))
(check "startup registers Nim" (language-name (language-for-file "test.nim")) "Nim")
(check "two-space procedure body" (nim-test-indent (format nil "proc main() =~%echo 1")) 2)
(check "let section" (nim-test-indent (format nil "let~%value = 1")) 2)
(check "ordinary initializer" (nim-test-indent (format nil "  let value = 1~%echo value")) 2)
(check "else matches if" (nim-test-indent (format nil "if true:~%  echo 1~%else:")) 0)
(check "case branch" (nim-test-indent (format nil "case value~%of 1:")) 2)
(check "next case branch" (nim-test-indent (format nil "case value~%  of 1:~%    echo 1~%of 2:")) 2)
(check "bracket continuation" (nim-test-indent (format nil "let xs = [~%1,")) 2)
(check "closing bracket" (nim-test-indent (format nil "let xs = [~%  1,~%]")) 0)
(check "string indentation unchanged" (nim-test-indent (format nil "let text = \"\"\"hello~%world")) nil)
(check "nested unfinished comment unchanged" (nim-test-indent (format nil "#[ outer #[ nested ]#~%still comment")) nil)
(check "nested comments one token" (mapcar #'pm-token-kind (nim-lex "#[ outer #[ inner ]# end ]# echo 1")) '(:comment :name :number))
(check "documentation comments" (mapcar #'pm-token-kind (nim-lex "##[ outer ##[ inner ]## end ]##")) '(:comment))
(check "raw quote escapes" (mapcar #'pm-token-kind (nim-lex "r\"say \"\"hello\"\"\"")) '(:string))
(check "backtick operator" (mapcar #'pm-token-kind (nim-lex "proc `>>`(x: int) = x")) '(:name :name :operator :name :operator :name :operator :operator :name))
(check "range not a float" (mapcar #'pm-token-value (nim-lex "1..3 0xff'u8")) '("1" "." "." "3" "0xff'u8"))
(check "Unicode byte colors" (let* ((raw (octets "let café = \"你好\"")) (colors (make-array (length raw) :element-type '(unsigned-byte 8))))
                               (nim-highlight nil raw (length raw) colors)
                               (loop for i from (length (octets "let café = ")) below (length raw)
                                     always (= (aref colors i) (color-id :string)))) t)
(check "string is not a definition" (mapcar #'pm-token-kind (nim-lex "\"proc fake() =\"")) '(:string))
(check "keyword normalization preserves first letter" (list (nim-normalize "p_roc") (nim-normalize "Proc")) '("proc" "Proc"))
(check "compact menu includes comment" (let ((*menu-rendering* t) (*menu-filename* "example.nim"))
                                        (mapcar #'first (nim-menu "example" *mode-line-menu*)))
       '("?" "#" "SAVE" "UNDO" "Select" "MORE" "QUIT"))
(check "complete menu includes Build Run" (let ((*menu-full* t) (*menu-rendering* t) (*menu-filename* "example.nim"))
                                          (mapcar #'first (last (nim-menu "example" *full-menu*) 5)))
       '("BUILD" "RUN" "DEF>" "<DEF" "QUIT"))
(check "other menus unchanged" (let ((*menu-rendering* t) (*menu-filename* "file.lisp")) (nim-menu "file" '(a))) '(a))
(check "reload does not duplicate Nim menu" (progn (install-nim-mode) (install-nim-mode)
                                                 (count "nim" *mode-menu-providers* :key #'car :test #'equal)) 1)
#-win32
(check "shell quote handles apostrophe/space" (nim-command-line "a'b c.nim" t "5") "nim c -r --hints:off 'a'\"'\"'b c.nim' 5")
(check "Run saves named buffer and submits compiler command"
       (let* ((names '(buffer-filename get-buffer-name save-buffer buffer-modified-p prompt
                        shell-command-window insert shell-command-run))
              (saved (mapcar (lambda (name) (cons name (symbol-function name))) names))
              (calls nil))
         (unwind-protect
             (progn
               (setf (symbol-function 'buffer-filename) (lambda () "demo.nim")
                     (symbol-function 'get-buffer-name) (lambda () "demo")
                     (symbol-function 'save-buffer) (lambda (name) (push (list :save name) calls) t)
                     (symbol-function 'buffer-modified-p) (lambda () nil)
                     (symbol-function 'prompt) (lambda (&rest args) (declare (ignore args)) "5")
                     (symbol-function 'shell-command-window) (lambda () (push :window calls))
                     (symbol-function 'insert) (lambda (&rest args) (push (cons :insert args) calls))
                     (symbol-function 'shell-command-run) (lambda () (push :run calls)))
               (nim-execute t) (reverse calls))
           (dolist (entry saved) (setf (symbol-function (car entry)) (cdr entry)))))
       (list '(:save "demo") :window (list :insert (nim-command-line "demo.nim" t "5")) :run))
(format t "~D/~D Nim mode tests passed~%" (- *count* *failures*) *count*)
(sb-ext:exit :code (if (zerop *failures*) 0 1))
