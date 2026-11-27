# vsplit.md: testing C-x 3 with the backdoor open

Keep this script in the left pane and do the tests in the right pane. Type
only in the right pane; vsplit-test.md and vsplit-test.c (beside this file)
are disposable, so change them freely. The backdoor is configured for this
test (~/.chezemax/backdoor-claude.conf: 3000 lines, clicks, page, point and
mark, 40 bytes of typed text).

**If the cursor vanishes at any moment**, write down the step without
moving: M-: and then (change the number)

    (fe-backdoor-note "STEP 7 cursor lost")

then go on. If M-: itself shows no cursor, type it blind; the note is still
recorded. The same works for anything odd: "STEP 5 page jumped".

While the backdoor is open, the mode line shows B/D, and a pane is too narrow
for B/D, the buttons and the whole name: the name is cut at its left. That
is expected; so is a cut name ("nal*") for *terminal*, whose mode line
also carries Term.

## 0. Start

    cd demanding/interactions      (from the Chezweb source folder)
    chezweb vsplit.md

1. M-x backdoor-claude (B/D appears in the mode line).

## 1. Split, keeping the window

2. C-v, then C-n three times, so the cursor is on the 4th row of a
   scrolled window.
3. C-x 3. Both panes must show the same lines as before, the cursor still
   on the 4th row of the left pane. (Before today's fix it went to the
   bottom row.)
4. C-x o: the cursor moves to the right pane, same row.
5. C-x C-f vsplit-test.md RET in the right pane.

## 2. Typing and moving in the right pane

6. Type a few words in the first line. The cursor follows each character.
7. M-> and then M-<: the end and the beginning of the file.
8. C-s Korean RET, then C-n twice: the Korean line. C-f several times
   across 이상순 and the other wide characters; C-e; C-a. The cursor must
   never sit between the two columns of a character or past the bar.
9. Chezweb's own Korean input, on the 2-set keyboard: M-x korean-input
   RET. The mode line shows 한, and the message line "Korean input
   (2-set): ...". C-a, then C-f four times: the cursor after 이상순 and
   its space, in the middle of the line. Type r and then k: 가 (r is ㄱ,
   k is ㅏ). Then DEL until 가 is gone: while you compose, DEL takes back
   one letter (가, ㄱ, nothing). M-x korean-input RET again: 한 goes
   away, and the message line says "Korean input off". (Turn it off
   before the next step: while it is on, the letters you type become
   Korean.)
10. C-s Accents RET, C-n twice, then C-f across ação and coração; type ã
    and DEL.
11. M-< (the paragraph is above the accents, where C-s does not look),
    then C-s paragraph RET, C-n twice: the wrapped paragraph. C-n and C-p
    through its rows; C-e on a row of it.
12. C-v three times, then M-v three times.

## 3. A file that does not wrap

13. C-x C-f vsplit-test.c RET. C-n twice: the long line.
14. C-e: the end of the visible row. C-a, C-n, C-p.

## 4. The mouse

15. Click a word in the left pane (this script): the cursor goes there,
    the left pane is current. Do not type.
16. Click a word in the right pane: the cursor goes there, at the column
    you clicked.
17. Wheel down and up over the right pane, then over the left pane.
18. Click in the right pane again.

## 5. The same file in both panes

19. C-x o (to the left pane), C-x b, type vsplit-test.c, RET.
20. C-x o, type XYZ in the right pane: it appears in both panes; the
    cursor stays in the right pane.
21. C-x o, C-x b, type vsplit.md, RET: this script again on the left. C-x o.

## 6. The terminal in the right pane

22. M-x term RET in the right pane. The editor draws the terminal's
    cursor as a block.
23. Type `ls` RET, then `seq 1 100` RET.
24. C-c o: back to the left pane, the cursor shown there. C-x o: back to
    the terminal.
25. C-c C-x C-c: the question "A terminal is still running; quit anyway
    (y/n) ?" must show the cursor after the question (it did not, before
    today's fix). Answer n.
26. C-c M-x and then backdoor-claude would close the backdoor: do not; only
    check that C-c M-x shows the cursor in the minibuffer, then C-g.
27. C-c o, to leave the terminal.

## 7. What is refused, and closing

28. C-x 2 (you are in the left pane): refused; the message line says
    "Vertically split panes do not accept further splits".
29. Resize the terminal window narrower and wider, with the mouse. The bar
    and both panes follow; the cursor stays visible.
30. C-x 0 in the left pane: the left pane closes and the terminal takes the
    whole screen, its cursor block drawn.
31. C-c C-x 3: two panes again, the terminal in both. Type `echo hi` RET:
    it appears in both.
32. C-c C-x 1: one pane, full width.
33. C-c C-x b, type vsplit.md, RET: this script again.

## 8. Close the backdoor

34. M-x backdoor-claude (B/D disappears).
35. C-x C-c; answer y to the questions (the test files and the terminal are
    disposable).

Then tell me "Done." I will read ~/.chezemax/backdoor.txt. The previous
configuration (narrowing) is in ~/.chezemax/bkp/backdoor-claude.conf.narrowing.
