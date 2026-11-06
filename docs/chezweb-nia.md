# Nia Vardalos using Chezweb
-- just a test.
In order to get acquainted with editing and scripting, let us
accompany the Canadian programmer Nia Vardalos, while she explores
Chezweb.

When text is needed for carrying out a command, it is read from the
minibuffer, a one line window at the bottom of the screen. For
instance, if Nia presses `C-s` for finding a text, the text is read
from the minibuffer. After typing the text that she wants to localize,
Nia presses `C-s` again to start the search. For abandoning an ongoing
command, she may press `C-g`.

To transport a region from one place to another, Nia presses `C-Spc`
to start the selection process and move the cursor to select the
region. Then she presses `C-w` to kill her selection. Finally, she
moves the cursor to the insertion place, and presses the `C-y`
shortcut. Of course, she can select the region with the mouse instead.

To copy a region, Nia presses `C-Spc` and moves the cursor to select the region.
Then she presses `M-w` to save the selection into the kill ring. Finally,
she takes the cursor to the destination where the copy is to be inserted and
issues the `C-y` command. If she wants an earlier kill,
she presses `M-y` right after `C-y`, and Browsered replaces
the yanked text with the kill before it.

The kill ring and the system clipboard work together, as in
Emacs. Whatever Nia kills or copies with `C-w`, `M-w` or
`C-k` also goes to the clipboard, so she can paste it into any
other program. And when she copies something in another program,
say a paragraph in her browser, `C-y` inserts it, and it joins
the kill ring; `M-y` then goes on to her older kills. In a
terminal, Browsered reaches the clipboard through `pbcopy` and
`pbpaste` on the Macintosh, and through `wl-copy` or
`xclip` on Linux (install one of them); in a window, it needs
nothing.

When Nia selects text by dragging the mouse, Browsered copies it to
the clipboard at once: `Cmd-V` pastes it in her browser, and she never
needs `Cmd-C`. In fact, in a terminal `Cmd-C` finds nothing to copy,
because Browsered takes the mouse for itself (that is how the buttons
of the status line work); iTerm2 then complains that mouse reporting
has prevented making a selection. The text is already on the
clipboard. If Nia wants the terminal’s own selection, she keeps
`Option` down while she drags.

Nia noticed that there are two equivalent ways to issue an `M-`κ
command. She can press and release the `Esc` key, then strike the κ
key. Alternatively, she can keep the `Alt` key down and press the `κ`
key.

## Calculations with Lisp.
Chezweb offers a Lisp Scheme dialect to perform calculations and
text processing. Let us assume that Nia wants to find how many students
graduate from medical schools in California. She presses `Esc :` and
Chezweb will prompt her for a Lisp expression.

> `> (+ 190 180 170 160 120 100 100 90)``Enter`

In the above expression, the first thing after the open parenthesis is
the `+` sum operation identifier. After the name of the operation,
there is a list of the arguments to be added together. As soon as Nia
presses the `Enter` key, Chezweb shows the result of the addition:

> `1110`

The rule that worked for the `(+ x₁ x₂ …)` sum operation also works
for the other arithmetic function too.

  - Multiplication is performed by the `*` operation.
    
    > `Esc``:`  
    > `> (* 1 2 3 4 5)``Enter`  
    > 120

  - Division is obtained through the `/` operation.
    
    > `Esc``:`  
    > `> (/ 1 2 4)``Enter`  
    > 0.125
    
    The above operation performed the chain division `1/2/4`.
    
  - Subtraction has the syntax shown below.
    
    > `Esc``:`  
    > `> (- 1 2 4)``Enter`  
    > \-5

  - Mixed operations. One can nest subexpressions within an outer
    expression. For instance, to get the average student number
    graduating from medical school in California, one can calculate
    the expression:
    
    > `Esc``:`  
    > `> (/ (+ 190 180 170 160 120 100 100 90) 8.0)``Enter`  
    > 138.75


## Command execution.

When you press shortcut keys, Chezweb calls a command written in C
or in Scheme. You can get a complete list of all Chezweb keybindings
by pressing `C-h`.

There are commands that are not associated to shortcut keys. For
instance, the `undo-status` command tells how many steps of undo the
buffer keeps. Press `Esc``x` and type `undo-status` at the minibuffer
prompt. The `Tab` key completes the name of the command. Below you
will find a fairly complete list of Chezweb commands.

## Moving.

    C-f          forward one character (also the right arrow)
    C-b          back one character (also the left arrow)
    C-n          next line (also the down arrow)
    C-p          previous line (also the up arrow)
    M-f          forward one word
    M-b          back one word
    C-a          beginning of the line
    C-e          end of the line
    M-m          first non-blank character of the line
    M-a          back to the start of the sentence
    M-e          forward to the end of the sentence
    M-{          back one paragraph
    M-}          forward one paragraph
    C-v          next screen
    M-v          previous screen
    M-<          beginning of the file
    M->          end of the file
    M-g          go to a line number
    C-l          put the cursor's line in the middle of the window
    C-M-f        forward over an expression (Lisp: an s-expression)
    C-M-b        back over an expression
    C-M-u        out to the enclosing parenthesis
    C-M-d        into the next parenthesis
    C-M-a        beginning of the definition (defun, function)
    C-M-e        end of the definition

## Selecting.

The region is shaded.

    C-Spc        set the mark: the region runs from it to the cursor
    mouse        click to move the cursor or choose a window;
                 drag to select
    C-x h        select the whole file
    M-h          select the paragraph
    M-@          select to the end of the word
    C-M-Spc      select to the end of the expression
    C-x C-x      swap the cursor and the mark
    C-g          unselect; cancel a command

## Killing (cutting) and yanking (pasting).

    C-w          kill the region
    M-w          copy the region
    C-y          yank the last kill
    M-y          right after C-y: replace it with the kill before
    C-k          kill to the end of the line (again: joins the kills)
    M-d          kill the next word
    M-DEL        kill the previous word
    M-k          kill to the end of the sentence
    C-M-k        kill the next expression
    M-z          kill up to and including a character
    C-d          delete the character under the cursor
    DEL          delete the character before the cursor (Backspace)
    C-c i        choose a kill to insert
    C-c k        browse the kill ring

## Changing text.

    C-/          undo the last command; again: the one before
    C-M-_        redo what undo took back (also M-_)
    C-t          swap the two characters at the cursor
    M-t          swap two words
    C-x C-t      swap this line with the one above
    M-u          upper-case the next word
    M-l          lower-case the next word
    M-c          capitalize the next word
    C-x C-u      upper-case the region
    C-x C-l      lower-case the region
    C-o          open a line after the cursor
    C-j          new line, indented
    TAB          indent the line
    C-x TAB      indent the region (also C-M-\)
    M-^          join this line to the previous one
    M-\          delete the spaces around the cursor
    M-Spc        leave just one space
    C-x C-o      delete blank lines
    M-q          refill the paragraph or comment
    M-;          comment: add one, or (un)comment the region
    C-q          insert the next key as it is (C-q TAB: a tab)
    INS          overwrite mode on or off

## Searching, buffers, windows and macros.

    C-s          search forward (C-s again: next match)
    C-r          search backward
    M-%          replace, asking each time (also M-r)
    C-x C-g      grep: search files
    C-x !        next grep match
    C-x b        choose a buffer from a filtered, completing list
    C-x C-b      buffer menu
    C-x 2        split the window
    C-x o        go to the other window (or click it)
    C-x 0        close this window
    C-x 1        close the other windows
    C-x (        start recording keys
    C-x )        stop recording
    C-x e        replay them; then e replays again

## Lisp and assistants.

    C-x C-e      evaluate the expression before the cursor
    C-M-x        evaluate the top-level form around the cursor
    M-:          evaluate an expression typed at the bottom
    M-]          evaluate the block and insert the value
    M-!          a window for a shell command; C-c s runs it
    C-x C-r      reload the Lisp scripts (no rebuild needed)
    C-c r        Claude: hints, a question or a discussion
    C-c y        insert the code of the last answer
    C-c t        in the discussion: insert the snippet under the cursor
    C-c g        write a request for ChatGPT (Codex)

## Shell commands.

`M-!` opens a window below the file, where Nia writes a command for
the operating system, say `ls -l` or `sbcl --script fib.lisp`. A long
command may take several lines: `Enter` breaks the line, and Browsered
joins the lines again as the system expects (with `\` at the end of
each line on Linux and the Macintosh). `C-c s` runs the command in the
folder of her file. The window then shows the command and, below it,
what the command printed; if it failed, its exit status too. `C-x 1`
closes the window. Its status line has two buttons, so Nia can click
instead of typing:

> 
> 
>    *shell-command*, L. 1 == [SEND - C-c s] [CLOSE - C-x 1]

