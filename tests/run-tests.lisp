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

;;; indentation: the column the last line gets
(defun ind (language &rest lines)
  (indentation-for-text language (format nil "~{~A~^~%~}" lines)))

(check "Lisp: defun body" (ind "Common Lisp" "(defun foo (x)" "x") 2)
(check "Lisp: distinguished argument" (ind "Common Lisp" "(defun foo" "(x)") 4)
(check "Lisp: let bindings line up" (ind "Common Lisp" "(let ((a 1)" "(b 2))") 6)
(check "Lisp: function arguments line up" (ind "Common Lisp" "(foo bar" "baz") 5)
(check "Lisp: if branches line up" (ind "Common Lisp" "(defun f ()" "  (if a" "b") 6)
(check "Lisp: quoted data" (ind "Common Lisp" "'(a b" "c") 2)
(check "Lisp: flet function body" (ind "Common Lisp" "(flet ((f (x)" "x") 9)
(check "Lisp: top level" (ind "Common Lisp" "(defun f ()" "  x)" "y") 0)
(check "Lisp: inside a string, left alone" (ind "Common Lisp" "(defun f ()" "  \"doc" "x") nil)
(check "Lisp: #\( is not a paren" (ind "Common Lisp" "(when x" "  #\\( y)" "z") 0)
(check "Scheme: define" (ind "Scheme" "(define (f x)" "x") 2)
(check "C: block" (ind "C" "int main(void)" "{" "x") 4)
(check "C: statement after if" (ind "C" "int f(void) {" "    if (x)" "y") 8)
(check "C: closing brace" (ind "C" "int f(void) {" "    if (x) {" "        y;" "}") 4)
(check "C: arguments line up" (ind "C" "int f(void) {" "    foo(a," "b") 8)
(check "C: case labels" (ind "C" "f() {" "    switch (x) {" "        case 1:" "y;") 12)
(check "C: preprocessor" (ind "C" "f() {" "#define X" "y;") 4)
(check "C: comment continuation" (ind "C" "f() {" "    /* hi" "*") 5)
(check "C: brace on its own line" (ind "C" "int main(void)" "{") 0)
(check "Python: block" (ind "Python" "def f(x):" "x") 4)
(check "Python: after return" (ind "Python" "def f(x):" "    return x" "y") 0)
(check "Python: else matches its if"
       (ind "Python" "def f(x):" "    if x:" "        y" "else:") 4)
(check "Python: brackets" (ind "Python" "x = foo(a," "b") 8)
(check "Python: inside a docstring, left alone" (ind "Python" "def f():" "    \"\"\"doc" "x") nil)
(check "Ruby: def ... end" (ind "Ruby" "def f" "  x" "end") 0)
(check "Ruby: do |x|" (ind "Ruby" "foo.each do |x|" "y") 2)
(check "Haskell: do" (ind "Haskell" "main = do" "x") 4)
(check "Lean: by" (ind "Lean" "theorem t : p := by" "x") 2)
(check "TeX: \\end" (ind "TeX" "\\begin{itemize}" "  \\item a" "\\end{itemize}") 0)
(check "Prolog: clause body" (ind "Prolog" "foo(X) :-" "bar") 4)
(check "Prolog: next clause" (ind "Prolog" "foo(X) :-" "    bar(X)." "baz") 0)
(check "ML: let" (ind "ML" "let f x =" "x") 2)

;;; the assistant: JSON and proposed code
(check "json-read: object, array, escapes, surrogate pair"
       (json-read "{\"a\":[1,true,null],\"b\":\"x\\n\\u00e9\\ud83d\\ude00\"}")
       (list (list "a" 1 t :null) (cons "b" (format nil "x~%é~A" (code-char #x1F600)))))
(check "json-string escapes"
       (json-string (format nil "a\"b\\c~%~C" (code-char 1)))
       "\"a\\\"b\\\\c\\n\\u0001\"")
(check "json round trip" (json-read (json-string "olá \"q\"")) "olá \"q\"")
(check "proposed code is the first fenced block"
       (proposed-code (format nil "Try:~%```python~%x = 1~%y = 2~%```~%and ```z```"))
       (format nil "x = 1~%y = 2"))
(check "no code block" (proposed-code "just words") nil)
(check "C-c g opens or submits a Codex request"
       (key-binding "C-c g")
       'ask-codex)
(check "Codex is registered in the common assistant machinery"
       (assistant-name (find-assistant :codex))
       "Codex")
(check "C-c t dispatches both discussion windows"
       (key-binding "C-c t")
       'assistant-discussion-tangle)
(check "Codex menu has question and discussion choices"
       (list (not (null (search "Question:" *codex-menu*)))
             (not (null (search "Discussion:" *codex-menu*))))
       '(t t))
(check "old Codex stub key is removed" (key-binding "C-c x") nil)
(check "Codex prompt keeps request and saved source separate"
       (let ((*codex-saved-context* "SOURCE-CONTEXT"))
         (let ((text (codex-prompt "USER-REQUEST")))
           (list (not (null (search "USER REQUEST" text)))
                 (not (null (search "USER-REQUEST" text)))
                 (not (null (search "SOURCE CONTEXT" text)))
                 (not (null (search "SOURCE-CONTEXT" text))))))
       '(t t t t))
(check "Codex CLI is read-only and ephemeral"
       (let ((*codex-working-directory* "/tmp/project/")
             (*codex-model* nil))
         (codex-exec-arguments))
       '("exec" "--sandbox" "read-only" "--ephemeral" "--ignore-rules"
         "--skip-git-repo-check" "--color" "never" "-C" "/tmp/project/" "-"))
(check "Codex program setting is exported"
       (eq (find-symbol "*CODEX-PROGRAM*" '#:sbemacs-user)
           (find-symbol "*CODEX-PROGRAM*" '#:sbemacs))
       t)
(check "Codex installation candidates include the platform default"
       (plusp (length (codex-installation-candidates)))
       t)

;;; key names: Emacs notation -> the C core's names, and back
(check "normalize M-d" (normalize-key "M-d") "esc d")
(check "normalize C-M-f" (normalize-key "C-M-f") "esc C-f")
(check "normalize M-DEL" (normalize-key "M-DEL") "esc backspace")
(check "normalize C-x TAB" (normalize-key "C-x TAB") "C-x C-i")
(check "normalize C-/" (normalize-key "C-/") "C-_")
(check "normalize C-M-SPC" (normalize-key "C-M-SPC") "esc C-space")
(check "normalize leaves core names" (normalize-key "esc [1;5C") "esc [1;5C")
(check "display-key" (mapcar #'display-key '("esc C-f" "esc d" "C-x C-i" "esc backspace" "C-space"))
       '("C-M-f" "M-d" "C-x TAB" "M-DEL" "C-SPC"))
(check "every Emacs key in the keymap" 
       (every (lambda (k) (gethash (normalize-key k) *keymap*))
              '("M-d" "C-M-f" "M-;" "M-:" "C-h" "F1" "C-x h" "C-g" "M-q" "C-t" "C-o"))
       t)

;;; the Emacs editing scanners, on strings
(defun at (function string i &rest args)
  (let ((v (sb-ext:string-to-octets string :external-format :utf-8)))
    (apply function (octets-get v) (length v) i args)))

(check "forward word" (at #'forward-word-position "  foo bar" 0) 5)
(check "backward word" (at #'backward-word-position "foo bar  " 9) 4)
(check "words include UTF-8" (at #'forward-word-position "olá mundo" 0) 4)
(check "forward sentence" (at #'forward-sentence-position "One. Two? Three" 0) 4)
(check "forward sentence, last one" (at #'forward-sentence-position "One. Two" 5) 8)
(check "backward sentence" (at #'backward-sentence-position "One. Two three" 10) 5)
(check "backward sentence from a start" (at #'backward-sentence-position "One. Two" 5) 0)
(check "forward paragraph" (at #'forward-paragraph-position (format nil "a~%b~%~%c~%") 0) 4)
(check "backward paragraph" (at #'backward-paragraph-position (format nil "a~%~%b~%c") 6) 2)
(check "forward sexp: list" (at #'forward-sexp-position "(a (b) \")\") x" 0 t) 11)
(check "forward sexp: symbol" (at #'forward-sexp-position "  foo-bar)" 0 t) 9)
(check "forward sexp: quote and #\\(" (at #'forward-sexp-position "'(a #\\( b)" 0 t) 10)
(check "forward sexp: comment skipped" (at #'forward-sexp-position (format nil "; x (~%(y)") 0 t) 9)
(check "forward sexp: end of list" (at #'forward-sexp-position "a)" 1 t) nil)
(check "backward sexp: list" (at #'backward-sexp-position "x (a (b))" 9 t) 2)
(check "backward sexp: quoted" (at #'backward-sexp-position "x '(a)" 6 t) 2)
(check "backward sexp: string" (at #'backward-sexp-position "x \"a)\"" 6 t) 2)
(check "up list" (up-list-position (octets-get (sb-ext:string-to-octets "(a (b c" :external-format :utf-8)) 6) 3)
(check "down list" (at #'down-list-position "x (y)" 0) 3)
(check "C braces" (at #'forward-sexp-position "{ a('}'); }" 0 nil) 11)
(check "beginning of defun (Lisp)"
       (at #'beginning-of-defun-position (format nil "(defun a ()~%  1)~%(defun b ()~%  2)") 25 t) 17)
(check "end of defun (Lisp)"
       (at #'end-of-defun-position (format nil "(defun a ()~%  1)~%(defun b ()~%  2)") 3 t) 17)
(check "end of defun (C)"
       (at #'end-of-defun-position (format nil "int f()~%{~%  x;~%}~%int g()") 2 nil) 17)
(check "fill text" (fill-text '("aaa bbb" "ccc ddd eee") nil 11)
       (format nil "aaa bbb ccc~%ddd eee"))
(check "fill a comment keeps its prefix" (fill-text '("  ;; aaa bbb" "  ;; ccc") ";;" 14)
       (format nil "  ;; aaa bbb~%  ;; ccc"))
(check "fill prefix" (fill-prefix-of "    # foo" "#") "    # ")
(check "help has one line per key"
       (let ((text (help-text)))
         (list (and (search "  C-x C-s     save" text) t)
               (and (search "Ctrl-c r (hold down" text) t)
               ;; no line wider than 80 columns
               (every (lambda (l) (<= (length l) 80)) (split-lines text))))
       '(t t t))
(check "help scrolling stays inside the page"
       (list (help-scroll 1 -1 100 20) (help-scroll 80 5 100 20) (help-scroll 10 1 100 20))
       '(1 81 11))

(check "every snippet"
       (proposed-snippets (format nil "a~%```lisp~%(f 1)~%```~%b~%```~%(g)~%(h)~%```~%"))
       (list "(f 1)" (format nil "(g)~%(h)")))
(check "the snippet under the cursor"
       (let ((text (format nil "Claude:~%```~%(one)~%```~%and~%```~%(two)~%```~%")))
         (list (snippet-at text 2) (snippet-at text 14) (snippet-at text 24) (snippet-at text 30)))
       '(nil "(one)" nil "(two)"))
(check "an unclosed fence has no snippet" (proposed-snippets (format nil "```~%x")) nil)
(check "the last You: of a discussion"
       (let ((text (format nil "head~%You:~%one~%Claude:~%ok~%~%You:~%two")))
         (subseq text (last-marker-position text "You:")))
       "two")

;;; undo: what the history keeps (applying it needs a buffer)
(defun rec (id kind pos string)
  (let ((v (sb-ext:string-to-octets string :external-format :utf-8)))
    (sb-sys:with-pinned-objects (v)
      (record-change id kind pos (sb-sys:vector-sap v) (length v)))))

(defun history-summary (id)
  (let ((h (gethash id *undo-histories*)))
    (mapcar (lambda (g)
              (mapcar (lambda (c) (list (change-kind c) (change-pos c)
                                        (sb-ext:octets-to-string (change-text c) :external-format :utf-8)))
                      (undo-group-changes g)))
            (undo-history-done h))))

(check "typing joins, a new command starts a group"
       (let ((*command-serial* 500) (*command-buffer-id* 9999))
         (remhash 9999 *undo-histories*)
         (rec 9999 #\i 0 "ab") (rec 9999 #\i 2 "c")
         (incf *command-serial*)
         (rec 9999 #\d 2 "c") (rec 9999 #\d 1 "b")      ; DEL, DEL
         (incf *command-serial*)
         (rec 9999 #\d 0 "x") (rec 9999 #\d 0 "y")      ; C-d, C-d
         (history-summary 9999))
       '(((:delete 0 "xy")) ((:delete 1 "bc")) ((:insert 0 "abc"))))
(check "a change after undo forgets redo; saving remembers the top"
       (let ((*command-serial* 600) (*command-buffer-id* 9998))
         (remhash 9998 *undo-histories*)
         (rec 9998 #\i 0 "a")
         (record-change 9998 #\s 0 (sb-sys:int-sap 0) 0)
         (let ((h (gethash 9998 *undo-histories*)))
           (push (pop (undo-history-done h)) (undo-history-undone h))
           (incf *command-serial*)
           (rec 9998 #\i 0 "b")
           (list (length (undo-history-undone h)) (undo-history-saved-id h) (top-id h))))
       '(0 600 601))
(check "a load forgets the history"
       (progn (record-change 9998 #\r 0 (sb-sys:int-sap 0) 0) (gethash 9998 *undo-histories*))
       nil)
(check "the history stays under *undo-limit*"
       (let ((*undo-limit* 10) (*command-buffer-id* 9997))
         (remhash 9997 *undo-histories*)
         (loop for i from 1 to 5
               do (let ((*command-serial* (+ 700 i))) (rec 9997 #\i 0 "abcd")))
         (let ((h (gethash 9997 *undo-histories*)))
           (list (length (undo-history-done h)) (<= (undo-history-bytes h) 10))))
       '(2 t))

;;; Markdown
(defun md (string) (remove-if (lambda (r) (member (car r) (list +alpha+ +symbol+)))
                              (highlight-string string "x.md")))
(check "Markdown heading" (md "# Title") '((11 . "# Title")))
(check "Markdown emphasis, strong, code, snake_case"
       (md "a **b** *c* `d` e_f_g") '((13 . "**b**") (12 . "*c*") (9 . "`d`")))
(check "Markdown list, link, quotation"
       (md (format nil "- [l](u)~%> q")) '((4 . "- ") (14 . "[l]") (7 . "(u)") (7 . "> q")))
(check "Markdown setext heading and rule"
       (md (format nil "T~%==~%~%---")) (list (cons 11 (format nil "T~%==")) '(7 . "---")))
(check "Markdown code block in its own language"
       (md (format nil "```c~%int x;~%```")) '((7 . "```c") (4 . "int") (7 . "```")))
(check "Markdown multi-line comment"
       (md (format nil "<!-- a~%b -->")) '((8 . "<!-- a") (8 . "b -->")))
(check "Markdown: under the text of the item above"
       (list (ind "Markdown" "- item" "x") (ind "Markdown" "  1. item" "x")
             (ind "Markdown" "- item" "- next") (ind "Markdown" "text" "x"))
       '(2 5 0 0))
(check "Markdown: RET continues a list, an empty item ends it"
       (mapcar (lambda (l) (multiple-value-list (markdown-continuation l)))
               '("- milk" "  2. eggs" "- " "> said" "- [x] done" "plain"))
       '(("- " nil) ("  3. " nil) ("- " :end) ("> " nil) ("- [ ] " nil) (nil)))
(check "M-q keeps a list item's marker and hangs the rest"
       (fill-text '("- aaa bbb ccc" "ddd") nil 12)
       (format nil "- aaa bbb~%  ccc ddd"))

;;; script loading
(check "unchanged scripts are not loaded again"
       (load-scripts :files (script-files *script-directory*)
                     :cache-directory (merge-pathnames "build/test-scripts/" cl-user::*root*))
       nil)
(check "an edited script is loaded again, a new one is picked up"
       (let* ((dir (merge-pathnames "build/test-lisp/" cl-user::*root*))
              (lang (merge-pathnames "languages/zz.lisp" dir)))
         (ensure-directories-exist lang)
         (flet ((write-lang (kw)
                  (with-open-file (o lang :direction :output :if-exists :supersede)
                    (format o "(in-package #:sbemacs)~%(define-language \"ZZ\" :extensions \".zz2\" :keywords '(~S))~%" kw))))
           (write-lang "one")
           (load-scripts :files (list lang) :cache-directory (merge-pathnames "cache/" dir))
           (sleep 1.1)                  ; file-write-date has 1 s resolution
           (write-lang "two")
           (list (length (load-scripts :files (list lang) :cache-directory (merge-pathnames "cache/" dir)))
                 (faces "one two" "x.zz2"))))
       '(1 ((4 . "two"))))

(format t "~&~D/~D tests passed~%" (- *count* *failures*) *count*)
(sb-ext:exit :code (if (zerop *failures*) 0 1))
