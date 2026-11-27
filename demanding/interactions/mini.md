# Reproducing a bug
Author: Codex.
Just a test.
Yes for the sequence I reproduced. It produced the same symptom on the old build and passed on the fixed build. We still don’t know whether it was your original sequence.

Run the same steps in `chezbug` first, then in the rebuilt `~/mysand/chezmoi`:

1. Open Chezweb in a **text terminal** with a single editing pane. Use
   a file with at least 20 lines so the difference is visible.
2. Shrink the terminal to **8 rows**. 
3. Press **`C-x b`** to open the buffer picker. Leave it open.
4. With the picker still open, enlarge the terminal to **18 rows**.
5. Press **`C-g`** to cancel the picker. Look at the mode line before
   running any other command.

**`chezbug`** should leave the mode line just below the old six-row editing pane, with blank space down to the minibuffer. **The fixed build** should place the mode line just above the minibuffer, leaving 16 text rows.

There’s no need to split the window or press `C-x 0`. The apparent second pane is the unused space below the one editing pane.

## How I used the backdoor to fix the bug

On 14 November 2026, I read the trace Eduardo recorded with `M-x backdoor-codex`.
It recorded resize events and showed that the buffer picker ran inside `C-x b`.
An earlier trace showed an 18-row terminal with an editing pane still six rows high.
The blank area below the mode line looked like a second pane. Only one pane existed.

I reproduced the mismatch in a disposable terminal by resizing from 8 to 18 rows
while the buffer picker was open. The picker consumed the resize event.
I changed redraw to check the pane layout against the terminal height and recalculate it when they differ.
On the same test, the fixed build used 16 text rows, with one row each for the mode line and minibuffer.
Eduardo confirmed the reproduction and kept the old checkout as `chezbug`.
