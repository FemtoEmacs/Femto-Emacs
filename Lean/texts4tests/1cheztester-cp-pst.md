# SBEmacs commands

**How to type a command.**
`C-` is the `Ctrl` key and `M-` is the `Esc` key.

|         |                                                                    |
| :------ | :----------------------------------------------------------------- |
| C-f     | Keep `Ctrl` down and press `f`.                                    |
| M-f     | Press `Esc` and let go of it, then press `f`.                      |
|         | or keep `Alt` (`Option` on a Mac) down and press `f`.              |
| C-x C-s | Keep `Ctrl` down and press `x`, then `s`. Then let go of `Ctrl`.   |
| C-x b   | Keep `Ctrl` down and press `x`. Let go of `Ctrl`, then press `b`.  |
| C-M-f   | Press `Esc` and let go of it, then keep `Ctrl` down and press `f`. |

-----

**Files** 

|           |                        |
| :-------- | :--------------------- |
| `C-x C-f` | open a file            |
| `C-x C-s` | save                   |
| `C-x C-w` | save with another name |
| `C-x i`   | insert a file          |
| `C-x C-c` | quit                   |

**Moving**  

|            |                            |
| :--------- | :------------------------- |
| `C-f  C-b` | forward, back one char     |
| `C-n  C-p` | next, previous line        |
| `M-f  M-b` | forward, back one word     |
| `C-a  C-e` | beginning, end of the line |
| `C-v  M-v` | next, previous screen      |
| `M-<  M->` | beginning, end of the file |
| `M-g`      | go to a line number        |

**Editing**  

|         |                               |
| :------ | :---------------------------- |
| `BkSp`  | delete char before the cursor |
| `C-d`   | delete char under the cursor  |
| `C-k`   | kill to end of line           |
| `C-/`   | undo; again: undo more        |
| `C-M-_` | redo                          |
| `TAB`   | indent the line               |
| `M-q`   | refill the paragraph          |
| `M-;`   | comment line or region        |


**Code blocks**
In Markdown, commands such as `M-;` (comment line) and `TAB` (indent the line)
work only in code blocks, and obey the syntax of the computer language you are
editing.

```Scheme
(define (fib n)
  (if (< n 2) 1
      (+ (fib (- n 2))
         (fib (- n 1)) )))

```

**Region (shaded)**  

|         |                            |
| :------ | :------------------------- |
| `C-Spc` | set mark                   |
| `mouse` | drag to select             |
| `C-w`   | kill region                |
| `M-w`   | copy the region            |
| `C-y`   | yank (paste)               |
| `M-y`   | after C-y: an earlier kill |
| `C-g`   | cancel command             |

**Searching**  

|       |                 |
| :---- | :-------------- |
| `C-s` | search forward  |
| `C-r` | search backward |
| `M-%` | replace         |

**Buffers and windows**  

|           |                                                  |
| :-------- | :----------------------------------------------- |
| `C-x b`   | choose a buffer from a filtered, completing list |
| `C-x C-b` | buffer menu                                      |
| `C-x 2`   | split the window                                 |
| `C-x o`   | other window (or click it)                       |
| `C-x 0`   | close this window                                |
| `C-x 1`   | close other window                               |

**Help, Lisp and AI**  

|           |                         |
| :-------- | :---------------------- |
| `C-h`     | help with keybinding    |
| `M-x`     | run a command by name   |
| `M-:`     | eval a Lisp             |
| `C-x C-e` | eval Lisp before cursor |
| `C-c r`   | call Claude             |
| `C-c y`   | insert Claude’s code    |
| `C-c g`   | call Codex/ChatGPT      |
| `C-c q`   | close Codex/Claude      |

# The commands in detail

This chapter explains the commands on the first page in more detail.
The next chapter shows how to install and run Browsered.

In the following cheat sheet, `Spc` denotes
the space bar, `C-` is the `Ctrl` prefix, `M-` represents
the `Alt` prefix, and κ can be any key.

### Help.

If you forget a command, press `C-h` or `F1`.
Browsered shows all its keybindings on a page of their own,
one key per line. The arrows, `C-n` and `C-p` scroll
the page; any other key takes you back to the file you are editing.

### The status line is a menu.

At the bottom of each window,
the status line shows the name of the file and the line where the
cursor is. An asterisk after the file name means that the file has
been modified, but not saved. Then come buttons that the mouse can
click:

> 
> 
>  fib.lisp*, L. 5  [?] [SAVE][UNDO][Select][MORE][TTFY][GRAMMAR] ...

A button does what its key does, so Nia, the Canadian
girl who is learning how to code, can work before she
learns the keys, and learn them from the buttons:

> 
> 
> |                  |           |                             |
> | :--------------- | :-------- | :-------------------------- |
> | `[?]` + 1        | `C-h`     | every key on one page       |
> | `[SAVE]`         | `C-x C-s` | save the file               |
> | `[UNDO]`         | `C-/`     | undo                        |
> | `[MORE]` Open    | `C-x C-f` | open a file                 |
> | `[MORE]` Copy    | `M-w`     | copy the selection          |
> | `[MORE]` Paste   | `C-y`     | paste                       |
> | `[?]` 2 or 3     |           | how to ask Claude or Codex  |
> | `[MORE]` Buffers | `C-x b`   | switch to another open file |
> | `[QUIT]`         | `C-x C-c` | leave SBEmacs               |
> | `[GRAMMAR]`      |           | Toggle Grammarly            |
> 

Grammarly is a pain in the ass, but if you need to write in English,
you have no choice. It's the only Computer-Aided Writing Tool that
gets past any AI detector. The Grammarly button lets you toggle
Grammarly on and off. Word of advice: when you're not using Grammarly,
leave it turned off.
  
The file name is also a button. A name longer than 18
characters is shortened at the front, as in
`...src/fib.lisp`. A click on the name opens a window with the
full name of the file, its number of lines, words, characters and
bytes, the line of the cursor, the language, and whether and when it
was saved. Any key closes that window.
To copy, Nia drags the mouse over the text and clicks
`[MORE] Copy`; she then clicks where the copy should go, and clicks
`[MORE] Paste`. A button lights up while she presses it, and acts
when she lets it go; if she changes her mind, she moves the mouse
off the button before letting go. If Nia leaves Browsered with
`[QUIT]` while a file is not saved, the Editor asks first.

The whole status line is written in Scheme, in
`scheme/extensions/menu.scm`. The buttons are a list,
`*mode-line-menu*`, which Nia can change in her init file:

> 
> 
>     (set! *mode-line-menu*
>           (append *mode-line-menu* '(("KILL" "C-x k"))))

### Basic commands.

`C-`κ – Keep `Ctrl` down
and press `κ`

> `C-s` then type some text, and press `C-s` again
> – search for text.  
> `C-r` then type some text, and press `C-r` again
> – reverse search.  
> `C-k` – kill a line.  
> `C-h` – help (the backspace key deletes backward).  
> `C-d` – delete char forward.  
> `C-Spc` then move the cursor – select a region.  
> `M-w` – save selected region into the kill ring.  
> `C-w` – kill region.  
> `C-y` – insert killed or saved region.  
> `C-g` – cancel minibuffer reading, or unselect the region.  
> `C-a` – go to beginning of line.  
> `C-e` – go to end of line.  
> `C-b` – move backward one character.  
> `C-f` – move forward one character.  
> `C-n` – move cursor to the next line.  
> `C-p` – move cursor to the previous line.  
> `C-l` – put the line of the cursor in the middle of the window.  
> `C-/` – undo. `C-u` also undoes.  
> `C-v` – forward page.  
> `INS` – toggle overwrite mode.  
> `←` `→` `↑` `↓` – arrows move the cursor.  

### Control-x commands.

`C-x C-`κ – Keep `Ctrl`
down and press `x`, then `κ.`

> `C-x C-f` – open a file into a new buffer.  
> `C-x C-w` – write file with a new name.  
> `C-x C-s` – save file.  
> `C-x s` – save every modified file, asking first.  
> `C-x C-c` – exit Browsered.  
> `C-x i` – insert file at the cursor.  
> `C-x ?` – describes a key stroke.  
> `C-x @` – shell command. After `C-x @`,
> if one types `ls` at the prompt, the computer
> will list the current folder.
> It is possible to use any other shell command
> just like the `ls` example.

### Window commands.

One can have more
than one window on the screen. Below, you will
find commands that cope with this situation.

  - ` C-x  `κ – Keep `Ctrl` down and press `x`;
    let go of `Ctrl`, then press `κ`
    
    > `C-x b` – choose a buffer. Type to filter the visible list,
    > `Tab` completes the common prefix, the arrow keys select an entry,
    > `Enter` opens it, and `C-g` cancels. The previous buffer is
    > selected initially, so repeated use quickly alternates between two buffers.  
    > `C-x n` – next buffer.  
    > `C-x C-n` – next buffer. Same as above.  
    > `C-x C-b` – list buffers.  
    > `C-x k` – kill current buffer.  
    > `C-x =` – cursor position.  
    > `C-x 2` – split window into cursor window and other window.  
    > `C-x o` – jump to the other window.  
    > `C-x 1` – close the other window.  
    > `C-x 0` – close the cursor window.  
    > `C-x ^` – make the cursor window taller.
    > `C-^`   - make the cursor window taller.
      
  - `Esc` κ – Press the `Esc` key and let go of it,
    then press the `κ` key.
    
    > `Esc >` – go to the end of buffer.  
    > `Esc <` – go to the beginning of buffer.  
    > `Esc f` – word forward.  
    > `Esc b` – word backward.  

  - `M`-κ – Keep the `Alt` key
    down and press the `κ` key. On the Macintosh,
    the `Alt` key is called `Option`; in the Terminal
    application, you must tick *Use Option as Meta key*
    in Settings, Profiles, Keyboard. In iTerm2, open Settings,
    Profiles, Keys and set *Left Option key* to *Esc+*.
    The right Option key may remain *Normal* for entering Mac symbols.
    
    > `M-b`   – move backward one word.  
    > `M-f`   – move forward one word.  
    > `M-g`   – go to the line given in the minibuffer.  
    > `C-x →` – activate the next buffer.  
    > `C-x ←` - activate the previous buffer.
    > `M-r`   – query replace. `M-%` does the same.

### The mouse.

You can click on a window to move
the cursor there; a click on another window selects that window.
If you keep the button down and drag the mouse, you select a region.
This works in the graphical window and in the text terminal.
In a text terminal, SBEmacs takes the mouse from the terminal; if
you want the terminal’s own selection, hold down the `Shift`
key (the `Option` key in the Macintosh Terminal) while
you drag, or start the Editor with the `--no-mouse` option.

### The region.

The region is the text between the mark,
which you set with `C-Spc`, and the cursor. Like in Emacs,
SBEmacs shades the region while it is active. The shade goes away
when you change the text, when you copy the region with `M-w`,
or when you press `C-g`.

### Query replace.

If you press `Esc``r`,
the computer enters in the query replace mode.
First, Browsered prompts for the text snippet S
that you want to replace. Then it prompts for
the replacement R. When you type the R text and
press the `Enter` key, the cursor jumps to
the first occurence of S, and SBEmacs
asks whether you want to
replace it. If the answer is
`y`, Browsered will replace S
with `R` and jump to the next occurence.
If the answer is `n`, SBEmacs will
jump to the next occurrence of S without
performing the replacement.

### Go to line.

When you try to compile
code containing errors, the compiler
usually reports the line number where the error occurred.
If you press `Esc``g`, Browsered
prompts for a line number. As soon as you
type the number and press the `Enter`
key, the cursor jumps to the line where the
error occurred.

In order to know the position of the cursor,
press the `C-x =` command,
and SBEmacs gives information concerning
the character under the
cursor, the corresponding code, the line,
and the character position in the text.

### Markdown.

Browsered colours Markdown files (`.md`):
headings, `**strong**` and `*emphasis*`, code between back
quotes, links, quotations and lists. A block of code that names its language,
like ` ```lisp `, is coloured as that language. In a list,
`Enter` starts the next item, ` -  ` or ` 3. `;
`Enter` on an empty item ends the list. `Tab` nests an item under
the item above, and `M-q` refills a paragraph or a list item.

### Undo.

The `C-/` command undoes the last
command. If you press it again, it undoes the command before,
and so on. Typed text is undone a word at a time, and a command
that changed many lines, like `M-q` (fill paragraph), is undone
at once. If you undo too much, `C-M-_` (or `M-_`) redoes
what undo took back. When you undo all the changes made since the
file was saved, the asterisk disappears from the status line.
--End-of-File
