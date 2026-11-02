(define (show . xs) (for-each display xs) (newline))
(define p (open-input-string "(a b . c) #(1 2.5 \"s\\n\\x41;\") #\\space #\\x41 #\\a 'q `(x ,y ,@z) #| block #| nested |# |# 12 ; comment
 -3.5e2 #t #false |sym bol| #;(skipped) last #u8(1 2 255) 1/2 #xff #e1.5 [x y] .5 -inf.0 +.5e1 a.b 1e400 -0.0 #\\newline"))
(let loop () (let ((x (read p))) (if (not (eof-object? x)) (begin (write x) (newline) (loop)))))
(show (map string->number '("12" "-12" "1.5" "1e3" "abc" "1/3" "#b101" "+5" "-" "." "1." ".1" "1e" "12x" "#i3" "1e-2")))
