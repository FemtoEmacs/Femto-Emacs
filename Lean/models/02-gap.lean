import Std

/-!
02: watch a gap buffer work.

In native Chezweb, open this file. Press M-!, write
  lean --run 02-gap.lean
then press C-c s. Read the frames in *output*; M-> shows the end.
Lean checks the proofs and interprets the simulation. No C executable is built.

Three lists describe adjacent regions of physical memory: left, free, right.
The gap occupies indices start through finish - 1. finish is its far boundary.
Logical text skips the free cells. Their old contents need not be erased.
The cursor is a logical byte offset. It is separate from the gap.
The examples use ASCII so each visible character occupies one byte.
-/
namespace Gap02

-- Keep all bytes, including stale bytes inside the unused region.
structure Gap where
  left : List UInt8
  free : List UInt8
  right : List UInt8
  deriving Repr, BEq

def Gap.text (g : Gap) := g.left ++ g.right
def Gap.memory (g : Gap) := g.left ++ (g.free ++ g.right)
def Gap.start (g : Gap) := g.left.length
def Gap.finish (g : Gap) := g.left.length + g.free.length
def Gap.capacity (g : Gap) := g.memory.length

-- Make a gap at offset p. New free cells initially contain zero.
def gapAt (text : List UInt8) (p room : Nat) : Gap :=
  ⟨text.take p, List.replicate room 0, text.drop p⟩

-- Creating a gap preserves every byte of the original text.
theorem gapAt_text (text : List UInt8) (p room : Nat) :
    (gapAt text p room).text = text := by
  simp [gapAt, Gap.text]

-- The two gap boundaries are ordered and lie within physical memory.
theorem boundaries_ordered (g : Gap) :
    g.start ≤ g.finish ∧ g.finish ≤ g.capacity := by
  simp only [Gap.start, Gap.finish, Gap.capacity, Gap.memory, List.length_append]
  omega

-- Logical addresses after the gap skip its unused cells, just as C ptr does.
def Gap.address (g : Gap) (p : Nat) : Nat :=
  if p < g.left.length then p else p + g.free.length

-- A valid text address always selects a cell inside physical memory.
theorem address_in_memory (g : Gap) (h : p < g.text.length) :
    g.address p < g.memory.length := by
  simp only [Gap.text, Gap.memory, List.length_append] at *
  unfold Gap.address
  split <;> omega

-- Reading through the physical address gives exactly the logical text byte.
-- The proof checks the regions before and after the gap separately.
theorem physical_read (g : Gap) (p : Nat) :
    g.memory[g.address p]? = g.text[p]? := by
  by_cases h : p < g.left.length
  · simp [Gap.memory, Gap.address, Gap.text, List.getElem?_append, h]
  · have h₁ : ¬p + g.free.length < g.left.length := by omega
    have h₂ : ¬p + g.free.length - g.left.length < g.free.length := by omega
    have h₃ : p + g.free.length - g.left.length - g.free.length = p - g.left.length := by omega
    simp [Gap.memory, Gap.address, Gap.text, List.getElem?_append, h, h₁, h₂, h₃]

-- Copy the last left byte across the gap. Its old cell becomes unused.
def moveLeft (g : Gap) : Gap :=
  if h : g.left = [] then g else
    let byte := g.left.getLast h
    ⟨g.left.dropLast, ([byte] ++ g.free).take g.free.length, byte :: g.right⟩

-- Moving left preserves the complete logical text, including at the left edge.
theorem moveLeft_text (g : Gap) : (moveLeft g).text = g.text := by
  unfold moveLeft
  split
  · rfl
  next h =>
    simpa [Gap.text, List.append_assoc] using
      congrArg (fun left => left ++ g.right) (List.dropLast_concat_getLast h)

-- Moving left keeps the number of free cells and the allocation size fixed.
theorem moveLeft_space (g : Gap) :
    (moveLeft g).free.length = g.free.length ∧
    (moveLeft g).capacity = g.capacity := by
  unfold moveLeft
  split
  · exact ⟨rfl, rfl⟩
  next h =>
    simp [Gap.capacity, Gap.memory, List.length_dropLast]
    have := List.length_pos_iff.mpr h
    omega

-- Copy the first right byte across the gap. Its old cell becomes unused.
def moveRight (g : Gap) : Gap :=
  match g.right with
  | [] => g
  | byte :: rest =>
      ⟨g.left ++ [byte], (g.free.drop 1 ++ [byte]).take g.free.length, rest⟩

-- Moving right also preserves the text, including at the right edge.
theorem moveRight_text (g : Gap) : (moveRight g).text = g.text := by
  cases h : g.right <;> simp [moveRight, h, Gap.text, List.append_assoc]

-- Moving right also reuses the same free cells and the same allocation.
theorem moveRight_space (g : Gap) :
    (moveRight g).free.length = g.free.length ∧
    (moveRight g).capacity = g.capacity := by
  cases h : g.right
  · simp [moveRight, h]
  · simp [moveRight, h, Gap.capacity, Gap.memory]
    omega

-- Insertion consumes one free cell. A full gap returns none.
def insertByte (g : Gap) (byte : UInt8) : Option Gap :=
  match g.free with
  | [] => none
  | _ :: rest => some ⟨g.left ++ [byte], rest, g.right⟩

-- Successful insertion adds exactly one byte between the old text segments.
theorem insertByte_text (g : Gap) (h : insertByte g byte = some result) :
    result.text = g.left ++ [byte] ++ g.right := by
  cases hf : g.free
  · simp [insertByte, hf] at h
  · simp only [insertByte, hf, Option.some.injEq] at h
    rw [← h]
    rfl

-- Insertion consumes exactly one free cell without changing allocation size.
theorem insertByte_space (g : Gap) (h : insertByte g byte = some result) :
    result.free.length + 1 = g.free.length ∧ result.capacity = g.capacity := by
  cases hf : g.free
  · simp [insertByte, hf] at h
  · simp only [insertByte, hf, Option.some.injEq] at h
    rw [← h]
    simp [hf, Gap.capacity, Gap.memory, Nat.add_assoc, Nat.add_left_comm]

-- Delete the byte after the gap. Its cell joins the unused region.
-- At the right edge, there is no byte to delete.
def deleteRight (g : Gap) : Gap :=
  ⟨g.left, g.free ++ g.right.take 1, g.right.drop 1⟩

-- Deletion removes only the first right-hand byte and keeps the allocation size.
theorem deleteRight_correct (g : Gap) :
    (deleteRight g).text = g.left ++ g.right.drop 1 ∧
    (deleteRight g).capacity = g.capacity := by
  cases h : g.right <;> simp [deleteRight, Gap.text, Gap.capacity, Gap.memory, h]

-- Grow the unused region. The two text segments stay in order.
def grow (g : Gap) (extra : Nat) : Gap :=
  { g with free := g.free ++ List.replicate extra 0 }

-- Growth preserves text and adds exactly the requested number of cells.
theorem grow_correct (g : Gap) (extra : Nat) :
    (grow g extra).text = g.text ∧
    (grow g extra).capacity = g.capacity + extra := by
  simp [grow, Gap.text, Gap.capacity, Gap.memory, Nat.add_comm, Nat.add_left_comm]

-- A scene keeps the cursor separate from the gap being demonstrated.
structure Scene where
  gap : Gap
  cursor : Nat
  deriving Repr, BEq

-- Move the gap without moving the cursor.
def moveGap (s : Scene) (move : Gap → Gap) : Scene :=
  { s with gap := move s.gap }

-- Changing the gap does not silently move the buffer cursor.
theorem gap_cursor_separate (s : Scene) (move : Gap → Gap) :
    (moveGap s move).cursor = s.cursor := by
  rfl

-- Printable cells use their character. A space is shown as [_].
def cell (b : UInt8) : String :=
  if b == 32 then "[_]"
  else if 33 ≤ b.toNat && b.toNat ≤ 126 then s!"[{Char.ofNat b.toNat}]"
  else s!"[{b.toNat}]"

-- Show unused cells as [.], even when they hold stale bytes.
def physical (g : Gap) : String :=
  String.join (g.left.map cell) ++ String.join (g.free.map (fun _ => "[.]")) ++
    String.join (g.right.map cell)

-- Place a visible | at the logical cursor, independently of the gap.
def logical (s : Scene) : String :=
  let bytes := s.gap.text
  let render : List UInt8 → String := fun xs => String.join (xs.map (fun b => String.singleton (Char.ofNat b.toNat)))
  render (bytes.take s.cursor) ++ "|" ++ render (bytes.drop s.cursor)

-- Print one visual frame. Check the expected text, gap and cursor before printing.
def frame (name : String) (s : Scene) (text : String) (gap cursor : Nat) : IO Unit := do
  unless s.gap.text == text.toUTF8.toList && s.gap.start == gap && s.cursor == cursor do
    throw (IO.userError s!"Unexpected state in frame: {name}")
  IO.println s!"(frame (action {reprStr name})"
  IO.println s!"  (physical {reprStr (physical s.gap)})"
  IO.println s!"  (logical  {reprStr (logical s)})"
  let unused := String.intercalate " " (s.gap.free.map (fun b => toString b.toNat))
  IO.println s!"  (unused-bytes ({unused}))"
  IO.println s!"  (cursor {s.cursor}) (gap-start {s.gap.start}) (gap-end {s.gap.finish})"
  IO.println s!"  (free {s.gap.free.length}) (capacity {s.gap.capacity}))"

-- Insert at the cursor once the gap has reached it; advance the cursor by one.
def typeByte (s : Scene) (byte : UInt8) : IO Scene := do
  unless s.cursor == s.gap.start do throw (IO.userError "Move the gap to the cursor first")
  let some gap := insertByte s.gap byte | throw (IO.userError "Grow the gap first")
  return ⟨gap, s.cursor + 1⟩

end Gap02

-- The simulation uses the same gap operations checked by the proofs above.
def main : IO Unit := do
  IO.println "(gap-demonstration (legend \"[.] unused; [_] space; | cursor\"))"
  -- The cursor starts inside Hello. The gap starts after Hello.
  let mut s : Gap02.Scene := ⟨Gap02.gapAt "Hello world".toUTF8.toList 5 2, 3⟩
  Gap02.frame "start: cursor and gap differ" s "Hello world" 5 3
  -- Copy o across the gap. Text and cursor stay put.
  s := Gap02.moveGap s Gap02.moveLeft
  Gap02.frame "move gap left: copy o" s "Hello world" 4 3
  -- Copy the second l. The gap now reaches the cursor.
  s := Gap02.moveGap s Gap02.moveLeft
  Gap02.frame "move gap left: copy l" s "Hello world" 3 3
  -- Inserting X consumes one free cell and advances the cursor.
  s ← Gap02.typeByte s 88
  Gap02.frame "insert X" s "HelXlo world" 4 4
  -- Inserting Y consumes the last free cell.
  s ← Gap02.typeByte s 89
  Gap02.frame "insert Y: gap is full" s "HelXYlo world" 5 5
  -- A full gap refuses another byte. Grow it, then insert safely.
  unless (Gap02.insertByte s.gap 90).isNone do throw (IO.userError "Full gap accepted a byte")
  s := Gap02.moveGap s (fun gap => Gap02.grow gap 3)
  Gap02.frame "grow by three cells" s "HelXYlo world" 5 5
  s ← Gap02.typeByte s 90
  Gap02.frame "insert Z after growth" s "HelXYZlo world" 6 6
  -- Delete the l immediately after the gap. Its cell becomes unused.
  s := Gap02.moveGap s Gap02.deleteRight
  Gap02.frame "delete next byte: l" s "HelXYZo world" 6 6
  -- Copy o leftward across the gap. The cursor stays at byte 6.
  s := Gap02.moveGap s Gap02.moveRight
  Gap02.frame "move gap right: copy o" s "HelXYZo world" 7 6
  IO.println "(result pass)"
