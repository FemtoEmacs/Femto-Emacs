import Std

/-!
01: a small read-only window.

In native Chezweb, open this file and save it. Press M-!, write
  lean --run 01-rdonly.lean
then press C-c s. The output appears in *output*.
Lean checks the proofs, then interprets main. No C executable is built.

Positions count bytes from zero. Newline is byte 10. This first model moves
between logical lines. Word wrapping and Unicode display widths come next.
The window has a height; its horizontal view is unrestricted at this stage.
The examples use ASCII: one byte is one displayed column.
-/
namespace ReadOnly01

-- The gap is unused space between the left and right text segments.
structure Gap where
  left : List UInt8
  room : Nat
  right : List UInt8
  deriving Repr, BEq

def Gap.text (g : Gap) : List UInt8 := g.left ++ g.right

-- Build the same text with its gap at a chosen byte offset.
def gapAt (text : List UInt8) (offset room : Nat) : Gap :=
  ⟨text.take offset, room, text.drop offset⟩

-- Moving the gap changes storage layout, not the logical text.
theorem gap_keeps_text (text : List UInt8) (offset room : Nat) :
    (gapAt text offset room).text = text := by
  simp [gapAt, Gap.text]

-- A buffer owns its gap, byte cursor and modified flag.
structure Buffer where
  gap : Gap
  point : Nat
  modified : Bool
  deriving Repr, BEq

-- The window saves its own byte position and its displayed row and column.
-- top counts logical lines from zero. height counts visible text rows.
structure Window where
  point : Nat
  top : Nat
  height : Nat
  row : Nat
  column : Nat
  deriving Repr, BEq

-- Aux holds selection, environment and display state without expanding them.
structure State (Aux : Type) where
  buffer : Buffer
  window : Window
  auxiliary : Aux

-- Count bytes from p to the next newline or EOF.
def remaining (text : List UInt8) (p : Nat) : Nat :=
  ((text.drop p).takeWhile (· != 10)).length

-- Find the current byte column and logical line number.
def columnAt (text : List UInt8) (p : Nat) : Nat :=
  ((text.take p).reverse.takeWhile (· != 10)).length

def lineAt (text : List UInt8) (p : Nat) : Nat :=
  ((text.take p).filter (· == 10)).length

-- Find the following line, then clamp the old column to its content length.
def nextStart (text : List UInt8) (p : Nat) : Nat :=
  min text.length (p + remaining text p + 1)

def destination (text : List UInt8) (p : Nat) : Nat :=
  let start := nextStart text p
  min text.length (start + min (columnAt text p) (remaining text start))

-- Complete one Enter: move, scroll if needed, and synchronize both cursors.
def enter (s : State Aux) : State Aux :=
  let text := s.buffer.gap.text
  let point := destination text s.buffer.point
  let line := lineAt text point
  let top := min line (max s.window.top (line + 1 - s.window.height))
  { s with
    buffer := { s.buffer with point := point }
    window := { s.window with point := point, top := top,
                              row := line - top, column := columnAt text point } }

-- Enter always leaves the buffer cursor between byte zero and EOF.
theorem enter_in_buffer (s : State Aux) :
    (enter s).buffer.point ≤ s.buffer.gap.text.length := by
  exact Nat.min_le_left _ _

-- Before EOF, Enter moves strictly forward. It cannot get stuck.
theorem enter_progress (s : State Aux)
    (h : s.buffer.point < s.buffer.gap.text.length) :
    s.buffer.point < (enter s).buffer.point := by
  simp only [enter, destination, nextStart]
  omega

-- At EOF, another Enter leaves the byte position at EOF.
theorem enter_stays_at_eof (s : State Aux)
    (h : s.buffer.point = s.buffer.gap.text.length) :
    (enter s).buffer.point = s.buffer.point := by
  simp only [enter, destination, nextStart]
  omega

-- Enter preserves the gap, text, modified flag and opaque auxiliary state.
theorem enter_preserves (s : State Aux) :
    (enter s).buffer.gap = s.buffer.gap ∧
    (enter s).buffer.gap.text = s.buffer.gap.text ∧
    (enter s).buffer.modified = s.buffer.modified ∧
    (enter s).auxiliary = s.auxiliary := by
  exact ⟨rfl, rfl, rfl, rfl⟩

-- After the step, the window and buffer save the same byte position.
theorem cursors_agree (s : State Aux) :
    (enter s).window.point = (enter s).buffer.point := by
  rfl

-- A window with at least one text row shows the resulting cursor inside it.
theorem cursor_visible (s : State Aux) (h : 0 < s.window.height) :
    (enter s).window.row < s.window.height := by
  simp only [enter]
  omega

-- Repeat Enter a finite number of times.
def presses : Nat → State Aux → State Aux
  | 0, s => s
  | n + 1, s => enter (presses n s)

-- Any number of Enter presses preserves the original buffer storage and text.
theorem repetition_preserves (n : Nat) (s : State Aux) :
    (presses n s).buffer.gap = s.buffer.gap := by
  induction n with
  | zero => rfl
  | succ n ih => exact ih

-- Prepare a simulation. Each example uses printable ASCII and LF newlines.
def exampleState (text : String) (point gap : Nat) : State Unit :=
  let bytes := text.toUTF8.toList
  { buffer := ⟨gapAt bytes gap 8, point, false⟩
    window := ⟨point, 0, 2, lineAt bytes point, columnAt bytes point⟩
    auxiliary := () }

-- Print a short S-expression for each step and compare its expected position.
def simulate (name : String) (s : State Unit) (expected : List Nat) : IO Unit := do
  IO.println s!"(simulation (name \"{name}\")"
  let mut current := s
  for (point, step) in expected.zipIdx do
    unless current.buffer.point == point do
      throw (IO.userError s!"{name}: step {step}, expected {point}, got {current.buffer.point}")
    IO.println s!"  (step {step} (buffer-cursor {current.buffer.point}) (window-cursor {current.window.point})"
    IO.println s!"    (row {current.window.row}) (column {current.window.column}) (top-line {current.window.top}))"
    current := enter current
  IO.println "  (result pass))"

end ReadOnly01

-- Run the three small simulations after Lean has checked the theorems.
def main : IO Unit := do
  -- Start at column 3. Clamp to the short next line, then scroll to final EOF.
  ReadOnly01.simulate "short-next-line"
    (ReadOnly01.exampleState "abcd\nx\n" 3 4) [3, 6, 7, 7]
  -- With no final newline, the short last line ends at byte 5. Stay there.
  ReadOnly01.simulate "no-final-newline"
    (ReadOnly01.exampleState "abc\nz" 2 1) [2, 5, 5]
  -- An empty buffer is already at EOF. Repeated Enter leaves it there.
  ReadOnly01.simulate "empty-buffer"
    (ReadOnly01.exampleState "" 0 0) [0, 0, 0]
