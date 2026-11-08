/-!
### 1. fixture_newline_only_at_end
For the artificial sample only, each row has a newline (byte 10) exactly at
column 15, counting from zero, and nowhere earlier. Each generated row
therefore has 15 ASCII characters followed by a newline: 16 bytes in total.

This sample gives the historical protocol-v1 navigation tests predictable byte
positions. It is not the file user choose with M-x chez-tester. That workflow
uses the file's actual contents and the text_* theorems below; it imposes no
15-character line limit.
-/
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

/- One observation describes what the editor actually did after a reset
or Enter.  Acceptance means: the right step, mode, byte position and line
number; the entire fixture is unchanged; no Scheme runtime failure was
observed. -/
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

/-!
### 2. observation_sound
In the fixed-width test, an accepted observation has the expected sequence
number, is within the planned observation count, and satisfies Conforms: the
planned action, mode, byte position and line number, plus intact = 1 and
error = 0. This proves what the Boolean checker accepts, not that the
C observer reports the editor's state truthfully. It does not concern
parsing a string.
-/
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

/-!
### 3. batch_sound
If the fixed-width checker accepts a batch, its observations form a
ConformingTrace starting at start. Sequence numbers are consecutive, every
observation is within the plan, and each satisfies Conforms. An empty or
partial batch can pass: this theorem does not require a complete run or validate parsing.
-/
theorem batch_sound (h : checkBatch c start os = true) : ConformingTrace c start os := by
  induction os generalizing start with
  | nil => exact .nil start
  | cons o os ih =>
    simp only [checkBatch, Bool.and_eq_true] at h
    obtain ⟨hs, hb, hc⟩ := observation_sound h.1
    exact .cons hs hb hc (ih h.2)

/-!
### 4. batch_append
Checking two lists together gives exactly the same Boolean result as checking
the first list at start and the second at start + the first list's length.
This permits incremental checking without retaining an already accepted prefix,
provided its ending sequence count is retained. It does not itself delete logs
or bound memory.
-/
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

/-!
### 5. conforming_indices
The sequence numbers in a ConformingTrace are exactly start, start + 1,
and so on, for as many observations as the trace contains. They have no gaps,
duplicates or reordering. The first number is zero only when start is zero.
-/
theorem conforming_indices (h : ConformingTrace c start os) :
    os.map Observation.seq = planIndices start os.length := by
  induction h with
  | nil => rfl
  | cons hs _ _ _ ih => simp [planIndices, hs, ih]

def checkComplete (c : Config) (os : List Observation) : Bool :=
  checkBatch c 0 os && decide (os.length = c.total)

/-!
### 6. complete_sound
If the fixed-width complete-run checker accepts a list, the list is a
ConformingTrace from zero, has exactly c.total observations, and its sequence
numbers cover that entire range. The total counts observations, not elapsed
time. This theorem describes the whole-list model; streaming completion is
checked separately by finished and complete_not_prefix.
-/
theorem complete_sound (h : checkComplete c os = true) :
    ConformingTrace c 0 os ∧ os.length = c.total ∧
    os.map Observation.seq = planIndices 0 c.total := by
  simp only [checkComplete, Bool.and_eq_true] at h
  have hn : os.length = c.total := of_decide_eq_true h.2
  have ht := batch_sound h.1
  exact ⟨ht, hn, hn ▸ conforming_indices ht⟩
