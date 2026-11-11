import Std

/-!
Gap calculator, 7 November 2026. Run: lean --run gap_bp-calculator.lean.
Only growgap and movegap are modelled. No C files are changed.
For C reconstruction, read the sibling gap_bp-reconstruction-plan.md.
It supplies allocation, pointer updates, copy directions and framework rules.
The buffer base is offset zero; end is left.length + gap + right.length.
left and right contain the actual bytes outside the gap. Unused gap bytes
are unspecified: copying them has no observable effect on the text.
extra stands for every unrelated buffer field; it is carried through unchanged.
The ten C assertions become consequences of this representation and theorems.
ptr/pos need no pointer arithmetic here: splitting text at an offset performs
logical addressing directly. Movement accepts offsets from zero through EOF.

Allocation paths (S-expression):
(allocation
  (initial (size-rejected fatal) (malloc-null fatal) (success continue))
  (existing (size-rejected false) (realloc-null false) (success continue)))
There are six paths, four branch/outcome pairs, and three overall outcomes.
The dummy chooses NULL or success only after the size check passes.
A successful allocation preserves old bytes and supplies enough new storage.
The host supplies maxSize. Arithmetic uses mathematical integers: correspondence
with C requires buflen + max(n,512) to fit point_t before C evaluates it.
The negative-size arm remains explicit in the dummy, as in the C block.
Allocation addresses, libc calls, messages and fatal exit are replaced by values.
The suffix-copy loop becomes preservation of right while gap grows. The two
movement loops become take/drop of text. Insertion and deletion are excluded.
C integration, physical copying and restoration of asserts are later work.
-/

namespace GapBP

-- CALCULATION BEGIN: this entire section, including comments, is under 80 lines.
-- These pieces describe one allocation; unrelated editor fields are opaque.
structure BP (Extra : Type) where
  left : List UInt8
  gap : Nat
  right : List UInt8
  extra : Extra
  deriving Repr, DecidableEq
-- Reading ignores the unused gap.
def text (b : BP α) := b.left ++ b.right
-- These are the four physical pointer offsets, with base fixed at zero.
def base (_b : BP α) : Nat := 0
def gapStart (b : BP α) := b.left.length
def gapEnd (b : BP α) := b.left.length + b.gap
def bufferEnd (b : BP α) := b.left.length + b.gap + b.right.length
-- Preserve each failure reason, even when two reasons have the same outcome.
inductive Allocation where
  | success | sizeRejected | allocatorNull
  deriving Repr, DecidableEq
-- The Boolean represents the allocator's choice, not a random test generator.
def allocDummy (newlen : Int) (maxSize : Nat) (succeeds : Bool) : Allocation :=
  if newlen < 0 ∨ newlen > (maxSize : Int) then .sizeRejected
  else if succeeds then .success else .allocatorNull
-- Fatal does not return to C; rejected returns FALSE with the old buffer intact.
inductive Growth (α : Type) where
  | success (bp : BP α) | rejected (why : Allocation) (bp : BP α)
  | fatal (why : Allocation)
  deriving Repr, DecidableEq
-- Growth adds at least 512 bytes; suffix bytes and logical gap position stay put.
def growgap (b : BP α) (n : Int) (maxSize : Nat) (succeeds : Bool) : Growth α :=
  let amount := (max n 512).toNat
  match allocDummy (bufferEnd b + amount) maxSize succeeds with
  | .success => .success { b with gap := b.gap + amount }
  | why => if bufferEnd b = 0 then .fatal why else .rejected why b
-- An invalid offset returns none. Every valid offset gives a new buffer and point.
def movegap (b : BP α) (offset : Nat) : Option (Nat × BP α) :=
  if offset ≤ (text b).length then
    some (offset, { b with left := (text b).take offset, right := (text b).drop offset })
  else none
-- CALCULATION END.

-- All three entry assertions and all three movement assertions hold by construction.
theorem pointer_order (b : BP α) :
    base b ≤ gapStart b ∧ gapStart b ≤ gapEnd b ∧ gapEnd b ≤ bufferEnd b := by
  unfold base gapStart gapEnd bufferEnd
  omega

-- Repositioning the gap keeps every text byte in the same order.
theorem movement_preserves_text (b : BP α) (p : Nat) (h : p ≤ (text b).length) :
    ∃ out, movegap b p = some (p, out) ∧ text out = text b ∧
      gapStart out = p ∧ out.gap = b.gap ∧ out.extra = b.extra := by
  refine ⟨{ b with left := (text b).take p, right := (text b).drop p }, ?_⟩
  simp only [text, List.length_append] at h
  simp [movegap, text, gapStart, h, Nat.min_eq_left h]

-- Growth preserves text, gap position and all unrelated fields; its new gap is larger.
theorem growth_success (b : BP α) (n : Int) (limit : Nat) (ok : Bool)
    (h : allocDummy (bufferEnd b + (max n 512).toNat) limit ok = .success) :
    ∃ out, growgap b n limit ok = .success out ∧ text out = text b ∧
      gapStart out = gapStart b ∧ out.extra = b.extra ∧
      out.gap = b.gap + (max n 512).toNat ∧ b.gap < out.gap := by
  have hn : 0 < (max n 512).toNat := by omega
  refine ⟨{ b with gap := b.gap + (max n 512).toNat }, ?_⟩
  simp only [growgap, h]
  simp [text, gapStart, hn]

-- These four inequalities restore exactly the successful-growth exit assertions.
theorem growth_exit_assertions (b : BP α) (amount : Nat) (h : 0 < amount) :
    let out := { b with gap := b.gap + amount }
    base out < bufferEnd out ∧ base out ≤ gapStart out ∧
      gapStart out < gapEnd out ∧ gapEnd out ≤ bufferEnd out := by
  simp only [base, gapStart, gapEnd, bufferEnd]
  omega

-- A failed existing allocation returns the original buffer, including its extra fields.
theorem rejected_unchanged (b : BP α) (n : Int) (limit : Nat) (ok : Bool)
    (existsBuffer : bufferEnd b ≠ 0)
    (why : Allocation) (failed : why ≠ .success)
    (h : allocDummy (bufferEnd b + (max n 512).toNat) limit ok = why) :
    growgap b n limit ok = .rejected why b := by
  cases why <;> simp_all [growgap]

-- Moving past EOF is refused without producing a replacement buffer.
theorem beyond_eof (b : BP α) (p : Nat) (h : (text b).length < p) :
    movegap b p = none := by
  simp [movegap, Nat.not_le_of_gt h]

-- A size rejection never calls on the allocator's choice.
theorem invalid_size (n : Int) (limit : Nat) (ok : Bool)
    (h : n < 0 ∨ n > (limit : Int)) : allocDummy n limit ok = .sizeRejected := by
  simp [allocDummy, h]

-- Moving twice has the same final buffer as moving directly to the second point.
theorem movement_composes (b : BP α) (p q : Nat)
    (hp : p ≤ (text b).length) (hq : q ≤ (text b).length) :
    (movegap b p).bind (fun x => movegap x.2 q) = movegap b q := by
  simp only [text, List.length_append] at hp hq
  simp [movegap, text, hp, hq, List.take_append_drop]

-- Each simulation checks its expected value and prints a short observation.
def check (name : String) (ok : Bool) : IO Unit := do
  unless ok do throw (IO.userError s!"FAIL: {name}")
  IO.println s!"pass: {name}"

end GapBP

-- Exercise the dummy's six paths and movement boundaries without touching a file.
def main : IO Unit := do
  let b : GapBP.BP Nat := ⟨[65, 66], 2, [67, 68], 99⟩
  let empty : GapBP.BP Nat := ⟨[], 0, [], 99⟩
  GapBP.check "initial / size rejected" (GapBP.growgap empty 1 1 true == .fatal .sizeRejected)
  GapBP.check "initial / malloc NULL" (GapBP.growgap empty 1 1024 false == .fatal .allocatorNull)
  GapBP.check "initial / success" (GapBP.growgap empty 1 1024 true == .success { empty with gap := 512 })
  GapBP.check "existing / size rejected" (GapBP.growgap b 1 1 true == .rejected .sizeRejected b)
  GapBP.check "existing / realloc NULL" (GapBP.growgap b 1 1024 false == .rejected .allocatorNull b)
  GapBP.check "existing / success" (GapBP.growgap b 1 1024 true == .success { b with gap := 514 })
  GapBP.check "move left to BOF" (GapBP.movegap b 0 == some (0, { b with left := [], right := [65,66,67,68] }))
  GapBP.check "move right to EOF" (GapBP.movegap b 4 == some (4, { b with left := [65,66,67,68], right := [] }))
  GapBP.check "stay at gap" (GapBP.movegap b 2 == some (2, b))
  GapBP.check "empty buffer" (GapBP.movegap empty 0 == some (0, empty))
  GapBP.check "beyond EOF" (GapBP.movegap b 5 == none)
