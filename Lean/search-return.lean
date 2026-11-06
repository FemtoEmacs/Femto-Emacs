import Std

/-!
Open this buffer in native Chezweb, edit Settings, invoke M-x chez-tester,
and choose a UTF-8 file or a directory of Markdown files. Tests use private
copies. Each visible cycle saves a seeded random origin, searches with C-s
or C-r and Enter, then returns to that origin with M-g, C-a and C-f.

Six cases alternate directions: search from BOF/EOF for a random printable
substring; guaranteed failure from EOF/BOF; and search starting at the
substring's start/end. This avoids conflating failed incremental prefixes
with complete-pattern failure. Empty/nonprintable files use a fixed query.
The reference matcher is independent of the editor. C/OS/IO observations
remain trusted; these theorems do not prove the editor or its GC correct.
-/
namespace Settings
-- Cycles per file; one million cycles maximum across at most 64 files.
def seed : Nat := 20261105
def repetitions : Nat := 1000
-- Milliseconds after each visible stage; set zero for full speed.
def delayMilliseconds : Nat := 2
def maxFileBytes : Nat := 1024 * 1024
def maxTotalBytes : Nat := 8 * 1024 * 1024
end Settings

namespace SearchReturn
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

theorem substring_in_file (s : List Char) (start count : Nat) :
    bytePosition s start ≤ bytePosition s (start + count) ∧
    bytePosition s (start + count) ≤ byteLength s := by
  constructor
  · unfold bytePosition
    rw [List.take_add, byteLength_append]
    omega
  · exact byte_position_in_file

-- At most eight Unicode scalars (32 bytes), below the C search capacity.
def boundedQuery : List Char → List Char
  | [] => "chez-tester".toList
  | c :: cs => c :: cs.take 7

theorem query_nonempty (s : List Char) : boundedQuery s ≠ [] := by
  cases s <;> simp [boundedQuery]

theorem query_bytes_bounded (s : List Char) : byteLength (boundedQuery s) ≤ 32 := by
  cases s with
  | nil => decide
  | cons c cs =>
    have h := utf8_bytes_bounded (c :: cs.take 7)
    have ht := List.length_take_le 7 cs
    simp only [List.length_cons] at h
    change byteLength (c :: cs.take 7) ≤ 32
    omega

-- A reference hit carries the proof that all bytes match within the file.
def Match (text pattern : ByteArray) (i : Nat) : Prop :=
  0 < pattern.size ∧ i + pattern.size ≤ text.size ∧
  (List.range pattern.size).all (fun j => text[i+j]! == pattern[j]!) = true
instance : Decidable (Match text pattern i) := inferInstanceAs (Decidable (_ ∧ _))

def forward (text pattern : ByteArray) : Nat → Nat → Option {i : Nat // Match text pattern i}
  | 0, _ => none
  | fuel+1, i => if h : Match text pattern i then some ⟨i,h⟩ else forward text pattern fuel (i+1)

def backward (text pattern : ByteArray) : Nat → Option {i : Nat // Match text pattern i}
  | 0 => none
  | i+1 => if h : Match text pattern i then some ⟨i,h⟩ else backward text pattern i

def resultPosition (text pattern : ByteArray) (start : Nat) (reverse : Bool)
    (hit : Option {i : Nat // Match text pattern i}) : Nat :=
  match hit with
  | none => start
  | some h => if reverse then h.val else h.val + pattern.size

theorem reference_hit_matches (hit : {i : Nat // Match text pattern i}) :
    hit.val + pattern.size ≤ text.size ∧
    (List.range pattern.size).all (fun j => text[hit.val+j]! == pattern[j]!) = true :=
  hit.property.2

theorem search_position_in_file (hs : start ≤ text.size)
    (hit : Option {i : Nat // Match text pattern i}) :
    resultPosition text pattern start reverse hit ≤ text.size := by
  cases hit with
  | none => exact hs
  | some h =>
    have hb := h.property.2.1
    simp only [resultPosition]
    split <;> omega

-- Search only moves point in this specification. Returning restores all fields.
structure EditorState where
  text : List Char
  point : Nat
  modified : Bool
  killRing : List String
  undo : List String
  redo : List String
  deriving BEq

def cycleModel (s : EditorState) (searchPoint : Nat) : EditorState :=
  { {s with point := searchPoint} with point := s.point }

theorem cycle_identity (s : EditorState) : cycleModel s p = s := by rfl

def scheduleModel (positions : List Nat) (s : EditorState) : EditorState :=
  positions.foldl cycleModel s

theorem any_schedule_preserves (positions : List Nat) (s : EditorState) :
    scheduleModel positions s = s := by
  induction positions generalizing s with
  | nil => rfl
  | cons p ps ih => simpa [scheduleModel, cycle_identity] using ih s

structure Observation where
  cycle : Nat
  point : Nat
  matched : Nat
  textSame : Nat
  dirtySame : Nat
  returned : Nat
  historySame : Nat
  querySame : Nat
  queryBytes : Nat
  error : Nat
  deriving Repr

def Acceptable (cycle position found origin bytes : Nat) (o : Observation) : Prop :=
  o.cycle = cycle ∧ o.point = position ∧ o.matched = found ∧
  o.textSame = 1 ∧ o.dirtySame = 1 ∧ o.returned = origin ∧
  o.historySame = 1 ∧ o.querySame = 1 ∧ o.queryBytes = bytes ∧
  0 < bytes ∧ bytes ≤ 32 ∧ o.error = 0
instance : Decidable (Acceptable c p f o b obs) := inferInstanceAs (Decidable (_ ∧ _))
def checkObservation (c p f o b : Nat) (obs : Observation) : Bool :=
  decide (Acceptable c p f o b obs)

theorem checker_sound (h : checkObservation c p f o b obs = true) :
    Acceptable c p f o b obs := of_decide_eq_true h

theorem accepted_preserves (h : checkObservation c p f o b obs = true) :
    obs.textSame = 1 ∧ obs.dirtySame = 1 ∧ obs.returned = o ∧ obs.historySame = 1 := by
  rcases checker_sound h with ⟨_,_,_,ht,hd,hr,hh,_⟩
  exact ⟨ht,hd,hr,hh⟩

-- One observation is acknowledged before its trace slot can be reused.
-- Managed report slots retain at most 20 KiB, independently of cycle count.
theorem fixed_report_bound : 8192 + 8192 + 4096 ≤ 20480 := by decide

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
  let "R" :: values := s.splitOn " " | none
  let [c,p,f,t,d,r,h,q,b,e] ← values.mapM String.toNat? | none
  return ⟨c,p,f,t,d,r,h,q,b,e⟩

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
  raw : ByteArray
  candidates : Array Nat
  deriving Inhabited

def prepare (text : String) : File := Id.run do
  let mut starts := #[]
  let mut lengths := #[]
  let mut index := 0
  for line in text.splitOn "\n" do
    starts := starts.push index
    lengths := lengths.push line.length
    index := index + line.length + 1
  let mut candidates := #[]
  let chars := text.toList.toArray
  for i in [:chars.size] do
    let c := chars[i]!
    if c.toNat ≥ 32 && c.toNat != 127 then candidates := candidates.push i
  return ⟨text, text.toList, starts, lengths, text.toUTF8, candidates⟩

def choose (f : File) (random : Nat) : Nat :=
  let row := random % f.lineStarts.size
  randomMove f.chars.length f.lineStarts[row]! f.lineLengths[row]! (nextRandom random)

partial def fileCycles (f : File) (base offset : Nat) (input out : IO.FS.Stream)
    (cycle random : Nat) : IO Nat := do
  if cycle = Settings.repetitions then return random
  let r1 := nextRandom random
  let origin := bytePosition f.chars (choose f r1)
  let r2 := nextRandom r1
  let selected := if f.candidates.isEmpty then 0 else
    if cycle % 12 = 0 then f.candidates[0]! else
    if cycle % 12 = 1 then f.candidates[f.candidates.size-1]! else
    f.candidates[r2 % f.candidates.size]!
  let run := if f.candidates.isEmpty then [] else
    ((f.chars.drop selected).takeWhile fun c => c.toNat ≥ 32 && c.toNat != 127).take 8
  let query := String.ofList (boundedQuery run) |>.toUTF8
  let a := if run.isEmpty then 0 else bytePosition f.chars selected
  let b := if run.isEmpty then 0 else bytePosition f.chars (selected + run.length)
  let style := cycle % 6
  let reverse := style % 2 == 1
  let start := if style = 0 || style = 3 then 0 else
    if style = 1 || style = 2 then f.raw.size else if reverse then b else a
  let hit := if reverse then backward f.raw query start else
    forward f.raw query (f.raw.size + 1 - start) start
  let expected := resultPosition f.raw query start reverse hit
  reply out s!"S {cycle} {origin} {start} {if reverse then 1 else 0} {a} {b}"
  let some o := observe (← boundedLine input) | throw (IO.userError "invalid search observation")
  unless checkObservation cycle expected (if hit.isSome then 1 else 0) origin query.size o do
    throw (IO.userError "search match, return, text or history invariant failed")
  reply out s!"ACK {offset+cycle+1}"
  fileCycles f base offset input out (cycle+1) r2

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
    IO.FS.writeBinFile (directory / s!"input-{i}.md") bytes
    loaded := loaded.push (prepare text)
  let out ← IO.getStdout
  let input ← IO.getStdin
  reply out s!"PLAN4 {loaded.size} {Settings.repetitions} {Settings.delayMilliseconds} {Settings.seed % 4294967296}"
  unless (← boundedLine input) == "READY" do throw (IO.userError "native driver not ready")
  let base ← files loaded directory input out 0 Settings.seed
  reply out s!"DONE {loaded.size * Settings.repetitions}"
  unless (← boundedLine input) == "SEARCH-RESTORED 1" do
    throw (IO.userError "previous search state was not restored")
  let ["COMPLETE", a,b,c,d,e,f,g,h] := (← boundedLine input).splitOn " " | throw (IO.userError "native cleanup incomplete")
  let some [rc,rb,done,undone,counted,actual,changes,histories] := numbers (String.intercalate " " [a,b,c,d,e,f,g,h]) | throw (IO.userError "invalid final histories")
  unless rc ≤ 60 && rb ≤ 4194304 && done + undone ≤ 200 && counted = actual &&
      actual ≤ 8388608 && changes ≤ 10000 && histories = base do
    throw (IO.userError "final editor histories exceed their limits")
  reply out s!"PASS {loaded.size * Settings.repetitions}"
  return 0
end SearchReturn

def main (args : List String) : IO UInt32 := do
  try
    let ["--editor-file", path, snapshot] := args | throw (IO.userError "run from M-x chez-tester")
    SearchReturn.run path snapshot
  catch e =>
    let out ← IO.getStdout
    let detail := String.ofList ((e.toString.toList.map fun c => if ' ' ≤ c && c ≤ '~' then c else '?').take 80)
    SearchReturn.reply out ("FAIL " ++ detail)
    return (1 : UInt32)
