# Chezweb, simply Emacs
Chezweb is a simpler implementation of Emacs, where simpler means fewer
features, but also means it's easier to learn and install.

## Installation on Silicon macOS
There is no macOS installer yet. On the Mac, you build Chezweb from
its sources with one command, `make`, which takes care of everything
else; see [Building from sources](#building-from-sources).
The same steps work on Intel Macs.

## Installation on Linux
On Ubuntu (22.04 or later) and Debian (12 or later), download the
installer for your processor:
[chezweb_amd64.deb](https://github.com/FemtoEmacs/Femto-Emacs/releases/download/chezweb-linux/chezweb_amd64.deb)
for Intel and AMD, or
[chezweb_arm64.deb](https://github.com/FemtoEmacs/Femto-Emacs/releases/download/chezweb-linux/chezweb_arm64.deb)
for ARM (`dpkg --print-architecture` says which). Then, in the folder
where it is:

```sh
sudo apt install ./chezweb_amd64.deb
```

apt installs the libraries that Chezweb needs, and the installation
makes the machine code for your processor, which takes about half a
minute. Then `chezweb notes.md` opens the editor in the terminal, in any
folder, and **Chezweb** in the applications menu opens it in a window.
`sudo apt remove chezweb` removes it. The
[release page](https://github.com/FemtoEmacs/Femto-Emacs/releases/tag/chezweb-linux)
has the checksums. On other distributions, build from the sources, as
explained in [Building from sources](#building-from-sources).

## Installation on Windows
Download **Chezweb-Windows-x86_64-Setup.exe** from the
[Chezweb 0.1 for Windows](https://github.com/FemtoEmacs/Femto-Emacs/releases/tag/chezweb-windows-0.1-2026-11-07)
release and run it. It installs for you alone, so it does not ask for an
administrator's password. If Windows warns that the publisher is
unknown, click *More info*, then *Run anyway*. The Start menu then has a
Chezweb folder with **Chezweb** (the editor in a text window), **Chezweb
GUI** (the graphical window) and **Uninstall**. For the browser editor,
install Google Chrome. You need no compiler. The installer is a preview,
made on 7 November 2026: the features added since then, such as Org mode
and Korean input, are not in it yet.

## Building from sources
First, the tools that every Mac and Linux machine can have:

- **macOS:** Apple's command line tools. In the Terminal, type
  `xcode-select --install`.
- **Debian or Ubuntu:**
  `sudo apt install build-essential libncurses-dev pkg-config curl xz-utils git`.
- **The graphical window (optional):** `brew install sdl2 sdl2_ttf` on
  the Mac (with [Homebrew](https://brew.sh)), or
  `sudo apt install libsdl2-dev libsdl2-ttf-dev` on Debian or Ubuntu.
  Without them, you still get the text window and the browser editor.

Then clone the repository and build:

```sh
git clone https://github.com/FemtoEmacs/Femto-Emacs.git
cd Femto-Emacs
make
./chezweb notes.md
```

The first `make` downloads the WebAssembly runtime (Wasmtime, checked
against its published checksum) and takes a few minutes. You need no
Node.js, Python or Scheme installation, and no API keys. `./chezweb`
opens the text window, and `./chezweb --gui` the graphical window. On
the Mac, you can also double-click `Chezweb.command` or
`Chezweb-GUI.command`, and `make app` makes an application, `Chezweb.app`.
To update, type `git pull`, then `make`.

**The path.** Chezweb finds its scripts beside itself, so leave
`chezweb` in its folder, and do not copy it elsewhere or make a link
to it. Put the folder on your path instead, so that `chezweb` works in
any folder. On the Mac, whose shell is zsh, type in the `Femto-Emacs`
folder:

```sh
echo "export PATH=\"$(pwd):\$PATH\"" >> ~/.zshrc
```

On Linux, whose shell is usually bash, write `~/.bashrc` instead of
`~/.zshrc`. Open a new terminal window, and `chezweb paper.md` opens
your paper wherever you are.

## Keybindings
Chezweb tries really hard to use the same basic keybindings as Emacs.
Therefore, if you already use Emacs, you should be able to create
documents with Chezweb the very day you download it. If you don't
know Emacs, it is not difficult to find tutorials online. Meanwhile,
the short cheat sheet below will be useful.

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

## An editor that runs on a browser
Chezweb runs in a Text User Interface and in a Graphical User Interface,
like Emacs or Neovim. The difference is that Chezweb runs also in your
browser, where it preserves the full features of the text windows and
helps you to communicate with online applications.

You need Google Chrome (or Chromium on Linux). Open a file in the text
window or in the graphical window, and press **C-c d**. Chrome opens with
the same text, unsaved changes included, and the window you left stays
open. In Chrome, **C-x C-s** saves the file: the native window writes it
to disk and gets your text too. If you edited the file in both windows,
Chezweb does not let one overwrite the other: it says so, and keeps your
text in both. Then **M-x native-window-update** puts the browser's text
in the native window, and C-x C-s saves it.

To open other files in Chrome, press **C-x C-f**, then **TAB**. Chrome
asks you to choose a folder, and asks only once per folder. TAB then
completes the names of its subfolders and files, and C-x C-s saves
straight into it. The **Choose folder** button grants another folder.
Chezweb reads nothing on your computer that you did not grant, and
writes only when you save.

The browser has the same keys and your settings (`~/.chezemax`). The
assistants (C-c r, C-c g) stay in the native window, which keeps your
login; in Chrome, those keys tell you to use it. **C-x C-c** closes the
browser tab and leaves the native window open.

## The commands in detail

This chapter explains the commands on the first page in more detail.

In the following cheat sheet, `Spc` denotes the space bar, `C-` is the
`Ctrl` prefix, `M-` represents the `Alt` prefix, and κ can be any key.

### Help.

If you forget a command, press `C-h` or `F1`. Chezweb shows all its
keybindings on a page of their own, one key per line. The arrows,
`C-n` and `C-p` scroll the page; any other key takes you back to the
file you are editing.

### The status line is a menu.

At the bottom of each window, the status line shows the name of the
file and the line where the cursor is. An asterisk after the file name
means that the file has been modified, but not saved. Then come
buttons that the mouse can click:

> 
> 
>  fib.lisp*, L. 5  [?][SAVE][UNDO][Select][MORE][TTFY]   [QUIT]

A button does what its key does, so Nia, the Canadian girl who is
learning how to code, can work before she learns the keys, and learn
them from the buttons:

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
> | `[QUIT]`         | `C-x C-c` | leave Chezweb               |
> | `Grammarly: off` |           | toggle Grammarly (browser)  |
> 

Grammarly is a pain in the ass, but if you need to write in English,
you have no choice. It's the only Computer-Aided Writing Tool that
gets past any AI detector. The Grammarly button, above the text in
the browser, lets you toggle Grammarly on and off. Word of advice:
when you're not using Grammarly, leave it turned off.
  
The file name is also a button. A name longer than 18 characters is
shortened at the front, as in `...src/fib.lisp`. A click on the name
opens a window with the full name of the file, its number of lines,
words, characters and bytes, the line of the cursor, the language, and
whether and when it was saved. Any key closes that window. To copy,
Nia drags the mouse over the text and clicks `[MORE] Copy`; she then
clicks where the copy should go, and clicks `[MORE] Paste`. A button
lights up while she presses it, and acts when she lets it go; if she
changes her mind, she moves the mouse off the button before letting
go. If Nia leaves Chezweb with `[QUIT]` while a file is not saved,
the Editor asks first.

The whole status line is written in Scheme, in
`compiled/scripts/menu.scm`. The buttons are a list,
`*mode-line-menu*`, which Nia can change in her init file:

> 
> 
>     (set! *mode-line-menu*
>           (append *mode-line-menu* '(("KILL" "C-x k"))))

### Basic commands.

`C-`κ – Keep `Ctrl` down and press `κ`

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

`C-x C-`κ – Keep `Ctrl` down and press `x`, then `κ.`

> `C-x C-f` – open a file into a new buffer.  
> `C-x C-w` – write file with a new name.  
> `C-x C-s` – save file.  
> `C-x s` – save every modified file, asking first.  
> `C-x C-c` – exit Chezweb.  
> `C-x i` – insert file at the cursor.  
> `C-x ?` – describes a key stroke.  
> `C-x @` – shell command. After `C-x @`,
> if one types `ls` at the prompt, the computer
> will list the current folder.
> It is possible to use any other shell command
> just like the `ls` example.

### Window commands.

One can have more than one window on the screen. Below, you will find
commands that cope with this situation.

  - ` C-x  `κ – Keep `Ctrl` down and press `x`;
    let go of `Ctrl`, then press `κ`
    
    > `C-x b` – choose a buffer. Type to filter the visible list,
    > `Tab` completes the common prefix, the arrow keys select an entry,
    > `Enter` opens it, and `C-g` cancels. The previous buffer is
    > selected initially, so repeated use quickly alternates between two buffers.  
    > `C-x C-n` – next buffer.  
    > `C-x n n` – narrow: show only the region; `C-x n w` widens.  
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

  - `M`-κ – Keep the `Alt` key down and press the `κ` key. On the
    Macintosh, the `Alt` key is called `Option`; in the Terminal
    application, you must tick *Use Option as Meta key* in Settings,
    Profiles, Keyboard. In iTerm2, open Settings, Profiles, Keys and
    set *Left Option key* to *Esc+*. The right Option key may remain
    *Normal* for entering Mac symbols.
    
    > `M-b`   – move backward one word.  
    > `M-f`   – move forward one word.  
    > `M-g`   – go to the line given in the minibuffer.  
    > `C-x →` – activate the next buffer.  
    > `C-x ←` - activate the previous buffer.
    > `M-r`   – query replace. `M-%` does the same.

### The mouse.

You can click on a window to move the cursor there; a click on another
window selects that window. If you keep the button down and drag the
mouse, you select a region. This works in the graphical window and in
the text terminal. In a text terminal, Chezweb takes the mouse from
the terminal; if you want the terminal’s own selection, hold down the
`Shift` key (the `Option` key in the Macintosh Terminal) while you
drag, or start the Editor with the `--no-mouse` option.

### The region.

The region is the text between the mark, which you set with `C-Spc`,
and the cursor. Like in Emacs, Chezweb shades the region while it is
active. The shade goes away when you change the text, when you copy
the region with `M-w`, or when you press `C-g`.

### Query replace.

If you press `Esc``r`, the computer enters in the query replace mode.
First, Chezweb prompts for the text snippet S that you want to
replace. Then it prompts for the replacement R. When you type the R
text and press the `Enter` key, the cursor jumps to the first
occurence of S, and Chezweb asks whether you want to replace it. If
the answer is `y`, Chezweb will replace S with `R` and jump to the
next occurence. If the answer is `n`, Chezweb will jump to the next
occurrence of S without performing the replacement.

### Go to line.

When you try to compile code containing errors, the compiler usually
reports the line number where the error occurred. If you press
`Esc``g`, Chezweb prompts for a line number. As soon as you type the
number and press the `Enter` key, the cursor jumps to the line where
the error occurred.

In order to know the position of the cursor, press the `C-x =`
command, and Chezweb gives information concerning the character under
the cursor, the corresponding code, the line, and the character
position in the text.

### Markdown.

Chezweb colours Markdown files (`.md`): headings, `**strong**` and
`*emphasis*`, code between back quotes, links, quotations and lists. A
block of code that names its language, like ` ```lisp `, is coloured
as that language. In a list, `Enter` starts the next item, ` - ` or `
3. `; `Enter` on an empty item ends the list. `Tab` nests an item
under the item above, and `M-q` refills a paragraph or a list item.

### Undo.

The `C-/` command undoes the last command. If you press it again, it
undoes the command before, and so on. Typed text is undone a word at a
time, and a command that changed many lines, like `M-q` (fill
paragraph), is undone at once. If you undo too much, `C-M-_` (or
`M-_`) redoes what undo took back. When you undo all the changes made
since the file was saved, the asterisk disappears from the status
line.

### Nia Vardalos.

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
she presses `M-y` right after `C-y`, and Chezweb replaces
the yanked text with the kill before it.

The kill ring and the system clipboard work together, as in
Emacs. Whatever Nia kills or copies with `C-w`, `M-w` or
`C-k` also goes to the clipboard, so she can paste it into any
other program. And when she copies something in another program,
say a paragraph in her browser, `C-y` inserts it, and it joins
the kill ring; `M-y` then goes on to her older kills. In a
terminal, Chezweb reaches the clipboard through `pbcopy` and
`pbpaste` on the Macintosh, and through `wl-copy` or
`xclip` on Linux (install one of them); in a window, it needs
nothing.

When Nia selects text by dragging the mouse, Chezweb copies it to
the clipboard at once: `Cmd-V` pastes it in her browser, and she never
needs `Cmd-C`. In fact, in a terminal `Cmd-C` finds nothing to copy,
because Chezweb takes the mouse for itself (that is how the buttons
of the status line work); iTerm2 then complains that mouse reporting
has prevented making a selection. The text is already on the
clipboard. If Nia wants the terminal’s own selection, she keeps
`Option` down while she drags.

Nia noticed that there are two equivalent ways to issue an `M-`κ
command. She can press and release the `Esc` key, then strike the κ
key. Alternatively, she can keep the `Alt` key down and press the `κ`
key.

## Exporting to LaTeX
**M-x latex-export**, in an Org or a Markdown file, writes the LaTeX
beside it (`paper.md` gives `paper.tex`) and opens it; if that file
exists, Chezweb asks before replacing it. In Org, **C-c C-e l l** does
the same, as in Emacs. Compile the result with `xelatex paper.tex`.
Headings, emphasis, links, images, lists, quotes, code blocks, tables
(sexp tables too, with their formulas computed) and Org's title, author
and date are exported. Math (`$...$`, `$$...$$`, `\(...\)`, `\[...\]`,
`\begin{equation}`) goes through untouched, and Greek, Korean and
Chinese get fonts that have them.

## Korean text input
**M-x korean-input** turns on the standard Korean keyboard (2-set,
두벌식); the same command turns it off. The mode line shows 한. You type
as on a Korean keyboard: `gksrmf` gives 한글, and `dkssud` gives 안녕.
The syllable you are typing changes as you type, before the cursor. A
vowel takes the last consonant into the next syllable, as in 갈 + ㅏ =
가라. **DEL** takes back the last letter of the syllable. Shift gives the
double consonants (`R` ㄲ, `T` ㅆ) and the vowels ㅒ and ㅖ. Korean input
costs nothing to those who do not turn it on.

## Chinese text input
**M-x chinese-input** turns on Chinese typed in tonal pinyin; the same
command turns it off. The mode line shows 中. Type the letters of a
syllable (ü is `v`), and its characters appear at the bottom, the most
frequent first. A digit from 1 to 5 picks the tone (5 is the neutral
tone), and then a digit from 1 to 9 picks the character; SPC takes the
first one. So `zhong1 1` types 中. After a character, the characters
that most often follow it appear: `1` after 中 gives 国. `-` and `=`
turn the pages of candidates, **DEL** takes back the tone or a letter,
**RET** inserts the letters as typed, and **C-g** drops them. The
punctuation `, . ? ! : ;` becomes ，。？！：；. The tables are read only
when you turn the input on. In the browser, use your system's pinyin
input method instead.

## Polytonic Greek input
Polytonic Greek is Greek written with all its accents and marks: the
acute, grave and circumflex accents, the smooth and rough breathings,
the iota subscript and the diaeresis. Homer, Plato and the New Testament
are printed this way, and so was Modern Greek until 1982, when Greece
adopted the monotonic system, with one accent.

**M-x polytonic** turns on a Greek keyboard in Beta Code, the convention
of the Thesaurus Linguae Graecae; the same command turns it off. The mode
line shows Ἑλ. Letters type Greek (`a` α, `b` β, `q` θ, `c` ξ, `w` ω),
and marks typed after a letter change it: `)` smooth breathing, `(`
rough breathing, `/` acute, `\` grave, `=` circumflex, `|` iota
subscript, and `+` diaeresis. So `a)/` gives ἄ, and `w(=|` gives ᾧ. A
capital is `*` before the letter, with its marks in between (`*)/a` Ἄ).
σ becomes ς at the end of a word, and `:` types the ano teleia (·).
`*)en a)rxh=| h)=n o( lo/gos` types Ἐν ἀρχῇ ἦν ὁ λόγος.

## AI help
**C-c r** asks Claude, and **C-c g** asks Codex (ChatGPT). Each offers
three choices: **h**, hints about the code at the cursor; **q**, a
question that you write in a window of its own, and send with the same
key; **d**, a discussion that stays open. **C-c y** inserts the code of
an answer, after asking you; in a discussion, **C-c t** inserts the
snippet under the cursor. **C-c q** closes the assistant's window. The
assistants only read: nothing enters your file unless you accept it,
and C-/ takes it back.

Claude is called through Claude Code (`claude`, with your usual login)
or, without it, through the API with the key in `ANTHROPIC_API_KEY` or
in `~/.chezemax/anthropic-api-key`. Codex needs the Codex command line
program, or the ChatGPT application. The assistants work in the text
and graphical windows.

**Grammarly** works in the browser editor, with the Grammarly extension
installed in Chrome. It is always off when the editor starts. The
**Grammarly: off** button above the text turns it on, and Grammarly then
checks the text on the screen; your Emacs keys keep working. Its
corrections enter the buffer as changes that C-/ undoes, and reach the
disk only when you save. Click the button again to turn it off.

## Backdoor
An assistant cannot see your screen. The backdoor shows it what your
editor did: it records each key you press, where the cursor and the
window were, and what each key changed. Use it when Chezweb misbehaves
and you want Claude or Codex to find out why:

1. Type **M-x backdoor-claude** (or **M-x backdoor-codex**). The mode
   line shows B/D.
2. Repeat the keys that show the problem.
3. Type the same command to close the backdoor.
4. Tell the assistant what went wrong. It reads the record in
   `~/.chezemax/backdoor.txt`.

The backdoor records only while it is open, and keeps the record on
your computer; Chezweb sends it nowhere. The assistant may first write
a configuration in `~/.chezemax`, saying what to record for that
problem. Closed, the backdoor costs nothing.

## Your settings
Your settings go in `~/.chezemax/init.scm`, which Chezweb loads when it
starts, in the text window, the graphical window and the browser.
**C-x C-r** loads it again after you change it. For example:

```scheme
(global-set-key "C-c i" 'insert-day)       ; Emacs key notation
(set-color 'comment 244)                   ; a face, 0-255 or "#rrggbb"
(set! *fill-column* 78)
(set! *gui-theme* 'light)                  ; or M-x light-theme
(set-gui-font "/Library/Fonts/JetBrainsMono-Regular.ttf" 14)
```

For the details of the implementation, the browser bridge, the compiled
scripts, TTFY, the plots and the tests, see
[docs/implementation.md](docs/implementation.md).

