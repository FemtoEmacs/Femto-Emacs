;;
;; samples/undotest.scm
;; hugh barney AT gmail dot com
;; 5 Nov 2016
;;
;;

;;## TEST START
;;LINE 10:The Quick 12$34 Brown Fox ¢56€ Jumps over the lazy 7998𐍈0
;;LINE 11:The Quick 12$34 Brown Fox ¢56€ Jumps over the lazy 7998𐍈0
;;## TEST END


;;Start on line 1: and CTRL+D delete the words The and Quick
;;Now drop to line 2: and CTRL+E to end of line
;;Backspace up to the l of lazy.
;;Now CTRL+A and type FISH
;;Now Move up 1 line and CTRL+D Fox, move to Jumps and CTRL+D that word
;;Now backspace across the ¢56€ UTF8 chars.
;;Go to line 2 and CTRL+D all of ¢56€
;;Go to line 1, CTRL+E to EOL, arrow right to the start of 7998𐍈0
;;Now CTRL+D all of 7998𐍈0
;;No do CTRL+U until it says 'Out of Undo'

(goto-line 10)