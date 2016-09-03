;;
;; work in progress, no finnished yet
;; To demo it, you need to have at least 3 files open, to try this out
;;
;;


;; this is just a start
(define (buffer-menu)
    (define obuf (get-buffer-name))
    (list-buffers)
    (message "buffer menu: 1,2,k,x")    
    (update-display)
    (define ky (get-key))
    (cond  ( (equal? ky "1") 
             (bufm-get-buf-at-line 3))
           ( (equal? ky "2")
             (bufm-get-buf-at-line 5)
             (split-window-below)
             (select-buffer-by-name obuf))
           ( (equal? ky "k")
             (message "you selected option k\n"))
           ( (equal? ky "x")
             (message "you selected option x\n"))
           (else (do-nothing))))


(define (bufm-get-buf-at-line l)
 (select-buffer-by-name "*buffers*")
 (goto-line l)
 (forward-character 11)
 (set-mark)
 (forward-character 17)
 (copy-region)
 (define nbuf (trim (get-clipboard)))
 (select-buffer-by-name nbuf) 
 (message nbuf)
 (update-display))

(define (do-nothing)
	(message "unknown option !, press key to continue")
	(update-display)
	(get-key))




