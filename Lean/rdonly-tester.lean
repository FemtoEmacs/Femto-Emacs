import Std

/-!
Bounded streaming conformance checker for Chezweb's visible native tester.
The proofs concern the pure specification/protocol, not C, the OS, or IO parsing.
The normal workflow tests the existing text chosen at the filename prompt.
Protocol v1 (numbered rows) is retained only for small regression fixtures.
-/
/-!
EDIT THE SETTINGS BELOW, then invoke M-x chez-tester in this buffer.
The filename prompt chooses the existing text to test.
There is no need to save: Chezweb runs a private snapshot of this buffer.
Lean checks every theorem before the first test step.

READ means read-only navigation. Vim is the editor's copy-only Vim mode.
Each pass starts at the beginning and presses Enter through the whole fixture,
then eight more times to check that the cursor stays at the end of the file.
-/
namespace TestSettings

inductive Mode where
  | readOnly
  | vim
  | alternating
  deriving BEq

-- Choose .readOnly, .vim, or .alternating (Vim first, then READ).
def mode : Mode := .alternating
-- Number of complete traversals of the chosen document (each pass uses its disposable copy).
def passes : Nat := 4
-- Safety limit: a pass must reach EOF and hold there eight times before this.
def maxEnterPressesPerPass : Nat := 10000
-- Input snapshot limit (default 1 MiB). Raise for larger texts, up to 64 MiB.
def maxInputBytes : Nat := 1024 * 1024
-- Pause after each Enter, in milliseconds. Zero runs as fast as possible.
def delayMilliseconds : Nat := 10
-- Optional: keep a complete trace for a tiny file/run (at most 60 observations).
def keepReference : Bool := false

end TestSettings

namespace ChezTester

def batchBytes : Nat := 8192
def failureBytes : Nat := 8192
def summaryBytes : Nat := 4096
def diskLimit : Nat := 20480
def lineLimit : Nat := 128

-- Historical fixed-width profile: independent tiny checker examples only.
structure Config where
  lines : Nat
  passes : Nat
  profile : Nat  -- 1 READ, 2 copy-only Vim, 3 alternating Vim/READ
  batch : Nat
  deriving Repr, BEq

def Config.period (c : Config) : Nat := c.lines + 9

def Config.total (c : Config) : Nat := c.passes * c.period

def Config.valid (c : Config) : Bool := decide
  (1 ≤ c.lines ∧ c.lines ≤ 4096 ∧ 1 ≤ c.passes ∧ c.passes ≤ 1000 ∧
   1 ≤ c.profile ∧ c.profile ≤ 3 ∧ 1 ≤ c.batch ∧ c.batch ≤ 62 ∧ c.total ≤ 1000000)

def expectedMode (c : Config) (seq : Nat) : Nat :=
  if c.profile = 3 then (if seq / c.period % 2 = 0 then 2 else 1) else c.profile

def expectedPosition (c : Config) (seq : Nat) : Nat :=
  min (seq % c.period) c.lines * 16

-- Numbered rows make actual scrolling visible without changing the stride.
def fixtureByte (row col : Nat) : Nat :=
  if col < 5 then
    match col with
    | 0 => 108 | 1 => 105 | 2 => 110 | 3 => 101 | _ => 32
  else if col = 15 then 10
  else 48 + ((row + 1) / 10 ^ (14 - col)) % 10

theorem fixture_newline_only_at_end (hc : col < 16) :
    fixtureByte row col = 10 ↔ col = 15 := by
  unfold fixtureByte
  split
  next hp =>
    have cases : col = 0 ∨ col = 1 ∨ col = 2 ∨ col = 3 ∨ col = 4 := by omega
    rcases cases with h | h | h | h | h <;> subst col <;> simp
  next hp =>
    split
    next he => simp_all
    next he => omega

/- One observation describes what the editor actually did after a reset or Enter.
   Acceptance means: the right step, mode, byte position and line number;
   the entire fixture is unchanged; no Scheme runtime failure was observed. -/
structure Observation where
  seq : Nat
  action : Nat  -- 0 reset/mode entry; 1 Enter
  mode : Nat
  position : Nat
  line : Nat
  intact : Nat  -- exact C fixture comparison, not a hash
  error : Nat  -- Scheme callback failure counter since run start
  deriving Repr, BEq

def Conforms (c : Config) (o : Observation) : Prop :=
  o.action = (if o.seq % c.period = 0 then 0 else 1) ∧
  o.mode = expectedMode c o.seq ∧
  o.position = expectedPosition c o.seq ∧
  o.line = o.position / 16 + 1 ∧ o.intact = 1 ∧ o.error = 0
instance (c : Config) (o : Observation) : Decidable (Conforms c o) := inferInstanceAs
  (Decidable (_ ∧ _ ∧ _ ∧ _ ∧ _ ∧ _))

def checkObservation (c : Config) (next : Nat) (o : Observation) : Bool :=
  decide (o.seq = next ∧ next < c.total ∧ Conforms c o)

theorem observation_sound (h : checkObservation c next o = true) :
    o.seq = next ∧ next < c.total ∧ Conforms c o := by
  exact of_decide_eq_true h

inductive ConformingTrace (c : Config) : Nat → List Observation → Prop
  | nil (start) : ConformingTrace c start []
  | cons : o.seq = start → start < c.total → Conforms c o →
      ConformingTrace c (start + 1) os → ConformingTrace c start (o :: os)

-- Check observations in order. Missing or repeated indices cannot be accepted.
def checkBatch (c : Config) (start : Nat) : List Observation → Bool
  | [] => true
  | o :: os => checkObservation c start o && checkBatch c (start + 1) os

theorem batch_sound (h : checkBatch c start os = true) : ConformingTrace c start os := by
  induction os generalizing start with
  | nil => exact .nil start
  | cons o os ih =>
    simp only [checkBatch, Bool.and_eq_true] at h
    obtain ⟨hs, hb, hc⟩ := observation_sound h.1
    exact .cons hs hb hc (ih h.2)

theorem batch_append (xs ys : List Observation) :
    checkBatch c start (xs ++ ys) =
      (checkBatch c start xs && checkBatch c (start + xs.length) ys) := by
  induction xs generalizing start with
  | nil => simp [checkBatch]
  | cons x xs ih => simp [checkBatch, ih, Nat.add_comm, Nat.add_left_comm,
                         Bool.and_assoc]

-- A mathematical complete-run checker. Runtime streaming uses the same
-- observation checker and batch_append to discard accepted prefixes safely.
def planIndices (start : Nat) : Nat → List Nat
  | 0 => []
  | n + 1 => start :: planIndices (start + 1) n

theorem conforming_indices (h : ConformingTrace c start os) :
    os.map Observation.seq = planIndices start os.length := by
  induction h with
  | nil => rfl
  | cons hs _ _ _ ih => simp [planIndices, hs, ih]

def checkComplete (c : Config) (os : List Observation) : Bool :=
  checkBatch c 0 os && decide (os.length = c.total)

theorem complete_sound (h : checkComplete c os = true) :
    ConformingTrace c 0 os ∧ os.length = c.total ∧
    os.map Observation.seq = planIndices 0 c.total := by
  simp only [checkComplete, Bool.and_eq_true] at h
  have hn : os.length = c.total := of_decide_eq_true h.2
  have ht := batch_sound h.1
  exact ⟨ht, hn, hn ▸ conforming_indices ht⟩

structure State where
  next : Nat := 0
  verified : Nat := 0
  pending : Nat := 0
  deriving Repr, BEq

def State.valid (c : Config) (s : State) : Prop :=
  s.next = s.verified + s.pending ∧ s.next ≤ c.total ∧ s.pending ≤ c.batch

theorem initial_valid (c : Config) : ({} : State).valid c := by
  simp [State.valid]

def feed (c : Config) (s : State) (o : Observation) : Option State :=
  if checkObservation c s.next o && decide (s.pending < c.batch) then
    some { s with next := s.next + 1, pending := s.pending + 1 }
  else none

def acknowledge (s : State) (n : Nat) : Option State :=
  if n = s.next ∧ 0 < s.pending then
    some { next := s.next, verified := s.next, pending := 0 }
  else none

def finished (c : Config) (s : State) (n : Nat) : Bool :=
  decide (n = c.total ∧ s.next = c.total ∧ s.verified = c.total ∧ s.pending = 0)

theorem feed_sound (h : feed c s o = some t) :
    Conforms c o ∧ o.seq = s.next ∧ t.next = s.next + 1 := by
  unfold feed at h
  split at h
  next hc =>
    simp only [Bool.and_eq_true] at hc
    obtain ⟨hs, _, hp⟩ := observation_sound hc.1
    cases h
    exact ⟨hp, hs, rfl⟩
  next => cases h

theorem feed_preserves (hv : s.valid c) (h : feed c s o = some t) : t.valid c := by
  unfold feed at h
  split at h
  next hc =>
    simp only [Bool.and_eq_true] at hc
    have hb := (observation_sound hc.1).2.1
    have hp : s.pending < c.batch := of_decide_eq_true hc.2
    cases h
    unfold State.valid at *
    simp only at *
    omega
  next => cases h

theorem acknowledge_preserves (hv : s.valid c) (h : acknowledge s n = some t) :
    t.valid c ∧ t.verified = s.next ∧ t.pending = 0 := by
  unfold acknowledge at h
  split at h
  next =>
    cases h
    exact ⟨⟨by simp, hv.2.1, Nat.zero_le _⟩, rfl, rfl⟩
  next => cases h

theorem complete_not_prefix (h : finished c s n = true) :
    s.next = c.total ∧ s.verified = c.total ∧ s.pending = 0 := by
  have hs := of_decide_eq_true h
  exact ⟨hs.2.1, hs.2.2.1, hs.2.2.2⟩

-- Writer model: a reservation fails rather than exceeding the byte quota.
def reserve (used extra cap : Nat) : Option Nat :=
  if used + extra ≤ cap then some (used + extra) else none

theorem reservation_bound (h : reserve used extra cap = some n) : n ≤ cap := by
  unfold reserve at h
  split at h
  next hb => cases h; exact hb
  next => cases h

theorem fixed_disk_bound (hp : p ≤ batchBytes) (hf : f ≤ failureBytes)
    (hs : s ≤ summaryBytes) : p + f + s ≤ diskLimit := by
  unfold batchBytes failureBytes summaryBytes diskLimit at *
  omega

-- Reuse is allowed only after a matching checker acknowledgment.
def recycle (_pending next ack : Nat) : Option Nat :=
  if ack = next then some 0 else none

theorem recycle_requires_ack (h : recycle p next ack = some n) : ack = next ∧ n = 0 := by
  unfold recycle at h
  split at h
  next he => cases h; exact ⟨he, rfl⟩
  next => cases h

-- A header and at most 62 bounded records fit the pending file.
theorem batch_encoding_bound (hh : header ≤ lineLimit) (hk : checkpoint ≤ lineLimit)
    (hc : count ≤ 62) (hb : bytes ≤ count * lineLimit) :
    header + checkpoint + bytes ≤ batchBytes := by
  unfold batchBytes lineLimit at *
  omega

theorem reference_encoding_bound (hh : header ≤ lineLimit) (hb : batch ≤ lineLimit)
    (he : ending ≤ lineLimit) (hr : records ≤ 60 * lineLimit) :
    header + records + batch + ending ≤ batchBytes := by
  unfold lineLimit batchBytes at *
  omega

/- Existing-file profile. Enter moves by a visual row, so a wrapped logical
   line may require several presses. We check forward progress and logical
   line numbers independently of the editor, not fixed 16-byte positions. -/
structure TextPlan where
  text : ByteArray
  newlines : List Nat
  passes : Nat
  profile : Nat
  maxEnters : Nat
  reference : Bool

def textLine (p : TextPlan) (offset : Nat) : Nat :=
  1 + (p.newlines.takeWhile (fun n => n < offset)).length

def textMode (p : TextPlan) (pass : Nat) : Nat :=
  if p.profile = 3 then (if pass % 2 = 0 then 2 else 1) else p.profile

structure TextState where
  count : State := {}
  pass : Nat := 0
  step : Nat := 0
  position : Nat := 0
  eofHolds : Nat := 0

def TextConforms (p : TextPlan) (s : TextState) (o : Observation) : Prop :=
  o.seq = s.count.next ∧ s.pass < p.passes ∧ s.step ≤ p.maxEnters ∧
  o.mode = textMode p s.pass ∧ o.intact = 1 ∧ o.error = 0 ∧
  o.position ≤ p.text.size ∧ o.line = textLine p o.position ∧
  (if s.step = 0 then o.action = 0 ∧ o.position = 0
   else o.action = 1 ∧ o.line ≤ textLine p s.position + 1 ∧
     (if s.position < p.text.size then s.position < o.position
      else o.position = p.text.size))

instance (p : TextPlan) (s : TextState) (o : Observation) :
    Decidable (TextConforms p s o) := inferInstanceAs (Decidable (_ ∧ _))

def feedText (p : TextPlan) (s : TextState) (o : Observation) : Option TextState :=
  if decide (TextConforms p s o) && decide (s.count.pending < 62) &&
      (!p.reference || decide (s.count.next < 60)) then
    let holds := if s.step > 0 && s.position = p.text.size then s.eofHolds + 1 else 0
    let advance := holds = 8
    some { count := { s.count with next := s.count.next + 1, pending := s.count.pending + 1 },
           pass := if advance then s.pass + 1 else s.pass,
           step := if advance then 0 else s.step + 1,
           position := if advance then 0 else o.position,
           eofHolds := if advance then 0 else holds }
  else none

theorem text_step_sound (h : feedText p s o = some t) : TextConforms p s o := by
  unfold feedText at h
  split at h
  next hc =>
    simp only [Bool.and_eq_true] at hc
    exact of_decide_eq_true hc.1.1
  next => cases h

theorem text_line_sound (h : feedText p s o = some t) :
    o.position ≤ p.text.size ∧ o.line = textLine p o.position := by
  have hc := text_step_sound h
  exact ⟨hc.2.2.2.2.2.2.1, hc.2.2.2.2.2.2.2.1⟩

theorem text_progress (h : feedText p s o = some t) (hs : s.step ≠ 0)
    (hp : s.position < p.text.size) : s.position < o.position := by
  have hc := (text_step_sound h).2.2.2.2.2.2.2.2
  simp only [if_neg hs, if_pos hp] at hc
  exact hc.2.2

theorem text_feed_pending_bound (h : feedText p s o = some t) :
    t.count.pending ≤ 62 ∧ t.count.next = s.count.next + 1 := by
  unfold feedText at h
  split at h
  next hc =>
    simp only [Bool.and_eq_true] at hc
    have hp : s.count.pending < 62 := of_decide_eq_true hc.1.2
    cases h
    dsimp
    constructor
    · omega
    · rfl
  next => cases h

theorem text_pass_requires_eof (h : feedText p s o = some t)
    (ha : s.pass < t.pass) :
    s.position = p.text.size ∧ o.position = p.text.size ∧ s.eofHolds + 1 = 8 := by
  have conform := text_step_sound h
  unfold feedText at h
  split at h
  next hc =>
    cases h
    dsimp only at ha
    split at ha
    next holds =>
      simp only [Bool.and_eq_true, decide_eq_true_eq] at holds
      have hs := holds
      have he : s.eofHolds + 1 = 8 := by
        split at ha
        next he => exact he
        next => omega
      have lineCheck := conform.2.2.2.2.2.2.2.2
      have notZero : s.step ≠ 0 := by omega
      have notBefore : ¬s.position < p.text.size := by omega
      simp only [if_neg notZero, if_neg notBefore] at lineCheck
      refine ⟨hs.2, lineCheck.2.2, ?_⟩
      exact he
    next => simp at ha
  next => cases h

def textFinished (p : TextPlan) (s : TextState) (n : Nat) : Bool :=
  decide (s.pass = p.passes ∧ s.step = 0 ∧ s.count.next = n ∧
          s.count.verified = n ∧ s.count.pending = 0)

theorem text_complete_not_prefix (h : textFinished p s n = true) :
    s.pass = p.passes ∧ s.step = 0 ∧ s.count.next = n ∧
    s.count.verified = n ∧ s.count.pending = 0 := of_decide_eq_true h

-- IO preparation computes this once. The file read is bounded separately.
def textNewlines (bytes : ByteArray) : List Nat := Id.run do
  let mut offsets : Array Nat := #[]
  for i in [:bytes.size] do
    if bytes[i]! == 10 then offsets := offsets.push i
  return offsets.toList

end ChezTester

namespace ChezTester

/- Execution boundary: the definitions below read bounded protocol lines and
   call the proved checker. These IO operations and the C observer are trusted;
   the pure proofs above do not verify the editor or operating system. -/
-- Bounded IO adapter. It never uses unbounded getLine/readToEnd.
def readBounded (input : IO.FS.Stream) : IO (Option String) := do
  let rec go : Nat → ByteArray → IO (Option String)
    | 0, _ => throw (IO.userError "input line exceeds 128 bytes")
    | fuel + 1, bytes => do
      let b ← input.read 1
      if b.isEmpty then
        if bytes.isEmpty then return none
        else throw (IO.userError "unterminated input line")
      let v := b[0]!
      if v == 10 then
        match String.fromUTF8? bytes with
        | some s => return some s
        | none => throw (IO.userError "invalid UTF-8")
      go fuel (bytes.push v)
  go 128 ByteArray.empty

def words (s : String) : List String := s.splitOn " "
def nat (s : String) : Option Nat :=
  if s.isEmpty || !(s.toList.all fun c => '0' ≤ c && c ≤ '9') then none else s.toNat?

def parseConfig (s : String) : Option Config := do
  let ["H", "1", l, p, m, b] := words s | none
  let c : Config := ⟨← nat l, ← nat p, ← nat m, ← nat b⟩
  if c.valid then some c else none

def parseObservation (s : String) : Option Observation := do
  let ["S", n, a, m, p, l, i, e] := words s | none
  return ⟨← nat n, ← nat a, ← nat m, ← nat p, ← nat l, ← nat i, ← nat e⟩

def reply (out : IO.FS.Stream) (s : String) : IO Unit := do
  out.putStrLn s
  out.flush

partial def serve (c : Config) (s : State) (input out : IO.FS.Stream) : IO UInt32 := do
  let some line ← readBounded input | throw (IO.userError "incomplete run: no end marker")
  if line.startsWith "S " then
    let some o := parseObservation line | throw (IO.userError "invalid observation")
    let some t := feed c s o | throw (IO.userError "observation or batch rejected")
    serve c t input out
  else if line.startsWith "B " then
    let ["B", value] := words line | throw (IO.userError "invalid batch marker")
    let some n := nat value | throw (IO.userError "invalid batch count")
    let some t := acknowledge s n | throw (IO.userError "acknowledgment rejected")
    reply out s!"ACK {n}"
    serve c t input out
  else if line.startsWith "Z " then
    let ["Z", value] := words line | throw (IO.userError "invalid end marker")
    let some n := nat value | throw (IO.userError "invalid end count")
    if finished c s n then
      unless (← input.read 1).isEmpty do throw (IO.userError "trailing input after end marker")
      reply out s!"PASS {n}"
      return (0 : UInt32)
    else throw (IO.userError "incomplete or unacknowledged run")
  else throw (IO.userError "unknown protocol record")

def chosenProfile : Nat := match TestSettings.mode with
  | .readOnly => 1 | .vim => 2 | .alternating => 3

partial def serveText (p : TextPlan) (s : TextState) (input out : IO.FS.Stream) : IO UInt32 := do
  let some line ← readBounded input | throw (IO.userError "incomplete file test")
  if line.startsWith "S " then
    let some o := parseObservation line | throw (IO.userError "invalid observation")
    let some t := feedText p s o | throw (IO.userError "file navigation check failed")
    serveText p t input out
  else if line.startsWith "B " then
    let ["B", value] := words line | throw (IO.userError "invalid batch marker")
    let some n := nat value | throw (IO.userError "invalid batch count")
    let some count := acknowledge s.count n | throw (IO.userError "acknowledgment rejected")
    reply out s!"ACK {n}"
    serveText p { s with count := count } input out
  else if line.startsWith "Z " then
    let ["Z", value] := words line | throw (IO.userError "invalid end marker")
    let some n := nat value | throw (IO.userError "invalid end count")
    unless textFinished p s n do throw (IO.userError "not every file traversal completed")
    unless (← input.read 1).isEmpty do throw (IO.userError "trailing input")
    reply out s!"PASS {n}"
    return 0
  else throw (IO.userError "unknown protocol record")

-- Bounded reads continue to EOF; a short read cannot silently truncate input.
partial def readTextChunks (file : IO.FS.Handle) (limit : Nat) (bytes : ByteArray) : IO ByteArray := do
  let chunk ← file.read ((min 65536 (limit + 1 - bytes.size)).toUSize)
  if chunk.isEmpty then return bytes
  let next := bytes ++ chunk
  unless next.size ≤ limit do throw (IO.userError "input exceeds maxInputBytes")
  readTextChunks file limit next

def parseTextHeader (text : ByteArray) (header : String) : Option TextPlan := do
  let ["H", "2", b, m, n, mode, batch] := words header | none
  let size ← nat b
  let limit ← nat m
  let passes ← nat n
  let profile ← nat mode
  let count ← nat batch
  if size = text.size ∧ count = 62 ∧ 1 ≤ passes ∧ passes ≤ 1000 ∧
      1 ≤ profile ∧ profile ≤ 3 ∧ 8 ≤ limit ∧ passes * (limit + 1) ≤ 1000000 then
    some { text := text, newlines := textNewlines text, passes := passes,
           profile := profile, maxEnters := limit, reference := false }
  else none

def runFile (path snapshot : String) (input out : IO.FS.Stream) : IO UInt32 := do
  unless snapshot.isEmpty || (1 ≤ TestSettings.passes && TestSettings.passes ≤ 1000 &&
      8 ≤ TestSettings.maxEnterPressesPerPass &&
      TestSettings.passes * (TestSettings.maxEnterPressesPerPass + 1) ≤ 1000000 &&
      TestSettings.delayMilliseconds ≤ 1000 &&
      1 ≤ TestSettings.maxInputBytes && TestSettings.maxInputBytes ≤ 67108864) do
    throw (IO.userError "invalid test settings")
  let limit := if snapshot.isEmpty then 67108864 else TestSettings.maxInputBytes
  let text ← IO.FS.withFile path .read fun file => readTextChunks file limit ByteArray.empty
  unless (String.fromUTF8? text).isSome do throw (IO.userError "input is not UTF-8 text")
  let p : TextPlan :=
    { text := text
      newlines := textNewlines text
      passes := TestSettings.passes
      profile := chosenProfile
      maxEnters := TestSettings.maxEnterPressesPerPass
      reference := TestSettings.keepReference }
  -- One immutable byte snapshot is shared with the C observer. It has the
  -- chosen file's extension so normal Markdown wrapping/highlighting runs.
  if !snapshot.isEmpty then
    IO.FS.writeBinFile snapshot text
    reply out s!"PLAN2 {text.size} {p.maxEnters} {p.passes} {p.profile} {TestSettings.delayMilliseconds} {if p.reference then 1 else 0}"
  let some header ← readBounded input | throw (IO.userError "missing file-test header")
  if snapshot.isEmpty then
    let some checked := parseTextHeader text header | throw (IO.userError "invalid file-test header")
    reply out "READY"
    return ← serveText checked {} input out
  let expected := s!"H 2 {text.size} {p.maxEnters} {p.passes} {p.profile} 62"
  unless header == expected do throw (IO.userError "editor did not follow Lean plan")
  reply out "READY"
  serveText p {} input out

end ChezTester

def main (args : List String) : IO UInt32 := do
  let out ← IO.getStdout
  try
    let input ← IO.getStdin
    match args with
    | ["--editor-file", path, snapshot] => ChezTester.runFile path snapshot input out
    | ["--check-file", path] => ChezTester.runFile path "" input out
    | [] =>
      let some header ← ChezTester.readBounded input | throw (IO.userError "missing header")
      let some config := ChezTester.parseConfig header | throw (IO.userError "invalid header")
      ChezTester.reply out "READY"
      ChezTester.serve config {} input out
    | _ => throw (IO.userError "unknown arguments")
  catch e =>
    -- Keep even Unicode/path exceptions within one bounded ASCII reply.
    let detail := String.ofList ((e.toString.toList.map fun c =>
      if ' ' ≤ c && c ≤ '~' then c else '?').take 80)
    ChezTester.reply out ("FAIL " ++ detail)
    return (1 : UInt32)
