import Std

/-!
04-simgap: first reconstruction draft. Recorded 6 November 2026.
Inspected gap.c SHA-256: 818ae296129e7993f6467145a8aec04121bc5d42e053ab6f1a81093bfa41d339

Run in native Chezweb: M-!, lean --run 04-simgap.lean, C-c s.
Lean checks the theorems and interprets the simulations. No real files are edited.
Result zero can be the expected C failure return. The final simulation-checks
record reports whether all scenarios produced their expected outcomes.
Use --c-oracle to print the 43 defined comparison scenarios alone. This lets a
candidate C module be compared with the model using an ordinary bytewise cmp.

RECONSTRUCTION RULES
Generate new_gap.c with #include <sys/stat.h>, #include <errno.h>,
#include "header.h", and the thirteen procedure heads
written below. Keep make_parent_folders static. Keep the other symbols public.
Additional C subfunctions may be static helpers; do not export simulator names.
Use the existing C structures and external functions named in these comments.
A slot denotes the same mutable buffer object across calls. A Lean record update
means assigning only the named C fields in place, preserving all other fields.
Only growgap changes the text allocation. External callbacks may change globals.
Do not add b_cells, allocation IDs, or simulator fields to the C ABI.
Use #ifdef _WIN32 for the Windows filename branch. Use NAME_MAX, MAX_SIZE_T,
LONG_MAX and INT_MAX from the target headers. Never emit allocationLimit as a
new file-size limit: it only selects simulated malloc/realloc failures.

The model stores pointer offsets and an allocation identity instead of machine
addresses. In C, replace a buffer offset k by bp->b_buf + k. After realloc,
rebuild b_gap, b_egap and b_ebuf from the new base and saved offsets.
An initially unallocated C buffer has base NULL and zero offsets. Generate an
explicit initial-allocation branch before subtracting any NULL pointers.
Some unused cells contain none: their contents have not been initialized.
Copying such a cell preserves none. Reading it as text reports undefined C.

The thirteen entries in c-heads are module definitions. Emit each mapped body,
including bodies whose Lean names start with sim_, such as sim_save_buffer.
Other sim_ primitives with outside C heads become calls to those host functions.
Helpers such as sim_allocate and stream only organize the model; they are not
new public C APIs. Lower sim_read_int/sim_write_int to caller-pointer accesses.
Keep call order, early returns, partial writes and flag masks.
The in-memory filesystem and fault choices below make the paths executable.
Use the real libc/editor calls, rather than translating that fake filesystem
into new_gap.c. events, changes, hook choices and closed-stream records are
observations for these simulations. C uses the existing callbacks and actual
FILE objects; it does not acquire new persistent trace lists.

A stopped simulation distinguishes an assertion, a fatal exit, and undefined C.
For defined inputs, reproduce the return value, state changes and outside calls.
An undefined-C label supplies no old C result to reproduce. Choose any safe
extension explicitly in the next revision. None is visible to Lean; a raw int*
does not carry an initialization flag. Keep that distinction when generating C.
Check signed limits before arithmetic when choosing a safe overflow policy.

(abi
  (char_t "unsigned char; sizeof(char_t) = 1")
  (point_t "long; signed")
  (size_t "unsigned; selected by the target ABI")
  (constants (TRUE 1) (FALSE 0) (NOMARK -1) (MIN_GAP_EXPAND 512))
  (constants (NBUFN 17) (TEMPBUF 512))
  (flags (B_MODIFIED 1) (B_OVERWRITE 2) (B_SPECIAL 4)
         (B_UNDO 8) (B_READONLY 16)))

The constants NAME_MAX, MAX_SIZE_T and the signed limits are target parameters.
The default profile below is a 64-bit target. Use the target's header values
when generating C. Filename arguments are NUL-terminated byte strings, not Unicode indices.
Buffer contents are counted raw bytes: they may contain NUL or UTF-8 sequences.
Never use strlen to measure a buffer or a file payload.
-/
/-!
## Reading map

Data comes first. Pointer and gap logic follows. The sim_ functions then supply
filesystem, screen and callback effects. The last section runs small scenarios.

(c-heads
  (public "int growgap(buffer_t *bp, point_t n)" (model growgap))
  (public "point_t movegap(buffer_t *bp, point_t offset)" (model movegap))
  (public "char_t *ptr(buffer_t *bp, point_t offset)" (model ptr))
  (public "point_t pos(buffer_t *bp, char_t *cp)" (model pos))
  (public "int posix_file(char *fn)" (model sim_posix_file))
  (private "static int make_parent_folders(char *fn)" (model sim_make_parent_folders))
  (public "int save_buffer(buffer_t *bp, char *fn)" (model sim_save_buffer))
  (public "void clear_buffer(void)" (model sim_clear_buffer))
  (public "int load_file(char *fn)" (model sim_load_file))
  (public "int insert_file(char *fn, int modflag)" (model sim_insert_file))
  (public "void undoset(void)" (model sim_undoset))
  (public "point_t line_to_point(int ln)" (model line_to_point))
  (public "void get_line_stats(int *curline, int *lastline)" (model get_line_stats)))

(adapter-results
  (Bool "true = C TRUE for editor procedures")
  (sim_stat "some = stat returned 0; none = stat returned -1")
  (sim_fopen "some handle = FILE*; none = NULL")
  (sim_fclose "true = fclose returned 0")
  (sim_mkdir "true = mkdir returned 0")
  (sim_malloc "some = non-NULL allocation; none = NULL")
  (sim_fread "list length = size_t count returned; copy bytes into the gap")
  (sim_fwrite "Nat = size_t count accepted by fwrite"))

(message-map
  (no-changes (literal "(No changes need to be saved)"))
  (external-save-failed
    (literal "Save failed; changes are still unsaved. See the browser notice."))
  (browser-saved (literal "File saved. See the destination above."))
  (m_alloc (global m_alloc)) (m_badname (global m_badname))
  (m_open (global m_open) (arguments fn))
  (m_stat (global m_stat) (arguments fn))
  (m_toobig (global m_toobig) (arguments fn))
  (m_write (global m_write) (arguments fn))
  (m_close (global m_close) (arguments fn))
  (m_saved (global m_saved) (arguments fn point_t-byte-count))
  (m_loaded (global m_loaded) (arguments fn size_t-byte-count))
  (f_alloc (global f_alloc)))

The replacement includes header.h. It links these existing globals:
  extern buffer_t *curbp;
  extern window_t *curwp;
  extern char *f_alloc, *m_alloc, *m_badname, *m_open, *m_stat, *m_toobig;
  extern char *m_write, *m_close, *m_saved, *m_loaded;
Keep register qualifiers optional; they do not change any procedure's ABI.

Pass the original fn to C message calls. spelling exists only to display traces.
S-expression records follow Rivest and Eastlake, RFC 9804 (June 2025):
https://www.rfc-editor.org/rfc/rfc9804.html

## Data and outside state
-/
namespace SimGap04

abbrev sim_bytes := List UInt8

-- Filename lists have an implicit final NUL; an embedded NUL stops earlier.
-- Buffer/file payload lists instead have exactly their stated byte length.
def cstr (s : sim_bytes) : sim_bytes := s.takeWhile (· != 0)
def bytes (s : String) : sim_bytes := s.toUTF8.toList
def spelling (s : sim_bytes) : String :=
  (String.fromUTF8? ⟨(cstr s).toArray⟩).getD "<byte-path>"

-- C: typedef struct undo_t { point_t u_point,u_gap,u_egap; char u_flags; } undo_t;
-- Save the three offsets and the low eight flag bits. This is the old snapshot,
-- not the Scheme undo tree. Preserve its bytes until undoset is called.
structure sim_undo_t where
  u_point : Int := 0
  u_gap : Nat := 0
  u_egap : Nat := 0
  u_flags : UInt8 := 0
  deriving Repr, BEq, Inhabited

-- C position fields use point_t: b_mark, b_point, b_paren, b_paren_at,
-- b_cpoint, b_page, b_epage. b_id is long; b_read_count is unsigned.
-- b_cnt, b_size, b_psize, b_row, b_col and the other b_read_* fields are int.
-- b_flags is buffer_flags_t; b_fname is char[NAME_MAX+1]; b_bname is char[NBUFN].
-- C: buffer_t from header.h. b_buf names an allocation; b_cells holds its cells.
-- b_gap/b_egap/b_ebuf are offsets from b_buf. All other fields keep their C names.
-- Only explicitly updated fields change. The other fields pass through intact.
-- In C, b_next is a buffer_t*, filenames are fixed char arrays, and b_ubuf is undo_t.
structure sim_buffer_t where
  b_next : Option Nat := none
  b_mark : Int := -1
  b_point : Int := 0
  b_paren : Int := -1
  b_paren_at : Int := -1
  b_cpoint : Int := 0
  b_page : Int := 0
  b_epage : Int := 0
  b_cnt : Int := 0
  b_size : Int := 0
  b_psize : Int := 0
  b_buf : Nat := 0
  b_ebuf : Nat := 0
  b_gap : Nat := 0
  b_egap : Nat := 0
  b_row : Int := 0
  b_col : Int := 0
  b_fname : sim_bytes := []
  b_bname : sim_bytes := []
  b_read_mode : Int := 0
  b_read_visual : Int := 0
  b_read_pending : Int := 0
  b_read_count : Nat := 0
  b_flags : UInt32 := 0
  b_ubuf : sim_undo_t := {}
  b_id : Int := 1
  b_cells : Array (Option UInt8) := #[]
  deriving Repr, BEq, Inhabited

-- C: window_t*. Only beginning_of_buffer uses it here, changing w_point.
-- Keep the remaining window_t fields unchanged in C. w_bufp refers to a buffer slot.
-- Their opaque bytes are represented by unchanged. Their C declarations are:
-- window_t *w_next; buffer_t *w_hijack; point_t w_mark,w_page,w_epage;
-- char w_top,w_rows; int w_row,w_col,w_update; char w_name[STRBUF_S];
-- STRBUF_S is 16. Never overwrite these fields when synchronizing w_point.
structure sim_window_t where
  w_bufp : Nat := 0
  w_point : Int := 0
  unchanged : List UInt8 := []
  deriving Repr, BEq, Inhabited

-- C: char_t*. A pointer carries the allocation identity and an offset.
-- Pointers from an old allocation cannot be used after that allocation moves.
structure sim_pointer where
  block : Nat
  offset : Int
  deriving Repr, BEq, Inhabited

-- C: struct stat. The module reads st_size and tests S_ISREG(st_mode).
-- Call host stat in C; leave all other struct stat fields to the host.
inductive sim_kind where | regular | directory | other
  deriving Repr, BEq, Inhabited
structure sim_stat_data where
  st_size : Nat
  st_mode : sim_kind
  deriving Repr, BEq, Inhabited

-- C local: char dir[NAME_MAX+1]. Own this storage separately from fn.
-- Copy bytes before the final slash, then write a NUL at that slash index.
-- C may temporarily replace a slash with NUL while passing a prefix to mkdir.
structure sim_char_array where
  cells : Array (Option UInt8)
  deriving Repr, BEq, Inhabited

-- A simulated filesystem entry supplies stat metadata and file bytes.
-- advertisedSize permits a file to shrink or grow between stat and fread.
structure sim_entry where
  path : sim_bytes
  kind : sim_kind := .regular
  data : sim_bytes := []
  advertisedSize : Option Nat := none
  deriving Repr, BEq, Inhabited

-- C: FILE*. The integer handle indexes this record. fopen owns it until fclose.
-- A short fwrite in the current save_buffer returns without closing the handle.
structure sim_FILE where
  path : sim_bytes
  writing : Bool
  position : Nat := 0
  closed : Bool := false
  deriving Repr, BEq, Inhabited

inductive sim_errno where | ok | enoent | eexist | eacces | eio | enomem | eisdir
  deriving Repr, BEq, Inhabited
inductive sim_stop where
  | assertion (reason : String)
  | fatal (message : String)
  | undefinedC (reason : String)
  | indeterminate (reason : String)
  deriving Repr, BEq, Inhabited

-- Choose failures before a run. Each list names paths whose host operation fails.
-- readLimit and writeLimit select short transfers. closeFails closes then fails.
structure sim_faults where
  allocationFails : Bool := false
  statDenied : List sim_bytes := []
  readDenied : List sim_bytes := []
  writeDenied : List sim_bytes := []
  mkdirDenied : List sim_bytes := []
  readLimit : Option Nat := none
  writeLimit : Option Nat := none
  closeFails : Bool := false
  externalSaveOK : Bool := true
  deriving Repr, BEq, Inhabited

-- C integer limits, path classification, platform and allocation choices.
-- alnumExtra models locale-dependent isalnum for additional byte values.
structure sim_profile where
  nameMax : Nat := 255
  sizeMax : Nat := 18446744073709551615
  pointMax : Int := 9223372036854775807
  intMax : Int := 2147483647
  minGap : Nat := 512
  allocationLimit : Nat := 1048576
  windows : Bool := false
  backend : String := "terminal"
  screenRows : Int := 24
  alnumExtra : List UInt8 := []
  deriving Repr, BEq, Inhabited

-- These are record_change callback arguments. Copy inserted text before reuse.
structure sim_change where
  bufferID : Int
  kind : UInt8
  position : Int
  text : sim_bytes
  deriving Repr, BEq, Inhabited
-- A callback may replace buffers or switch curbp. Re-read globals after it.
structure sim_hook_effect where
  buffers : Option (Array sim_buffer_t) := none
  curbp : Option Nat := none
  curwp : Option sim_window_t := none
  flags : Option UInt32 := none
  stop : Option sim_stop := none
  deriving Repr, Inhabited

structure sim_event where
  name : String
  args : List String := []
  deriving Repr, BEq, Inhabited

-- C globals: curbp and curwp select mutable buffer/window slots.
-- errno, open streams, messages, prompts and callbacks are explicit state.
-- hookEffects supplies one state transition per delivered callback.
-- intCells models int* output storage; equal indices mean aliased pointers.
structure sim_data where
  buffers : Array sim_buffer_t := #[{}]
  curbp : Nat := 0
  curwp : sim_window_t := {}
  entries : List sim_entry := []
  streams : Array sim_FILE := #[]
  errno : sim_errno := .ok
  profile : sim_profile := {}
  faults : sim_faults := {}
  nextBlock : Nat := 1
  answerYes : Bool := false
  keys : List Int := []
  changeHook : Bool := true
  hookEffects : List sim_hook_effect := []
  intCells : Array (Option Int) := #[none, none]
  changes : List sim_change := []
  events : List sim_event := []
  message : sim_event := ⟨"", []⟩
  prompt : String := ""
  deriving Repr

abbrev sim_M (α : Type) := ExceptT sim_stop (StateM sim_data) α

def event (name : String) (args : List String := []) : sim_M Unit :=
  modify fun s => { s with events := s.events ++ [⟨name, args⟩] }
-- C macro: assert(condition). False stops this debug-model transition.
def require (h : Bool) (why : String) : sim_M Unit :=
  unless h do throw (.assertion why)
def getBuffer (slot : Nat) : sim_M sim_buffer_t := do
  let s ← get
  let some b := s.buffers[slot]? | throw (.undefinedC "invalid buffer pointer")
  return b
def putBuffer (slot : Nat) (b : sim_buffer_t) : sim_M Unit := do
  let s ← get
  require (slot < s.buffers.size) "buffer slot exists"
  modify fun s => { s with buffers := s.buffers.set! slot b }
def current : sim_M Nat := return (← get).curbp

def valid (b : sim_buffer_t) : Bool :=
  b.b_gap ≤ b.b_egap && b.b_egap ≤ b.b_ebuf && b.b_ebuf == b.b_cells.size

def logicalCells (b : sim_buffer_t) : List (Option UInt8) :=
  b.b_cells.toList.take b.b_gap ++ b.b_cells.toList.drop b.b_egap

def documentSize (b : sim_buffer_t) : Nat := b.b_ebuf - (b.b_egap - b.b_gap)

-- C head: point_t document_size(buffer_t *bp); src/buffer.c.
-- The C buffer has byte-sized char_t, so pointer differences count bytes.
def sim_document_size (slot : Nat) : sim_M Nat := do
  let b ← getBuffer slot
  require (valid b) "ordered gap pointers"
  return documentSize b

-- C head: void msg(char *format, ...); src/main.c.
-- name identifies the existing C message constant; args supply its arguments.
-- Host msg formats into msgline[TEMPBUF] and sets msgflag. It returns normally.
def sim_msg (name : String) (args : List String := []) : sim_M Unit := do
  event "msg" (name :: args)
  modify fun s => { s with message := ⟨name, args⟩ }

-- C head: void fatal(char *message); src/main.c. It ends this execution.
def sim_fatal (message : String) : sim_M α := do
  event "fatal" [message]
  throw (.fatal message)

-- Allocation helper: preserve cells, add uninitialized cells, choose a fresh base.
-- A failed allocation preserves the old buffer. The budget selects host OOM.
def sim_allocate (tag : String) (old : Array (Option UInt8)) (size : Nat) :
    sim_M (Option (Nat × Array (Option UInt8))) := do
  event tag [toString size]
  let s ← get
  if s.faults.allocationFails || size > s.profile.allocationLimit then
    modify fun s => { s with errno := .enomem }
    return none
  let memory := old ++ Array.replicate (size - old.size) none
  modify fun s => { s with nextBlock := s.nextBlock + 1 }
  return some (s.nextBlock, memory)
-- C head: void *malloc(size_t size); NULL means failure.
def sim_malloc (size : Nat) := sim_allocate "malloc" #[] size
-- C head: void *realloc(void *old,size_t size); called only to grow here.
def sim_realloc (old : Array (Option UInt8)) (size : Nat) := sim_allocate "realloc" old size

/-!
## Pointer and allocation transitions
-/

-- C head: int growgap(buffer_t *bp, point_t n);
-- Keep the prefix at its old offset. Copy the suffix backwards from the old
-- allocation end to the new end. Extra cells therefore enlarge only the gap.
def growgap (slot : Nat) (requested : Int) : sim_M Bool := do
  let b ← getBuffer slot
  require (valid b) "growgap entry pointers"
  let s ← get
  let extra := max s.profile.minGap requested.toNat
  let newlen := b.b_ebuf + extra
  if (newlen : Int) > s.profile.pointMax then
    throw (.undefinedC "growgap: signed point_t addition overflow")
  if newlen > s.profile.sizeMax then
    if b.b_ebuf == 0 then sim_fatal "f_alloc"
    else sim_msg "m_alloc"; return false
  let allocation ← if b.b_ebuf == 0 then sim_malloc newlen else sim_realloc b.b_cells newlen
  let some (base, memory) := allocation |
    if b.b_ebuf == 0 then sim_fatal "f_alloc" else sim_msg "m_alloc"; return false
  let mut cells := memory
  let mut oldEnd := b.b_ebuf
  let mut newEnd := newlen
  while b.b_egap < oldEnd do
    oldEnd := oldEnd - 1
    newEnd := newEnd - 1
    cells := cells.set! newEnd cells[oldEnd]!
  let updated := { b with b_buf := base, b_ebuf := newlen, b_egap := newEnd, b_cells := cells }
  require (valid updated && updated.b_gap < updated.b_egap) "growgap exit pointers"
  putBuffer slot updated
  return true

-- Arithmetic shared by ptr and pos. Values here are offsets from b_buf.
def ptr_offset (b : sim_buffer_t) (offset : Int) : Int :=
  if offset < 0 then 0 else offset + if offset < b.b_gap then 0 else (b.b_egap : Int) - b.b_gap

def pos_offset (b : sim_buffer_t) (cp : Int) : Int :=
  cp - if cp < b.b_egap then 0 else (b.b_egap : Int) - b.b_gap

-- C head: char_t *ptr(buffer_t *bp, point_t offset);
-- Negative input returns the base, not the first byte after a gap at zero.
def ptr (slot : Nat) (offset : Int) : sim_M sim_pointer := do
  let b ← getBuffer slot
  let p := ptr_offset b offset
  if p < 0 || p > b.b_ebuf then throw (.undefinedC "ptr outside allocation")
  return ⟨b.b_buf, p⟩

-- C head: point_t pos(buffer_t *bp, char_t *cp);
-- cp must belong to this allocation, including its one-past-end pointer.
-- Preserve the C formula even for a cp that lies inside the gap.
def pos (slot : Nat) (cp : sim_pointer) : sim_M Int := do
  let b ← getBuffer slot
  require (cp.block == b.b_buf && 0 ≤ cp.offset && cp.offset ≤ b.b_ebuf) "pos pointer belongs to buffer"
  return pos_offset b cp.offset

-- C head: point_t movegap(buffer_t *bp, point_t offset);
-- Hold the physical target fixed while copying bytes one at a time.
-- Moving right uses the old physical target; do not replace it with offset.
def movegap (slot : Nat) (offset : Int) : sim_M Int := do
  let p ← ptr slot offset
  let mut b ← getBuffer slot
  require (valid b) "movegap entry pointers"
  while p.offset < b.b_gap do
    require (b.b_gap > 0 && b.b_egap > 0) "movegap left indices"
    let gap := b.b_gap - 1
    let egap := b.b_egap - 1
    b := { b with b_gap := gap, b_egap := egap, b_cells := b.b_cells.set! egap b.b_cells[gap]! }
  while (b.b_egap : Int) < p.offset do
    require (b.b_egap < b.b_ebuf) "movegap right source"
    b := { b with b_cells := b.b_cells.set! b.b_gap b.b_cells[b.b_egap]!,
                  b_gap := b.b_gap + 1, b_egap := b.b_egap + 1 }
  require (valid b) "movegap exit pointers"
  putBuffer slot b
  pos slot ⟨b.b_buf, b.b_egap⟩

-- Logical reads use the same pointer translation as C and detect unknown text.
def readByte (slot : Nat) (offset : Int) : sim_M UInt8 := do
  let p ← ptr slot offset
  let b ← getBuffer slot
  if p.offset == b.b_ebuf then throw (.undefinedC "dereference one-past-end")
  let some byte := b.b_cells[p.offset.toNat]! | throw (.indeterminate "text read has no chosen byte value")
  return byte

/-!
## Filename, filesystem and screen simulations
-/

-- C head: int isalnum(int byte); the argument is cast to unsigned char.
-- Use host locale in C. The simulation defaults to ASCII classification.
def sim_isalnum (profile : sim_profile) (b : UInt8) : Bool :=
  let n := b.toNat
  (48 ≤ n && n ≤ 57) || (65 ≤ n && n ≤ 90) || (97 ≤ n && n ≤ 122) || profile.alnumExtra.contains b

-- C head: int strcmp(const char *a,const char *b);
-- Only equality is used in gap.c. The other return magnitudes are immaterial.
def sim_strcmp (a b : sim_bytes) : Int :=
  if cstr a == cstr b then 0 else 1

-- C head: int posix_file(char *fn);
-- The empty string passes this predicate. fopen may still reject it.
def sim_posix_file (profile : sim_profile) (filename : sim_bytes) : Bool :=
  let name := cstr filename
  name.head? != some 95 && name.all (fun b => sim_isalnum profile b ||
    [46, 95, 45, 47].contains b || (profile.windows && [92, 58].contains b))

-- C macro: S_ISREG(mode_t mode). Test the file-type bits, not equality to S_IFREG.
def sim_S_ISREG (mode : sim_kind) : Bool := mode == .regular

-- C head: int stat(const char *path, struct stat *out);
-- A successful call leaves errno alone. A failure sets it.
-- The simulated filesystem uses exact byte-path keys. Host stat resolves paths in C.
def sim_stat (filename : sim_bytes) : sim_M (Option sim_stat_data) := do
  let path := cstr filename
  event "stat" [spelling path]
  let s ← get
  if s.faults.statDenied.contains path then
    modify fun s => { s with errno := .eacces }; return none
  match s.entries.find? (fun f => f.path == path) with
  | none => modify fun s => { s with errno := .enoent }; return none
  | some f => return some ⟨f.advertisedSize.getD f.data.length, f.kind⟩

-- C head: size_t strlen(const char *s);
def sim_strlen (s : sim_bytes) : Nat := (cstr s).length

-- C head: char *strrchr(const char *s,int byte); used here for '/'.
-- The returned index becomes a char* into the original string in generated C.
def sim_strrchr (path : sim_bytes) (byte : UInt8) : Option Nat :=
  (List.range (cstr path).length).reverse.find? (fun i => path[i]? == some byte)

def lastSlash (path : sim_bytes) : Option Nat := sim_strrchr path 47

def parentForOpen (path : sim_bytes) : sim_bytes :=
  match lastSlash path with
  | none => bytes "."
  | some 0 => bytes "/"
  | some i => path.take i

def storeEntry (entry : sim_entry) : sim_M Unit :=
  modify fun s => { s with entries := entry :: s.entries.filter (fun f => f.path != entry.path) }

-- C head: int mkdir(const char *path, mode_t mode);
-- Return EEXIST when the named entry already exists, even if it is not a folder.
def sim_mkdir (path : sim_bytes) : sim_M Bool := do
  event "mkdir" [spelling path, "0755"]
  let s ← get
  if s.entries.any (fun f => f.path == path) then
    modify fun s => { s with errno := .eexist }; return false
  if s.faults.mkdirDenied.contains path then
    modify fun s => { s with errno := .eacces }; return false
  storeEntry ⟨path, .directory, [], none⟩
  return true

-- C head: int screen_rows(void); MSGLINE is screen_rows()-1.
def sim_screen_rows : sim_M Int := return (← get).profile.screenRows

-- C head: void screen_mvaddstr(int row,int col,const char *text);
def sim_screen_mvaddstr (row col : Int) (text : String) : sim_M Unit := do
  event "screen_mvaddstr" [toString row, toString col, text]
  modify fun s => { s with prompt := text }

-- C head: void screen_addstr(const char *text);
def sim_screen_addstr (text : String) : sim_M Unit := do
  event "screen_addstr" [text]
  modify fun s => { s with prompt := s.prompt ++ text }

-- C head: void screen_clrtoeol(void); prompt characters already written remain.
def sim_screen_clrtoeol : sim_M Unit := event "screen_clrtoeol"

-- C head: void screen_refresh(void); the screen becomes observable.
def sim_screen_refresh : sim_M Unit := event "screen_refresh"

-- The four C screen calls that display the missing-directory question.
def sim_prompt (dir : sim_bytes) : sim_M Unit := do
  sim_screen_mvaddstr ((← sim_screen_rows) - 1) 0 "Folder "
  sim_screen_addstr (spelling dir)
  sim_screen_addstr " does not exist; create it (y/n) ?"
  sim_screen_clrtoeol

-- C head: int read_key_byte(void); keys supplies one chosen keyboard result.
def sim_read_key_byte : sim_M Int := do
  let s ← get
  match s.keys with
  | key :: rest => modify fun s => { s with keys := rest }; return key
  | [] => return if s.answerYes then 121 else 110

-- C head: int yesno(int default_answer); src/command.c.
-- Enter uses the default; otherwise y/Y means yes. The prompt is flushed first.
def sim_yesno (defaultAnswer : Bool := false) : sim_M Bool := do
  sim_screen_addstr ((if defaultAnswer then " y" else " n") ++ String.singleton (Char.ofNat 8))
  sim_screen_refresh
  let key ← sim_read_key_byte
  if key == 13 || key == 10 then return defaultAnswer
  return key == 121 || key == 89

-- C head: void *memcpy(void *dst,const void *src,size_t count);
-- This module's memcpy copies the filename prefix into a separate local array.
def sim_memcpy (destination : sim_char_array) (source : sim_bytes) (count : Nat) :
    sim_M sim_char_array := do
  if count > source.length || count > destination.cells.size then
    throw (.undefinedC "memcpy crosses a source or destination boundary")
  let mut cells := destination.cells
  for i in List.range count do cells := cells.set! i (some source[i]!)
  return ⟨cells⟩

-- Prepare the local NUL-terminated directory array without touching fn.
def directoryPrefix (path : sim_bytes) (slash capacity : Nat) : sim_M sim_bytes := do
  let copied ← sim_memcpy ⟨Array.replicate capacity none⟩ path slash
  require (slash < copied.cells.size) "directory terminator fits"
  let terminated := copied.cells.set! slash (some 0)
  return cstr (terminated.toList.map (fun byte => byte.getD 0))

-- C head: static int make_parent_folders(char *fn);
-- Scan slash-separated prefixes starting at index 1, including the final end.
-- An existing parent or a missing slash returns FALSE before asking anything.
def sim_make_parent_folders (filename : sim_bytes) : sim_M Bool := do
  let path := cstr filename
  if sim_strlen path > (← get).profile.nameMax then return false
  let some slash := lastSlash path | return false
  if slash == 0 then return false
  let dir ← directoryPrefix path slash ((← get).profile.nameMax + 1)
  if (← sim_stat dir).isSome then return false
  sim_prompt dir
  unless (← sim_yesno) do return false
  for i in List.range (dir.length + 1) do
    if i > 0 && (i == dir.length || dir[i]? == some 47) then
      let part := dir.take i
      if (← sim_stat part).isNone then
        unless (← sim_mkdir part) do
          unless (← get).errno == .eexist do return false
  return true

-- C head: FILE *fopen(const char *path, const char *mode);
-- "wb" truncates immediately, before movegap, fwrite, fclose or confirmation.
-- "rb" can open a directory; its fread then returns zero in this simulator.
def sim_fopen (filename : sim_bytes) (writing : Bool) : sim_M (Option Nat) := do
  let path := cstr filename
  event "fopen" [spelling path, if writing then "wb" else "rb"]
  let s ← get
  if (if writing then s.faults.writeDenied else s.faults.readDenied).contains path then
    modify fun s => { s with errno := .eacces }; return none
  let entry := s.entries.find? (fun f => f.path == path)
  if writing then
    if entry.any (fun f => f.kind == .directory) then
      modify fun s => { s with errno := .eisdir }; return none
    if path.isEmpty || (entry.isNone && !(s.entries.any (fun f =>
        f.path == parentForOpen path && f.kind == .directory))) then
      modify fun s => { s with errno := .enoent }; return none
    storeEntry ⟨path, .regular, [], none⟩
  else if entry.isNone then
    modify fun s => { s with errno := .enoent }; return none
  let handle := (← get).streams.size
  modify fun s => { s with streams := s.streams.push ⟨path, writing, 0, false⟩ }
  return some handle

def stream (handle : Nat) : sim_M sim_FILE := do
  let some f := (← get).streams[handle]? | throw (.undefinedC "invalid FILE pointer")
  require (!f.closed) "FILE is open"
  return f

-- C head: size_t fread(void *dst,size_t size,size_t count,FILE *fp);
-- All calls in gap.c use size=1. The returned list contains the accepted bytes.
-- Short reads are not errors to insert_file: it never calls ferror.
def sim_fread (handle count : Nat) : sim_M sim_bytes := do
  let f ← stream handle
  require (!f.writing) "fread on read stream"
  event "fread" [toString count]
  let s ← get
  let some entry := s.entries.find? (fun e => e.path == f.path) |
    throw (.undefinedC "simulation entry disappeared while open")
  let data := if entry.kind == .directory then [] else
    (entry.data.drop f.position).take (min count (s.faults.readLimit.getD count))
  modify fun s => { s with streams := s.streams.set! handle { f with position := f.position + data.length } }
  return data

-- C head: size_t fwrite(const void *src,size_t size,size_t count,FILE *fp);
-- A short write leaves its accepted prefix in the simulated file.
-- The C comparison flushes still-open streams before observing accepted file bytes.
def sim_fwrite (handle : Nat) (data : sim_bytes) : sim_M Nat := do
  let f ← stream handle
  require f.writing "fwrite on write stream"
  event "fwrite" [toString data.length]
  let s ← get
  let count := min data.length (s.faults.writeLimit.getD data.length)
  let some entry := s.entries.find? (fun e => e.path == f.path) |
    throw (.undefinedC "simulation entry disappeared while open")
  storeEntry { entry with data := entry.data.take f.position ++ data.take count ++ entry.data.drop (f.position + count) }
  modify fun s => { s with streams := s.streams.set! handle { f with position := f.position + count } }
  return count

-- C head: int fclose(FILE *fp); it closes even when it reports failure.
def sim_fclose (handle : Nat) : sim_M Bool := do
  let f ← stream handle
  event "fclose"
  modify fun s => { s with streams := s.streams.set! handle { f with closed := true } }
  return !(← get).faults.closeFails

-- C head: const char *screen_backend(void); host names are terminal/gui/browser.
def sim_screen_backend : sim_M String := return (← get).profile.backend

-- C head: int screen_save_file(const char *path);
-- Native backends return 1. The browser waits for its external save receipt.
def sim_screen_save_file (path : sim_bytes) : sim_M Bool := do
  event "screen_save_file" [spelling path]
  let s ← get
  return (← sim_screen_backend) != "browser" || s.faults.externalSaveOK

-- C head: void delete_mode(buffer_t *bp,buffer_flags_t mode); buffer.c.
def sim_delete_mode (slot : Nat) (mode : UInt32) : sim_M Unit := do
  let b ← getBuffer slot
  putBuffer slot { b with b_flags := b.b_flags &&& (~~~mode) }

-- C head: void record_change(buffer_t *bp,int kind,point_t pos,
--                          const char_t *text,long len); undo.c.
-- Copy callback data now. Disabled hooks and zero-byte insert/delete calls
-- deliver no callback. The selected buffer may change during a callback.
def sim_record_change (slot : Nat) (kind : UInt8) (position : Int) (data : sim_bytes) : sim_M Unit := do
  event "record_change" [toString kind.toNat, toString data.length]
  let s ← get
  if !s.changeHook || ((kind == 105 || kind == 100) && data.isEmpty) then return
  let b ← getBuffer slot
  modify fun s => { s with changes := s.changes ++ [⟨b.b_id, kind, position, data⟩] }
  match s.hookEffects with
  | [] => pure ()
  | effect :: rest =>
      modify fun s =>
        { s with
          hookEffects := rest
          buffers := effect.buffers.getD s.buffers
          curbp := effect.curbp.getD s.curbp
          curwp := effect.curwp.getD s.curwp }
      if let some flags := effect.flags then
        putBuffer slot { (← getBuffer slot) with b_flags := flags }
      if let some stop := effect.stop then throw stop

-- Pure helper for the old undo snapshot.
def undoSnapshot (b : sim_buffer_t) : sim_undo_t :=
  ⟨b.b_point, b.b_gap, b.b_egap, b.b_flags.toUInt8⟩
-- C head: void undoset(void); snapshot offsets before insertion.
def sim_undoset : sim_M Unit := do
  let slot ← current
  let b ← getBuffer slot
  putBuffer slot { b with b_ubuf := undoSnapshot b }

/-!
## Save, insert, clear and load
-/

-- C head: int save_buffer(buffer_t *bp,char *fn);
-- Keep the clean-file shortcut before name validation. Move the gap to zero
-- only after opening succeeds. Keep the short-write handle leak visible.
def sim_save_buffer (slot : Nat) (filename : sim_bytes) : sim_M Bool := do
  let path := cstr filename
  let b ← getBuffer slot
  if b.b_flags &&& 1 == 0 && sim_strcmp path b.b_fname == 0 then
    if let some info ← sim_stat path then
      if sim_S_ISREG info.st_mode then
        sim_msg "no-changes"; return true
  unless sim_posix_file (← get).profile path do sim_msg "m_badname"; return false
  let mut opened ← sim_fopen path true
  if opened.isNone && (← get).errno == .enoent then
    if (← sim_make_parent_folders path) then opened ← sim_fopen path true
  let some handle := opened | sim_msg "m_open" [spelling path]; return false
  let _ ← movegap slot 0
  let b ← getBuffer slot
  let mut data : sim_bytes := []
  for offset in List.range (b.b_ebuf - b.b_egap) do
    data := data ++ [← readByte slot offset]
  unless (← sim_fwrite handle data) == data.length do
    sim_msg "m_write" [spelling path]; return false
  unless (← sim_fclose handle) do sim_msg "m_close" [spelling path]; return false
  unless (← sim_screen_save_file path) do sim_msg "external-save-failed"; return false
  sim_delete_mode slot 1
  sim_record_change slot 115 0 []
  if (← sim_screen_backend) == "browser" then sim_msg "browser-saved"
  else
    let b ← getBuffer slot
    let length ← pos slot ⟨b.b_buf, b.b_ebuf⟩
    sim_msg "m_saved" [spelling path, toString length]
  return true

-- Pure helper: make the full allocation unused and clear point/mark.
def clearedBuffer (b : sim_buffer_t) : sim_buffer_t :=
  { b with b_gap := 0, b_egap := b.b_ebuf, b_point := 0, b_mark := -1 }
-- C head: void zero_buffer(buffer_t *bp); buffer.c. It preserves allocation.
def sim_zero_buffer (slot : Nat) : sim_M Unit := do
  putBuffer slot (clearedBuffer (← getBuffer slot))
  sim_record_change slot 114 0 []

-- C head: void beginning_of_buffer(void); command.c.
-- It changes both the selected buffer point and the selected window point.
def sim_beginning_of_buffer : sim_M Unit := do
  let slot ← current
  let b ← getBuffer slot
  putBuffer slot { b with b_point := 0 }
  modify fun s => { s with curwp := { s.curwp with w_point := 0 } }

-- C head: void clear_buffer(void); the zero_buffer callback precedes window sync.
def sim_clear_buffer : sim_M Unit := do
  sim_zero_buffer (← current)
  sim_beginning_of_buffer

-- The C mask is &=, not |=. With modflag=true it discards every other flag
-- and does not set B_MODIFIED if that bit was previously zero.
def insertFlags (flags : UInt32) (modflag : Int) : UInt32 :=
  flags &&& (if modflag != 0 then 1 else ~~~(1 : UInt32))

-- C head: int insert_file(char *fn,int modflag);
-- Stat and possible growth precede fopen. Keep the point at the insertion
-- start, snapshot old undo offsets, then advance b_gap by the actual read count.
def sim_insert_file (filename : sim_bytes) (modflag : Int) : sim_M Bool := do
  let slot ← current
  let some info ← sim_stat filename | sim_msg "m_stat" [spelling filename]; return false
  if info.st_size > (← get).profile.sizeMax then sim_msg "m_toobig" [spelling filename]; return false
  let b ← getBuffer slot
  if b.b_egap - b.b_gap < info.st_size then
    unless (← growgap slot info.st_size) do return false
  let some handle ← sim_fopen filename false | sim_msg "m_open" [spelling filename]; return false
  let point ← movegap slot (← getBuffer slot).b_point
  putBuffer slot { (← getBuffer slot) with b_point := point }
  sim_undoset
  let data ← sim_fread handle info.st_size
  let mut b ← getBuffer slot
  require (data.length ≤ b.b_egap - b.b_gap) "fread fits gap"
  for (byte, i) in data.zipIdx do b := { b with b_cells := b.b_cells.set! (b.b_gap + i) (some byte) }
  b := { b with b_gap := b.b_gap + data.length }
  putBuffer slot b
  sim_record_change slot 105 point data
  unless (← sim_fclose handle) do sim_msg "m_close" [spelling filename]; return false
  -- record_change may have switched curbp. C now masks that selected buffer.
  let target ← current
  b ← getBuffer target
  putBuffer target { b with b_flags := insertFlags b.b_flags modflag }
  sim_msg "m_loaded" [spelling filename, toString data.length]
  return true

-- C head: int load_file(char *fn);
-- A failed load still clears the old buffer and reports the final reset.
def sim_load_file (filename : sim_bytes) : sim_M Bool := do
  sim_clear_buffer
  let ok ← sim_insert_file filename 0
  sim_record_change (← current) 114 0 []
  return ok

/-!
## Logical lines and output pointers
-/

-- C head: point_t line_to_point(int ln);
-- Lines are one-based. The final newline creates an empty last line.
def line_to_point (ln : Int) : sim_M Int := do
  if ln < 1 then return -1
  if ln == 1 then return 0
  let slot ← current
  let size ← sim_document_size slot
  let mut remaining := ln
  for p in List.range size do
    if (← readByte slot p) == 10 then
      remaining := remaining - 1
      if remaining == 1 then return p + 1
  return -1

-- C: int*. The index selects an int cell. None means uninitialized storage.
-- Use the caller's real pointers in C; aliased indices share the same cell here.
abbrev sim_int_pointer := Nat

def sim_write_int (address : sim_int_pointer) (value : Int) : sim_M Unit := do
  require (address < (← get).intCells.size) "int output address exists"
  let limit := (← get).profile.intMax
  if value > limit || value < -limit - 1 then throw (.undefinedC "int arithmetic overflow")
  modify fun s => { s with intCells := s.intCells.set! address (some value) }

def sim_read_int (address : sim_int_pointer) : sim_M Int := do
  let some cell := (← get).intCells[address]? | throw (.undefinedC "invalid int pointer")
  let some value := cell | throw (.undefinedC "read uninitialized int output")
  return value

-- C head: void get_line_stats(int *curline,int *lastline);
-- Writes happen in C order. Thus aliased pointers also work as in C.
-- Empty text reads the caller's old *lastline before adding one.
def get_line_stats (curline lastline : sim_int_pointer) : sim_M Unit := do
  let slot ← current
  let b ← getBuffer slot
  let endp ← pos slot ⟨b.b_buf, b.b_ebuf⟩
  sim_write_int curline (-1)
  let mut line : Int := 0
  for p in List.range endp.toNat do
    let byte ← readByte slot p
    if byte == 10 then line := line + 1
    if line > (← get).profile.intMax then throw (.undefinedC "line counter overflows int")
    sim_write_int lastline line
    if (← sim_read_int curline) == -1 && (p : Int) == b.b_point then
      sim_write_int curline (if byte == 10 then line else line + 1)
  sim_write_int lastline ((← sim_read_int lastline) + 1)
  if b.b_point == endp then sim_write_int curline (← sim_read_int lastline)

/-!
## Small proofs
-/

-- Nonnegative logical positions survive a pointer/offset round trip.
theorem pointer_roundtrip (b : sim_buffer_t) (p : Int)
    (hp : 0 ≤ p) (hg : b.b_gap ≤ b.b_egap) : pos_offset b (ptr_offset b p) = p := by
  unfold pos_offset ptr_offset
  split <;> split <;> omega

-- Every valid logical position maps within the allocation, including its end.
theorem pointer_bounds (b : sim_buffer_t) (p : Int)
    (hg : b.b_gap ≤ b.b_egap) (he : b.b_egap ≤ b.b_ebuf)
    (hp : 0 ≤ p) (hn : p ≤ documentSize b) :
    0 ≤ ptr_offset b p ∧ ptr_offset b p ≤ b.b_ebuf := by
  unfold documentSize at hn
  have nonnegative : ¬p < 0 := by omega
  simp only [ptr_offset, if_neg nonnegative]
  split <;> omega

-- The clearing helper makes the allocation unused before calling the hook.
theorem clear_preserves_allocation (b : sim_buffer_t) :
    (clearedBuffer b).b_cells = b.b_cells ∧
    (clearedBuffer b).b_gap = 0 ∧ (clearedBuffer b).b_egap = b.b_ebuf := by
  exact ⟨rfl, rfl, rfl⟩

-- The old undo snapshot records the exact point and gap offsets.
theorem undo_snapshot_offsets (b : sim_buffer_t) :
    (undoSnapshot b).u_point = b.b_point ∧
    (undoSnapshot b).u_gap = b.b_gap ∧ (undoSnapshot b).u_egap = b.b_egap := by
  exact ⟨rfl, rfl, rfl⟩

-- The true modflag branch keeps only bit zero; a clean buffer can stay clean.
theorem insert_mask_example : insertFlags 22 1 = 0 ∧ insertFlags 23 1 = 1 := by
  decide

-- The false modflag branch removes bit zero and preserves the other low flags.
theorem load_mask_example : insertFlags 23 0 = 22 := by
  decide

-- Growth requests always reserve at least MIN_GAP_EXPAND cells.
theorem minimum_growth (profile : sim_profile) (request : Int) :
    profile.minGap ≤ max profile.minGap request.toNat := by
  exact Nat.le_max_left _ _

-- A leading underscore is rejected before the remaining filename is scanned.
theorem underscore_rejected (profile : sim_profile) (tail : sim_bytes) :
    sim_posix_file profile (95 :: tail) = false := by
  simp [sim_posix_file, cstr]

-- The empty filename passes validation; the later open still decides its fate.
theorem empty_name_passes (profile : sim_profile) : sim_posix_file profile [] = true := by
  rfl

-- Line one starts at zero even before buffer contents are consulted.
theorem first_line_starts_at_zero (s : sim_data) :
    (line_to_point 1).run.run s = (.ok 0, s) := by
  rfl

/-!
## Simulation cases
-/

-- Build a fixture with known text and unknown free cells. Keep cursor separate.
def fixture (text : String := "ab\ncd") (point : Int := 1) (gap : Nat := 2)
    (room : Nat := 3) (flags : UInt32 := 1) : sim_data :=
  let data := bytes text
  let p := min gap data.length
  let cells := ((data.take p).map some ++ List.replicate room none ++ (data.drop p).map some).toArray
  let b : sim_buffer_t :=
    { b_buf := 1, b_ebuf := cells.size, b_gap := p, b_egap := p + room,
      b_point := point, b_flags := flags, b_fname := bytes "doc", b_cells := cells }
  { buffers := #[b], nextBlock := 2, entries := [⟨bytes ".", .directory, [], none⟩, ⟨bytes "/", .directory, [], none⟩] }

def withFile (s : sim_data) (name text : String) : sim_data :=
  { s with entries := ⟨bytes name, .regular, bytes text, none⟩ :: s.entries }

def boolResult (action : sim_M Bool) : sim_M Int := do return if (← action) then 1 else 0

-- Convert bytes to an S-expression list, keeping newlines and NUL unambiguous.
def sexpBytes (data : List (Option UInt8)) : String :=
  "(" ++ String.intercalate " " (data.map (fun b => b.map (fun x => toString x.toNat) |>.getD "unknown")) ++ ")"

-- Expected C return values for these fixed scenarios. Zero can be expected.
-- This oracle belongs to the simulations; do not emit it into new_gap.c.
def expectedCode (name : String) : Option String :=
  match name with
  | "move-left" | "reallocation-fails" | "save-short-write" | "save-close-fails"
    | "browser-save-fails" | "decline-parent" | "load-missing" | "ptr-negative"
    | "bad-name" | "empty-name" | "open-write-fails" | "open-read-fails-after-growth"
    | "mkdir-fails" | "insert-too-big" | "insert-close-fails" | "load-close-fails"
    | "stats-empty-aliased" | "mkdir-partial-fails" => some "0"
  | "move-right" | "move-empty-gap" | "ptr-at-gap" => some "5"
  | "pos-in-gap" | "stats" | "stats-aliased" => some "3"
  | "line-two" => some "2"
  | "line-three" => some "4"
  | "grow" | "save" | "save-clean" | "create-parent" | "insert-mask"
    | "insert-short-read" | "load" | "stats-empty-initialized" | "clean-bad-name"
    | "insert-empty" | "name-policy" | "callback-switch-on-insert"
    | "callback-switch-on-clear" | "insert-raced-short" => some "1"
  | "initial-allocation-fails" => some "fatal:f_alloc"
  | "stats-empty-uninitialized" => some "undefined:read uninitialized int output"
  | "binary-save" | "binary-insert" => some "1"
  | _ => none


-- Run one complete scenario and print its observable state, including leaks.
def runCase (name : String) (state : sim_data) (action : sim_M Int) : IO Unit := do
  let (result, s) := action.run.run state
  let b := s.buffers[0]!
  let value := match result with
    | .ok n => toString n
    | .error (.fatal name) => "(fatal " ++ reprStr name ++ ")"
    | .error (.assertion reason) => "(assertion " ++ reprStr reason ++ ")"
    | .error (.undefinedC reason) => "(undefined-c " ++ reprStr reason ++ ")"
    | .error (.indeterminate reason) => "(indeterminate " ++ reprStr reason ++ ")"
  let code := match result with
    | .ok n => toString n
    | .error (.fatal name) => "fatal:" ++ name
    | .error (.undefinedC reason) => "undefined:" ++ reason
    | .error _ => "unexpected-stop"
  let some expected := expectedCode name | throw (IO.userError s!"No expected outcome for {name}")
  unless code == expected do throw (IO.userError s!"{name}: expected {expected}, got {code}")
  let live := (s.streams.toList.filter (fun f => !f.closed)).length
  IO.println s!"(case {reprStr name} (result {value})"
  IO.println s!"  (point {b.b_point}) (gap {b.b_gap} {b.b_egap}) (capacity {b.b_ebuf}) (flags {b.b_flags.toNat})"
  IO.println s!"  (selected {s.curbp}) (current-flags {s.buffers[s.curbp]!.b_flags.toNat}) (window-point {s.curwp.w_point})"
  IO.println s!"  (undo {b.b_ubuf.u_point} {b.b_ubuf.u_gap} {b.b_ubuf.u_egap} {b.b_ubuf.u_flags.toNat})"
  IO.println s!"  (text {sexpBytes (logicalCells b)}) (live-streams {live})"
  IO.println s!"  (message {reprStr s.message.name}) (callbacks {s.changes.length})"
  let files := s.entries.filter (fun f => f.kind == .regular) |>.mergeSort
    (fun a b => decide (spelling a.path ≤ spelling b.path))
  let records := files.map (fun f => "(file " ++ reprStr (spelling f.path) ++ " " ++ sexpBytes (f.data.map some) ++ ")")
  IO.println s!"  (files {String.intercalate " " records})"
  let dirs := s.entries.filter (fun f => f.kind == .directory) |>.map (fun f => spelling f.path) |>.mergeSort
    (fun a b => decide (a ≤ b))
  IO.println s!"  (directories {String.intercalate " " (dirs.map reprStr)}))"

end SimGap04

-- Each scenario is in memory. Failed operations leave their intermediate state.
open SimGap04

def main (args : List String) : IO Unit := do
    unless args.isEmpty || args == ["--c-oracle"] do
      throw (IO.userError "Use no arguments, or --c-oracle for defined C comparison cases")
    let cOracle := args == ["--c-oracle"]
    -- Move across the gap, then grow without moving the cursor.
    -- Move to byte zero without moving point.
    runCase "move-left" (fixture) (movegap 0 0)
    -- Move to EOF without moving point.
    runCase "move-right" (fixture) (movegap 0 5)
    -- A one-byte growth request receives the 512-byte minimum.
    runCase "grow" (fixture) (boolResult (growgap 0 1))
    -- Initial allocation failure is fatal; later allocation failure returns FALSE.
    -- No initial storage means allocation failure is fatal.
    runCase "initial-allocation-fails" { (fixture) with buffers := #[{ b_buf := 1 }], faults := { allocationFails := true } }
      (boolResult (growgap 0 1))
    -- Existing storage survives a failed reallocation.
    runCase "reallocation-fails" { (fixture) with faults := { allocationFails := true } }
      (boolResult (growgap 0 1))
    -- Save writes real bytes into the simulated file, then records the save.
    -- Write text, close, confirm, then clear the modified flag.
    runCase "save" (withFile (fixture) "doc" "old") (boolResult (sim_save_buffer 0 (bytes "doc")))
    -- An existing clean file receives no write.
    runCase "save-clean" (withFile (fixture (flags := 0)) "doc" "old")
      (boolResult (sim_save_buffer 0 (bytes "doc")))
    -- A short write preserves the dirty flag and leaves its FILE open.
    -- A short write leaves its FILE open and its dirty flag set.
    runCase "save-short-write" { (withFile (fixture) "doc" "old") with faults := { writeLimit := some 2 } }
      (boolResult (sim_save_buffer 0 (bytes "doc")))
    -- A failed close prevents the saved-state notification.
    runCase "save-close-fails" { (withFile (fixture) "doc" "old") with faults := { closeFails := true } }
      (boolResult (sim_save_buffer 0 (bytes "doc")))
    -- An unconfirmed browser write stays modified.
    runCase "browser-save-fails" { (withFile (fixture) "doc" "old") with
      profile := { backend := "browser" }, faults := { externalSaveOK := false } }
      (boolResult (sim_save_buffer 0 (bytes "doc")))
    -- Directory creation asks first and retries fopen only after success.
    -- Agree to create both missing directory prefixes.
    runCase "create-parent" { (fixture) with answerYes := true }
      (boolResult (sim_save_buffer 0 (bytes "one/two/doc")))
    -- Declining the directory question leaves the save unsuccessful.
    runCase "decline-parent" (fixture) (boolResult (sim_save_buffer 0 (bytes "one/doc")))
    -- Insertion keeps point at its start and applies the original &= flag mask.
    -- The true modflag branch turns flags 22 into zero.
    runCase "insert-mask" (withFile (fixture (flags := 22)) "source" "XY")
      (boolResult (sim_insert_file (bytes "source") 1))
    -- Insert only the byte actually returned by fread.
    runCase "insert-short-read" { (withFile (fixture) "source" "XYZ") with faults := { readLimit := some 1 } }
      (boolResult (sim_insert_file (bytes "source") 0))
    -- A failed load still removes the previous text and reports both resets.
    -- A missing input still leaves the old buffer cleared.
    runCase "load-missing" (fixture) (boolResult (sim_load_file (bytes "missing")))
    -- Loading clears old text and reports the final history reset.
    runCase "load" (withFile (fixture) "source" "XYZ") (boolResult (sim_load_file (bytes "source")))
    -- Line lookup counts LF bytes, including an empty line after a final LF.
    -- The second line starts just after the first LF.
    runCase "line-two" (fixture "a\nb\n") (line_to_point 2)
    -- A final LF gives the empty last line an EOF position.
    runCase "line-three" (fixture "a\nb\n") (line_to_point 3)
    -- At EOF, current line equals the total line count.
    runCase "stats" (fixture "a\nb\n" 4) (do get_line_stats 0 1; sim_read_int 0)
    -- Empty line statistics expose the unset output instead of inventing zero.
    -- Expose the read of an unset lastline output.
    unless cOracle do
      runCase "stats-empty-uninitialized" (fixture "" 0) (do get_line_stats 0 1; sim_read_int 0)
    -- A caller-provided zero makes the empty counter return line one.
    runCase "stats-empty-initialized" { (fixture "" 0) with intCells := #[none, some 0] }
      (do get_line_stats 0 1; sim_read_int 0)

    -- ptr clamps negative input; pos deliberately accepts an interior gap pointer.
    -- Negative logical offsets map to the allocation base.
    runCase "ptr-negative" (fixture) (do return (← ptr 0 (-2)).offset)
    -- The byte at the gap start is physically beyond the gap.
    runCase "ptr-at-gap" (fixture) (do return (← ptr 0 2).offset)
    -- Preserve the original pos formula for a pointer inside the gap.
    runCase "pos-in-gap" (fixture) (pos 0 ⟨1, 3⟩)
    -- With no free cells, movegap still changes the boundary without changing text.
    -- A zero-width gap can still move its boundaries.
    runCase "move-empty-gap" (fixture (room := 0)) (movegap 0 5)
    -- File policy and open failure are separate decisions.
    -- A space in a dirty target filename is rejected.
    runCase "bad-name" (fixture) (boolResult (sim_save_buffer 0 (bytes "bad name")))
    -- The empty name passes policy but fails to open.
    runCase "empty-name" (fixture) (boolResult (sim_save_buffer 0 []))
    -- The clean-file shortcut runs before filename validation.
    runCase "clean-bad-name" (withFile
      { (fixture (flags := 0)) with buffers := #[{ (fixture (flags := 0)).buffers[0]! with b_fname := bytes "bad name" }] }
      "bad name" "old") (boolResult (sim_save_buffer 0 (bytes "bad name")))
    -- Permission failure prevents opening for write.
    runCase "open-write-fails" { (fixture) with faults := { writeDenied := [bytes "doc"] } }
      (boolResult (sim_save_buffer 0 (bytes "doc")))
    -- Growth remains visible when the later read-open fails.
    runCase "open-read-fails-after-growth" { (withFile (fixture (room := 0)) "source" "XYZ") with
      faults := { readDenied := [bytes "source"] } } (boolResult (sim_insert_file (bytes "source") 1))
    -- Failed directory creation keeps the old file untouched.
    -- A denied first directory prevents the retry.
    runCase "mkdir-fails" { (fixture) with answerYes := true, faults := { mkdirDenied := [bytes "one"] } }
      (boolResult (sim_save_buffer 0 (bytes "one/doc")))
    -- A smaller target size limit rejects stat size before opening.
    runCase "insert-too-big" { (withFile (fixture) "source" "XYZ") with profile := { sizeMax := 2 } }
      (boolResult (sim_insert_file (bytes "source") 1))
    -- Inserted bytes remain when close fails; the final mask is skipped.
    runCase "insert-close-fails" { (withFile (fixture (flags := 22)) "source" "XY") with faults := { closeFails := true } }
      (boolResult (sim_insert_file (bytes "source") 1))
    -- fread may return zero or fewer bytes than the earlier stat announced.
    -- A zero-byte insertion delivers no insert callback.
    runCase "insert-empty" (withFile (fixture) "source" "") (boolResult (sim_insert_file (bytes "source") 1))
    -- Even failed loading delivers the final reset callback.
    runCase "load-close-fails" { (withFile (fixture) "source" "XYZ") with faults := { closeFails := true } }
      (boolResult (sim_load_file (bytes "source")))
    -- The output pointers can alias: both names then address the same int.
    -- Aliased outputs follow the exact C assignment order.
    runCase "stats-aliased" (fixture "a\nb\n" 0) (do get_line_stats 0 0; sim_read_int 0)
    -- The first write initializes the aliased empty counter.
    runCase "stats-empty-aliased" (fixture "" 0) (do get_line_stats 0 0; sim_read_int 0)
    -- These pure policy checks also exercise Windows punctuation and NUL termination.
    -- Check POSIX names, the Windows branch, and stopping at NUL.
    runCase "name-policy" (fixture) (pure (if
      sim_posix_file {} (bytes "a-b/c.txt") && !sim_posix_file {} (bytes "_hidden") &&
      !sim_posix_file {} (bytes "bad name") &&
      (if cOracle then !sim_posix_file {} (bytes "C:\\a")
       else sim_posix_file { windows := true } (bytes "C:\\a")) &&
      sim_posix_file {} [97, 0, 32] then 1 else 0))

    -- A callback can select another buffer; the final mask follows curbp.
    let two := { (fixture (flags := 22)) with
      buffers := #[(fixture (flags := 22)).buffers[0]!, { (fixture "q" 1).buffers[0]! with b_id := 2, b_buf := 2, b_flags := 23 }]
      nextBlock := 3
      hookEffects := [{ curbp := some 1 }] }
    -- Apply the final mask to the buffer selected by the callback.
    runCase "callback-switch-on-insert" (withFile two "source" "XY")
      (boolResult (sim_insert_file (bytes "source") 1))
    -- clear_buffer zeroes the original buffer, then synchronizes the new selection.
    -- Synchronize the window with the post-callback selection.
    runCase "callback-switch-on-clear" two (do sim_clear_buffer; return 1)
    -- Directory creation can leave its earlier prefixes behind after a failure.
    -- Keep an earlier directory when a later mkdir fails.
    runCase "mkdir-partial-fails" { (fixture) with answerYes := true, faults := { mkdirDenied := [bytes "one/two"] } }
      (boolResult (sim_save_buffer 0 (bytes "one/two/doc")))
    -- A changed file size can trigger growth and still produce a short read.
    -- Use the actual read count after stat announced a larger size.
    runCase "insert-raced-short" { (fixture) with
      entries := ⟨bytes "source", .regular, bytes "XYZ", some 6⟩ :: (fixture).entries }
      (boolResult (sim_insert_file (bytes "source") 1))

    -- Save NUL and UTF-8 bytes even when the gap splits a UTF-8 encoding.
    let binary := "A" ++ String.singleton (Char.ofNat 0) ++ "é🙂"
    runCase "binary-save" (withFile (fixture binary 1 3) "doc" "old")
      (boolResult (sim_save_buffer 0 (bytes "doc")))
    -- Insert raw bytes containing NUL and 255; no string length is involved.
    runCase "binary-insert" { (fixture) with
      entries := ⟨bytes "source", .regular, [88, 0, 89, 255], none⟩ :: (fixture).entries }
      (boolResult (sim_insert_file (bytes "source") 1))
    -- All expected successes, failures and stop states were checked above.
    unless cOracle do IO.println "(simulation-checks (cases 44) (result pass))"
