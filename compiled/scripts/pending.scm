;;;; pending.scm -- what the compiled scripts call in scripts not compiled yet
;;;;
;;;; While the scripts move to compiled/scripts/ one by one (step 4), the
;;;; compiled ones may call procedures of those still in scheme/.  Each is
;;;; here, failing with a clear message, until its own file is compiled; then
;;;; its line goes.  When this file is empty, the switch can be made.
;;;;
;;;; compiled/scripts/ORDER lists the files of the compiled scripts, in the
;;;; order init.scm loads them; a script that needs no change (most
;;;; language files) is listed from scheme/ itself.

(define (%pending name) (lambda args (error "not compiled yet:" name)))

