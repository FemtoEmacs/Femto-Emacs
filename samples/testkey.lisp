;;
;; Demonstrate how get-key works when a bound key is pressed:
;; how to retrieve the key name and its binding.
;; If the key is not bound, get-key returns the typed text and
;; get-key-name / get-key-binding return "".
;;
;; Note the call of update-display, otherwise you will not see anything
;; while the function runs, and the second get-key so that you can read
;; the message.
;;
;; Esc-] on the defun, then Esc-; (test-key)
;;

(defun test-key ()
  (message "press a key")
  (update-display)
  (let ((typed (get-key)))
    (if (string= typed "")
        (message "You pressed ~A which is bound to ~A, press a key"
                 (get-key-name) (get-key-binding))
        (message "You typed ~S, press a key" typed)))
  (update-display)
  (get-key)
  (clear-message-line))
