;; tests/endurance.sh: long sessions in one editor, compiled into it once as
;; a user's script (chezemax --compile-scripts, ~/.chezemax/users), as
;; tests/fuzz-editor.scm is.  Keys:
;;   C-c 6  buffer churn: $ENDURANCE_CYCLES times, open a file of
;;          $ENDURANCE_DIR (f-N.md .org .scm .txt, and big-N.txt, which
;;          opens in shards), show it, use it as its kind is used (folds,
;;          narrowing, read mode, a second window), and kill it as C-x k
;;          does; every $ENDURANCE_SHELLS-th cycle, an M-x term shell too.
;;          Every $ENDURANCE_EVERY cycles one line of meters goes to
;;          $CHEZWEB_METERS: "churn CYCLE LEAKS T1..T8 HEAP RSS FDS BUFFERS
;;          WINDOWS" -- LEAKS 1 when LeakSanitizer finds memory nothing
;;          reaches, T1..T8 the sizes of the Scheme tables that keep
;;          something by buffer, then the meters of src/meters.c.
;;   C-c 5  undo eviction: $ENDURANCE_UNDO_CYCLES times, insert a chunk of
;;          1 to 3 MB at the end of the buffer and delete it again, each a
;;          command of its own, so that the history passes *undo-limit*
;;          (8 MB) again and again and its oldest groups are dropped; every
;;          tenth cycle a chunk of 20 MB, which no history keeps; every
;;          fifth, three undos and three redos.  A line of meters a cycle:
;;          "undo CYCLE HISTORY-BYTES GROUPS LIMIT heap rss fds buffers
;;          windows".  Says (ENDURANCE UNDO DONE N).  Says (ENDURANCE DONE N) at the end.

(define (endurance-number name default)
  (let ((v (getenv name))) (or (and v (string->number v)) default)))

;; the Scheme tables that keep something by buffer (name, id or file name)
(define (endurance-tables)
  (list (hashtable-size *undo-histories*) (hashtable-size *buffer-faces*)
        (hashtable-size *buffer-menus*) (hashtable-size *buffer-hints*)
        (hashtable-size *vim-states*) (hashtable-size *vim-kinds*)
        (hashtable-size *language-overrides*) (hashtable-size *word-wrap-overrides*)))

(define (endurance-note label check)
  ;; under LeakSanitizer (when CHECK), the memory nothing reaches is
  ;; reported now (standard error) and counted: 1 if any.  A check stops
  ;; the editor for seconds: at the start, the middle and the end only.
  (let ((leaks (if check (fe-leak-check) 0)))
    (fe-meter-note
     (apply string-append label " " (number->string leaks)
            (map (lambda (n) (string-append " " (number->string n))) (endurance-tables))))))

(define (endurance-file dir i)
  (let ((kind (remainder i 5)))
    (string-append dir "/" (if (= kind 4) "big-" "f-") (number->string i)
                   (vector-ref (vector ".md" ".org" ".scm" ".txt" ".txt") kind))))

(define (endurance-use i)
  "What a person does with a file of this kind, briefly."
  (let ((kind (remainder i 5)) (size (buffer-size)))
    (cond ((= kind 1)                                   ; Org: fold a heading
           (let ((end (let loop ((p 1)) (if (or (>= p size) (= (buffer-get p) 10)) p (loop (+ p 1))))))
             (when (< (+ end 2) size) (fe-fold end (- size 1)) (fe-update-display) (fe-unfold 0 size))))
          ((= kind 2)                                   ; Scheme: narrow to a part
           (when (> size 10) (fe-narrow 0 (quotient size 2)) (fe-update-display) (fe-widen)))
          ((= kind 3) (fe-read-mode 1) (fe-update-display) (fe-read-mode 0))
          (else #f))
    (when (= (remainder i 7) 0)                         ; a second window on it
      (fe-split-window) (fe-update-display) (fe-delete-other-windows))
    (fe-update-display)))

(defcommand (endurance-churn)
  (let ((dir (or (getenv "ENDURANCE_DIR") "/tmp"))
        (cycles (endurance-number "ENDURANCE_CYCLES" 1000))
        (every (endurance-number "ENDURANCE_EVERY" 100))
        (shells (endurance-number "ENDURANCE_SHELLS" 25)))
    ;; big-N.txt files (some 40 KB) open in shards of 8 KB
    (fe-shard-threshold 20000)
    (fe-shard-size 8192)
    (endurance-note "start 0" #t)
    (let loop ((i 0))
      (when (< i cycles)
        (find-file (endurance-file dir i))
        (fe-update-display)
        (endurance-use i)
        (execute-builtin "kill-buffer")                 ; C-x k
        (when (and (> shells 0) (= (remainder i shells) (- shells 1)))
          ;; M-x term; C-x k would ask whether to stop the shell, so it is
          ;; killed by name, as the C core does after that question
          (term)
          (fe-update-display)
          (fe-kill-buffer (get-buffer-name)))
        (when (= (remainder (+ i 1) every) 0)
          (endurance-note (string-append "churn " (number->string (+ i 1)))
                          (or (= (+ i 1) cycles) (= (+ i 1) (quotient cycles 2)))))
        (loop (+ i 1))))
    (fe-update-display)
    (message "(ENDURANCE DONE " (number->string cycles) ")")))

(global-set-key "C-c 6" 'endurance-churn)

;; one command: what undo-boundary marks, as a key would
(define (endurance-command thunk)
  (undo-boundary "endurance")
  (thunk))

(define (endurance-history)
  (let ((h (current-history)))
    (if h
        (list (undo-history-bytes h) (+ (length (undo-history-done h)) (length (undo-history-undone h))))
        (list 0 0))))

(defcommand (endurance-undo)
  (let ((cycles (endurance-number "ENDURANCE_UNDO_CYCLES" 60)))
    (let loop ((i 0))
      (when (< i cycles)
        (let* ((mb (if (= (remainder i 10) 9) 20 (+ 1 (remainder i 3))))
               (chunk (make-bytevector (* mb 1024 1024) (+ 97 (remainder i 26))))
               (start (buffer-size)))
          (endurance-command (lambda () (fe-insert-bytes start chunk)))
          (endurance-command (lambda () (fe-delete-region start (buffer-size))))
          (when (= (remainder i 5) 4)
            (endurance-command (lambda () (undo) (undo) (undo)))
            (endurance-command (lambda () (redo) (redo) (redo))))
          (let ((h (endurance-history)))
            (fe-meter-note (string-append "undo " (number->string (+ i 1)) " "
                                          (number->string (car h)) " " (number->string (cadr h)) " "
                                          (number->string *undo-limit*))))
          (loop (+ i 1)))))
    (fe-update-display)
    (message "(ENDURANCE UNDO DONE " (number->string cycles) ")")))

(global-set-key "C-c 5" 'endurance-undo)
