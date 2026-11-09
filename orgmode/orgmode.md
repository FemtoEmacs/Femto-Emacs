# Org mode design
Our next step is to develop a tiny clone of Emacs org mode.
It has a modular design, so we can add new features in the
future. Schemer will be the implementation language, but you
may want to enrich the C-core to make the implementation
easier. For people who don't want to use it, tiny org shouldn't
represent a burden. When one toggles off M-x org-mode, it
is as if it didn't exist.

In the browser, when I press Tab to choose a new folder, chezweb asks to allow access to the folder. This is correct. But whenever I press subsequent Tab keys, it keeps asking for permission instead of completing the folder, subfolder and file names.

Also, you recommend using cd --pick to select orgmode (the folder name). I thought the idea interesting, but I don't know how to use it. Can you explain what you had in mind when you proposed cd --pick to select orgmode?

## Tables

Org mode tabs are a nuisance when they lose alignment or when their lines are too long to format correctly. So I'm considering a sexpr-represented table.

( ((Title: (Org table:))
  (( Name  ) ( Phone ) ( Age ) ( Age-24   ))
  (( ----- ) ( ----- ) ( --- ) ( -------- ))
  (( Peter ) ( 1234  ) ( 24  ) ( -1       ))
  (( Anna  ) ( 4321  ) ( 25  ) ( 7        ))
  (( Susan ) ( 9876  ) ( 18  ) (          ))
) (#+TBLFM: (set! Age-24 (- Age 24)) etc.)

### Structural Compatibility with Full Org Mode
The following sections are suggestions that you may change to make implementation easier or safer. To ensure that a full Emacs Org-mode parser doesn't completely choke on this data format, wrap the sexp inside a standard Org Special Block or a customized Greater Element Block.

#+BEGIN_SEXP_TABLE
(
 ((Title: "Org table"))
 (( Name  ) ( Phone ) ( Age ) ( Age-24 ))
 (( ----- ) ( ----- ) ( --- ) ( ------ ))
 (( Peter ) ( 1234  ) ( 24  ) ( -1     ))
 (( Anna  ) ( 4321  ) ( 25  ) ( 7      ))
 (( Susan ) ( 9876  ) ( 18  ) ( ""     ))
)
#+TBLFM: $4=(- $3 24)
#+END_SEXP_TABLE

However, I am not sure whether this would make things easier for Emacs.

### Standardizing the Internal Data Structure
I suspect that, to make it highly maintainable in Schemer, the raw S-expression should be normalized into an internal association list (alist) or record type:

;; Internal representation archetype
(define-record-type org-table
  (fields title headers rows formulas))

;; Example parsed instance
'#%org-table(
  title: "Org table"
  headers: (Name Phone Age Age-24)
  rows: ((Peter 1234 24 -1)
         (Anna  4321 25 7)
         (Susan 9876 18 ""))
  formulas: (($4 . (- $3 24)))
)

### Keybindings

* C-c C-v t -- tangle
* C-c C-c -- format a table