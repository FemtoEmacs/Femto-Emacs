import Std

/-!
Open this buffer in native Chezweb and invoke M-x chez-tester.
Choose one text file or a directory of Markdown files. Directory scans are
sorted, nonrecursive, and limited to 64 files. Original files are read only.

Each cycle: random move, C-SPC and up to 200 counted Unicode scalar values, M-w,
random move, C-y, Control-slash (the C-_ terminal code), M-<. The temporary paste
must disappear exactly. Histories are measured, never cleared between cycles.
-/
namespace Settings
-- Reproducible pseudo-random experiment: change the seed to explore new moves.
def seed : Nat := 20261105
-- Cycles per Markdown file. A run is limited to one million cycles in total.
def repetitions : Nat := 1000
-- Pause after each visible stage. Zero runs at full speed.
def delayMilliseconds : Nat := 2
-- Per-file and combined snapshot budgets. Both can be lowered.
def maxFileBytes : Nat := 1024 * 1024
def maxTotalBytes : Nat := 8 * 1024 * 1024
end Settings

namespace EditStress

-- The generator is deterministic; there is no claim of cryptographic randomness.
def nextRandom (s : Nat) : Nat := (1664525 * s + 1013904223) % 4294967296

-- Random logical line, then a character column within that line. The outer
-- clamp also makes malformed line metadata harmless to the mathematical move.
def randomMove (fileSize lineStart lineLength random : Nat) : Nat :=
  min fileSize (lineStart + random % (lineLength + 1))

theorem movement_in_file : randomMove n start len random ≤ n := Nat.min_le_left _ _

-- Positions in the editor count UTF-8 bytes; selections count Unicode scalars.
-- Tail-recursive at runtime: List.sum's foldr can exhaust Lean's interpreter
-- stack on real documents. The accumulator law below is proved explicitly.
def byteLength (s : List Char) : Nat := s.foldl (fun n c => n + c.utf8Size) 0

theorem byteFold_acc (s : List Char) (n : Nat) :
    s.foldl (fun n c => n + c.utf8Size) n = n + byteLength s := by
  induction s generalizing n with
  | nil => simp [byteLength]
  | cons c cs ih =>
    change cs.foldl (fun n c => n + c.utf8Size) (n + c.utf8Size) =
      n + cs.foldl (fun n c => n + c.utf8Size) (0 + c.utf8Size)
    rw [ih (n + c.utf8Size), ih (0 + c.utf8Size)]
    omega

theorem byteLength_cons (c : Char) (s : List Char) :
    byteLength (c :: s) = c.utf8Size + byteLength s := by
  simp only [byteLength, List.foldl_cons, Nat.zero_add]
  exact byteFold_acc s c.utf8Size
def bytePosition (s : List Char) (i : Nat) : Nat := byteLength (s.take i)

theorem byteLength_append (a b : List Char) :
    byteLength (a ++ b) = byteLength a + byteLength b := by
  simp only [byteLength, List.foldl_append]
  exact byteFold_acc b (byteLength a)

theorem byte_position_in_file : bytePosition s i ≤ byteLength s := by
  have h := byteLength_append (s.take i) (s.drop i)
  rw [List.take_append_drop] at h
  unfold bytePosition
  omega

def selectionStart (n move : Nat) : Nat := if move < n then move else 0
theorem selection_start_in_file : selectionStart n move ≤ n := by
  unfold selectionStart
  split <;> omega

def selectionLength (n start random : Nat) : Nat :=
  if start < n then 1 + random % min 200 (n - start) else 0

theorem selection_bound (hs : start ≤ n) :
    selectionLength n start random ≤ 200 ∧ start + selectionLength n start random ≤ n := by
  unfold selectionLength
  split
  next hn =>
    have hp : 0 < min 200 (n - start) := by omega
    have hr := Nat.mod_lt random hp
    have h1 := Nat.min_le_left 200 (n - start)
    have h2 := Nat.min_le_right 200 (n - start)
    omega
  next => omega

-- Undo removes exactly the inserted span. This is a proof about the model;
-- the C driver's real paste/undo behavior is checked against this byte-for-byte.
def pasted (front selection suffix : List α) : List α := front ++ selection ++ suffix
def undoInserted (front selection suffix : List α) : List α :=
  (pasted front selection suffix).take front.length ++
  (pasted front selection suffix).drop (front.length + selection.length)

theorem paste_undo_identity (front selection suffix : List α) :
    undoInserted front selection suffix = front ++ suffix := by
  simp [undoInserted, pasted, List.drop_append, List.append_assoc]

def cycleModel (text selection : List α) (destination : Nat) : List α :=
  undoInserted (text.take destination) selection (text.drop destination)

theorem cycle_preserves_text : cycleModel text selection destination = text := by
  rw [cycleModel, paste_undo_identity, List.take_append_drop]

def repeatedModel (selection : List α) (destination : Nat) : Nat → List α → List α
  | 0, text => text
  | n+1, text => repeatedModel selection destination n (cycleModel text selection destination)

theorem thousands_preserve_text (n : Nat) : repeatedModel selection destination n text = text := by
  induction n with
  | zero => rfl
  | succ n ih => simpa [repeatedModel, cycle_preserves_text] using ih

-- The actual pseudo-random experiment uses a different move/selection each
-- cycle. Round-trip preservation holds for every finite schedule, not just
-- one repeated example or one particular seed.
def scheduleModel (operations : List (Nat × List α)) (text : List α) : List α :=
  operations.foldl (fun t op => cycleModel t op.2 op.1) text

theorem any_schedule_preserves (operations : List (Nat × List α)) :
    scheduleModel operations text = text := by
  induction operations generalizing text with
  | nil => rfl
  | cons op rest ih => simpa [scheduleModel, cycle_preserves_text] using ih (text := text)

theorem utf8_bytes_bounded (s : List Char) : byteLength s ≤ 4 * s.length := by
  induction s with
  | nil => simp [byteLength]
  | cons c cs ih =>
    have h := Char.utf8Size_le_four c
    rw [byteLength_cons]
    simp only [List.length_cons]
    omega

theorem small_region_bytes (h : s.length ≤ 200) : byteLength s ≤ 800 := by
  have hb := utf8_bytes_bounded s
  omega

-- Native observations report independent comparisons, never just a checksum.
structure Observation where
  cycle : Nat
  start : Nat
  finish : Nat
  destination : Nat
  copied : Nat
  pasted : Nat
  restored : Nat
  home : Nat
  ringCount : Nat
  ringBytes : Nat
  done : Nat
  undone : Nat
  accounted : Nat
  actual : Nat
  changes : Nat
  histories : Nat
  error : Nat
  deriving Repr

def Acceptable (baseHistories payloadBytes : Nat) (o : Observation) : Prop :=
  o.copied = 1 ∧ o.pasted = 1 ∧ o.restored = 1 ∧ o.home = 0 ∧ o.error = 0 ∧
  o.ringCount ≤ 60 ∧ o.ringBytes ≤ 48000 ∧
  (payloadBytes > 0 → o.ringCount > 0) ∧
  o.done = 0 ∧ o.undone = (if payloadBytes = 0 then 0 else 1) ∧
  o.accounted = o.actual ∧ o.actual = payloadBytes ∧ o.changes ≤ 1 ∧
  o.histories = baseHistories + (if payloadBytes = 0 then 0 else 1)
instance : Decidable (Acceptable h b o) := inferInstanceAs (Decidable (_ ∧ _))
def checkObservation (base bytes : Nat) (o : Observation) : Bool := decide (Acceptable base bytes o)

theorem checker_sound (h : checkObservation base bytes o = true) : Acceptable base bytes o :=
  of_decide_eq_true h

theorem accepted_restores (h : checkObservation base bytes o = true) : o.restored = 1 ∧ o.home = 0 :=
  ⟨(checker_sound h).2.2.1, (checker_sound h).2.2.2.1⟩

-- IO/driver boundary: source evaluation, file discovery/UTF-8 conversion,
-- key injection and byte/history observations remain trusted, as in rdonly.
def reply (out : IO.FS.Stream) (s : String) : IO Unit := out.putStrLn s *> out.flush

def boundedLine (input : IO.FS.Stream) : IO String := do
  let rec loop : Nat → ByteArray → IO String
    | 0, _ => throw (IO.userError "protocol line exceeds 128 bytes")
    | n+1, bytes => do
      let b ← input.read 1
      if b.isEmpty then throw (IO.userError "incomplete experiment")
      if b[0]! == 10 then
        let some text := String.fromUTF8? bytes | throw (IO.userError "bad UTF-8 protocol")
        return text
      loop n (bytes.push b[0]!)
  loop 128 ByteArray.empty

def numbers (s : String) : Option (List Nat) := s.splitOn " " |>.mapM String.toNat?
def observe (s : String) : Option Observation := do
  let ["R", c, a, b, d, co, pa, re, home, rc, rb, done, undone, acc, actual, changes, histories, err] := s.splitOn " " | none
  let [c,a,b,d,co,pa,re,home,rc,rb,done,undone,acc,actual,changes,histories,err] ←
    numbers (String.intercalate " " [c,a,b,d,co,pa,re,home,rc,rb,done,undone,acc,actual,changes,histories,err]) | none
  return ⟨c,a,b,d,co,pa,re,home,rc,rb,done,undone,acc,actual,changes,histories,err⟩

partial def readBytes (h : IO.FS.Handle) (acc : ByteArray) : IO ByteArray := do
  let more ← h.read ((min 65536 (Settings.maxFileBytes + 1 - acc.size)).toUSize)
  if more.isEmpty then return acc
  let result := acc ++ more
  unless result.size ≤ Settings.maxFileBytes do throw (IO.userError "file exceeds maxFileBytes")
  readBytes h result

structure File where
  text : String
  chars : List Char
  lineStarts : Array Nat
  lineLengths : Array Nat
  deriving Inhabited

def prepare (text : String) : File := Id.run do
  let mut starts := #[]
  let mut lengths := #[]
  let mut index := 0
  for line in text.splitOn "\n" do
    starts := starts.push index
    lengths := lengths.push line.length
    index := index + line.length + 1
  return ⟨text, text.toList, starts, lengths⟩

def choose (f : File) (random : Nat) : Nat :=
  let row := random % f.lineStarts.size
  randomMove f.chars.length f.lineStarts[row]! f.lineLengths[row]! (nextRandom random)

partial def fileCycles (f : File) (base offset : Nat) (input out : IO.FS.Stream)
    (cycle random : Nat) : IO Nat := do
  if cycle = Settings.repetitions then return random
  let r1 := nextRandom random
  let start := selectionStart f.chars.length (choose f r1)
  let r2 := nextRandom r1
  let count := selectionLength f.chars.length start r2
  let r3 := nextRandom r2
  let dest := choose f r3
  let a := bytePosition f.chars start
  let b := bytePosition f.chars (start + count)
  let d := bytePosition f.chars dest
  reply out s!"E {cycle} {a} {b} {d}"
  let some o := observe (← boundedLine input) | throw (IO.userError "invalid native observation")
  unless b-a ≤ 800 && o.cycle = cycle && o.start = a && o.finish = b && o.destination = d &&
      checkObservation base (b-a) o do throw (IO.userError "cycle, text restoration or history check failed")
  reply out s!"ACK {offset+cycle+1}"
  fileCycles f base offset input out (cycle+1) r3

partial def files (all : Array File) (directory : System.FilePath) (input out : IO.FS.Stream)
    (idx random : Nat) (baseline : Nat := 0) : IO Nat := do
  if idx = all.size then return baseline
  let f := all[idx]!
  reply out s!"FILE {idx} {f.text.utf8ByteSize}"
  let ["BASE", n] := (← boundedLine input).splitOn " " | throw (IO.userError "missing history baseline")
  let some base := n.toNat? | throw (IO.userError "invalid baseline")
  let next ← fileCycles f base (idx * Settings.repetitions) input out 0 random
  reply out s!"CLOSE {idx}"
  unless (← boundedLine input) == s!"CLEAN {idx} {base}" do
    throw (IO.userError "deleted buffer retained undo history")
  files all directory input out (idx+1) next base

def run (path snapshot : String) : IO UInt32 := do
  unless 1 ≤ Settings.repetitions && Settings.repetitions ≤ 1000000 &&
      Settings.delayMilliseconds ≤ 1000 && 1 ≤ Settings.maxFileBytes &&
      Settings.maxFileBytes ≤ 67108864 && Settings.maxTotalBytes ≤ 67108864 do
    throw (IO.userError "invalid bounded settings")
  let target : System.FilePath := path
  let metadata ← target.metadata
  let mut paths : Array System.FilePath := #[]
  if metadata.type == .dir then
    for entry in (← target.readDir) do
      let name := entry.fileName.toLower
      if name.endsWith ".md" || name.endsWith ".markdown" then
        if (← entry.path.metadata).type == .file then paths := paths.push entry.path
  else paths := #[target]
  paths := paths.qsort (fun a b => a.toString < b.toString)
  unless 0 < paths.size && paths.size ≤ 64 && paths.size * Settings.repetitions ≤ 1000000 do
    throw (IO.userError "choose 1..64 Markdown files, at most one million cycles")
  let directory := (System.FilePath.mk snapshot).parent.getD "."
  let mut loaded : Array File := #[]
  let mut total := 0
  for i in [:paths.size] do
    let bytes ← IO.FS.withFile paths[i]! .read fun h => readBytes h ByteArray.empty
    total := total + bytes.size
    unless total ≤ Settings.maxTotalBytes do throw (IO.userError "snapshot total exceeds maxTotalBytes")
    let some text := String.fromUTF8? bytes | throw (IO.userError "input is not UTF-8")
    unless !text.isEmpty do throw (IO.userError s!"no selectable text in {paths[i]!}")
    IO.FS.writeBinFile (directory / s!"input-{i}.md") bytes
    loaded := loaded.push (prepare text)
  let out ← IO.getStdout
  let input ← IO.getStdin
  reply out s!"PLAN3 {loaded.size} {Settings.repetitions} {Settings.delayMilliseconds} {Settings.seed % 4294967296}"
  unless (← boundedLine input) == "READY" do throw (IO.userError "native driver not ready")
  let base ← files loaded directory input out 0 Settings.seed
  reply out s!"DONE {loaded.size * Settings.repetitions}"
  let ["COMPLETE", a,b,c,d,e,f,g,h] := (← boundedLine input).splitOn " " | throw (IO.userError "native cleanup incomplete")
  let some [rc,rb,done,undone,counted,actual,changes,histories] := numbers (String.intercalate " " [a,b,c,d,e,f,g,h]) | throw (IO.userError "invalid final histories")
  unless rc ≤ 60 && rb ≤ 4194304 && done + undone ≤ 200 && counted = actual &&
      actual ≤ 8388608 && changes ≤ 10000 && histories = base do
    throw (IO.userError "final editor histories exceed their limits")
  reply out s!"PASS {loaded.size * Settings.repetitions}"
  return 0
end EditStress

def main (args : List String) : IO UInt32 := do
  try
    let ["--editor-file", path, snapshot] := args | throw (IO.userError "run from M-x chez-tester")
    EditStress.run path snapshot
  catch e =>
    let out ← IO.getStdout
    let detail := String.ofList ((e.toString.toList.map fun c => if ' ' ≤ c && c ≤ '~' then c else '?').take 80)
    EditStress.reply out ("FAIL " ++ detail)
    return (1 : UInt32)
