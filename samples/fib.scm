;;
;; calc fibonacci sequence entry
;;


(define (fib n)
  (cond {(< n 2) 1}
        {else (+ (fib (- n 1))
                 (fib (- n 2)))}))


;; Linha um
;; Linha dois
;; Linha tres
;; Linha quatro













