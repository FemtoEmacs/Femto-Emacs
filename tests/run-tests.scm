;;;; run-tests.scm -- non-interactive tests (make check)
;;;;
;;;; Port of SBEmacs's tests/run-tests.lisp, plus Chezemax's own checks.
;;;; Run by the editor without a screen:
;;;;
;;;;   ./chezemax --eval '(load "tests/run-tests.scm")'
;;;;
;;;; It checks what does not need a terminal: the highlighter, indentation,
;;;; the editing scanners, undo's history, the mode line, help, the shell
;;;; window, file completion and the assistants' plumbing.  It ends with an
;;;; error when a check fails, so the exit status says it.

(define *failures* 0)
(define *count* 0)
(define *failure-report* (buffer))

(define-macro (check name form expected)
  `(let ((got (trycatch ,form (lambda (e) (list 'error (describe-error e)))))
         (want ,expected))
     (set! *count* (+ *count* 1))
     (unless (equal? got want)
       (set! *failures* (+ *failures* 1))
       (io.write *failure-report*
                 (string-append "FAIL " ,name "\n  expected " (value->string want)
                                "\n  got      " (value->string got) "\n")))))

(define (faces string file)
  "Runs as (face . text), keeping only the interesting faces."
  (filter (lambda (run) (not (memv (car run) (list +alpha+ +symbol+))))
          (highlight-string string file)))

(define (lines . ls) (string-join ls "\n"))

;;; highlighting
(check "C keywords, numbers, comments" (faces "int x = 42; // hi" "a.c")
       '((4 . "int") (6 . "42") (7 . "// hi")))
(check "C block comment and string" (faces "/* a */ \"s\\\"q\"" "a.c")
       '((8 . "/* a */") (9 . "\"s\\\"q\"")))
(check "C char literal with a double quote does not open a string" (faces "c = '\"'; return" "a.c")
       '((9 . "'\"'") (4 . "return")))
(check "identifiers containing digits are not numbers" (faces "x1 utf8 1.5e3" "a.c") '((6 . "1.5e3")))
(check "Lisp: hyphenated words are not keywords" (faces "(defun define-x (let) #\\\" 1)" "a.lisp")
       '((4 . "defun") (4 . "let") (6 . "1")))
(check "Lisp is case-insensitive" (faces "(DEFUN f ())" "a.lisp") '((4 . "DEFUN")))
(check "Lisp block comment" (faces "#| x |# ; y" "a.lisp") '((8 . "#| x |#") (7 . "; y")))
(check "Python triple quotes and single quotes" (faces "def f(): '''doc''' + 'x'" "a.py")
       '((4 . "def") (11 . "f") (9 . "'''doc'''") (9 . "'x'")))
(check "TeX commands" (faces "\\section{A} % c" "a.tex") '((4 . "\\section") (11 . "A") (7 . "% c")))
(check "LaTeX: math, emphasis, references and environment names"
       (faces "$x^2$ \\emph{a} \\cite{k} \\begin{itemize}" "a.tex")
       '((9 . "$x^2$") (4 . "\\emph") (12 . "a") (4 . "\\cite") (14 . "k") (4 . "\\begin") (6 . "itemize")))
(check "LaTeX: a math environment is coloured as math"
       (faces "\\begin{equation}E=mc\\end{equation}" "a.tex")
       '((4 . "\\begin") (6 . "equation") (9 . "E=mc") (4 . "\\end") (6 . "equation")))
(check "HTML: tags, attributes, values, comments, entities"
       (faces "<p class=\"x\">a&amp;b</p><!-- c -->" "a.html")
       '((4 . "<p") (6 . "class") (9 . "\"x\"") (4 . ">") (6 . "&amp;") (4 . "</p>") (7 . "<!-- c -->")))
(check "HTML: text in a heading, in bold and in a link"
       (faces "<h1>T</h1><b>B</b><a href=\"u\">L</a>" "a.html")
       '((4 . "<h1>") (11 . "T") (4 . "</h1><b>") (13 . "B") (4 . "</b><a") (6 . "href") (9 . "\"u\"") (4 . ">") (14 . "L") (4 . "</a>")))
(check "HTML without tags: blocks, items and entities"
       (call-with-values (lambda () (tags-hidden "<h1>Title</h1><p>a &amp; b</p><ul><li>one</li></ul>" html-strip))
         (lambda (text pieces) text))
       "Title\n\na & b\n\n- one\n")
(check "LaTeX without commands: preamble, titles, emphasis, citations, items"
       (call-with-values
           (lambda () (tags-hidden "\\documentclass{article}\n\\begin{document}\n\\section{Intro}Some \\emph{new} work \\cite{k1}.% note\n\\begin{itemize}\\item one\\end{itemize}\n\\end{document}" latex-strip))
         (lambda (text pieces) text))
       "Intro\nSome new work [k1].\n\n- one\n")
(check "the cursor keeps its place in the text, there and back"
       (call-with-values (lambda () (tags-hidden "<p>Hello <b>world</b></p>" html-strip))
         (lambda (text pieces)
           (let ((v (tag-view-source->view pieces 12)))      ; the "w" of world
             (list (byte-substring text v (+ v 5)) (tag-view-view->source pieces v)))))
       '("world" 12))
(check "C-c TAB and C-c l toggle the tags"
       (list (key-binding "C-c TAB") (key-binding "C-c l")) '(html-toggle-tags latex-toggle-tags))
(check "only the view without tags wraps among buffers without a file"
       (list (word-wrap-file-p "*tags-hidden*") (word-wrap-file-p "*scratch*") (word-wrap-file-p "a.tex"))
       '(#t #f #t))
(check "#include is a keyword" (faces "#include <x.h>" "a.h") '((4 . "#include")))
(check "UTF-8 text keeps byte alignment" (faces "/* café */ 7" "a.c") '((8 . "/* café */") (6 . "7")))
(check "unknown extension: numbers and strings only" (faces "if 3 \"q\"" "README") '((6 . "3") (9 . "\"q\"")))
(check "unterminated block comment runs to the end" (faces "/* open" "a.c") '((8 . "/* open")))
(check "a later define-language wins"
       (begin (define-language "Test" 'extensions ".zz" 'keywords '("foo")) (faces "foo bar" "x.zz"))
       '((4 . "foo")))
(check "Scheme scripts are coloured as Scheme" (faces "(define x 1)" "init.scm") '((4 . "define") (6 . "1")))

;;; the Python and Nim modes' highlighters (src/highlight.c)
(check "Python: decorators and builtins" (faces "@dec\nprint(len(x))" "a.py")
       '((14 . "dec") (12 . "print") (12 . "len")))
(check "Python: f-string fields are code" (faces "x = f\"a{y!r}b\" # c" "a.py")
       '((9 . "f\"a") (9 . "r") (9 . "b\"") (7 . "# c")))
(check "Python: match is a keyword only as a statement" (faces "match x:\n    pass\nmatch = 1" "a.py")
       '((4 . "match") (4 . "pass") (6 . "1")))
(check "Nim: definitions and style-insensitive keywords" (faces "proc fooBar*(x: int) = disCard\nlet s = \"q\"" "a.nim")
       '((4 . "proc") (11 . "fooBar") (4 . "disCard") (4 . "let") (9 . "\"q\"")))

;;; init.lsp ports
(check "what-day" (what-day '(2016 9 3)) "Saturday")
(check "what-day 2026-10-05" (what-day '(2026 10 5)) "Monday")
(check "read-string" (read-string "(2016 8 31)") '(2016 8 31))
(check "trim" (trim "  buf  ") "buf")
(check "summarize-kill" (summarize-kill (lines "line one" "line two")) "line one")
(check "buffer picker filters case-insensitive prefixes"
       (buffer-picker-matches "*CO" '("*scratch*" "*codex-chat*" "code.lisp")) '("*codex-chat*"))
(check "buffer picker completes the common prefix"
       (buffer-picker-common-prefix '("alpha.lisp" "alphabet.txt" "Alpine")) "alp")
(check "buffer picker empty completion" (buffer-picker-common-prefix '()) "")
(check "buffer picker accepts CR from the GUI Return key" (buffer-picker-key-action "\r") 'accept)
(check "buffer picker accepts LF from a terminal Return key" (buffer-picker-key-action "\n") 'accept)

;;; the evaluator used by C-x C-e, C-M-x and M-:
(check "eval-string evaluates every form" (eval-string "(define (sq x) (* x x)) (sq 12)") 144)
(check "errors become one-line messages" (describe-error '(error "boom\n   bang")) "Error: boom bang")
(check "eval-for-message shows printed output and the value"
       (eval-for-message "(display \"hi\") 42") "hi => 42")

;;; indentation: the column the last line gets
(define (ind language . ls) (indentation-for-text language (string-join ls "\n")))

(check "Lisp: defun body" (ind "Common Lisp" "(defun foo (x)" "x") 2)
(check "Lisp: distinguished argument" (ind "Common Lisp" "(defun foo" "(x)") 4)
(check "Lisp: let bindings line up" (ind "Common Lisp" "(let ((a 1)" "(b 2))") 6)
(check "Lisp: function arguments line up" (ind "Common Lisp" "(foo bar" "baz") 5)
(check "Lisp: if branches line up" (ind "Common Lisp" "(defun f ()" "  (if a" "b") 6)
(check "Lisp: quoted data" (ind "Common Lisp" "'(a b" "c") 2)
(check "Lisp: flet function body" (ind "Common Lisp" "(flet ((f (x)" "x") 9)
(check "Lisp: top level" (ind "Common Lisp" "(defun f ()" "  x)" "y") 0)
(check "Lisp: inside a string, left alone" (ind "Common Lisp" "(defun f ()" "  \"doc" "x") #f)
(check "Lisp: #\\( is not a paren" (ind "Common Lisp" "(when x" "  #\\( y)" "z") 0)
(check "Scheme: define" (ind "Scheme" "(define (f x)" "x") 2)
(check "Scheme: defcommand" (ind "Scheme" "(defcommand (f)" "x") 2)
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
(check "Python: else matches its if" (ind "Python" "def f(x):" "    if x:" "        y" "else:") 4)
(check "Python: brackets" (ind "Python" "x = foo(a," "b") 8)
(check "Python: inside a docstring, left alone" (ind "Python" "def f():" "    \"\"\"doc" "x") #f)
(check "Ruby: def ... end" (ind "Ruby" "def f" "  x" "end") 0)
(check "Ruby: do |x|" (ind "Ruby" "foo.each do |x|" "y") 2)
(check "Haskell: do" (ind "Haskell" "main = do" "x") 4)
(check "Lean: by" (ind "Lean" "theorem t : p := by" "x") 2)
(check "TeX: \\end" (ind "TeX" "\\begin{itemize}" "  \\item a" "\\end{itemize}") 0)
(check "Prolog: clause body" (ind "Prolog" "foo(X) :-" "bar") 4)
(check "Prolog: next clause" (ind "Prolog" "foo(X) :-" "    bar(X)." "baz") 0)
(check "ML: let" (ind "ML" "let f x =" "x") 2)
(check "Nim: proc body" (ind "Nim" "proc f(x: int) =" "x") 2)

;;; the assistant: JSON and proposed code
(check "json-read: object, array, escapes, surrogate pair"
       (json-read "{\"a\":[1,true,null],\"b\":\"x\\n\\u00e9\\ud83d\\ude00\"}")
       (list (list "a" 1 #t 'null) (cons "b" (string-append "x\né" (string (integer->char #x1F600))))))
(check "json-string escapes" (json-string (string-append "a\"b\\c\n" (string (integer->char 1))))
       "\"a\\\"b\\\\c\\n\\u0001\"")
(check "json round trip" (json-read (json-string "olá \"q\"")) "olá \"q\"")
(check "proposed code is the first fenced block"
       (proposed-code (lines "Try:" "```python" "x = 1" "y = 2" "```" "and ```z```"))
       (lines "x = 1" "y = 2"))
(check "no code block" (proposed-code "just words") #f)
(check "C-c g opens or submits a Codex request" (key-binding "C-c g") 'ask-codex)
(check "Codex is registered in the common assistant machinery" (assistant-name (find-assistant 'codex)) "Codex")
(check "C-c t dispatches both discussion windows" (key-binding "C-c t") 'assistant-discussion-tangle)
(check "C-c f textifies a PDF" (key-binding "C-c f") 'ttfy-menu)
(check "Codex discussion buffer name fits the C core" (<= (length *codex-discussion-buffer*) 16) #t)
(check "old Codex stub key is removed" (key-binding "C-c x") #f)
(check "Codex prompt keeps request and saved source separate"
       (let ((saved *codex-saved-context*))
         (set! *codex-saved-context* "SOURCE-CONTEXT")
         (let ((text (codex-prompt "USER-REQUEST")))
           (set! *codex-saved-context* saved)
           (map (lambda (s) (and (string-search s text) #t))
                '("USER REQUEST" "USER-REQUEST" "SOURCE CONTEXT" "SOURCE-CONTEXT"))))
       '(#t #t #t #t))
(check "Codex CLI is read-only and ephemeral"
       (let ((d *codex-working-directory*) (m *codex-model*))
         (set! *codex-working-directory* "/tmp/project/")
         (set! *codex-model* #f)
         (let ((args (codex-exec-arguments)))
           (set! *codex-working-directory* d) (set! *codex-model* m)
           args))
       '("exec" "--sandbox" "read-only" "--ephemeral" "--ignore-rules"
         "--skip-git-repo-check" "--color" "never" "--cd=/tmp/project/" "-"))
(check "Codex never sends an empty --cd value"
       (let ((d *codex-working-directory*))
         (set! *codex-working-directory* "")
         (let ((arg (find (lambda (a) (starts-with-p "--cd=" a)) (codex-exec-arguments))))
           (set! *codex-working-directory* d)
           (and arg (> (length arg) (length "--cd=")))))
       #t)
(check "Codex installation candidates include the current ChatGPT bundle"
       (and (member "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
                    (codex-installation-candidates)) #t)
       #t)
(check "Codex explicit executable overrides discovery"
       (let ((p *codex-program*))
         (set! *codex-program* "/bin/sh")
         (let ((found (find-codex-program))) (set! *codex-program* p) found))
       "/bin/sh")
(check "Claude runs with its tools disabled"
       (let ((saved run-with-input) (seen #f))
         (set! run-with-input (lambda (program args input . rest) (set! seen args) (values "answer" "" 0)))
         (let ((saved-find claude-program))
           (set! claude-program (lambda () "/bin/true"))
           (claude-cli-ask "Q" "CONTEXT")
           (set! claude-program saved-find))
         (set! run-with-input saved)
         (list (car seen) (cadr seen) (caddr seen) (car (last-pair seen))))
       '("-p" "--tools" "" "Q"))

;;; Markdown wrapping changes display boundaries, never the source bytes.
(define (wrap-test-rows text width)
  (let loop ((text text) (rows '()))
    (if (= 0 (length text)) (reverse rows)
        (let ((end (markdown-wrap-end text width)))
          (loop (byte-substring text end) (cons (byte-substring text 0 end) rows))))))

(check "Markdown wraps before a word" (wrap-test-rows "one two three" 9) '("one two " "three"))
(check "Markdown splits only words wider than the window" (wrap-test-rows "abcdefghij" 4) '("abcd" "efgh" "ij"))
(check "Markdown UTF-8 wraps on character boundaries" (wrap-test-rows "café ação" 6) '("café " "ação"))
(check "Markdown exact-width line includes its newline" (wrap-test-rows "abcd\nef" 4) '("abcd\n" "ef"))
(check "Markdown blank lines survive" (wrap-test-rows "a\n\nb" 4) '("a\n" "\n" "b"))
(check "Markdown tabs use tab stops" (wrap-test-rows "a\tb cd" 9) '("a\tb " "cd"))
(check "Blanks at a break hang at the end of the upper row, as in Emacs"
       (wrap-test-rows "one two  three four" 7) '("one two  " "three " "four"))
(check "A newline after hanging blanks ends the same row"
       (wrap-test-rows "abcd  \nef" 4) '("abcd  \n" "ef"))
(check "Markdown CRLF survives" (wrap-test-rows "abcd\r\nef" 4) '("abcd\r\n" "ef"))
(check "Word wrapping is enabled for Markdown, TeX and plain-text files"
       (map (lambda (name) (markdown-wrap-row name "" 20))
            '("a.md" "a.markdown" "a.mdown" "a.mkd" "a.tex" "a.sty" "a.bib" "a.lisp" "a.c" "a.txt" ""))
       '(-1 -1 -1 -1 -1 -1 -1 0 0 -1 0))
(check "TeX display callback wraps words and preserves commands and source bytes"
       (let* ((text "\\section{Introdução} café ação e texto")
              (end (markdown-wrap-row "document.tex" text 26)))
         (list (byte-substring text 0 end) (string=? text (apply string-append (wrap-test-rows text 26)))))
       '("\\section{Introdução} café " #t))
(check "number->string keeps the decimals of reals"
       (map number->string (list 0.8 -3.5 100 2.0 1e20)) '("0.8" "-3.5" "100" "2.0" "1e+20"))
(check "Plot labels have at most two decimals"
       (map fmt-num (list 0.8 2.7 24 -0.25 0.5 0.006)) '("0.8" "2.7" "24" "-0.25" "0.5" "0.01"))
(check "Plot tables with # outside strings are refused (#. would run code)"
       (map safe-sexp-text? '("(estimator-plot :title \"#1\")" "(estimator-plot #.(boom))" "(a ; # here\n b)"))
       '(#t #f #t))
(define *km-sample* "text\n```lisp\n(estimator-plot :title \"T\"\n  :axes (:x (:label \"Months\" :limits (0 12)) :y (:unit proportion :limits (0 1)))\n  :cohorts ((:id a :label \"Arm A\" :style (:color \"red\")))\n  :curves ((:cohort a :steps ((:kind :start :time 0 :survival 1.0) (:kind :drop :time 2 :from 1.0 :to 0.9)\n    (:kind :drop :time 5 :from 0.8 :to 0.75) (:kind :end :time 11 :survival 0.75))\n    :censors ((:time 3 :survival 0.9))\n    :unresolved ((:from-time 0 :to-time 1 :reason \"dense\") (:from-time 0 :to-time 4 :feature :censors))))\n  :numbers-at-risk (:times (0 6 12) :rows ((:cohort a :counts (20 12 5)))))\n```\nafter\n")
(define (km-sample-lines)
  (let ((span (form-at *km-sample* 30)))
    (km-drawing (read-sketch-form (string.sub *km-sample* (car span) (cdr span))))))
(check "C-c p finds the plot table only with the cursor in it"
       (let ((end (sexp-end *km-sample* 13)))
         (list (car (form-at *km-sample* 13)) (car (form-at *km-sample* 40)) (car (form-at *km-sample* end))
               (form-at *km-sample* 0) (form-at *km-sample* 5) (form-at *km-sample* (+ end 2))
               (form-at *km-sample* (- (length *km-sample*) 2))))
       '(13 13 13 #f #f #f #f))
(check "Kaplan-Meier steps become horizontal and vertical segments"
       (filter (lambda (l) (string-prefix? "seg" l)) (km-sample-lines))
       '("seg 0 0.0 1.0 2.0 1.0" "seg 0 2.0 1.0 2.0 0.9" "seg 0 2.0 0.9 5.0 0.9"
         "seg 0 5.0 0.8 5.0 0.75" "seg 0 5.0 0.75 11.0 0.75"))
(check "The plot keeps the legend colour, censor marks, curve gaps and numbers at risk"
       (filter (lambda (l) (member (car (string-split l " ")) '("series" "censor" "gap" "risk" "risktimes")))
               (km-sample-lines))
       '("series 0 214 39 40 0 Arm A" "censor 0 3.0 0.9" "gap 0 0.0 1.0 dense"
         "risktimes 0.0 6.0 12.0" "risk 0 20 12 5"))
(check "A drop that does not start where the curve was is reported, not repaired"
       (and (find (lambda (l) (string-search "the drop starts at 0.8, but the curve was at 0.9" l)) (km-sample-lines)) #t)
       #t)
(define *km-landmarks* "(estimator-plot :axes (:x (:limits (0 24)) :y (:limits (0 1)))\n  :cohorts ((:id a :label \"A\") (:id b :label \"B\"))\n  :curves ((:cohort (a b) :steps ((:kind :start :time 0 :survival 1.0) (:kind :landmark :time 6 :survival 0.8)))\n    (:cohort a :steps ((:kind :landmark :time 12 :survival 0.7) (:kind :end :time 18 :survival 0.6)))\n    (:cohort a :steps ((:kind :landmark :time 20 :survival 0.55))))\n  :statistics ((:kind :median :cohort a :value 15 :unit month) (:kind :median :cohort b :value :not-reached)\n    (:kind :p-value :comparison \"A vs B\" :value \"< .001\") (:kind :p-value :value \".2\")))")
(define (km-landmark-lines) (km-drawing (read-sketch-form *km-landmarks*)))
(check "Sampled landmarks are dots joined by dotted links, never steps"
       (filter (lambda (l) (member (car (string-split l " ")) '("seg" "link" "point"))) (km-landmark-lines))
       '("link 2 0.0 1.0 6.0 0.8" "point 2 6.0 0.8"
         "link 0 12.0 0.7 18.0 0.6" "point 0 12.0 0.7" "point 0 18.0 0.6" "point 0 20.0 0.55"))
(check "A trace shared by cohorts is labelled with all of them; a cohort is listed once"
       (filter (lambda (l) (string-prefix? "series" l)) (km-landmark-lines))
       '("series 2 60 60 60 0 A / B (overlapping)" "series 0 31 119 180 0 A"))
(check "Statistics given as rows: medians and p-values in words"
       (filter (lambda (l) (string-prefix? "stat" l)) (km-landmark-lines))
       '("stat Median, A: 15 month" "stat Median, B: not reached" "stat p < .001 (A vs B)" "stat p = .2"))
(define *table-sample* "(data-table :schema schememax/data-table/1 :table \"1\" :caption \"Cohort\"\n  :provenance (:source \"p.pdf\" :pdf-page 3) :basis :printed :stub \"Characteristic\"\n  :columns ((:id c1 :label \"A, No. (%)\") (:id c2 :label \"p\"))\n  :rows ((:label \"Stage\" :cells (nil (:< 0.001))\n          :rows ((:label \"Local\" :cells ((:count 18053 :percent 82.3) nil))))\n         (:label \"Median\" :cells ((:value 33.0 :ci (141 :na)) \"—\")))\n  :notes (\"NA, not reached.\") :abbreviations nil)")
(check "C-c p finds a data table"
       (let ((span (form-at *table-sample* 40))) (and span (= (car span) 0))) #t)
(check "A data table becomes header and row records, cells as printed"
       (table-drawing *table-sample*)
       (list "table 1" "title Table 1. Cohort" "subtitle [p.pdf, PDF page 3]"
             "header\tCharacteristic\tA, No. (%)\tp"
             "row 0 1\tStage\t\t<0.001" "row 1 0\tLocal\t18,053 (82.3)\t"
             "row 0 0\tMedian\t33.0 (141–NA)\t—" "remark NA, not reached."))
(check "Without a display a data table is aligned text"
       (let ((s (text-table (table-drawing *table-sample*))))
         (list (and (string-search "  Local         18,053 (82.3)" s) #t)
               (and (string-search "Median          33.0 (141–NA)" s) #t)))
       '(#t #t))
(check "Without a display the plot is a character sketch with a legend"
       (let ((s (text-plot (km-sample-lines))))
         (list (and (string-search "A = Arm A" s) #t) (and (string-search "Months" s) #t)))
       '(#t #t))
(check "The help page has an M-x commands section naming toggle-word-wrap"
       (let ((text (help-text)))
         (and (string-search "M-x commands" text) (string-search "toggle-word-wrap" text) #t))
       #t)
(check "Markdown rows preserve all source bytes at every width"
       (let ((text "# café\n\n  - ação and averylongword\n```yaml\n\ta: b\n```\n"))
         (let loop ((w 1))
           (or (> w 35)
               (and (string=? text (apply string-append (wrap-test-rows text w))) (loop (+ w 1))))))
       #t)

(check "comment marker in Scheme string is ignored"
       (line-comment-position "(display \";\") ; real" 0 "a.scm") 14)
(check "C comment marker in string is ignored"
       (line-comment-position "puts(\"//\"); // real" 0 "a.c") 12)
(check "comment search respects the current line"
       (line-comment-position "; old\n(foo)" 6 "a.scm") #f)

(check "buffer menu resolves full long names"
       (bufm-name-from-line "   1234567 a very long buffer name.scm /tmp/file" '("a very long buffer name.scm" "a very"))
       "a very long buffer name.scm")
(check "buffer menu resolves Unicode names"
       (bufm-name-from-line "        10 café.scm         /tmp/café.scm" '("café.scm")) "café.scm")
(check "buffer menu refuses an unknown listing name"
       (bufm-name-from-line "        10 missing.scm      /tmp/file" '("known.scm")) "")

(check "format-time accepts modern timestamps"
       (string-length (format-time 1739365794)) 16)
(check "format-time accepts timestamps beyond signed int32"
       (string-length (format-time 2200000000)) 16)
(check "format-time keeps epoch and negative timestamps"
       (map (lambda (stamp) (string-length (format-time stamp))) '(0 -1)) '(16 16))
(check "format-time rejects non-integers"
       (trycatch (begin (format-time "not a timestamp") #f) (lambda (e) #t)) #t)

(check "shell completion respects open quotes"
       (shell-completion-context "cd \"my dir/fi") '("cd " "my dir/fi" ("cd")))
(check "shell completion respects escaped spaces"
       (shell-completion-context "cat my\\ file") '("cat " "my file" ("cat")))
(check "shell completion resets command after pipe"
       (shell-completion-context "echo x | cd ~/ed") '("echo x | cd " "~/ed" ("cd")))
(check "shell completion escapes spaces and metacharacters"
       (shell-escape-token "my file;$x") "my\\ file\\;\\$x")
(check "shell completion common prefix preserves Unicode"
       (shell-common-prefix '("cat café-a" "cat café-b")) "cat café-")

;;; key names: Emacs notation -> the C core's names, and back
(check "normalize M-d" (normalize-key "M-d") "esc d")
(check "normalize C-M-f" (normalize-key "C-M-f") "esc C-f")
(check "normalize M-DEL" (normalize-key "M-DEL") "esc backspace")
(check "normalize C-x TAB" (normalize-key "C-x TAB") "C-x C-i")
(check "normalize C-/" (normalize-key "C-/") "C-_")
(check "normalize C-M-SPC" (normalize-key "C-M-SPC") "esc C-space")
(check "normalize leaves core names" (normalize-key "esc [1;5C") "esc [1;5C")
(check "display-key" (map display-key '("esc C-f" "esc d" "C-x C-i" "esc backspace" "C-space"))
       '("C-M-f" "M-d" "C-x TAB" "M-DEL" "C-SPC"))
(check "every Emacs key in the keymap"
       (every (lambda (k) (and (get *keymap* (normalize-key k) #f) #t))
              '("M-d" "C-M-f" "M-;" "M-:" "C-h" "F1" "C-x h" "C-g" "M-q" "C-t" "C-o" "M-w" "C-/"))
       #t)

;;; the Emacs editing scanners, on strings
(define (at f string i . args) (apply f (octets-get string) (length string) i args))

(check "forward word" (at forward-word-position "  foo bar" 0) 5)
(check "backward word" (at backward-word-position "foo bar  " 9) 4)
(check "words include UTF-8" (at forward-word-position "olá mundo" 0) 4)
(check "forward sentence" (at forward-sentence-position "One. Two? Three" 0) 4)
(check "forward sentence, last one" (at forward-sentence-position "One. Two" 5) 8)
(check "backward sentence" (at backward-sentence-position "One. Two three" 10) 5)
(check "backward sentence from a start" (at backward-sentence-position "One. Two" 5) 0)
(check "forward paragraph" (at forward-paragraph-position (lines "a" "b" "" "c" "") 0) 4)
(check "backward paragraph" (at backward-paragraph-position (lines "a" "" "b" "c") 6) 2)
(check "forward sexp: list" (at forward-sexp-position "(a (b) \")\") x" 0 #t) 11)
(check "forward sexp: symbol" (at forward-sexp-position "  foo-bar)" 0 #t) 9)
(check "forward sexp: quote and #\\(" (at forward-sexp-position "'(a #\\( b)" 0 #t) 10)
(check "forward sexp: comment skipped" (at forward-sexp-position (lines "; x (" "(y)") 0 #t) 9)
(check "forward sexp: end of list" (at forward-sexp-position "a)" 1 #t) #f)
(check "forward sexp: comma advances" (at forward-sexp-position "a,b" 1 #f) 2)
(check "forward sexp: semicolon advances" (at forward-sexp-position "a;b" 1 #f) 2)
(check "forward sexp: trailing comma" (at forward-sexp-position "a," 1 #f) 2)
(check "backward sexp: comma advances" (at backward-sexp-position "a,b" 2 #f) 1)
(check "backward sexp: semicolon advances" (at backward-sexp-position "a;b" 2 #f) 1)
(check "Lisp comma remains an unquote prefix" (at forward-sexp-position ",@foo" 0 #t) 5)
(check "punctuation motion always advances"
       (every (lambda (text)
                (let ((get (octets-get text)) (size (length text)))
                  (let loop ((pos 0))
                    (if (= pos size) #t
                        (let ((next (forward-sexp-position get size pos #f)))
                          (and next (> next pos) (loop next)))))))
              '("one,two;three" "a,,b" "café,ação" "; ,")) #t)
(check "backward sexp: list" (at backward-sexp-position "x (a (b))" 9 #t) 2)
(check "backward sexp: quoted" (at backward-sexp-position "x '(a)" 6 #t) 2)
(check "backward sexp: string" (at backward-sexp-position "x \"a)\"" 6 #t) 2)
(check "up list" (up-list-position (octets-get "(a (b c") 6) 3)
(check "down list" (at down-list-position "x (y)" 0) 3)
(check "C braces" (at forward-sexp-position "{ a('}'); }" 0 #f) 11)
(check "beginning of defun (Lisp)"
       (at beginning-of-defun-position (lines "(defun a ()" "  1)" "(defun b ()" "  2)") 25 #t) 17)
(check "end of defun (Lisp)"
       (at end-of-defun-position (lines "(defun a ()" "  1)" "(defun b ()" "  2)") 3 #t) 17)
(check "end of defun (C)" (at end-of-defun-position (lines "int f()" "{" "  x;" "}" "int g()") 2 #f) 17)
(check "fill text" (fill-text '("aaa bbb" "ccc ddd eee") #f 11) (lines "aaa bbb ccc" "ddd eee"))
(check "fill a comment keeps its prefix" (fill-text '("  ;; aaa bbb" "  ;; ccc") ";;" 14)
       (lines "  ;; aaa bbb" "  ;; ccc"))
(check "fill prefix" (fill-prefix-of "    # foo" "#") "    # ")
(check "help has one line per key"
       (let ((text (help-text)))
         (list (and (string-search "  C-x C-s     save" text) #t)
               (and (string-search "Ctrl-c r (hold down" text) #t)
               (every (lambda (l) (<= (string-length l) 80)) (split-lines text))))
       '(#t #t #t))
(check "help scrolling stays inside the page"
       (list (help-scroll 1 -1 100 20) (help-scroll 80 5 100 20) (help-scroll 10 1 100 20))
       '(1 81 11))
(check "every snippet" (proposed-snippets (lines "a" "```lisp" "(f 1)" "```" "b" "```" "(g)" "(h)" "```" ""))
       (list "(f 1)" (lines "(g)" "(h)")))
(check "the snippet under the cursor"
       (let ((text (lines "Claude:" "```" "(one)" "```" "and" "```" "(two)" "```" "")))
         (list (snippet-at text 2) (snippet-at text 14) (snippet-at text 24) (snippet-at text 30)))
       '(#f "(one)" #f "(two)"))
(check "an answer can propose a buffer, with <<FILE>> for the whole file"
       (proposed-buffers (lines "Here:" "```new-buffer naia-questions" "1. Why?" "" "<<FILE>>" "```"))
       '(("naia-questions" . "1. Why?\n\n<<FILE>>")))
(check "a proposed buffer is not code to insert"
       (proposed-snippets (lines "```new-buffer q" "1. Why?" "```" "```lisp" "(f)" "```")) '("(f)"))
(check "a buffer name is cut to the 16 characters the core keeps"
       (car (car (proposed-buffers (lines "```new-buffer sarcoma-naia-questions" "x" "```"))))
       "sarcoma-naia-que")
(check "<<FILE>> becomes the file's text"
       (expand-file-placeholder "1. Why?\n<<FILE>>\nend" "paper line 1\npaper line 2")
       "1. Why?\npaper line 1\npaper line 2\nend")
(check "both assistants are told how to propose a buffer"
       (list (and (string-search "```new-buffer NAME" *assistant-instructions*) #t)
             (and (string-search "```new-buffer NAME" *codex-instructions*) #t))
       '(#t #t))
(check "a whole paper fits in what the assistants are sent" (>= *assistant-context-bytes* 200000) #t)
(check "the assistants never see their own windows or the help page"
       (every (lambda (n) (member n *private-buffer-names*))
              (list *assistant-buffer* *claude-request-buffer* *claude-discussion-buffer*
                    *codex-answer-buffer* *codex-request-buffer* *codex-discussion-buffer* *help-buffer*))
       #t)
(check "a discussion window has no [?]: it is one of the assistants' windows"
       (and (ai-menu-buffer-p *claude-discussion-buffer*) (ai-menu-buffer-p *codex-discussion-buffer*) #t) #t)
(check "an unclosed fence has no snippet" (proposed-snippets (lines "```" "x")) '())
(check "the last You: of a discussion"
       (let ((text (lines "head" "You:" "one" "Claude:" "ok" "" "You:" "two")))
         (byte-substring text (last-marker-position text "You:")))
       "two")

;;; undo: what the history keeps (applying it needs a buffer)
(define (history-summary id)
  (map (lambda (g) (map (lambda (c) (list (change-kind c) (change-pos c) (change-text c))) (undo-group-changes g)))
       (undo-history-done (get *undo-histories* id #f))))

(check "typing joins, a new command starts a group"
       (begin
         (set! *command-serial* 500) (set! *command-buffer-id* 9999)
         (table-remove! *undo-histories* 9999)
         (record-change 9999 105 0 "ab") (record-change 9999 105 2 "c")
         (set! *command-serial* (+ *command-serial* 1))
         (record-change 9999 100 2 "c") (record-change 9999 100 1 "b")      ; DEL, DEL
         (set! *command-serial* (+ *command-serial* 1))
         (record-change 9999 100 0 "x") (record-change 9999 100 0 "y")      ; C-d, C-d
         (history-summary 9999))
       '(((delete 0 "xy")) ((delete 1 "bc")) ((insert 0 "abc"))))
(check "a change after undo forgets redo; saving remembers the top"
       (begin
         (set! *command-serial* 600) (set! *command-buffer-id* 9998)
         (table-remove! *undo-histories* 9998)
         (record-change 9998 105 0 "a")
         (record-change 9998 115 0 "")
         (let ((h (get *undo-histories* 9998 #f)))
           (vector-set! h 1 (cons (car (undo-history-done h)) (undo-history-undone h)))
           (vector-set! h 0 (cdr (undo-history-done h)))
           (set! *command-serial* (+ *command-serial* 1))
           (record-change 9998 105 0 "b")
           (list (length (undo-history-undone h)) (undo-history-saved-id h) (top-id h))))
       '(0 600 601))
(check "a load forgets the history"
       (begin (record-change 9998 114 0 "") (get *undo-histories* 9998 #f))
       #f)
(check "the history stays under *undo-limit*"
       (let ((limit *undo-limit*))
         (set! *undo-limit* 10) (set! *command-buffer-id* 9997)
         (table-remove! *undo-histories* 9997)
         (do ((i 1 (+ i 1))) ((> i 5)) (set! *command-serial* (+ 700 i)) (record-change 9997 105 0 "abcd"))
         (set! *undo-limit* limit)
         (let ((h (get *undo-histories* 9997 #f)))
           (list (length (undo-history-done h)) (<= (undo-history-bytes h) 10))))
       '(2 #t))

;;; Markdown
(define (md string) (faces string "x.md"))
(check "Markdown heading" (md "# Title") '((11 . "# Title")))
(check "Markdown emphasis, strong, code, snake_case" (md "a **b** *c* `d` e_f_g")
       '((13 . "**b**") (12 . "*c*") (9 . "`d`")))
(check "Markdown list, link, quotation" (md (lines "- [l](u)" "> q"))
       '((4 . "- ") (14 . "[l]") (7 . "(u)") (7 . "> q")))
(check "Markdown setext heading and rule" (md (lines "T" "==" "" "---"))
       (list (cons 11 (lines "T" "==")) '(7 . "---")))
(check "Markdown code block in its own language" (md (lines "```c" "int x;" "```"))
       '((7 . "```c") (4 . "int") (7 . "```")))
(check "Markdown multi-line comment" (md (lines "<!-- a" "b -->")) '((8 . "<!-- a") (8 . "b -->")))
(check "Markdown: under the text of the item above"
       (list (ind "Markdown" "- item" "x") (ind "Markdown" "  1. item" "x")
             (ind "Markdown" "- item" "- next") (ind "Markdown" "text" "x"))
       '(2 5 0 0))
(check "Markdown: code in ``` indented by the fence's language"
       (list (ind "Markdown" "Text." "```Scheme" "(define (fib n)" "    (if (< n 2) 1" "x")
             (ind "Markdown" "```scheme" "x")
             (ind "Markdown" "```c" "int f(void) {" "x")
             (ind "Markdown" "```python" "def f(x):" "x"))
       '(8 0 4 4))
(check "Markdown: code in ``` with no known language, like the line above"
       (list (ind "Markdown" "```" "    foo" "x") (ind "Markdown" "```text" "    foo" "x"))
       '(4 4))
(check "Markdown: the language of a ``` block, from its first line"
       (let* ((t (lines "Text." "```Scheme" "(foo)" "```" "x"))
              (in (md-code-place t (string-search "(foo)" t)))
              (out (md-code-place t (- (length t) 1))))
         (list (language-name (car in)) (cdr in) out))
       (list "Scheme" (string-search "(foo)" (lines "Text." "```Scheme" "(foo)")) #f))
(check "Markdown: after the block, prose again"
       (ind "Markdown" "```scheme" "(define x" "  1)" "```" "x") 0)
(check "Markdown: RET continues a list, an empty item ends it"
       (map (lambda (l) (call-with-values (lambda () (markdown-continuation l)) list))
            '("- milk" "  2. eggs" "- " "> said" "- [x] done" "plain"))
       '(("- " #f) ("  3. " #f) ("- " end) ("> " #f) ("- [ ] " #f) (#f #f)))
(check "M-q keeps a list item's marker and hangs the rest" (fill-text '("- aaa bbb ccc" "ddd") #f 12)
       (lines "- aaa bbb" "  ccc ddd"))

;;; script loading
(check "every script loads" (reverse *script-errors*) '())
(check "C-x C-r keeps the kill ring and key bindings"
       (let ((kills *kill-ring*))
         (set! *kill-ring* '("kept"))
         (load (string-append *scheme-dir* "/core.scm"))
         (let ((r (list *kill-ring* (key-binding "C-c r"))))
           (set! *kill-ring* kills)
           r))
       '(("kept") ask-claude))

;;; The mode line (menu.scm): decode what C would paint
(define (decoded-mode-line name line flags cols)
  "The pieces as (text face-id clickable)."
  (let ((encoded (mode-line-pieces name "" name line flags cols)))
    (and encoded
         (map (lambda (piece)
                (let* ((parts (string-split piece (string (integer->char 31)))))
                  (list (caddr parts) (string->number (car parts)) (> (string->number (cadr parts)) 0))))
              (string-split encoded (string (integer->char 30)))))))

(define (mode-line-string name line flags cols)
  (apply string-append (map car (decoded-mode-line name line flags cols))))

(check "compact status: QUIT ends each width with a safe blank gap"
       (every (lambda (width)
                (let ((text (mode-line-string "teste.lisp" 3 1 width)))
                  (and (= (string-length text) width)
                       (string-search "[?][SAVE][UNDO][Select][MORE]" text)
                       (equal? (substring text (- width 9) width) "   [QUIT]"))))
              '(80 95 120))
       #t)
(check "mode line: a long name is shortened at the front, buttons kept"
       (let ((s (mode-line-string "/home/nia/projects/fibonacci/src/fib.lisp" 1 3 90)))
         (list (substring s 0 3) (and (string-search "src/fib.lisp*, L. 1" s) #t)
               (and (string-search "[QUIT]" s) #t) (<= (string-length s) 90)))
       (list "..." #t #t #t))
(check "mode line: a narrow window drops buttons from the right"
       (let ((s (mode-line-string "teste.lisp" 1 1 60)))
         (list (and (string-search "[?]" s) #t) (and (string-search "[QUIT]" s) #t) (<= (string-length s) 60)))
       '(#t #t #t))
(check "mode line: QUIT remains visible in narrow windows"
       (let loop ((w 40)) (or (> w 80) (and (string-search "[QUIT]" (mode-line-string "test.py" 1 1 w)) (loop (+ w 1)))))
       #t)
(check "mode line: MORE survives growing line numbers"
       (every (lambda (line)
                (let loop ((w 40))
                  (or (> w 80) (and (string-search "[MORE]" (mode-line-string "long-python-file.py" line 1 w)) (loop (+ w 1))))))
              '(1 99 100 999 1000 1000000))
       #t)
(check "MORE content contains every supplied action"
       (let ((text (more-menu-text '(("?" "C-h") ("QUIT" "C-x C-c") ("#" "M-;") ("DEF>" python-next-definition)))))
         (every (lambda (s) (string-search s text))
                '("Help" "Quit" "Comment / uncomment" "Next definition" "C-x C-c" "python-next-definition")))
       #t)
(check "menu: QUIT uses the normal quit command" (cadr (assoc "QUIT" *mode-line-menu*)) "C-x C-c")
(check "mode line: the name and the buttons are clickable, the rest is not"
       (map caddr (list-head (decoded-mode-line "a.txt" 1 1 120) 4))
       '(#t #f #t #t))
(check "mode line: modified and other window marks" (substring (mode-line-string "a.txt" 7 2 120) 0 12)
       "a.txt*, L. 7")
(check "mode line: a buffer with a hint shows the hint, no buttons"
       (begin (set-buffer-hint "*x*" "C-c t tangle")
              (let ((s (mode-line-string "*x*" 2 1 120))) (set-buffer-hint "*x*" #f) s))
       "*x*, L. 2 [?] C-c t tangle")
(check "mode line: a name over 18 characters is always shortened"
       (let ((s (mode-line-string "a-rather-long-name.lisp" 1 1 200))) (byte-substring s 0 (string-search "," s)))
       "...-long-name.lisp")
(check "mode line: a name of 18 characters is not"
       (let ((s (mode-line-string "eighteen-chars.txt" 1 1 200))) (byte-substring s 0 (string-search "," s)))
       "eighteen-chars.txt")
(check "mode line: no buttons, the C core's mode line"
       (let ((menu *mode-line-menu*))
         (set! *mode-line-menu* '())
         (let ((r (mode-line-pieces "a" "" "a" 1 1 80))) (set! *mode-line-menu* menu) r))
       #f)
(check "file info: lines and words"
       (call-with-values (lambda () (count-lines-words (lines "one two" "three" "four five six"))) list)
       '(3 6))

;;; File name completion: no shell, the same everywhere
(define *complete-dir* "/tmp/chezemax-test-complete")
(run-program "/bin/sh" (list "-c" (string-append "rm -rf " *complete-dir* " && mkdir -p " *complete-dir*
                                                 "/sub " *complete-dir* "/.hidden && cd " *complete-dir*
                                                 " && for f in a.lisp ab.txt Makefile 'with space.md' .dot sub/x.lisp; do echo x > \"$f\"; done"))
             "" 10 #f)
(check "complete: a prefix" (file-name-completions "a" *complete-dir*) '("a.lisp" "ab.txt"))
(check "complete: everything, folders end in /, hidden names left out"
       (file-name-completions "" *complete-dir*) '("Makefile" "a.lisp" "ab.txt" "sub/" "with space.md"))
(check "complete: hidden names when a dot is typed" (file-name-completions "." *complete-dir*) '(".dot" ".hidden/"))
(check "complete: inside a folder" (file-name-completions "sub/" *complete-dir*) '("sub/x.lisp"))
(check "complete: wild cards" (file-name-completions "*.lisp" *complete-dir*) '("a.lisp"))
(check "complete: a name with a space" (file-name-completions "wi" *complete-dir*) '("with space.md"))
(check "complete: nothing" (file-name-completions "zz" *complete-dir*) '())
(check "complete: a folder that does not exist" (file-name-completions "nowhere/a" *complete-dir*) '())

(check "mode line: a window with buttons of its own"
       (list (mode-line-string "*shell-command*" 1 1 120) (map caddr (decoded-mode-line "*shell-command*" 1 1 120)))
       (list "*shell-command*, L. 1 [?][SEND - C-c s][CLOSE - C-c q]" '(#t #f #t #t #t)))
(check "selection status replaces Select with COPY and DELETE"
       (begin (set! *menu-region* #t)
              (let ((r (map car (mode-line-buttons "a")))) (set! *menu-region* #f) r))
       '("?" "SAVE" "UNDO" "COPY" "DELETE" "MORE" "TTFY" "QUIT"))
(check "help has exactly Keybindings, ChatGPT and Claude"
       (let ((saved choose-menu) (captured #f))
         (set! choose-menu (lambda (buttons) (set! captured buttons) #f))
         (help-menu)
         (set! choose-menu saved)
         captured)
       '(("Keybindings" menu-keybindings) ("ChatGPT" menu-chatgpt) ("Claude" menu-claude)))
(check "ChatGPT and Claude choices route to their existing assistants"
       (let ((saved (map (lambda (s) (cons s (top-level-value s)))
                         '(get-buffer-name assistant-buffer-p call-in-window-of ask-codex ask-claude)))
             (calls '()))
         (set! get-buffer-name (lambda () "test.py"))
         (set! assistant-buffer-p (lambda (name) #f))
         (set! call-in-window-of (lambda (name f) (f)))
         (set! ask-codex (lambda () (set! calls (cons 'codex calls))))
         (set! ask-claude (lambda () (set! calls (cons 'claude calls))))
         (menu-chatgpt) (menu-claude)
         (for-each (lambda (p) (set-top-level-value! (car p) (cdr p))) saved)
         (reverse calls))
       '(codex claude))
(check "AI request menu has SEND/CLOSE without global help"
       (begin (set-buffer-menu "*codex-request*" '(("SEND" "C-c g") ("CLOSE" close-assistant-windows)))
              (let ((text (mode-line-string "*codex-request*" 1 1 80)))
                (set-buffer-menu "*codex-request*" '())
                (and (string-search "[SEND][CLOSE]" text) (not (string-search "[?]" text)) #t)))
       #t)
(check "assistant chooser offers h/q/d only"
       (let ((saved choose-menu) (choices #f))
         (set! choose-menu (lambda (buttons) (set! choices buttons) "q"))
         (let ((r (choose-assistant-menu "Ask Claude"))) (set! choose-menu saved) (list r choices)))
       '("q" (("h Hints" "h") ("q Question" "q") ("d Discussion" "d"))))
(check "Python files get [#] and INDENT on the mode line"
       (let ((s (mode-line-pieces "a.py" "a.py" "a.py" 1 1 200)))
         (and (string-search "[#]" s) #t))
       #t)

;;; M-! (shell.scm)
(check "shell: one line stays as it is" (shell-command-line "ls -l") "ls -l")
(check "shell: line breaks become continuations" (shell-command-line (lines "echo one" "  two" "three"))
       (lines "echo one \\" "  two \\" "three"))
(check "shell: a line ending in \\ is not doubled; blank lines go" (shell-command-line (lines "echo a \\" "" "b" ""))
       (lines "echo a \\" "b"))
(check "shell: a continued command runs as one"
       (call-with-values (lambda () (run-shell (shell-command-line (lines "echo one" "two")) #f)) list)
       (list "one two\n" 0))
(check "shell: a failure keeps its message and status"
       (call-with-values (lambda () (run-shell "ls /no/such/folder" #f))
         (lambda (out code) (list (> (length out) 0) (not (= code 0)))))
       '(#t #t))
(check "shell: the transcript shows the command, then the output"
       (shell-transcript (lines "echo a" "b") "a b\n" 0) (lines "$ echo a" "  b" "a b" ""))
(check "shell: and the exit status of a failure" (shell-transcript "false" "" 1)
       (lines "$ false" "[exit status 1]" ""))

;;; Chezemax's own: TTFY
(check "TTFY guidelines are installed" (and (string-search "Kaplan-Meier" (ttfy-read-guidelines)) #t) #t)
(check "TTFY failure classification"
       (list (ttfy-failed? "TTFY failed: unreadable") (ttfy-failed? "Assistant failed (timeout)")
             (ttfy-failed? "# A converted paper"))
       '(#t #t #f))
(check "TTFY providers" (map ttfy-choice-provider '(1 2)) '("codex" "claude"))
(check "TTFY finds pipe tables, not fenced ones"
       (ttfy-pipe-tables (split-lines "```\n| a | b |\n|---|---|\n```\n\n| x | y |\n|---|---|\n| 1 | 2 |\n| no rule |\n"))
       '((5 . 8)))
(check "TTFY: the same table in two layouts comes out the same"
       (equal? (ttfy-canonical "(data-table :table \"2\"\n    :rows ((:label \"a\" :cells (33.0 (:< 0.001)))\n (:label \"b\" :cells (nil :na))))")
               (ttfy-canonical "(data-table\n :table \"2\" :rows ((:label \"a\"\n :cells (33.0 (:< 0.001))) (:label \"b\" :cells (nil :na))))"))
       #t)
(check "TTFY layout keeps printed numbers and puts one key per line"
       (ttfy-canonical "(data-table :table \"1\" :cells (33.0 1.00))")
       "(data-table\n  :table \"1\"\n  :cells (33.0 1.00))")
(check "TTFY reports a lisp block that does not read"
       (ttfy-unreadable-blocks (split-lines "```lisp\n(data-table :x (1\n```\n"))
       '("the lisp block at line 1 does not read as one S-expression"))
(check "TTFY rewrites a pipe table with the provider's S-expression"
       (ttfy-fix-tables (lambda (prompt) "```lisp\n(data-table :table \"1\"\n   :rows ((:label \"a\" :cells (1))))\n```")
                        "T\n\n| A | B |\n|---|---|\n| a | 1 |\n\nEnd" "")
       (cons "T\n\n```lisp\n(data-table\n  :table \"1\"\n  :rows ((:label \"a\" :cells (1))))\n```\n\nEnd" '()))
(check "TTFY keeps a table it could not rewrite and says so"
       (cdr (ttfy-fix-tables (lambda (prompt) "Assistant failed (timeout)") "| A |\n|---|\n| a |" ""))
       '("the pipe table at line 1 could not be rewritten as an S-expression"))
(check "TTFY guidelines define the data-table schema"
       (and (string-search "schememax/data-table/1" (ttfy-read-guidelines)) #t) #t)
(check "TTFY is in the MORE window" (and (assoc "TTFY" *full-menu*) #t) #t)
(check "TTFY is a mode line button, kept in narrow windows"
       (let loop ((w 40))
         (or (> w 120)
             (and (string-search "[TTFY]" (mode-line-string "a-long-file-name.md" 1000 1 w)) (loop (+ w 1)))))
       #t)

;;; done
(define (test-report)
  (let ((summary (string-append (number->string (- *count* *failures*)) "/" (number->string *count*)
                                " tests passed")))
    (if (= *failures* 0)
        summary
        (error (string-append (io.tostring! *failure-report*) summary)))))
(test-report)
