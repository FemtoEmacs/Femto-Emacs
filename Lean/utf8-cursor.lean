/-
utf8-cursor.lean: where the cursor may be in UTF-8 text.

A byte offset is a character boundary when it is the end of the text or the
byte there is not a continuation byte (80 to BF). The specification: in
well-formed UTF-8, C-f, C-b, C-n, C-p (and the mouse, which ends in
`lncolumn`), typing, overwriting, C-d and backspace leave point on a
boundary, folds included, and the display, which runs between keys, never
sees half of a character (`cursor_on_boundary`).

The model follows the C functions it names: `utf8_size` (`size`),
`prev_utf8_char_size` (`prevSize`), `right` and `left` (the primitives),
`forward_character` and `backward_character` (C-f and C-b, which take a
letter and its combining accents together; `accent_at`, left open as `acc`),
`lnstart`,
`lncolumn`, `upup`, `dndn`, `insert`, `delete`, `backsp` (command.c, display.c), the
folds of fold.c and the key reader of key.c. What the screen decides (row
wraps, widths, the goal column) is left open in `Geometry`: the theorems hold
for every choice. The C code itself is not proved; this states what it must do.

Two requirements of the specification, which the C code did not meet:
- `readKey`: a byte that is not a complete character (a continuation byte
  alone, a lead byte without its continuation bytes, any other byte from 80
  up) is typed as U+FFFD. Before 18 November 2026, key.c and `insert`
  inserted it as it was, and the examples at the end show C-b and C-f
  stopping inside a character afterwards.
- `Cmd.fold`: a fold hides whole characters and starts on a boundary.
  Org's folds, from newline to newline, do (`newline_fold`); before 18
  November 2026, `fe_fold` checked only a < b < size.
Both are now in the C code (`insert` in command.c, `fe_fold` in fold.c);
M-x toggle-utf8-fix turns them off, to see the old behaviour.

Check: lean utf8-cursor.lean (core Lean 4.30.0, no Mathlib); make utf8-audit
lists the axioms.
-/

namespace Utf8Cursor

def isCont (b : Nat) : Bool := 128 ≤ b && b < 192

def size (b : Nat) : Nat :=
  if 192 ≤ b ∧ b < 224 then 2
  else if 224 ≤ b ∧ b < 240 then 3
  else if 240 ≤ b ∧ b < 248 then 4
  else 1

theorem size_pos (b : Nat) : 1 ≤ size b := by
  unfold size; repeat (first | omega | split)
theorem size_le (b : Nat) : size b ≤ 4 := by
  unfold size; repeat (first | omega | split)
theorem size_cont {b : Nat} (h : isCont b = true) : size b = 1 := by
  unfold isCont at h; simp at h; unfold size; repeat (first | omega | split)

structure Text where
  len : Nat
  byte : Nat → Nat

def Boundary (t : Text) (i : Nat) : Prop :=
  i = t.len ∨ (i < t.len ∧ isCont (t.byte i) = false)

structure WF (t : Text) : Prop where
  first : 0 < t.len → isCont (t.byte 0) = false
  fits  : ∀ i, i < t.len → isCont (t.byte i) = false → i + size (t.byte i) ≤ t.len
  conts : ∀ i, i < t.len → isCont (t.byte i) = false →
            ∀ j, 0 < j → j < size (t.byte i) → isCont (t.byte (i + j)) = true
  next  : ∀ i, i < t.len → isCont (t.byte i) = false → Boundary t (i + size (t.byte i))

theorem boundary_le {t : Text} {i : Nat} (h : Boundary t i) : i ≤ t.len := by
  unfold Boundary at h; omega

theorem boundary_zero {t : Text} (w : WF t) : Boundary t 0 := by
  unfold Boundary
  by_cases h : t.len = 0
  · exact Or.inl h.symm
  · exact Or.inr ⟨by omega, w.first (by omega)⟩

/-- No boundary falls strictly inside a character. -/
theorem inside_char {t : Text} (w : WF t) {j i : Nat} (hj : j < t.len)
    (hl : isCont (t.byte j) = false) (hji : j < i) (hb : Boundary t i) :
    j + size (t.byte j) ≤ i := by
  have hfit := w.fits j hj hl
  apply Classical.byContradiction
  intro hlt
  have hc := w.conts j hj hl (i - j) (by omega) (by omega)
  have : j + (i - j) = i := by omega
  rw [this] at hc
  unfold Boundary at hb
  rcases hb with hb | ⟨_, hb⟩
  · omega
  · rw [hb] at hc; exact Bool.false_ne_true hc

/-- Every byte lies in some character. -/
theorem cover {t : Text} (w : WF t) : ∀ p, p < t.len →
    ∃ j, j ≤ p ∧ isCont (t.byte j) = false ∧ p < j + size (t.byte j) := by
  intro p
  induction p with
  | zero => intro h; exact ⟨0, Nat.le_refl _, w.first h, by have := size_pos (t.byte 0); omega⟩
  | succ p ih =>
    intro h
    cases hc : isCont (t.byte (p+1)) with
    | false => exact ⟨p+1, Nat.le_refl _, hc, by have := size_pos (t.byte (p+1)); omega⟩
    | true =>
      obtain ⟨j, hjp, hl, hlt⟩ := ih (by omega)
      by_cases hlt2 : p + 1 < j + size (t.byte j)
      · exact ⟨j, by omega, hl, hlt2⟩
      · have hn := w.next j (by omega) hl
        have heq : j + size (t.byte j) = p + 1 := by omega
        rw [heq] at hn
        unfold Boundary at hn
        rcases hn with hn | ⟨_, hn⟩
        · omega
        · rw [hn] at hc; exact absurd hc (by decide)

/-- The character before a boundary. -/
theorem prev_char {t : Text} (w : WF t) {p : Nat} (hp : 0 < p) (hb : Boundary t p) :
    ∃ j, j < p ∧ isCont (t.byte j) = false ∧ j + size (t.byte j) = p := by
  have hle := boundary_le hb
  obtain ⟨j, hj, hl, hlt⟩ := cover w (p - 1) (by omega)
  have := inside_char w (by omega) hl (by omega) hb
  exact ⟨j, by omega, hl, by omega⟩


/-! ## C-f and C-b without hidden text (command.c: right, left) -/

/-- command.c, `prev_utf8_char_size`. -/
def prevSize (t : Text) (p : Nat) : Nat :=
  if 2 ≤ p ∧ size (t.byte (p - 2)) = 2 then 2
  else if 3 ≤ p ∧ size (t.byte (p - 3)) = 3 then 3
  else if 4 ≤ p ∧ size (t.byte (p - 4)) = 4 then 4
  else 1

/-- command.c, `right` before the folds: at most `utf8_size` bytes, not past the end. -/
def stepRight (t : Text) (p : Nat) : Nat := min (p + size (t.byte p)) t.len

/-- command.c, `left` before the folds. -/
def stepLeft (t : Text) (p : Nat) : Nat := p - prevSize t p

theorem stepRight_boundary {t : Text} (w : WF t) {p : Nat} (hb : Boundary t p) :
    Boundary t (stepRight t p) := by
  unfold stepRight
  rcases hb with h | ⟨hlt, hl⟩
  · rw [h]; have := size_pos (t.byte t.len); rw [Nat.min_eq_right (by omega)]
    exact Or.inl rfl
  · rw [Nat.min_eq_left (w.fits p hlt hl)]; exact w.next p hlt hl

theorem cont_at {t : Text} (w : WF t) {j p : Nat} (hj : j < t.len)
    (hl : isCont (t.byte j) = false) (h1 : j < p) (h2 : p < j + size (t.byte j)) :
    isCont (t.byte p) = true := by
  have hc := w.conts j hj hl (p - j) (by omega) (by omega)
  have : j + (p - j) = p := by omega
  rwa [this] at hc

/-- `prev_utf8_char_size` finds the character before a boundary. -/
theorem prevSize_eq {t : Text} (w : WF t) {p j : Nat} (hj : j < p) (hjl : j < t.len)
    (hl : isCont (t.byte j) = false) (he : j + size (t.byte j) = p) :
    prevSize t p = size (t.byte j) := by
  have hle := w.fits j hjl hl
  have s4 := size_le (t.byte j)
  have s1 := size_pos (t.byte j)
  -- a byte strictly after j and before p is a continuation, whose size is 1
  have mid : ∀ q, j < q → q < p → size (t.byte q) = 1 := fun q h1 h2 =>
    size_cont (cont_at w hjl hl h1 (by omega))
  -- a lead byte at q < j of size n ≥ 2 would make j a continuation, unless q + n ≤ j
  have before : ∀ q n, q < j → size (t.byte q) = n → 2 ≤ n → j < q + n → False := by
    intro q n hq hs hn hjq
    cases hcq : isCont (t.byte q) with
    | true => rw [size_cont hcq] at hs; omega
    | false =>
      have := cont_at w (by omega) hcq hq (by omega)
      rw [hl] at this; exact Bool.false_ne_true this
  unfold prevSize
  have hsz : size (t.byte j) = p - j := by omega
  by_cases h2 : 2 ≤ p ∧ size (t.byte (p - 2)) = 2
  · rw [if_pos h2]
    by_cases hq : p - 2 = j
    · rw [hq] at h2; omega
    · by_cases hlt : p - 2 < j
      · exact absurd (before (p-2) 2 hlt h2.2 (by omega) (by omega)) id
      · have := mid (p-2) (by omega) (by omega); omega
  · rw [if_neg h2]
    by_cases h3 : 3 ≤ p ∧ size (t.byte (p - 3)) = 3
    · rw [if_pos h3]
      by_cases hq : p - 3 = j
      · rw [hq] at h3; omega
      · by_cases hlt : p - 3 < j
        · exact absurd (before (p-3) 3 hlt h3.2 (by omega) (by omega)) id
        · have := mid (p-3) (by omega) (by omega); omega
    · rw [if_neg h3]
      by_cases h4 : 4 ≤ p ∧ size (t.byte (p - 4)) = 4
      · rw [if_pos h4]
        by_cases hq : p - 4 = j
        · rw [hq] at h4; omega
        · by_cases hlt : p - 4 < j
          · exact absurd (before (p-4) 4 hlt h4.2 (by omega) (by omega)) id
          · have := mid (p-4) (by omega) (by omega); omega
      · rw [if_neg h4]
        -- the character is one byte: otherwise one of the three tests matched
        apply Classical.byContradiction; intro hne
        have hs : 2 ≤ size (t.byte j) := by omega
        have hjp : j = p - size (t.byte j) := by omega
        rcases (by omega : size (t.byte j) = 2 ∨ size (t.byte j) = 3 ∨ size (t.byte j) = 4)
          with e | e | e
        · exact h2 ⟨by omega, by rw [show p - 2 = j by omega]; exact e⟩
        · exact h3 ⟨by omega, by rw [show p - 3 = j by omega]; exact e⟩
        · exact h4 ⟨by omega, by rw [show p - 4 = j by omega]; exact e⟩

theorem stepLeft_boundary {t : Text} (w : WF t) {p : Nat} (hb : Boundary t p) :
    Boundary t (stepLeft t p) := by
  unfold stepLeft
  by_cases hp : p = 0
  · rw [hp, Nat.zero_sub]; exact boundary_zero w
  · obtain ⟨j, hj, hl, he⟩ := prev_char w (by omega) hb
    have := boundary_le hb
    have hjl : j < t.len := by omega
    rw [prevSize_eq w hj hjl hl he, show p - size (t.byte j) = j by omega]
    exact Or.inr ⟨hjl, hl⟩


/-! ## Inserting a complete character, deleting a whole one -/

/-- The bytes of one complete character: a lead byte saying how many follow,
then that many continuation bytes (key.c reads them as one input event). -/
structure ValidChar (c : List Nat) : Prop where
  lead  : isCont (c.getD 0 0) = false
  len   : c.length = size (c.getD 0 0)
  conts : ∀ j, 0 < j → j < c.length → isCont (c.getD j 0) = true

def insertAt (t : Text) (i : Nat) (c : List Nat) : Text where
  len  := t.len + c.length
  byte := fun j => if j < i then t.byte j
                   else if j < i + c.length then c.getD (j - i) 0
                   else t.byte (j - c.length)

/-- Remove the `k` bytes from `i`. -/
def deleteAt (t : Text) (i k : Nat) : Text where
  len  := t.len - k
  byte := fun j => if j < i then t.byte j else t.byte (j + k)

section insert
variable {t : Text} {i : Nat} {c : List Nat}

theorem ins_lt {j : Nat} (h : j < i) : (insertAt t i c).byte j = t.byte j := by
  simp only [insertAt]; rw [if_pos h]
theorem ins_mid {j : Nat} (h1 : i ≤ j) (h2 : j < i + c.length) :
    (insertAt t i c).byte j = c.getD (j - i) 0 := by
  simp only [insertAt]; rw [if_neg (by omega), if_pos h2]
theorem ins_ge {j : Nat} (h : i + c.length ≤ j) :
    (insertAt t i c).byte j = t.byte (j - c.length) := by
  simp only [insertAt]; rw [if_neg (by omega), if_neg (by omega)]

theorem ins_old (hi : i ≤ t.len) {j : Nat} (hb : Boundary t j) (h : j < i) :
    Boundary (insertAt t i c) j := by
  rcases hb with e | ⟨_, hl⟩
  · omega
  · exact Or.inr ⟨by simp only [insertAt]; omega, by rw [ins_lt h]; exact hl⟩

theorem vc_pos (vc : ValidChar c) : 1 ≤ c.length := by
  rw [vc.len]; exact size_pos _

theorem ins_at (hi : i ≤ t.len) (vc : ValidChar c) : Boundary (insertAt t i c) i := by
  have := vc_pos vc
  refine Or.inr ⟨by simp only [insertAt]; omega, ?_⟩
  rw [ins_mid (Nat.le_refl _) (by omega), Nat.sub_self]; exact vc.lead

theorem ins_shift {j : Nat} (hb : Boundary t j) (h : i ≤ j) :
    Boundary (insertAt t i c) (j + c.length) := by
  rcases hb with e | ⟨hj, hl⟩
  · exact Or.inl (by simp only [insertAt]; omega)
  · refine Or.inr ⟨by simp only [insertAt]; omega, ?_⟩
    rw [ins_ge (by omega), Nat.add_sub_cancel]; exact hl

/-- Inserting a complete character at a boundary keeps the text well formed. -/
theorem insert_wf (w : WF t) (hb : Boundary t i) (vc : ValidChar c) : WF (insertAt t i c) := by
  have hi := boundary_le hb
  have hk := size_pos (c.getD 0 0)
  have hk' : 1 ≤ c.length := by rw [vc.len]; exact hk
  have hlen : (insertAt t i c).len = t.len + c.length := rfl
  constructor
  · intro _
    by_cases h0 : 0 < i
    · rw [ins_lt h0]; exact w.first (by omega)
    · rw [ins_mid (by omega) (by omega), show 0 - i = 0 by omega]; exact vc.lead
  · intro q hq hl
    rw [hlen] at hq ⊢
    by_cases h1 : q < i
    · rw [ins_lt h1] at hl ⊢
      have := inside_char w (by omega) hl h1 hb; omega
    · by_cases h2 : q < i + c.length
      · rw [ins_mid (by omega) h2] at hl ⊢
        have hq0 : q - i = 0 := by
          apply Classical.byContradiction; intro hne
          rw [vc.conts (q - i) (by omega) (by omega)] at hl; exact absurd hl (by decide)
        rw [hq0, ← vc.len]; omega
      · rw [ins_ge (by omega)] at hl ⊢
        have := w.fits (q - c.length) (by omega) hl; omega
  · intro q hq hl j hj0 hjk
    rw [hlen] at hq
    by_cases h1 : q < i
    · rw [ins_lt h1] at hl hjk
      have := inside_char w (by omega) hl h1 hb
      rw [ins_lt (by omega)]; exact w.conts q (by omega) hl j hj0 hjk
    · by_cases h2 : q < i + c.length
      · rw [ins_mid (by omega) h2] at hl hjk
        have hq0 : q - i = 0 := by
          apply Classical.byContradiction; intro hne
          rw [vc.conts (q - i) (by omega) (by omega)] at hl; exact absurd hl (by decide)
        rw [hq0, ← vc.len] at hjk
        rw [ins_mid (by omega) (by omega), show q + j - i = j by omega]
        exact vc.conts j hj0 hjk
      · rw [ins_ge (by omega)] at hl hjk
        rw [ins_ge (by omega), show q + j - c.length = (q - c.length) + j by omega]
        exact w.conts (q - c.length) (by omega) hl j hj0 hjk
  · intro q hq hl
    rw [hlen] at hq
    by_cases h1 : q < i
    · rw [ins_lt h1] at hl ⊢
      have hin := inside_char w (by omega) hl h1 hb
      have hn := w.next q (by omega) hl
      by_cases h3 : q + size (t.byte q) < i
      · exact ins_old hi hn h3
      · rw [show q + size (t.byte q) = i by omega]; exact ins_at hi vc
    · by_cases h2 : q < i + c.length
      · rw [ins_mid (by omega) h2] at hl ⊢
        have hq0 : q - i = 0 := by
          apply Classical.byContradiction; intro hne
          rw [vc.conts (q - i) (by omega) (by omega)] at hl; exact absurd hl (by decide)
        rw [hq0, ← vc.len, show q = i by omega, Nat.add_comm]
        rw [Nat.add_comm]; exact ins_shift hb (Nat.le_refl _)
      · rw [ins_ge (by omega)] at hl ⊢
        have hn := w.next (q - c.length) (by omega) hl
        have := ins_shift (i := i) (c := c) hn (by omega)
        rwa [show q - c.length + size (t.byte (q - c.length)) + c.length
              = q + size (t.byte (q - c.length)) by omega] at this

end insert


section delete
variable {t : Text} {i k : Nat}

theorem del_lt {j : Nat} (h : j < i) : (deleteAt t i k).byte j = t.byte j := by
  simp only [deleteAt]; rw [if_pos h]
theorem del_ge {j : Nat} (h : i ≤ j) : (deleteAt t i k).byte j = t.byte (j + k) := by
  simp only [deleteAt]; rw [if_neg (by omega)]

/-- The `k` bytes from `i` are one whole character. -/
structure WholeChar (t : Text) (i k : Nat) : Prop where
  lt   : i < t.len
  lead : isCont (t.byte i) = false
  size : k = size (t.byte i)

variable (w : WF t) (wc : WholeChar t i k)
include w wc

theorem wc_end : Boundary t (i + k) := by rw [wc.size]; exact w.next i wc.lt wc.lead
theorem wc_fits : i + k ≤ t.len := by rw [wc.size]; exact w.fits i wc.lt wc.lead

theorem del_old {j : Nat} (hb : Boundary t j) (h : j < i) : Boundary (deleteAt t i k) j := by
  have := wc_fits w wc
  rcases hb with e | ⟨_, hl⟩
  · omega
  · exact Or.inr ⟨by simp only [deleteAt]; omega, by rw [del_lt h]; exact hl⟩

theorem del_at : Boundary (deleteAt t i k) i := by
  have := wc_fits w wc
  rcases wc_end w wc with e | ⟨h, hl⟩
  · exact Or.inl (by simp only [deleteAt]; omega)
  · exact Or.inr ⟨by simp only [deleteAt]; omega, by rw [del_ge (Nat.le_refl _)]; exact hl⟩

omit w wc in
theorem del_shift {j : Nat} (hb : Boundary t j) (h : i + k ≤ j) :
    Boundary (deleteAt t i k) (j - k) := by
  rcases hb with e | ⟨hj, hl⟩
  · exact Or.inl (by simp only [deleteAt]; omega)
  · refine Or.inr ⟨by simp only [deleteAt]; omega, ?_⟩
    rw [del_ge (by omega), show j - k + k = j by omega]; exact hl

/-- Deleting a whole character keeps the text well formed. -/
theorem delete_wf : WF (deleteAt t i k) := by
  have hfit := wc_fits w wc
  have hbi : Boundary t i := Or.inr ⟨wc.lt, wc.lead⟩
  have hlen : (deleteAt t i k).len = t.len - k := rfl
  constructor
  · intro h0
    rw [hlen] at h0
    by_cases hi0 : 0 < i
    · rw [del_lt hi0]; exact w.first (by omega)
    · rw [del_ge (by omega), Nat.zero_add]
      rcases wc_end w wc with e | ⟨_, hl⟩
      · omega
      · rwa [show i + k = k by omega] at hl
  · intro q hq hl
    rw [hlen] at hq ⊢
    by_cases h1 : q < i
    · rw [del_lt h1] at hl ⊢
      have := inside_char w (by omega) hl h1 hbi; omega
    · rw [del_ge (by omega)] at hl ⊢
      have := w.fits (q + k) (by omega) hl; omega
  · intro q hq hl j hj0 hjm
    rw [hlen] at hq
    by_cases h1 : q < i
    · rw [del_lt h1] at hl hjm
      have := inside_char w (by omega) hl h1 hbi
      rw [del_lt (by omega)]; exact w.conts q (by omega) hl j hj0 hjm
    · rw [del_ge (by omega)] at hl hjm
      rw [del_ge (by omega), show q + j + k = (q + k) + j by omega]
      exact w.conts (q + k) (by omega) hl j hj0 hjm
  · intro q hq hl
    rw [hlen] at hq
    by_cases h1 : q < i
    · rw [del_lt h1] at hl ⊢
      have hin := inside_char w (by omega) hl h1 hbi
      have hn := w.next q (by omega) hl
      by_cases h3 : q + size (t.byte q) < i
      · exact del_old w wc hn h3
      · rw [show q + size (t.byte q) = i by omega]; exact del_at w wc
    · rw [del_ge (by omega)] at hl ⊢
      have hn := w.next (q + k) (by omega) hl
      have := del_shift (i := i) (k := k) hn (by omega)
      rwa [show q + k + size (t.byte (q + k)) - k = q + size (t.byte (q + k)) by omega] at this

end delete

/-! ## Hidden text (fold.c) -/

/-- A fold hides the bytes `a + 1 .. b`. -/
structure Fold where
  a : Nat
  b : Nat

/-- What a fold must satisfy: it starts on a boundary and hides whole
characters. Org's folds run from newline to newline, which gives this
(`newline_fold`); `fe_fold` checks it. -/
structure FoldOK (t : Text) (f : Fold) : Prop where
  ab : f.a < f.b
  bl : f.b < t.len
  ba : Boundary t f.a
  ba1 : Boundary t (f.a + 1)
  bb : Boundary t (f.b + 1)

def hides (f : Fold) (p : Nat) : Bool := f.a < p && p ≤ f.b

/-- fold.c, `outermost`: the largest fold hiding `p`. -/
def outermost : List Fold → Nat → Option Fold
  | [], _ => none
  | f :: fs, p =>
    match outermost fs p with
    | none => if hides f p then some f else none
    | some g => if hides f p && g.b - g.a < f.b - f.a then some f else some g

/-- fold.c, `fold_skip_forward`; the C `while` is this with enough fuel. -/
def skipFwd (fs : List Fold) : Nat → Nat → Nat
  | 0, p => p
  | n + 1, p =>
    match outermost fs p with
    | none => p
    | some f => skipFwd fs n (f.b + 1)

/-- fold.c, `fold_skip_backward`. -/
def skipBack (fs : List Fold) : Nat → Nat → Nat
  | 0, p => p
  | n + 1, p =>
    match outermost fs p with
    | none => p
    | some f => skipBack fs n f.a

def hidden (fs : List Fold) (p : Nat) : Bool := (outermost fs p).isSome

theorem outermost_mem : ∀ {fs : List Fold} {p : Nat} {f : Fold},
    outermost fs p = some f → f ∈ fs := by
  intro fs
  induction fs with
  | nil => intro p f h; simp [outermost] at h
  | cons g gs ih =>
    intro p f h
    simp only [outermost] at h
    split at h
    · split at h
      · cases h; exact List.mem_cons_self
      · cases h
    · split at h
      · cases h; exact List.mem_cons_self
      · cases h; exact List.mem_cons_of_mem _ (ih (by assumption))

theorem skipFwd_boundary {t : Text} {fs : List Fold} (hf : ∀ f ∈ fs, FoldOK t f) :
    ∀ n p, Boundary t p → Boundary t (skipFwd fs n p) := by
  intro n
  induction n with
  | zero => intro p h; exact h
  | succ n ih =>
    intro p h
    simp only [skipFwd]
    split
    · exact h
    · exact ih _ (hf _ (outermost_mem (by assumption))).bb

theorem skipBack_boundary {t : Text} {fs : List Fold} (hf : ∀ f ∈ fs, FoldOK t f) :
    ∀ n p, Boundary t p → Boundary t (skipBack fs n p) := by
  intro n
  induction n with
  | zero => intro p h; exact h
  | succ n ih =>
    intro p h
    simp only [skipBack]
    split
    · exact h
    · exact ih _ (hf _ (outermost_mem (by assumption))).ba

/-- A newline is a whole character, so a range from newline to newline
(Org's folds) has boundaries at both ends. -/
theorem newline_fold {t : Text} (w : WF t) {f : Fold} (hab : f.a < f.b) (hbl : f.b < t.len)
    (ha : t.byte f.a = 10) (hb : t.byte f.b = 10) : FoldOK t f := by
  have hn := w.next f.b hbl (by rw [hb]; decide)
  rw [hb, show size 10 = 1 by decide] at hn
  have hn1 := w.next f.a (by omega) (by rw [ha]; decide)
  rw [ha, show size 10 = 1 by decide] at hn1
  exact ⟨hab, hbl, Or.inr ⟨by omega, by rw [ha]; decide⟩, hn1, hn⟩

/-- fold.c, `fold_change` for an insertion of `k` bytes at `i`. -/
def foldIns (i k : Nat) (f : Fold) : Option Fold :=
  if i ≤ f.a then some ⟨f.a + k, f.b + k⟩ else if i ≤ f.b then none else some f

/-- fold.c, `fold_change` for a deletion of `k` bytes at `i`. -/
def foldDel (i k : Nat) (f : Fold) : Option Fold :=
  if i + k ≤ f.a then some ⟨f.a - k, f.b - k⟩ else if i ≤ f.b then none else some f

theorem foldIns_ok {t : Text} {i : Nat} {c : List Nat} (hb : Boundary t i) (vc : ValidChar c)
    {f g : Fold} (hf : FoldOK t f) (h : foldIns i c.length f = some g) :
    FoldOK (insertAt t i c) g := by
  have hi := boundary_le hb
  simp only [foldIns] at h
  split at h
  · cases h
    have hab := hf.ab
    refine ⟨by simp; exact hf.ab, by simp only [insertAt]; have := hf.bl; omega,
      ins_shift hf.ba (by omega), ?_, ?_⟩
    · have := ins_shift (i := i) (c := c) hf.ba1 (by omega)
      rwa [show f.a + 1 + c.length = f.a + c.length + 1 by omega] at this
    have := ins_shift (i := i) (c := c) hf.bb (by omega)
    rwa [show f.b + 1 + c.length = f.b + c.length + 1 by omega] at this
  · split at h
    · cases h
    · cases h
      have hab := hf.ab
      refine ⟨hf.ab, by simp only [insertAt]; have := hf.bl; omega,
        ins_old hi hf.ba (by omega), ins_old hi hf.ba1 (by omega), ?_⟩
      by_cases e : f.b + 1 < i
      · exact ins_old hi hf.bb e
      · rw [show f.b + 1 = i by omega]; exact ins_at hi vc

theorem foldDel_ok {t : Text} {i k : Nat} (w : WF t) (wc : WholeChar t i k)
    {f g : Fold} (hf : FoldOK t f) (h : foldDel i k f = some g) :
    FoldOK (deleteAt t i k) g := by
  have hfit := wc_fits w wc
  simp only [foldDel] at h
  split at h
  · cases h
    have hab := hf.ab
    refine ⟨by simp; omega, by simp only [deleteAt]; have := hf.bl; omega,
      del_shift hf.ba (by omega), ?_, ?_⟩
    · have := del_shift (i := i) (k := k) hf.ba1 (by omega)
      rwa [show f.a + 1 - k = f.a - k + 1 by omega] at this
    have := del_shift (i := i) (k := k) hf.bb (by omega)
    rwa [show f.b + 1 - k = f.b - k + 1 by omega] at this
  · split at h
    · cases h
    · cases h
      have hab := hf.ab
      refine ⟨hab, by simp only [deleteAt]; omega, del_old w wc hf.ba (by omega),
        del_old w wc hf.ba1 (by omega), ?_⟩
      by_cases e : f.b + 1 < i
      · exact del_old w wc hf.bb e
      · rw [show f.b + 1 = i by omega]; exact del_at w wc

/-! ## Rows: C-n, C-p and the mouse (display.c) -/

/-- display.c, `lnstart`: the start of the line holding `off` (it does not
look at byte 0, as in C). -/
def lnstart (t : Text) : Nat → Nat
  | 0 => 0
  | p + 1 => if p = 0 then 0 else if t.byte p = 10 then p + 1 else lnstart t p

theorem lnstart_boundary {t : Text} (w : WF t) : ∀ p, p ≤ t.len → Boundary t (lnstart t p) := by
  intro p
  induction p with
  | zero => intro _; exact boundary_zero w
  | succ p ih =>
    intro hp
    simp only [lnstart]
    split
    · exact boundary_zero w
    · split
      · have hn := w.next p (by omega) (by rename_i h; rw [h]; decide)
        rename_i h; rwa [h, show size 10 = 1 by decide] at hn
      · exact ih (by omega)

/-- A scan by whole characters, as `lncolumn`, `past_accents`, `segstart`
and `segnext` do: from `p`, step `utf8_size` bytes while the text goes on and
`stop` (the column reached, a newline, a wrapped row's end, an accent of
width 0 not found...) says to go on. `stop` and the fuel are left open, so
the theorem holds for every width table, wrap and column. -/
def walk (t : Text) (stop : Nat → Bool) : Nat → Nat → Nat
  | 0, p => p
  | n + 1, p => if p < t.len ∧ stop p = false then walk t stop n (p + size (t.byte p)) else p

theorem walk_boundary {t : Text} (w : WF t) (stop : Nat → Bool) :
    ∀ n p, Boundary t p → Boundary t (walk t stop n p) := by
  intro n
  induction n with
  | zero => intro p h; exact h
  | succ n ih =>
    intro p h
    simp only [walk]
    split
    · rename_i hc
      rcases h with e | ⟨hp, hl⟩
      · omega
      · exact ih _ (w.next p hp hl)
    · exact h

/-- What the screen decides: where rows wrap, how wide characters are, the
goal column. Every field is free. -/
structure Geometry where
  seg   : Nat → Bool      -- segstart's scan
  seg2  : Nat → Bool      -- segstart from the row above
  next  : Nat → Bool      -- segnext's scan to the next row
  col   : Nat → Bool      -- lncolumn: the goal column (b_col) reached
  acc   : Nat → Bool      -- past_accents: no accent of width 0 follows
  fuel  : Nat

/-- display.c, `lncolumn`. -/
def lncolumn (t : Text) (g : Geometry) (p : Nat) : Nat :=
  walk t g.acc g.fuel (walk t g.col g.fuel p)

/-- display.c, `dndn`: the next screen row, over a folded heading. -/
def dndn (t : Text) (fs : List Fold) (g : Geometry) (p : Nat) : Nat :=
  skipFwd fs (fs.length + 1) (walk t g.next g.fuel (walk t g.seg g.fuel (lnstart t p)))

/-- display.c, `upup`, first part: the start of the screen row above. -/
def rowAbove (t : Text) (g : Geometry) (p : Nat) : Nat :=
  let curr := lnstart t p
  if curr < walk t g.seg g.fuel curr then walk t g.seg2 g.fuel curr
  else walk t g.seg2 g.fuel (lnstart t (curr - 1))

/-- display.c, `upup`: the screen row above, to a folded heading's row. -/
def upup (t : Text) (fs : List Fold) (g : Geometry) (p : Nat) : Nat :=
  let off := rowAbove t g p
  if hidden fs off then walk t g.seg g.fuel (lnstart t (skipBack fs (fs.length + 1) off))
  else off

/-! ## The editor -/

structure State where
  text  : Text
  point : Nat
  folds : List Fold

/-- What every command must keep: the text is UTF-8, point is between two
characters, and each fold hides whole characters. -/
structure Inv (s : State) : Prop where
  wf    : WF s.text
  point : Boundary s.text s.point
  folds : ∀ f ∈ s.folds, FoldOK s.text f

/-- Apply `f` again while `cond` holds, at most `fuel` times: the C loops
`while (... accent_at(...)) right();` and `left();`. -/
def repeatWhile (f : Nat → Nat) (cond : Nat → Bool) : Nat → Nat → Nat
  | 0, p => p
  | n + 1, p => if cond p then repeatWhile f cond n (f p) else p

theorem repeatWhile_keeps {P : Nat → Prop} {f : Nat → Nat} (hf : ∀ p, P p → P (f p))
    (cond : Nat → Bool) : ∀ n p, P p → P (repeatWhile f cond n p) := by
  intro n
  induction n with
  | zero => intro p h; exact h
  | succ n ih =>
    intro p h
    simp only [repeatWhile]
    split
    · exact ih _ (hf p h)
    · exact h

/-- command.c, `right`, the primitive (the scripts' forward-char): one code
point, then over the folds. -/
def rightPrim (s : State) (p : Nat) : Nat :=
  skipFwd s.folds (s.folds.length + 1) (stepRight s.text p)

/-- command.c, `left`, the primitive (backward-char): one code point back,
then over the folds. -/
def leftPrim (s : State) (p : Nat) : Nat :=
  skipBack s.folds (s.folds.length + 1) (stepLeft s.text p)

/-- command.c, `forward_character` (C-f, the right arrow): `right`, then
`right` again while the character at point is a combining accent (`acc`,
`accent_at` in display.c, left open: any table). With `acc` false
everywhere this is one `right`, the scripts' forward-char, so the theorem
below covers the primitive too. -/
def forwardChar (acc : Nat → Bool) (s : State) : State :=
  let p := repeatWhile (rightPrim s) (fun q => decide (q < s.text.len) && acc q)
             s.text.len (rightPrim s s.point)
  { s with point := p }

/-- command.c, `backward_character` (C-b, the left arrow): `left`, then
`left` again while the character at point is an accent. -/
def backwardChar (acc : Nat → Bool) (s : State) : State :=
  let p := repeatWhile (leftPrim s) (fun q => decide (0 < q) && acc q)
             s.text.len (leftPrim s s.point)
  { s with point := p }

/-- command.c, `down` (C-n) and `up` (C-p); the mouse ends in `lncolumn` too. -/
def nextLine (g : Geometry) (s : State) : State :=
  { s with point := lncolumn s.text g (dndn s.text s.folds g s.point) }
def previousLine (g : Geometry) (s : State) : State :=
  { s with point := lncolumn s.text g (upup s.text s.folds g s.point) }

/-- command.c, `insert`: one complete character before point. -/
def insertChar (c : List Nat) (s : State) : State where
  text  := insertAt s.text s.point c
  point := s.point + c.length
  folds := s.folds.filterMap (foldIns s.point c.length)

/-- command.c, `delete` (C-d). -/
def deleteChar (s : State) : State :=
  if s.point < s.text.len then
    let k := size (s.text.byte s.point)
    { text := deleteAt s.text s.point k, point := s.point,
      folds := s.folds.filterMap (foldDel s.point k) }
  else s

/-- command.c, `backsp`. -/
def backspace (s : State) : State :=
  if 0 < s.point then
    let k := prevSize s.text s.point
    let j := s.point - k
    { text := deleteAt s.text j k, point := j, folds := s.folds.filterMap (foldDel j k) }
  else s

/-- command.c, `insert` in overwrite mode: the character at point, unless it
is a newline, is replaced by the typed one. -/
def overwriteChar (c : List Nat) (s : State) : State :=
  if s.point < s.text.len ∧ s.text.byte s.point ≠ 10 then insertChar c (deleteChar s)
  else insertChar c s

/-- fold.c, `fe_fold`, given a range whose ends are boundaries. -/
def addFold (f : Fold) (s : State) : State :=
  if f.a < f.b ∧ f.b < s.text.len then
    { s with folds := f :: s.folds, point := if hides f s.point then f.a else s.point }
  else s

/-- fold.c, `fe_unfold` and `fold_reveal`: open some folds. -/
def openFolds (keep : Fold → Bool) (s : State) : State :=
  { s with folds := s.folds.filter keep }

theorem rightPrim_boundary {s : State} (h : Inv s) :
    ∀ p, Boundary s.text p → Boundary s.text (rightPrim s p) := fun _ hp =>
  skipFwd_boundary h.folds _ _ (stepRight_boundary h.wf hp)

theorem leftPrim_boundary {s : State} (h : Inv s) :
    ∀ p, Boundary s.text p → Boundary s.text (leftPrim s p) := fun _ hp =>
  skipBack_boundary h.folds _ _ (stepLeft_boundary h.wf hp)

theorem forwardChar_inv (acc : Nat → Bool) {s : State} (h : Inv s) : Inv (forwardChar acc s) :=
  ⟨h.wf, repeatWhile_keeps (rightPrim_boundary h) _ _ _ (rightPrim_boundary h _ h.point), h.folds⟩

theorem backwardChar_inv (acc : Nat → Bool) {s : State} (h : Inv s) :
    Inv (backwardChar acc s) :=
  ⟨h.wf, repeatWhile_keeps (leftPrim_boundary h) _ _ _ (leftPrim_boundary h _ h.point), h.folds⟩

theorem lncolumn_boundary {t : Text} (w : WF t) (g : Geometry) {p : Nat} (h : Boundary t p) :
    Boundary t (lncolumn t g p) :=
  walk_boundary w _ _ _ (walk_boundary w _ _ _ h)

theorem dndn_boundary {t : Text} (w : WF t) {fs : List Fold} (hf : ∀ f ∈ fs, FoldOK t f)
    (g : Geometry) {p : Nat} (hp : p ≤ t.len) : Boundary t (dndn t fs g p) :=
  skipFwd_boundary hf _ _ (walk_boundary w _ _ _ (walk_boundary w _ _ _ (lnstart_boundary w p hp)))

theorem rowAbove_boundary {t : Text} (w : WF t) (g : Geometry) {p : Nat} (hp : p ≤ t.len) :
    Boundary t (rowAbove t g p) := by
  have hc := lnstart_boundary w p hp
  simp only [rowAbove]
  split
  · exact walk_boundary w _ _ _ hc
  · exact walk_boundary w _ _ _ (lnstart_boundary w _ (by have := boundary_le hc; omega))

theorem upup_boundary {t : Text} (w : WF t) {fs : List Fold} (hf : ∀ f ∈ fs, FoldOK t f)
    (g : Geometry) {p : Nat} (hp : p ≤ t.len) : Boundary t (upup t fs g p) := by
  have hoff := rowAbove_boundary w g hp
  unfold upup
  generalize rowAbove t g p = off at hoff
  dsimp only
  split
  · exact walk_boundary w _ _ _ (lnstart_boundary w _
      (boundary_le (skipBack_boundary hf _ _ hoff)))
  · exact hoff

theorem nextLine_inv (g : Geometry) {s : State} (h : Inv s) : Inv (nextLine g s) :=
  ⟨h.wf, lncolumn_boundary h.wf g (dndn_boundary h.wf h.folds g (boundary_le h.point)), h.folds⟩

theorem previousLine_inv (g : Geometry) {s : State} (h : Inv s) : Inv (previousLine g s) :=
  ⟨h.wf, lncolumn_boundary h.wf g (upup_boundary h.wf h.folds g (boundary_le h.point)), h.folds⟩

theorem insertChar_inv {c : List Nat} (vc : ValidChar c) {s : State} (h : Inv s) :
    Inv (insertChar c s) := by
  refine ⟨insert_wf h.wf h.point vc, ins_shift h.point (Nat.le_refl _), ?_⟩
  intro g hg
  obtain ⟨f, hf, he⟩ := List.mem_filterMap.mp hg
  exact foldIns_ok h.point vc (h.folds f hf) he

theorem deleteAt_inv {s : State} (h : Inv s) {j k : Nat} (wc : WholeChar s.text j k) :
    Inv { text := deleteAt s.text j k, point := j, folds := s.folds.filterMap (foldDel j k) } := by
  refine ⟨delete_wf h.wf wc, del_at h.wf wc, ?_⟩
  intro g hg
  obtain ⟨f, hf, he⟩ := List.mem_filterMap.mp hg
  exact foldDel_ok h.wf wc (h.folds f hf) he

theorem deleteChar_inv {s : State} (h : Inv s) : Inv (deleteChar s) := by
  unfold deleteChar
  split
  · rename_i hp
    have hl : isCont (s.text.byte s.point) = false := by
      rcases h.point with e | ⟨_, hl⟩
      · omega
      · exact hl
    exact deleteAt_inv h ⟨hp, hl, rfl⟩
  · exact h

theorem backspace_inv {s : State} (h : Inv s) : Inv (backspace s) := by
  unfold backspace
  split
  · rename_i hp
    obtain ⟨j, hj, hl, he⟩ := prev_char h.wf hp h.point
    have hjl : j < s.text.len := by have := boundary_le h.point; have := size_pos (s.text.byte j); omega
    have hk := prevSize_eq h.wf hj hjl hl he
    have hjj : s.point - prevSize s.text s.point = j := by omega
    dsimp only
    rw [hjj]
    exact deleteAt_inv h ⟨hjl, hl, by rw [hk]⟩
  · exact h

theorem overwriteChar_inv {c : List Nat} (vc : ValidChar c) {s : State} (h : Inv s) :
    Inv (overwriteChar c s) := by
  unfold overwriteChar
  split
  · exact insertChar_inv vc (deleteChar_inv h)
  · exact insertChar_inv vc h

theorem addFold_inv {f : Fold} {s : State} (h : Inv s) (ha : Boundary s.text f.a)
    (ha1 : Boundary s.text (f.a + 1)) (hb : Boundary s.text (f.b + 1)) : Inv (addFold f s) := by
  unfold addFold
  split
  · rename_i hr
    refine ⟨h.wf, ?_, ?_⟩
    · show Boundary s.text (if hides f s.point then f.a else s.point)
      split
      · exact ha
      · exact h.point
    · intro g hg
      rcases List.mem_cons.mp hg with e | e
      · rw [e]; exact ⟨hr.1, hr.2, ha, ha1, hb⟩
      · exact h.folds g e
  · exact h

theorem openFolds_inv (keep : Fold → Bool) {s : State} (h : Inv s) : Inv (openFolds keep s) :=
  ⟨h.wf, h.point, fun f hf => h.folds f (List.mem_filter.mp hf).1⟩

/-! ## Typing: one key is one complete character (key.c, `get_key`) -/

/-- Up to `n` continuation bytes from the front of the input; the first other
byte stays unread (key.c's `unread_key_bytes`). -/
def takeConts : Nat → List Nat → List Nat × List Nat
  | 0, bs => ([], bs)
  | _ + 1, [] => ([], [])
  | n + 1, b :: bs =>
    if isCont b then ((b :: (takeConts n bs).1), (takeConts n bs).2) else ([], b :: bs)

theorem takeConts_cont : ∀ n bs, ∀ x ∈ (takeConts n bs).1, isCont x = true := by
  intro n
  induction n with
  | zero => intro bs x h; simp [takeConts] at h
  | succ n ih =>
    intro bs x h
    cases bs with
    | nil => simp [takeConts] at h
    | cons b bs =>
      simp only [takeConts] at h
      split at h
      · rcases List.mem_cons.mp h with e | e
        · rw [e]; assumption
        · exact ih bs x e
      · simp at h

/-- U+FFFD, the replacement character. -/
def replacement : List Nat := [0xEF, 0xBF, 0xBD]

/-- The key reader as key.c has it, with `insert` before the fix (and with
toggle-utf8-fix off): a lead byte from C2 to F4 takes its continuation
bytes; if one is missing, only the lead byte is inserted; any other byte is
a key by itself, inserted as it is. -/
def readKeyC : List Nat → Option (List Nat × List Nat)
  | [] => none
  | b :: bs =>
    if 0xC2 ≤ b ∧ b ≤ 0xF4 then
      let r := takeConts (size b - 1) bs
      if r.1.length = size b - 1 then some (b :: r.1, r.2) else some ([b], r.2)
    else some ([b], bs)

/-- The key reader the specification asks for: the same, except that bytes
which are not a complete character (a lead byte without its continuation
bytes, a continuation byte alone, any other byte from 80 up) become U+FFFD,
as `insert` (command.c, `complete_char`) now does. -/
def readKey : List Nat → Option (List Nat × List Nat)
  | [] => none
  | b :: bs =>
    if 0xC2 ≤ b ∧ b ≤ 0xF4 then
      let r := takeConts (size b - 1) bs
      if r.1.length = size b - 1 then some (b :: r.1, r.2) else some (replacement, r.2)
    else if b < 0x80 then some ([b], bs)
    else some (replacement, bs)

theorem validChar_cons {b : Nat} {cs : List Nat} (hl : isCont b = false)
    (hn : cs.length + 1 = size b) (hc : ∀ x ∈ cs, isCont x = true) : ValidChar (b :: cs) := by
  refine ⟨by simpa using hl, by simpa using hn, ?_⟩
  intro j hj0 hjl
  obtain ⟨j', rfl⟩ : ∃ j', j = j' + 1 := ⟨j - 1, by omega⟩
  have hj' : j' < cs.length := by simp at hjl; omega
  have : (b :: cs).getD (j' + 1) 0 = cs.getD j' 0 := by simp
  rw [this]
  apply hc
  simp [List.getD_eq_getElem?_getD, List.getElem?_eq_getElem hj']

theorem replacement_valid : ValidChar replacement :=
  validChar_cons (by decide) (by decide) (by decide)

/-- Every key the specified reader delivers is one complete character. -/
theorem readKey_valid {bs c rest : List Nat} (h : readKey bs = some (c, rest)) : ValidChar c := by
  cases bs with
  | nil => simp [readKey] at h
  | cons b bs =>
    simp only [readKey] at h
    split at h
    · rename_i hb
      split at h
      · rename_i hn
        cases h
        have hl : isCont b = false := by unfold isCont; simp; omega
        have hs := size_pos b
        exact validChar_cons hl (by omega) (takeConts_cont _ _)
      · cases h; exact replacement_valid
    · split at h
      · rename_i hb
        cases h
        have hl : isCont b = false := by unfold isCont; simp; omega
        have hs : size b = 1 := by unfold size; repeat (first | omega | split)
        exact validChar_cons hl (by simp [hs]) (by simp)
      · cases h; exact replacement_valid

/-- Read every key of the input, as the main loop does (fuel: one key needs
at least one byte). -/
def readKeys : Nat → List Nat → List (List Nat)
  | 0, _ => []
  | n + 1, bs =>
    match readKey bs with
    | none => []
    | some (c, rest) => c :: readKeys n rest

theorem readKeys_valid : ∀ n bs, ∀ c ∈ readKeys n bs, ValidChar c := by
  intro n
  induction n with
  | zero => intro bs c h; simp [readKeys] at h
  | succ n ih =>
    intro bs c h
    simp only [readKeys] at h
    split at h
    · simp at h
    · rename_i c' rest hr
      rcases List.mem_cons.mp h with e | e
      · rw [e]; exact readKey_valid hr
      · exact ih rest c e

/-! ## Any sequence of commands -/

instance (t : Text) (i : Nat) : Decidable (Boundary t i) := by
  unfold Boundary; infer_instance

inductive Cmd where
  | forward (acc : Nat → Bool) | backward (acc : Nat → Bool)   -- acc: the accents
  | next (g : Geometry) | previous (g : Geometry)
  | type (input : List Nat)          -- the terminal's bytes, read key by key
  | overwrite (input : List Nat)     -- the same in overwrite mode
  | delete | backspace
  | fold (f : Fold)                  -- fe_fold, refused unless it hides whole characters
  | unfold (keep : Fold → Bool)

def typeKeys (over : Bool) : List (List Nat) → State → List State
  | [], _ => []
  | c :: cs, s =>
    let s' := if over then overwriteChar c s else insertChar c s
    s' :: typeKeys over cs s'

/-- The states the display can see while a command runs: after each key. -/
def Cmd.states : Cmd → State → List State
  | .forward acc, s => [forwardChar acc s]
  | .backward acc, s => [backwardChar acc s]
  | .next g, s => [nextLine g s]
  | .previous g, s => [previousLine g s]
  | .type bs, s => typeKeys false (readKeys bs.length bs) s
  | .overwrite bs, s => typeKeys true (readKeys bs.length bs) s
  | .delete, s => [deleteChar s]
  | .backspace, s => [Utf8Cursor.backspace s]
  | .fold f, s =>
    if Boundary s.text f.a ∧ Boundary s.text (f.a + 1) ∧ Boundary s.text (f.b + 1)
    then [addFold f s] else [s]
  | .unfold keep, s => [openFolds keep s]

/-- The state a command leaves. -/
def Cmd.run (c : Cmd) (s : State) : State := ((c.states s).getLast?).getD s

/-- Every state a display can observe while a list of commands runs. -/
def observed : List Cmd → State → List State
  | [], s => [s]
  | c :: cs, s => s :: (c.states s) ++ observed cs (c.run s)

theorem typeKeys_inv (over : Bool) : ∀ (cs : List (List Nat)), (∀ c ∈ cs, ValidChar c) →
    ∀ s, Inv s → ∀ s' ∈ typeKeys over cs s, Inv s' := by
  intro cs
  induction cs with
  | nil => intro _ s _ s' h; simp [typeKeys] at h
  | cons c cs ih =>
    intro hv s hs s' h
    have hvc := hv c List.mem_cons_self
    have h1 : Inv (if over then overwriteChar c s else insertChar c s) := by
      split
      · exact overwriteChar_inv hvc hs
      · exact insertChar_inv hvc hs
    simp only [typeKeys] at h
    rcases List.mem_cons.mp h with e | e
    · rw [e]; exact h1
    · exact ih (fun x hx => hv x (List.mem_cons_of_mem _ hx)) _ h1 s' e

theorem states_inv (c : Cmd) {s : State} (h : Inv s) : ∀ s' ∈ c.states s, Inv s' := by
  cases c with
  | forward acc => intro s' e; simp [Cmd.states] at e; rw [e]; exact forwardChar_inv acc h
  | backward acc => intro s' e; simp [Cmd.states] at e; rw [e]; exact backwardChar_inv acc h
  | next g => intro s' e; simp [Cmd.states] at e; rw [e]; exact nextLine_inv g h
  | previous g => intro s' e; simp [Cmd.states] at e; rw [e]; exact previousLine_inv g h
  | type bs => exact typeKeys_inv false _ (readKeys_valid _ _) s h
  | overwrite bs => exact typeKeys_inv true _ (readKeys_valid _ _) s h
  | delete => intro s' e; simp [Cmd.states] at e; rw [e]; exact deleteChar_inv h
  | backspace => intro s' e; simp [Cmd.states] at e; rw [e]; exact backspace_inv h
  | fold f =>
    intro s' e
    simp only [Cmd.states] at e
    split at e
    · rename_i hb; simp at e; rw [e]; exact addFold_inv h hb.1 hb.2.1 hb.2.2
    · simp at e; rw [e]; exact h
  | unfold keep => intro s' e; simp [Cmd.states] at e; rw [e]; exact openFolds_inv keep h

theorem run_inv (c : Cmd) {s : State} (h : Inv s) : Inv (c.run s) := by
  unfold Cmd.run
  cases e : (c.states s).getLast? with
  | none => exact h
  | some s' => exact states_inv c h s' (List.mem_of_getLast? e)

/-- **The specification.** From a well-formed state, whatever commands run,
every state the display can observe has point on a character boundary, the
text well formed and every fold over whole characters, hidden text included.
In particular the display never sees half of a typed character. -/
theorem cursor_on_boundary : ∀ (cs : List Cmd) (s : State), Inv s →
    ∀ s' ∈ observed cs s, Boundary s'.text s'.point ∧ WF s'.text := by
  intro cs
  induction cs with
  | nil => intro s h s' e; simp [observed] at e; rw [e]; exact ⟨h.point, h.wf⟩
  | cons c cs ih =>
    intro s h s' e
    simp only [observed] at e
    rcases List.mem_cons.mp e with e | e
    · rw [e]; exact ⟨h.point, h.wf⟩
    · rcases List.mem_append.mp e with e | e
      · have := states_inv c h s' e; exact ⟨this.point, this.wf⟩
      · exact ih _ (run_inv c h) s' e

/-! ## What the C code did before 18 November 2026 (toggle-utf8-fix off)

key.c passes a continuation byte alone, and a lead byte whose continuation
bytes do not follow, to `insert`, which inserted them. The text was then no
longer UTF-8, and C-b and C-f could stop inside a character. -/

/-- "a", point after it. -/
def textA : Text := ⟨1, fun j => if j = 0 then 97 else 0⟩

/-- A lone continuation byte (0x80), typed after "a", is inserted ... -/
example : readKeyC [0x80] = some ([0x80], []) := by decide

/-- ... and C-b from the end stops at the 0x80, which is not a boundary. -/
example : ¬ Boundary (insertAt textA 1 [0x80]) (stepLeft (insertAt textA 1 [0x80]) 2) := by decide

/-- "aé" (61 C3 A9). -/
def textAE : Text := ⟨3, fun j => if j = 0 then 97 else if j = 1 then 0xC3 else if j = 2 then 0xA9 else 0⟩

/-- E2 followed by "a": key.c keeps only E2 ... -/
example : readKeyC [0xE2, 97] = some ([0xE2], [97]) := by decide

/-- ... inserted before "aé", C-f from it jumps three bytes, into é. -/
example : ¬ Boundary (insertAt textAE 0 [0xE2]) (stepRight (insertAt textAE 0 [0xE2]) 0) := by decide

/-- The specified reader turns both into U+FFFD. -/
example : readKey [0x80] = some (replacement, []) := by decide
example : readKey [0xE2, 97] = some (replacement, [97]) := by decide

end Utf8Cursor
