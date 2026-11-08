;;;; chinese.scm -- Chinese typed in tonal pinyin (M-x chinese-input)
;;;;
;;;; Nothing here costs anything until M-x chinese-input: the tables, in the
;;;; folder Chinese/ of the installation (tools/chinese-tables.sh makes
;;;; them), are read the first time it is turned on, and dropped when it is
;;;; turned off.  While it is on the mode line shows 中.
;;;;
;;;;   letters        the pinyin (ü is v): zhong, lv; the candidates of every
;;;;                  tone show at the bottom, most frequent first
;;;;   1 2 3 4 5      after the letters: the tone (5 neutral); then only the
;;;;                  characters read in that tone
;;;;   1-9, SPC       after the tone: the candidate of that number, SPC the
;;;;                  first (SPC also takes the first before a tone)
;;;;   - =            the previous, the next page of candidates
;;;;   DEL            the tone, then the letters, back one at a time
;;;;   RET            the letters as typed;  C-g  nothing
;;;;
;;;; After a character, its 联想 (Liánxiǎng): the characters that most often
;;;; follow it (中: 国 心 央 学 ...), 1-9 to take one, which shows its own;
;;;; any other key goes on as usual.  , . ? ! : ; type ，。？！：；
;;;;
;;;; The key handler takes the keys before the others (core.scm's
;;;; *modal-key-handler*) and gives those it does not use to the handler it
;;;; replaced (vim mode's), which it gets back when the input is turned off.

(define *chinese* #f)
(define *chinese-pinyin* #f)        ; "zhong1 中钟..." -> table, read on demand
(define *chinese-follow* #f)        ; "中 国心..." -> table, read on demand
(define *chinese-previous-handler* #f)

(define *chinese-letters* "")       ; the pinyin being typed
(define *chinese-tone* #f)          ; its tone, a digit character, or #f
(define *chinese-page* 0)
(define *chinese-after* #f)         ; the character whose followers show

(define (chinese-table file)
  "FILE of the folder Chinese/: KEY VALUE lines, as a table; #f if absent."
  (let ((text (file-contents (string-append *install-dir* "/Chinese/" file))))
    (and (string? text)
         (let ((table (make-hashtable string-hash string=?)))
           (for-each (lambda (line)
                       (let ((space (string-search " " line)))
                         (when (and space (> space 0))
                           (hashtable-set! table (substring line 0 space)
                                           (substring line (+ space 1) (string-length line))))))
                     (split-lines text))
           table))))

(define (chinese-candidates)
  "The characters of the pinyin typed so far, a string; \"\" if none."
  (if (string=? *chinese-letters* "") ""
      (hashtable-ref *chinese-pinyin*
                     (if *chinese-tone* (string-append *chinese-letters* (string *chinese-tone*)) *chinese-letters*)
                     "")))

(define (chinese-page-of all)
  "The candidates of the current page of ALL, at most nine."
  (let* ((n (string-length all)) (pages (max 1 (quotient (+ n 8) 9))))
    (when (>= *chinese-page* pages) (set! *chinese-page* (- pages 1)))
    (when (< *chinese-page* 0) (set! *chinese-page* 0))
    (substring all (* 9 *chinese-page*) (min n (* 9 (+ *chinese-page* 1))))))

(define (chinese-numbered page)
  (let loop ((i 0) (out ""))
    (if (>= i (string-length page)) out
        (loop (+ i 1) (string-append out (if (= i 0) "" " ") (number->string (+ i 1))
                                     (string (string-ref page i)))))))

(define (chinese-show)
  "What is being typed and its candidates, at the bottom of the screen."
  (cond ((not (string=? *chinese-letters* ""))
         (let* ((all (chinese-candidates)) (page (chinese-page-of all))
                (pages (quotient (+ (string-length all) 8) 9)))
           (message *chinese-letters* (if *chinese-tone* (string *chinese-tone*) "") "  "
                    (if (string=? page "") "(no character)" (chinese-numbered page))
                    (if (> pages 1)
                        (string-append "  " (number->string (+ *chinese-page* 1)) "/" (number->string pages) " -=")
                        ""))))
        (*chinese-after*
         (let ((follow (hashtable-ref *chinese-follow* (string *chinese-after*) "")))
           (if (string=? follow "") (clear-message-line)
               (message (string *chinese-after*) "→ " (chinese-numbered follow)))))
        (else (clear-message-line))))

(define (chinese-reset)
  (set! *chinese-letters* "")
  (set! *chinese-tone* #f)
  (set! *chinese-page* 0))

(define (chinese-take c)
  "Insert the character C and show the characters that follow it."
  (insert (string c))
  (chinese-reset)
  (set! *chinese-after* c)
  (chinese-show)
  #t)

(define (chinese-choose n)
  "The candidate N (1-9) of the page, if there is one."
  (let ((page (chinese-page-of (chinese-candidates))))
    (if (<= n (string-length page))
        (chinese-take (string-ref page (- n 1)))
        (begin (chinese-show) #t))))

(define (chinese-composing?) (not (string=? *chinese-letters* "")))

(define *chinese-punctuation*
  '((#\, . #\xFF0C) (#\. . #\x3002) (#\? . #\xFF1F) (#\! . #\xFF01) (#\: . #\xFF1A) (#\; . #\xFF1B)))

(define (chinese-char key)
  "A typed character (a one-character string) while the input is on."
  (let* ((ch (string-ref key 0))
         (digit (and (char<=? #\0 ch) (char<=? ch #\9) (- (char->integer ch) 48))))
    (cond ((and (char<=? #\a ch) (char<=? ch #\z))
           (set! *chinese-after* #f)
           (when *chinese-tone*              ; a new syllable after a toned one
             (chinese-reset))
           (set! *chinese-letters* (string-append *chinese-letters* key))
           (set! *chinese-page* 0)
           (chinese-show)
           #t)
          ((chinese-composing?)
           (cond ((and digit (not *chinese-tone*) (<= 1 digit) (<= digit 5))
                  (set! *chinese-tone* ch) (set! *chinese-page* 0) (chinese-show) #t)
                 ((and digit *chinese-tone* (<= 1 digit)) (chinese-choose digit))
                 ((char=? ch #\space)
                  (let ((page (chinese-page-of (chinese-candidates))))
                    (if (string=? page "") (begin (chinese-show) #t) (chinese-take (string-ref page 0)))))
                 ((char=? ch #\-) (set! *chinese-page* (- *chinese-page* 1)) (chinese-show) #t)
                 ((char=? ch #\=) (set! *chinese-page* (+ *chinese-page* 1)) (chinese-show) #t)
                 ((memv ch '(#\return #\newline))
                  (let ((typed *chinese-letters*)) (chinese-reset) (clear-message-line) (insert typed) #t))
                 (else (chinese-reset) (clear-message-line) #f)))
          ((and *chinese-after* digit (<= 1 digit))
           (let ((follow (hashtable-ref *chinese-follow* (string *chinese-after*) "")))
             (if (<= digit (string-length follow))
                 (chinese-take (string-ref follow (- digit 1)))
                 (begin (set! *chinese-after* #f) (clear-message-line) #f))))
          ((assv ch *chinese-punctuation*)
           => (lambda (p) (set! *chinese-after* #f) (clear-message-line) (insert (string (cdr p))) #t))
          (else (when *chinese-after* (set! *chinese-after* #f) (clear-message-line)) #f))))

(define (chinese-key-handler kind key)
  "The key handler while the input is on (core.scm's *modal-key-handler*)."
  (or (and *chinese*
           (cond ((eq? kind 'char) (and (= (string-length key) 1) (chinese-char key)))
                 ((chinese-composing?)
                  (cond ((member key '("backspace" "C-h"))
                         (if *chinese-tone* (set! *chinese-tone* #f)
                             (set! *chinese-letters* (substring *chinese-letters* 0 (- (string-length *chinese-letters*) 1))))
                         (set! *chinese-page* 0) (chinese-show) #t)
                        ((string=? key "C-g") (chinese-reset) (clear-message-line) #t)
                        ((string=? key "RET")
                         (let ((typed *chinese-letters*)) (chinese-reset) (clear-message-line) (insert typed) #t))
                        (else (chinese-reset) (clear-message-line) #f)))
                 (*chinese-after* (set! *chinese-after* #f) (clear-message-line) #f)
                 (else #f)))
      (and *chinese-previous-handler*
           ((command-procedure *chinese-previous-handler*) kind key))))

(defcommand (chinese-input)
  "Toggle Chinese typed in tonal pinyin (chinese.scm); its tables are read
when it is turned on."
  (if *chinese*
      (begin (set! *chinese* #f)
             (chinese-reset) (set! *chinese-after* #f)
             (set! *chinese-pinyin* #f) (set! *chinese-follow* #f)   ; the tables go
             (when (eq? *modal-key-handler* 'chinese-key-handler)
               (set! *modal-key-handler* *chinese-previous-handler*))
             (set! *chinese-previous-handler* #f)
             (update-display)
             (message "Chinese input off"))
      (let ((pinyin (chinese-table "pinyin.txt")) (follow (chinese-table "lianxiang.txt")))
        (if (not pinyin)
            (message "Chinese input: " *install-dir* "/Chinese/pinyin.txt is missing")
            (begin (set! *chinese-pinyin* pinyin)
                   (set! *chinese-follow* (or follow (make-hashtable string-hash string=?)))
                   (chinese-reset) (set! *chinese-after* #f)
                   (unless (eq? *modal-key-handler* 'chinese-key-handler)
                     (set! *chinese-previous-handler* *modal-key-handler*)
                     (set! *modal-key-handler* 'chinese-key-handler))
                   (set! *chinese* #t)
                   (update-display)
                   (message "Chinese input: pinyin, a tone 1-5, then 1-9 or SPC (zhong1 1 = 中); M-x chinese-input again: off"))))))
