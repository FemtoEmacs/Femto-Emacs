/-
shards.lean: what saving a file in shards must do (src/shard.c), and a
proof that the C procedure does it.

A file too large to hold is cut into shards (Emacs's VLF). The index gives
each shard its offset and length; only one shard is in the buffer, and an
edited shard keeps its text in the index. C-x C-s writes, shard by shard,
the edited text or else the file's bytes from the shard's offset
(`copy_range`), then computes the offsets again from the new lengths.

The model: the file is the concatenation of its shards (`file = flatten
shards`): this is what the index promises, offsets being the sums of the
lengths before. `edits k` is the text kept for shard k, or none.

Proved:
- `copy_shard`: the bytes at shard k's offset, for its length, are shard
  k: what `copy_range` copies is the shard, for any shard of any file.
- `save_eq`: the saved file is the concatenation, shard by shard, of the
  edited text or the shard as it was.
- `save_unedited`: with no edits, the saved file is the file, byte for byte.
- `reread_after_save`: after the save, the new index reads back from the
  saved file exactly what the editor held for every shard: the edited
  text, or for a shard not edited the bytes it had. So a save changes
  only the shards that were edited, and moving to a shard after a save
  shows what was there before it.
- `cut_after_newline`, `cut_before_lead`: the two places `build_index`
  cuts are character boundaries (as defined in utf8-cursor.lean), so a
  shard never begins inside a UTF-8 character.

Check: lean shards.lean (core Lean 4.30.0, no Mathlib).
-/

namespace Shards

/-- The offset of shard `k`: the lengths of the shards before it. -/
def offset (shards : List (List Nat)) (k : Nat) : Nat :=
  ((shards.take k).map List.length).sum

/-- `copy_range(from, off, len)`: `len` bytes of `file` from `off`. -/
def copyRange (file : List Nat) (off len : Nat) : List Nat := (file.drop off).take len

theorem copy_shard : ∀ (shards : List (List Nat)) (k : Nat) (hk : k < shards.length),
    copyRange shards.flatten (offset shards k) (shards[k]'hk).length = shards[k]'hk := by
  intro shards
  induction shards with
  | nil => intro k hk; simp at hk
  | cons s ss ih =>
    intro k hk
    cases k with
    | zero => simp [copyRange, offset]
    | succ k =>
      have hk' : k < ss.length := by simp at hk; omega
      have := ih k hk'
      simp only [copyRange, offset] at this ⊢
      simp only [List.flatten_cons, List.take_succ_cons, List.map_cons, List.sum_cons,
        List.getElem_cons_succ]
      rw [List.drop_append, List.drop_eq_nil_of_le (by omega), List.nil_append,
        Nat.add_sub_cancel_left]
      exact this

/-- What shard `k` holds in the editor: its kept text, or its bytes. -/
def held (_shards : List (List Nat)) (edits : Nat → Option (List Nat)) (k : Nat) (s : List Nat) :
    List Nat :=
  (edits k).getD s

/-- The pieces `shard_save` writes, in order: for each shard, the kept text,
or the file's bytes from its offset for its length. -/
def pieces (shards : List (List Nat)) (edits : Nat → Option (List Nat)) : List (List Nat) :=
  (List.range shards.length).map fun k =>
    match edits k with
    | some t => t
    | none => copyRange shards.flatten (offset shards k) ((shards.getD k []).length)

def save (shards : List (List Nat)) (edits : Nat → Option (List Nat)) : List Nat :=
  (pieces shards edits).flatten

theorem piece_eq (shards : List (List Nat)) (edits : Nat → Option (List Nat)) (k : Nat)
    (hk : k < shards.length) :
    (pieces shards edits)[k]'(by simp [pieces]; exact hk) = held shards edits k (shards[k]'hk) := by
  simp only [pieces, List.getElem_map, List.getElem_range, held]
  cases e : edits k with
  | some t => simp
  | none =>
    simp only [Option.getD_none]
    have := copy_shard shards k hk
    rw [show shards.getD k [] = shards[k]'hk by simp [List.getD_eq_getElem?_getD, hk]]
    exact this

/-- The saved file is, shard by shard, what the editor held. -/
theorem save_eq (shards : List (List Nat)) (edits : Nat → Option (List Nat)) :
    pieces shards edits = (List.range shards.length).map
      (fun k => held shards edits k (shards.getD k [])) := by
  apply List.ext_getElem
  · simp [pieces]
  · intro k h1 h2
    have hk : k < shards.length := by simp [pieces] at h1; exact h1
    rw [piece_eq shards edits k hk]
    simp [held, List.getD_eq_getElem?_getD, hk]

theorem range_map_getD (shards : List (List Nat)) :
    (List.range shards.length).map (fun k => shards.getD k []) = shards := by
  apply List.ext_getElem
  · simp
  · intro k h1 h2
    simp [List.getD_eq_getElem?_getD, h2]

/-- With nothing edited, saving writes the file as it was. -/
theorem save_unedited (shards : List (List Nat)) :
    save shards (fun _ => none) = shards.flatten := by
  unfold save
  rw [save_eq]
  simp only [held, Option.getD_none]
  rw [range_map_getD]

/-- After the save, the offsets are computed again from the new lengths
(`e->off = off; off += e->len`), and reading shard k back from the saved
file gives what the editor held for it. -/
theorem reread_after_save (shards : List (List Nat)) (edits : Nat → Option (List Nat))
    (k : Nat) (hk : k < shards.length) :
    copyRange (save shards edits) (offset (pieces shards edits) k)
        (held shards edits k (shards[k]'hk)).length
      = held shards edits k (shards[k]'hk) := by
  have hk' : k < (pieces shards edits).length := by simp [pieces]; exact hk
  have := copy_shard (pieces shards edits) k hk'
  rw [piece_eq shards edits k hk] at this
  exact this

/-! ## Where build_index cuts -/

def isCont (b : Nat) : Bool := 128 ≤ b && b < 192

/-- As in utf8-cursor.lean: the end of the text, or a byte that is not a
continuation byte. -/
def Boundary (file : List Nat) (i : Nat) : Prop :=
  i = file.length ∨ (∃ h : i < file.length, isCont (file[i]'h) = false)

/-- A cut after a newline: the next byte follows a complete character
(newline is one byte), so in UTF-8 it is not a continuation byte. The
hypothesis states that of the text (in utf8-cursor.lean it follows from
well-formedness: after a one-byte character comes a boundary). -/
theorem cut_after_newline (file : List Nat) (i : Nat) (hi : i + 1 ≤ file.length)
    (hwf : ∀ h : i + 1 < file.length, isCont (file[i + 1]'h) = false) :
    Boundary file (i + 1) := by
  by_cases h : i + 1 < file.length
  · exact Or.inr ⟨h, hwf h⟩
  · exact Or.inl (by omega)

/-- A cut in a very long line, before a byte that is not a continuation
byte: a boundary by definition. -/
theorem cut_before_lead (file : List Nat) (i : Nat) (h : i < file.length)
    (hl : isCont (file[i]'h) = false) : Boundary file i :=
  Or.inr ⟨h, hl⟩

/-- An example: three shards, the second edited; the file saved and read
back. -/
example :
    let shards := [[1, 2, 10], [3, 10], [4, 5, 10]]
    let edits : Nat → Option (List Nat) := fun k => if k = 1 then some [7, 7, 7, 10] else none
    save shards edits = [1, 2, 10, 7, 7, 7, 10, 4, 5, 10] := by decide

end Shards
