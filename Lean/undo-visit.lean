/-
undo-visit.lean: why visiting a file used six times its size, and why the
fix changes nothing else.

The symptom (19 November 2026): opening a 100 MB file took 4.5 s and 651
MB of memory; a 300 MB file, 11 s and 1.77 GB. A file of 1 GB could not be
opened on a machine with 7 GB.

How the cause was found. A tracer of large allocations, run while Chezweb
opened the 100 MB file, showed two of them: the gap buffer's 100 MB (in
`insert_file`, gap.c), which the editor needs, and 200 MB requested by
`bridge_put_bytes` under `compiled_change`, that is, the report of the
change to the undo history. Reading the code then showed the whole path:

  insert_file reads the file into the gap buffer (copy 1), then reports
  record_change(curbp, 'i', point, text, len) with the whole text. The
  report goes to the compiled Scheme program: the bridge builds a message
  holding the text (copy 2, in C), puts it into the program's memory
  (copy 3, which never shrinks), and the program reads it into a
  bytevector (copy 4, in its garbage-collected heap, byte by byte: most of
  the 4.5 s). undo.scm then makes an undo group of it.

  And both callers of insert_file for visiting a file, load_file (gap.c)
  and main (main.c), report record_change(curbp, 'r', ...) at once, which
  deletes that buffer's undo history, the new group included.

So the four copies served a record that the very next call erased. This
file states that argument and proves it, in four parts:

1. `visit_forgets`: in the undo history, an insertion report followed by
   'r' gives the same history as 'r' alone, whatever undo.scm does with the
   insertion, as long as it touches only that buffer's history (it does:
   `history-of id`). So the report can be dropped without changing undo.
2. `visit_display`: the display still sees a change and the folds are
   still dropped, because 'r' does both by itself.
3. `peak_before`, `peak_after`, `held_before`, `held_after`: the memory
   of a visit, counted by the copies the code makes. Before the fix, four
   copies are made and three are held at once (one is released after
   delivery); after it, one.

4. `trim_oversized`: a recorded insertion larger than undo's limit (8 MB)
   empties the whole undo history, itself included. C-x i of such a file
   would copy it three times for nothing and erase the older history, so
   it is refused before any copy (19 November 2026).

The fix (gap.c, `insert_file`): report the insertion only when inserting
a file into a buffer (C-x i, MODFLAG 1), where undo needs it. Measured
after the fix: 100 MB opens in 0.35 s with 151 MB of memory (50 MB of
which the editor uses with an empty file); 1 GB opens in 2 s with 1 GB.

The model counts the copies that the code makes: 3 times the file, of the
6 times measured. The rest is the runtimes' own overhead when the compiled
program's memory and heap grow to take the text, which the model does not
describe. The measurement after the fix (the editor's base plus 1 times
the file) shows that all of it came from this report.

Check: lean undo-visit.lean (core Lean 4.30.0, no Mathlib).
-/

namespace UndoVisit

/-! ## 1. The undo histories (compiled/scripts/undo.scm) -/

/-- The undo histories: for each buffer id, its history or none. The
content of a history is left open (`H`): the theorem holds for any. -/
abbrev Histories (H : Type) := Nat → Option H

/-- 'r' (kind 114): `(hashtable-delete! *undo-histories* id)`. -/
def recordR {H : Type} (id : Nat) (u : Histories H) : Histories H :=
  fun j => if j = id then none else u j

/-- What undo.scm may do with an insertion report: anything, provided it
changes no other buffer's history. `record-change` works on
`(history-of id)` alone; its trimming, groups and saved boundary are inside
that history, so they are covered whatever they do. -/
def Local {H : Type} (id : Nat) (f : Histories H → Histories H) : Prop :=
  ∀ u j, j ≠ id → f u j = u j

/-- **The report of the insertion is dead.** For any treatment `recordI` of
the inserted text, as long as it is local to the buffer, reporting the
insertion and then 'r' leaves the same histories as 'r' alone. This is why
`insert_file` may skip the report when it visits a file. -/
theorem visit_forgets {H : Type} (id : Nat) (recordI : Histories H → Histories H)
    (hl : Local id recordI) (u : Histories H) :
    recordR id (recordI u) = recordR id u := by
  funext j
  unfold recordR
  by_cases h : j = id
  · simp [h]
  · simp [h, hl u j h]

/-! ## 2. What else record_change does (undo.c) -/

/-- The other effects of `record_change` on the buffer: a counter of
changes, which tells the display that its rows are stale, and the folds,
which follow the text. -/
structure BufState where
  changes : Nat
  folds   : List (Nat × Nat)

/-- 'i' of LEN bytes at POS: the counter grows; folds after POS move (the
model leaves this open as `shift`). -/
def changeI (shift : List (Nat × Nat) → List (Nat × Nat)) (b : BufState) : BufState :=
  { changes := b.changes + 1, folds := shift b.folds }

/-- 'r': the counter grows; all folds are dropped (`fold_change`). -/
def changeR (b : BufState) : BufState := { changes := b.changes + 1, folds := [] }

/-- The display redraws when the counter differs from the one it drew
(display.c compares `b_changes`). Without the 'i', the visit still leaves
no folds and a counter different from the one drawn before it. -/
theorem visit_display (shift : List (Nat × Nat) → List (Nat × Nat)) (b : BufState) :
    (changeR (changeI shift b)).folds = (changeR b).folds ∧
    (changeR (changeI shift b)).changes ≠ b.changes ∧
    (changeR b).changes ≠ b.changes := by
  simp [changeR, changeI]; omega

/-! ## 3. Memory: the copies of the file during a visit -/

/-- An allocation of `size` bytes, or its release. -/
inductive Event where
  | alloc (size : Nat)
  | free (size : Nat)

/-- The largest amount of memory held at once, starting from `live`. -/
def peakFrom : Nat → List Event → Nat
  | live, [] => live
  | live, .alloc s :: es => max (live + s) (peakFrom (live + s) es)
  | live, .free s :: es => max live (peakFrom (live - s) es)

def peak (es : List Event) : Nat := peakFrom 0 es

/-- Visiting a file of `n` bytes before the fix: the gap buffer; the
bridge's message (freed after delivery); the program's memory, which stays;
the bytevector, garbage after 'r' but held until a collection. -/
def visitBefore (n : Nat) : List Event :=
  [.alloc n,     -- gap buffer (insert_file)
   .alloc n,     -- bridge_out (bridge_put_bytes)
   .alloc n,     -- the compiled program's memory (deliver)
   .free n,      -- bridge_out released (BRIDGE_OUT_FREE)
   .alloc n]     -- the bytevector (%bridge-read-bytes)

/-- After the fix: the gap buffer only. -/
def visitAfter (n : Nat) : List Event := [.alloc n]

theorem peak_before (n : Nat) : peak (visitBefore n) = 3 * n := by
  simp [peak, visitBefore, peakFrom]; omega

theorem peak_after (n : Nat) : peak (visitAfter n) = n := by
  simp [peak, visitAfter, peakFrom]

/-- Held when the visit is over: the gap buffer, the program's memory and
the bytevector before the fix; the gap buffer alone after. -/
def heldAfter : Nat → List Event → Nat
  | live, [] => live
  | live, .alloc s :: es => heldAfter (live + s) es
  | live, .free s :: es => heldAfter (live - s) es

theorem held_before (n : Nat) : heldAfter 0 (visitBefore n) = 3 * n := by
  simp [visitBefore, heldAfter]; omega

theorem held_after (n : Nat) : heldAfter 0 (visitAfter n) = n := by
  simp [visitAfter, heldAfter]

/-- In megabytes, for the 100 MB file: 300 held before, 100 after (plus the
editor's own 50 MB, and before the fix the runtimes' heap overhead). -/
example : heldAfter 0 (visitBefore 100) = 300 ∧ heldAfter 0 (visitAfter 100) = 100 := by decide

/-! ## 4. C-x i of a file larger than undo keeps -/

/-- undo.scm's `trim-history`, for the sizes alone: the history is a list of
groups, newest first; while it holds more than `limit` bytes, the oldest
group goes. (`fuel`: each step removes one group.) -/
def trim (limit : Nat) : Nat → List Nat → List Nat
  | 0, h => h
  | n + 1, h => if h.sum > limit then trim limit n h.dropLast else h

theorem trim_nil (limit : Nat) : ∀ n, trim limit n [] = [] := by
  intro n; cases n <;> simp [trim]

/-- **A group larger than the limit empties the history.** Recorded, an
insertion of `g > limit` bytes sends every older group away, oldest first,
and then itself: nothing is left to undo, neither the insertion nor what
came before it. So the three copies that took the text to undo.scm bought a
history erased. This is why C-x i of such a file is refused before anything
is copied (command.c, `insertfile`; undo.scm, `undo-fits?`): the history
then stays as it was. -/
theorem trim_oversized (limit g : Nat) (hg : g > limit) :
    ∀ n (rest : List Nat), rest.length < n → trim limit n (g :: rest) = [] := by
  intro n
  induction n with
  | zero => intro rest h; omega
  | succ n ih =>
    intro rest hlen
    have hs : (g :: rest).sum > limit := by simp; omega
    simp only [trim]
    rw [if_pos hs]
    cases rest with
    | nil => simp [trim_nil]
    | cons r rs =>
      rw [show (g :: r :: rs).dropLast = g :: (r :: rs).dropLast by simp [List.dropLast_cons_cons]]
      exact ih _ (by simp at hlen ⊢; omega)

/-- Example: a history of three groups (100, 200, 300 bytes) and a C-x i of
9 MB with the 8 MB limit: nothing remains. -/
example : trim (8 * 1024 * 1024) 4 [9 * 1024 * 1024, 100, 200, 300] = [] :=
  trim_oversized _ _ (by decide) 4 _ (by decide)

/-! ## 5. Any change larger than the limit: its bytes are not sent

C-x i was the only route refused before the copy. A cut, a yank or a paste
of 21 MB still sent its bytes to undo.scm, where a byte of a bytevector
takes four, only for `trim_oversized` to drop them: C-w of 21 MB raised the
editor's memory by 231 MB that stayed (tests/endurance.sh, 22 November
2026). Since then the C core knows the limit (undo.scm tells it,
`sync-undo-limit`), and for such a change it sends 'o' without the bytes
(src/undo.c); undo.scm's `forget-oversized` empties the history. -/

/-- What undo.scm does on 'o', for the sizes alone: nothing is left. -/
def forgetOversized (_rest : List Nat) : List Nat := []

/-- **'o' leaves the history that recording the change would have left.**
Whatever came before, the history after `forget-oversized` is the one that
recording the oversized group and trimming gives: empty. So no undo is lost
by not sending the bytes. (undo.scm also forbids the rest of that command,
as recording did: the oldest group dropped was the command's own.) -/
theorem oversized_without_bytes (limit g : Nat) (hg : g > limit) (n : Nat) (rest : List Nat)
    (hn : rest.length < n) : forgetOversized rest = trim limit n (g :: rest) := by
  rw [trim_oversized limit g hg n rest hn]; rfl

end UndoVisit
