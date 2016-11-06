;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;  FILE:     dired.cmd
;  CREATED:  11-Aug-93
;  PURPOSE:  Dired for MicroEMACS
;  AUTHOR:   Hugh Barney
;            
;
;  Dired for MicroEMACS was inspired by the Dired utility available in
;  GNU EMACS.
;  Permission is granted to copy, distribute and use this software
;  wherever Daniel M Lawrence's MicroEMACS is used.
;
;  Amendments
;  V1.00 31-Oct-93 HGB Completed
;  V1.01 15-Nov-93 HGB made dired remember dired-fspec between invocations
;  V1.02 22-Nov-93 HGB Fixed crash when view called on a directory.
;  V1.03 28-Nov-93 HGB set $discmd TRUE whilst getting user reponse to
;        prompts on status line
;  V1.04 08-Dec-93 HGB delete procedures on exit using the command
;        delete-buffer "[proc-name]"
;  V1.05 15-Dec-93 Load %dired-dir from DIREDDIR environment variable
;        if %dired-dir is ""
;  V1.06 27-Jan-94 made use of $gflags =3 to supress redraw events
;        when executing muliple shell commands
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;  set up variables

set $discmd FALSE
set %dired-ver "Dired V1.06 27-Jan-94"
!if &and &equ 0 &len %dired-dir &len &env DIREDDIR
	set %dired-dir &env DIREDDIR
!endif
set %dired-rflag 0      ; reverse alpha list flag
set %dired-tflag 0      ; sort by time flag
set %dired-fg WHITE
set %dired-bg blue
set %spaces "              "
set %helpline "    (h=help)"
set %nofiles 0
set %ffunc ""           ; dos command function parameters
set %tfunc ""           ;

store-procedure get-fname
	end-of-line
	search-reverse " "
	forward-character
	set-mark
	end-of-line
	kill-region
	yank
	set %fname $kill
!endm

store-procedure status-line
	!if &equ &len %dired-fspec 0
		print &cat %cwd %helpline
	!else
		print &cat &cat &cat %cwd "/" %dired-fspec %helpline
	!endif
!endm

store-procedure kill-dired-bufs
	select-buffer [Dired]
	unmark-buffer
	!force select-buffer [FileList]
	unmark-buffer
	select-buffer main
	delete-other-windows
	!force delete-buffer [Dired]
	!force delete-buffer [FileList]
!endm

store-procedure kill-flist
	select-buffer [FileList]
	unmark-buffer
	select-buffer [Dired]
	delete-other-windows
	!force delete-buffer [FileList]
	update-screen
!endm

store-procedure is-dir
	set %file-is-dir 0
	beginning-of-line
	3 forward-character
	!if &seq "d" &chr $curchar
		set %file-is-dir 1
	!endif
!endm

store-procedure getcwd
	pipe-command "cd"
	delete-mode view
	replace-string "\" "/"
	beginning-of-line
	kill-to-end-of-line
	set %cwd &low &trim $kill
	unmark-buffer
	select-buffer main
	!force delete-buffer command
!endm

store-procedure make-target-cwd       ; make current working dir in unix form
	!if &seq %fname "."          ; as adjust by selected subdir
		!return
	!endif

	!if &seq %fname ".."
		!while &not &seq "/" &rig %cwd 1
			set %tmp &len %cwd
			set %tmp &sub %tmp 1
			set %cwd &lef %cwd %tmp
		!endwhile
		set %tmp &len %cwd
		set %tmp &sub %tmp 1
		set %cwd &lef %cwd %tmp
		!if &seq 2 &len %cwd
			set %cwd &cat %cwd "/"
		!endif
		!return
	!endif

	!if &not &seq "/" &rig %cwd 1
		set %cwd &cat %cwd "/"
	!endif
	set %cwd &cat %cwd %fname
!endm

store-procedure make-dos-path     ; convert unix path to a dos path string
	set %tmp &len %cwd       ; so we can pass it to emacs
	set %dos-path ""
	set %cnt 0
	!while &les %cnt %tmp
		set %cnt &add %cnt 1
		set %ch &mid %cwd %cnt 1
		!if &seq %ch "/"
			set %dos-path &cat %dos-path "\"
		!else
			set %dos-path &cat %dos-path %ch
		!endif
	!endwhile
	!if &seq "\" &rig %dos-path 1  ;; remove last "\" if just drive
		set %tmp &len %dos-path
		set %tmp &sub %tmp 1
		set %dos-path &lef %dos-path %tmp
	!endif
	set %dos-path &low %dos-path
!endm

store-procedure get-marked-files
	set %save-line $curline
	beginning-of-file
	set %mark-count 0
	!while &gre &len $line 0
		beginning-of-line
		!if &seq "M" &chr $curchar
			set %mark-count &add %mark-count 1
			run get-fname
			select-buffer [FileList]
			insert-string &cat %fname
			insert-string &left %spaces &sub 13 &len %fname
			select-buffer [Dired]
		!endif
		!force next-line
	!endwhile
	!if &gre %mark-count 0     ;;; wrap files in file list window
		select-buffer [FileList]
		beginning-of-file
		add-mode WRAP
		fill-paragraph
		delete-mode WRAP
		beginning-of-file
		replace-string "~n~n" ""
		replace-string "~n~n" ""
		unmark-buffer
		select-buffer [Dired]
	!endif
	!force %save-line goto-line
!endm

store-procedure display-flist
	2 split-current-window      ;;; ensure new window always at bottom
	select-buffer [FileList]
	add-mode %dired-fg
	add-mode %dired-bg
	end-of-file
	!force &sub $curline 1 resize-window
	!if &not $status
		21 resize-window
	!endif
	beginning-of-file
	next-window              ;;; dired window
	add-mode %dired-fg
	add-mode %dired-bg
	unmark-buffer
	update-screen
!endm

store-procedure dired-ffunc
	select-buffer [Dired]
	delete-other-windows
	beginning-of-file
	update-screen
	run make-dos-path
	set %mark-count 0
	!while &gre &len $line 0
		beginning-of-line
		!if &seq "M" &chr $curchar
			set %mark-count &add %mark-count 1
			run get-fname
			select-buffer [FileList]
			!if &gre &len %tfunc 0
				insert-string &cat &cat &cat &cat %&cat &cat %ffunc %dos-path "\" %fname " " %tfunc "~n"
			!else
				insert-string &cat &cat &cat &cat %ffunc %dos-path "\" %fname "~n"
			!endif
			select-buffer [Dired]
		!endif
		!force next-line
	!endwhile

	select-buffer [Dired]
	beginning-of-file
	update-screen
	select-buffer [FileList]
	beginning-of-file
	beginning-of-line

	; This loop executes the file management commands

	set $gflags 3 ; turn off redraws (maybe only in v3.12)

	!while &gre %mark-count 0
		set %tmp $line
		!force next-line
		!force shell-command %tmp
		print %tmp
		set %mark-count &sub %mark-count 1
	!endwhile
	set %save-line 1
	set $gflags 1 ; turn on redraws (maybe only in v3.12)
!endm

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;          main body of dired
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

set %save-line 1
!if &equ 0 &len %dired-dir
	run getcwd
!else
	set %cwd %dired-dir
!endif

*get-list   ;;;;;  read in directory list

run kill-dired-bufs
set %tmp ""
!if %dired-rflag
	set %tmp &cat %tmp "r"
!endif
!if %dired-tflag
	set %tmp &cat %tmp "t"
!endif
!if &gre &len %dired-fspec 0
	pipe-command &cat &cat &cat &cat &cat "ls -lad" %tmp " " %cwd "/" %dired-fspec
!else
	pipe-command &cat &cat &cat &cat "ls -la" %tmp " " %cwd
!endif

select-buffer "command"
delete-other-windows
update-screen
delete-mode view
add-mode %dired-fg
add-mode %dired-bg

!force 1 goto-line                         ;;; kill total line if exists
!if $status
	add-mode MAGIC
	!force search-forward "^total"
	!if $status
		beginning-of-line
		!force 1 kill-to-end-of-line
	!endif
	delete-mode MAGIC
	set %nofiles 0
!else
	insert-string &cat &cat "~n~n~tno files of type " %dired-fspec " found"
	unmark-buffer
	set %nofiles 1
!endif

1 goto-line
!force search-forward "_xlk"              ;;; kill _xlk line if exists
!if $status
	beginning-of-line
	!force 1 kill-to-end-of-line
!endif

1 goto-line
!force search-forward " .~n"              ;;; . directory if exists
!if $status
	backward-character
	beginning-of-line
	!force 1 kill-to-end-of-line
!endif

beginning-of-file                         ;;; remove junk from ls output
replace-string "1 anonymou anonymou" ""

beginning-of-file                         ;;; remove full path id quoted
!force search-forward ":/"
!if $status
	3 backward-character
	set-mark
	end-of-line
	search-reverse "/"
	forward-character
	kill-region
	set %tmp $kill
	replace-string %tmp ""
!endif

beginning-of-file                         ;;; format presentation
insert-string "   "
replace-string "~n" "~n   "

beginning-of-file                         ;;; rename to Dired buffer
set-mark
end-of-file
kill-region
unmark-buffer
select-buffer [Dired]
yank
beginning-of-file
!force delete-buffer command
replace-string "~n   ~n~n" ""
beginning-of-file
unmark-buffer

delete-other-windows
update-screen                 ; we need these 2 update-screens so that
run status-line               ; the %cwd is displayed on the message line
!force %save-line goto-line
!if &equ 0 &len $line
	!force previous-line
!endif
end-of-line
update-screen

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;       process key strokes whilst in Dired window
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

!while TRUE
	set %opt &gtc    ; get string of emacs command

 	!if &seq %opt "x"     ; exit dired and save current directory
		run kill-dired-bufs
		!break
	!endif

	!if &seq "s" %opt     ;;; set file spec
		set $discmd TRUE
		set %dired-fspec @"Enter filespec: "
		!if &seq %dired-fspec "Enter filespec: "
			set %fpsec ""
		!endif
		set $discmd FALSE
		!goto get-list
	!endif

	!if &seq "u" %opt         ;;; go up to parent directory
		!if &gre &len %cwd 3
			set %fname ".."
			make-target-cwd
			set %dired-fspec ""
			!goto get-list
		!endif
 		!goto endloop
	!endif

	!if &or &seq "h" %opt &seq "?" %opt
		kill-dired-bufs
		source diredhlp.cmd
		!goto get-list
	!endif

	!if %nofiles          ;;; don't allow other commands if nofiles
		!goto endloop
	!endif

	!if &seq "m" %opt     ;;; toggle file marker
		run is-dir
		!if %file-is-dir
			!force next-line
			!goto endloop
		!endif
		beginning-of-line
		!if &equ $curchar 77
			overwrite-string " "
		!else
			overwrite-string "M"
		!endif
		unmark-buffer
		!force next-line
		!goto endloop
	!endif

	!if &seq "~~" %opt    ;;; unmark all
		set %save-line $curline
		beginning-of-file
		!while &gre &len $line 0
			run is-dir
			!if &not %file-is-dir
				beginning-of-line
				overwrite-string " "
			!endif
			!force next-line
		!endwhile
		unmark-buffer
		%save-line goto-line
		!goto endloop
	!endif

	!if &seq "!" %opt   ;;; mark all
		set %save-line $curline
		beginning-of-file
		!while &gre &len $line 0
			run is-dir
			!if &not %file-is-dir
				beginning-of-line
				overwrite-string "M"
			!endif
			!force next-line
		!endwhile
		unmark-buffer
		%save-line goto-line
		!goto endloop
	!endif

	!if &seq "f" %opt   ;;; edit file or change directory
		get-fname
		!if &equ 0 &len %fname
			!goto endloop
		!endif
		run is-dir
		!if %file-is-dir
			set %dired-fspec ""
			make-target-cwd
			!goto get-list
		!else
			kill-dired-bufs
			make-dos-path
			find-file &cat &cat %dos-path "\" %fname
			!break
		!endif
	!endif

	!if &seq "d" %opt           ;;; delete marked files or current file
		run get-marked-files
		!if &gre %mark-count 0
			run display-flist
			print "Delete listed files y/n ? "
			!if &seq "y" &low &gtc
				set %ffunc "del "
				set %tfunc ""
				run dired-ffunc
				!goto get-list
			!endif
			run kill-flist
			!goto endloop
		!endif

		run is-dir          ;;; delete single file
		!if %file-is-dir    ;;; dont allow dirs to be deleted
			!goto endloop
		!endif
		get-fname
		set %save-line $curline
		make-dos-path
		print &cat &cat "Delete "  %fname " y/n ? "
		!if &seq "y" &low &gtc
			shell-command &cat &cat &cat "del " %dos-path "\" %fname
			!goto get-list
		!endif
		!goto endloop
	!endif

	!if &seq "r" %opt           ;;; rename file
		run is-dir
		!if %file-is-dir    ;;; skip a directory
			!goto endloop
		!endif
		get-fname
		set %save-line $curline
		make-dos-path
		set %tmp &cat &cat "rename "  %fname " to "
		set $discmd TRUE
		set %tfunc @%tmp
		set $discmd FALSE
		!if &seq %tfunc %tmp
			!goto endloop
		!endif

		;;; to rename a file with a path we do
		;;; an explicit copy followed by a delete

		!if &gre &len %tfunc 0
			shell-command &cat &cat &cat &cat &cat &cat &cat "copy " %dos-path "\" %fname " " %dos-path "\" %tfunc
			shell-command &cat &cat &cat "del " %dos-path "\" %fname
			!goto get-list
		!endif
		!goto endloop
	!endif

	!if &seq "v" %opt         ;;; load file in view mode
		get-fname
		!if &equ 0 &len %fname
			!goto endloop
		!endif
		run is-dir
		!if %file-is-dir
			set %dired-fspec ""
			make-target-cwd
			!goto get-list
		!endif
		kill-dired-bufs
		make-dos-path
		view-file &cat &cat %dos-path "\" %fname
		!break
	!endif

	!if &seq "o" %opt
		!if %dired-rflag
			set %dired-rflag 0
		!else
			set %dired-rflag 1
		!endif
		set %save-line 1
		kill-dired-bufs
		!goto get-list
	!endif

	!if &seq "t" %opt
		!if %dired-tflag
			set %dired-tflag 0
		!else
			set %dired-tflag 1
		!endif
		set %save-line 1
		kill-dired-bufs
		!goto get-list
	!endif

 	!if &or &seq "p" %opt &seq "previous-line" &bind %opt
 		!force previous-line
 		!goto endloop
 	!endif

 	!if &seq "\" %opt &seq   ;;; invoke incremental search through '\'
	 	set $discmd TRUE
	 	clear-message-line
 		execute-named-command "incremental-search"
	 	set $discmd FALSE
 		!goto endloop
 	!endif
 	                         ;;; enable all other bound search functions

 	!if &or &sin &bind %opt "search" &sin &bind %opt "hunt"
 		set %opt &bind %opt
	 	set $discmd TRUE
	 	clear-message-line
 		!force execute-named-command %opt
	 	set $discmd FALSE
 		!goto endloop
 	!endif

 	!if &or &seq "n" %opt &seq "next-line" &bind %opt
 		!force next-line
 		!goto endloop
 	!endif

 	!if &seq "previous-page" &bind %opt
 		!force 10 previous-line
 		!goto endloop
 	!endif

 	!if &seq "next-page" &bind %opt
 		!force 10 next-line
 		!goto endloop
 	!endif

 	!if &or &seq "beginning-of-line" &bind %opt &seq "beginning-of-file" &bind %opt
 		!force beginning-of-file
 		!goto endloop
 	!endif

 	!if &or &seq "end-of-file" &bind %opt &seq "end-of-line" &bind %opt
 		!force end-of-file
		!force previous-line
 		!goto endloop
 	!endif

*endloop

	!if &equ 0 &len $line
		!force previous-line
	!endif
	run status-line
	end-of-line
	unmark-buffer
	update-screen

!endwhile

delete-buffer "[get-fname]"
delete-buffer "[kill-dired-bufs]"
delete-buffer "[is-dir]"
delete-buffer "[getcwd]"
delete-buffer "[make-target-cwd]"
delete-buffer "[make-dos-path]"
delete-buffer "[count-marks]"
delete-buffer "[kill-flist]"
delete-buffer "[display-flist]"
delete-buffer "[status-line]"
delete-buffer "[dired-ffunc]"

set %dired-dir %cwd
set $discmd TRUE
