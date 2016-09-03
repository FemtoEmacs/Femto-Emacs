
;;
;; Demonstrate how get key works when a bound key is pressed
;; how to retrieve the key name and its binding
;; Note is get-key is not bound then the result of key-key-name and get-key-binding are undefined
;;
;; Note call of update-display otherwise you will not see anything when the script is running
;; Note also call to get-key again so that you can see the message displayed on the message line
;; 

(define (test-key)
 (message "press a key")
 (update-display)
 (get-key)
 (message (string-append "You pressed " (get-key-name) " which is bound to " (get-key-binding) ",press key"))
 (update-display)
 (get-key))

