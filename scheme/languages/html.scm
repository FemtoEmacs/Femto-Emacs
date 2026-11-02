;;;; html.scm -- colours for HTML, and HTML without its tags
;;;;
;;;; The colours (the faces of theme.scm):
;;;;
;;;;   <tag ... >, </tag>    keyword        <!DOCTYPE ...>   keyword
;;;;   attribute names       digits         "values"        string
;;;;   <!-- comments -->     comment        &amp; &#169;    digits
;;;;   text in <h1>..<h6>    heading        <b> <strong>    strong
;;;;   text in <i> <em>      emphasis       <a href=...>    link
;;;;   <script>, <style>, <code>, <pre>: their text as a string
;;;;
;;;; HTML-STRIP gives the text with the tags taken away, for C-c TAB
;;;; (extensions/tag-view.scm): block tags become line breaks, <li> a "- ",
;;;; entities their characters; comments, <script> and <style> go.

;;; ------------------------------------------------------------------
;;; Reading bytes
;;; ------------------------------------------------------------------

(define (html-letter? b) (or (and (<= 65 b) (<= b 90)) (and (<= 97 b) (<= b 122))))
(define (html-name-byte? b) (or (html-letter? b) (and (<= 48 b) (<= b 57)) (memv b '(45 95 58 46))))
(define (html-space? b) (memv b '(32 9 10 13 12)))

(define (html-name-end text i len)
  (let loop ((i i)) (if (and (< i len) (html-name-byte? (aref text i))) (loop (+ i 1)) i)))

(define (html-find text needle start len)
  "Index of NEEDLE (lower case) in TEXT from START, ignoring case, or #f."
  (let ((n (length needle)))
    (let loop ((i start))
      (cond ((> (+ i n) len) #f)
            ((match-at text len i needle #t) i)
            (else (loop (+ i 1)))))))

(define (html-tag-end text i len)
  "The index after the > that closes the tag opened at I, skipping quoted
values; LEN when the tag is not closed."
  (let loop ((i (+ i 1)) (q #f))
    (cond ((>= i len) len)
          (q (loop (+ i 1) (if (= (aref text i) q) #f q)))
          ((memv (aref text i) '(34 39)) (loop (+ i 1) (aref text i)))
          ((= (aref text i) 62) (+ i 1))
          (else (loop (+ i 1) #f)))))

(define (html-tag-name text i len)
  "The lower-case name of the tag at I (< or </ then the name), and
whether it closes: two values."
  (let* ((closing (and (< (+ i 1) len) (= (aref text (+ i 1)) 47)))
         (start (+ i (if closing 2 1)))
         (end (html-name-end text start len)))
    (values (string-downcase (byte-substring text start end)) closing)))

(define (html-entity-end text i len)
  "If an entity (&name; &#123; &#x1F;) starts at I, the index after its ;."
  (let loop ((j (+ i 1)))
    (cond ((or (>= j len) (> (- j i) 10)) #f)
          ((= (aref text j) 59) (and (> j (+ i 1)) (+ j 1)))
          ((or (html-name-byte? (aref text j)) (= (aref text j) 35)) (loop (+ j 1)))
          (else #f))))

;;; ------------------------------------------------------------------
;;; Colours
;;; ------------------------------------------------------------------

;; the face of the text inside these elements
(define *html-text-faces*
  '(("h1" . 11) ("h2" . 11) ("h3" . 11) ("h4" . 11) ("h5" . 11) ("h6" . 11) ("title" . 11)
    ("b" . 13) ("strong" . 13) ("i" . 12) ("em" . 12) ("cite" . 12) ("a" . 14)
    ("code" . 9) ("pre" . 9) ("tt" . 9) ("kbd" . 9) ("samp" . 9)))

;; elements whose content is not HTML: coloured as a string up to their end tag
(define *html-raw-elements* '("script" "style"))

(define (html-paint-tag text i end colors)
  "Colour the tag [I, END): its name and brackets, attributes and values."
  (let* ((name-start (+ i (if (and (< (+ i 1) end) (= (aref text (+ i 1)) 47)) 2 1)))
         (name-end (html-name-end text name-start end)))
    (paint colors i name-end +keyword+)
    (let loop ((j name-end))
      (when (< j end)
        (let ((b (aref text j)))
          (cond ((memv b '(34 39))
                 (let ((close (let find ((k (+ j 1)))
                                (cond ((>= k end) end) ((= (aref text k) b) (+ k 1)) (else (find (+ k 1)))))))
                   (paint colors j close +string+)
                   (loop close)))
                ((html-name-byte? b)
                 (let ((e (html-name-end text j end)))
                   (paint colors j e +digits+)
                   (loop e)))
                ((memv b '(62 47))
                 (paint colors j (+ j 1) +keyword+)
                 (loop (+ j 1)))
                (else (loop (+ j 1)))))))))

(define (html-highlight lang text len colors)
  (let loop ((i 0) (open '()))          ; OPEN: the styled elements we are in
    (when (< i len)
      (let ((b (aref text i))
            (text-face (if (pair? open) (cdar open) +alpha+)))
        (cond
         ;; <!-- comment -->
         ((match-at text len i "<!--")
          (let* ((e (html-find text "-->" (+ i 4) len))
                 (end (if e (+ e 3) len)))
            (paint colors i end +comment+)
            (loop end open)))
         ;; <!DOCTYPE ...>, <?xml ...?>
         ((and (= b 60) (< (+ i 1) len) (memv (aref text (+ i 1)) '(33 63)))
          (let ((end (html-tag-end text i len)))
            (paint colors i end +keyword+)
            (loop end open)))
         ;; a tag
         ((and (= b 60) (< (+ i 1) len)
               (let ((c (aref text (+ i 1))))
                 (or (html-letter? c) (and (= c 47) (< (+ i 2) len) (html-letter? (aref text (+ i 2)))))))
          (let ((end (html-tag-end text i len)))
            (html-paint-tag text i end colors)
            (let-values (((name closing) (html-tag-name text i len)))
              (cond ((and (not closing) (member name *html-raw-elements*))
                     (let* ((close (html-find text (string-append "</" name) end len))
                            (stop (or close len)))
                       (paint colors end stop +string+)
                       (loop stop open)))
                    ((assoc name *html-text-faces*)
                     => (lambda (entry)
                          (loop end (if closing
                                        (let drop ((l open))      ; close the innermost of that name
                                          (cond ((null? l) '())
                                                ((string=? (caar l) name) (cdr l))
                                                (else (cons (car l) (drop (cdr l))))))
                                        (cons entry open)))))
                    (else (loop end open))))))
         ;; &amp; &#169;
         ((and (= b 38) (html-entity-end text i len))
          => (lambda (end) (paint colors i end +digits+) (loop end open)))
         (else
          (aset! colors i (if (memv b '(32 9 10 13)) +symbol+ text-face))
          (loop (+ i 1) open)))))))

(define-language "HTML"
  'extensions '(".html" ".htm" ".xhtml" ".xml" ".svg")
  'highlighter html-highlight)

;;; ------------------------------------------------------------------
;;; The text without its tags (C-c TAB)
;;; ------------------------------------------------------------------

;; tags that start a new line in the text
(define *html-block-tags*
  '("p" "div" "br" "h1" "h2" "h3" "h4" "h5" "h6" "ul" "ol" "dl" "dt" "dd" "tr"
    "table" "thead" "tbody" "section" "article" "header" "footer" "nav" "aside"
    "main" "blockquote" "pre" "hr" "title" "figure" "figcaption" "form" "html"
    "head" "body" "caption"))

(define *html-entities*
  '(("amp" . "&") ("lt" . "<") ("gt" . ">") ("quot" . "\"") ("apos" . "'")
    ("nbsp" . " ") ("ndash" . "–") ("mdash" . "—") ("hellip" . "…") ("copy" . "©")
    ("reg" . "®") ("deg" . "°") ("plusmn" . "±") ("times" . "×") ("le" . "≤")
    ("ge" . "≥") ("ne" . "≠") ("alpha" . "α") ("beta" . "β") ("gamma" . "γ")
    ("mu" . "μ") ("micro" . "µ") ("laquo" . "«") ("raquo" . "»") ("ldquo" . "“")
    ("rdquo" . "”") ("lsquo" . "‘") ("rsquo" . "’") ("middot" . "·") ("bull" . "•")))

(define (html-entity-text entity)
  "The character of an entity such as \"&amp;\" or \"&#8211;\", or #f."
  (let ((name (byte-substring entity 1 (- (length entity) 1))))
    (cond ((assoc name *html-entities*) => cdr)
          ((and (> (length name) 1) (= (aref name 0) 35))
           (let ((n (if (memv (aref name 1) '(120 88))
                        (string->number (byte-substring name 2) 16)
                        (string->number (byte-substring name 1)))))
             (and (integer? n) (> n 0) (< n #x110000) (string (integer->char n)))))
          (else #f))))

(define (html-strip text out)
  "Write TEXT without its tags to OUT, a tag view (tag-view.scm)."
  (let ((len (length text)))
    (let loop ((i 0) (start 0))          ; [START, I) is text not yet written
      (define (flush) (tag-view-copy out text start i))
      (if (>= i len)
          (flush)
          (let ((b (aref text i)))
            (cond
             ((match-at text len i "<!--")
              (flush)
              (let ((e (html-find text "-->" (+ i 4) len)))
                (let ((end (if e (+ e 3) len))) (loop end end))))
             ((and (= b 60) (< (+ i 1) len)
                   (let ((c (aref text (+ i 1))))
                     (or (html-letter? c) (memv c '(33 63))
                         (and (= c 47) (< (+ i 2) len) (html-letter? (aref text (+ i 2)))))))
              (flush)
              (let ((end (html-tag-end text i len)))
                (let-values (((name closing) (html-tag-name text i len)))
                  (cond ((and (not closing) (member name *html-raw-elements*))
                         (let* ((close (html-find text (string-append "</" name) end len))
                                (stop (if close (html-tag-end text close len) len)))
                           (loop stop stop)))
                        (else
                         (cond ((string=? name "li") (unless closing (tag-view-emit out "\n" i) (tag-view-emit out "- " i +symbol+)))
                               ((member name *html-block-tags*) (tag-view-emit out "\n" i)))
                         (loop end end))))))
             ((and (= b 38) (html-entity-end text i len))
              => (lambda (end)
                   (let ((s (html-entity-text (byte-substring text i end))))
                     (if s
                         (begin (flush) (tag-view-emit out s i) (loop end end))
                         (loop end start)))))
             (else (loop (+ i 1) start))))))))
