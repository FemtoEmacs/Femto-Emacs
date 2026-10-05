;; quicksort; try Esc-] on the last line

(defun quick (xs)
  (if (or (null xs) (null (cdr xs)))
      xs
      (append (quick (remove-if-not (lambda (x) (< x (car xs))) (cdr xs)))
              (list (car xs))
              (quick (remove-if-not (lambda (x) (>= x (car xs))) (cdr xs))))))

(quick '(3 1 4 1 5 9 2 6 5 3 5))
