;;;; shards.scm -- the keys of files in shards (src/shard.c), as Emacs's VLF
;;;;
;;;;   C-c C-v n   the next shard
;;;;   C-c C-v p   the previous shard
;;;;   C-c C-v g   shard number N
;;;;   C-c C-v [   the first shard, at its start
;;;;   C-c C-v ]   the last shard, at its end
;;;;
;;;; A file larger than (fe-shard-threshold -1) bytes (1 GB) opens in
;;;; shards with C-x C-f; M-x find-file-shards opens any file so.  Each
;;;; shard is about (fe-shard-size -1) bytes (16 MB).  In init.scm:
;;;;   (fe-shard-threshold 500000000)   ; shards above 500 MB
;;;;   (fe-shard-size 4000000)          ; of 4 MB
;;;; In an Org buffer, C-c C-v is Org Babel's prefix; n, p, g, [ and ] after it
;;;; are these commands there too (org-babel-prefix, org.scm).

(define *shard-keys*
  (list (cons "n" (lambda () (execute-builtin "shard-next")))
        (cons "p" (lambda () (execute-builtin "shard-previous")))
        (cons "g" (lambda () (execute-builtin "shard-goto")))
        (cons "[" (lambda () (execute-builtin "shard-first")))
        (cons "]" (lambda () (execute-builtin "shard-last")))))

(define (shard-prefix)
  (message "C-c C-v-")
  (let* ((key (get-key))
         (entry (assoc key *shard-keys*)))
    (clear-message-line)
    (if entry
        ((cdr entry))
        (message "C-c C-v " key " is not bound (n p g [ ]: shards)"))))

(global-set-key "C-c C-v" shard-prefix)
;; org.scm, loaded after this file, keeps this binding for buffers that are
;; not Org; in an Org buffer its C-c C-v (Babel) passes n, p and g here.
