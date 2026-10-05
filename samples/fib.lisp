;;
;; calc fibonacci sequence entry
;; put the cursor on the closing paren of a form and press Esc-]
;;

(defun fib (n)
  (cond ((< n 2) 1)
        (t (+ (fib (- n 1))
              (fib (- n 2))))))

(fib 20)

;; Linha um
;; Linha dois
;; Linha tres
;; Linha quatro
