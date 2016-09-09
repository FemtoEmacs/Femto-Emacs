;;
;; buffer menu extension for FemtoEmacs, written in Femtolisp with FemtoEmacs bindings
;; Hugh Barney September 2016
;;
;; when run produces a list of buffers
;; use the arrow keys to move up or down the list
;; then select one of 1,2,s,k,x
;;
;; 1 - switch to buffer as a single window
;; 2 - split screen and select buffer and original buffer
;; s - save buffer if modified
;; k - kill buffer
;; x - exit buffer menu
;;
;;
;; (load "samples/bufmenu.scm")
;; (buffer-menu)
;;

(define bufm-line 3)   
(define bufm-start-line 3)
(define bufm-last-line 3)
(define bufm-max-ops 400)
(define bufm-stop #f)
(define bufm-obuf "")
(define bufm-buf "")
(define bufm-key "")

(define (buffer-menu)
    ;(bufm-debug "buffer-menu")
    (set! bufm-line bufm-start-line)   
    (set! bufm-last-line (+ bufm-start-line (get-buffer-count)))
    (set! bufm-last-line (- bufm-last-line 2))
    (set! bufm-obuf (get-buffer-name))
    (set! bufm-stop #f)
    (list-buffers)
    (goto-line bufm-line)
    (delete-other-windows)
    (set! bufm-buf (bufm-get-bufn))
    (do ((i 1 (1+ i)))
        ((or (> i bufm-max-ops) bufm-stop))        
        (bufm-loop-payload))
    (update-display))


(define (bufm-loop-payload)
    (message "buffer menu: 1,2,s,k,x")
    (update-display)
    (set! bufm-key (get-key))
    (if (equal? bufm-key "")
	 (bufm-handle-bound-key)
         (bufm-handle-single-key bufm-key)))

(define (bufm-handle-bound-key)
    ;(bufm-debug "bufm-handle-bound-key")
    (set! bufm-key (get-key-binding))
    (if (equal? bufm-key "previous-line")  (set! bufm-line (- bufm-line 1)) )
    (if (equal? bufm-key "next-line")  (set! bufm-line (+ 1 bufm-line)) )
    (set! bufm-line (bufm_check_line_limits bufm-line bufm-last-line bufm-start-line) )
    (set! bufm-buf (bufm-get-bufn)))

(define (bufm-handle-single-key k)
   ;(bufm-debug "bufm-handle-single-key")
   (set! bufm_count (get-buffer-count))
   (cond   ( (equal? k "x")
             (goto-line bufm-start-line)
             (beginning-of-line)
             (if (search-forward bufm-obuf)
                   (select-buffer bufm-obuf)
                   (select-buffer "*scratch*"))
             (set! bufm-stop #t)
	     (update-display))
           ( (and (equal? k "1") (> bufm_count 1))
             (select-buffer bufm-buf)
             (delete-other-windows)
             (set! bufm-stop #t))
           ( (and (equal? k "2") (> bufm_count 1))
             (select-buffer bufm-buf)
             (split-window)
             (select-buffer bufm-obuf)
             (other-window)
             (set! bufm-stop #t))
           ( (and (equal? k "s") (> bufm_count 1))
             (save-buffer bufm-buf)
             (list-buffers)
             (goto-line bufm-line))
           ( (and (equal? k "k") (> bufm_count 1))
	     (kill-buffer bufm-buf)
             (list-buffers)
             (set! bufm-last-line (+ bufm-start-line (get-buffer-count)))
             (set! bufm-last-line (- bufm-last-line 2))
             (set! bufm-line (bufm_check_line_limits bufm-line bufm-last-line bufm-start-line))
             (goto-line bufm-line)
             (set! bufm-buf (bufm-get-bufn)))))


;; fix forward-char should be forward-character

(define (bufm-get-bufn)
 (goto-line bufm-line)
 (beginning-of-line)
 (beginning-of-line)
 (forward-char 11)
 (set-mark)
 (forward-char 17)
 (copy-region)
 (beginning-of-line)
 (trim (get-clipboard)))

(define (bufm_check_line_limits v max min)
  (cond  ( (> v max) max)
         ( (> min v) min)
         ( else v)))

(define (log-var n v)
	(log-debug (string-append n "=" v "\n")))

(define (bufm-debug msg)
     (log-debug (string-append msg "\n"))
     (log-var "bufm-line" bufm-line)
     (log-var "bufm-start-line" bufm-start-line)
     (log-var "bufm-last-line" bufm-last-line)
     (log-var "bufm-obuf" bufm-obuf)
     (log-var "bufm-buf" bufm-buf)
     (log-debug "\n\n"))

