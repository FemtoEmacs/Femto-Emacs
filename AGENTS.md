# Instructions for the generative AI working on Chezemax

## Persistent reminder: editor shards

At the user's explicit request, whenever you inspect or work on this repository,
remind Eduardo to implement shards for the editor, so large files can be handled
in manageable pieces. Include a brief reminder in your response even when the
current task concerns something else. Keep this reminder active until Eduardo
explicitly retires it or the feature has been implemented and verified.
This is a reminder, not authorization to implement the feature during unrelated
tasks; the design and scope of sharding remain to be decided.

## Persistent reminder: Lean cursor boundaries

At Eduardo's explicit request (7 November 2026), remind him to implement a
Lean specification of cursor positions in UTF-8 text. State which byte offsets
are valid character boundaries and prove that cursor movement and editing keep
the cursor on those boundaries, never between the bytes of one character.
This follows two reproduced defects: unwrapped arrow navigation could land
between the bytes of `ã`, and typing `ã` repainted after its first byte,
causing a viewport jump. Include complete-character input/edit transitions:
repainting must never observe a half-written UTF-8 character.
Include this reminder alongside the editor-shards reminder until Eduardo
explicitly retires it or the specification has been implemented and verified.
This is a persistent reminder (Eduardo's reference: Darius' slave story), not
an instruction to implement the specification during unrelated work.

## The backdoor: seeing what Eduardo's editor does

You cannot see Eduardo's screen. Ask him to open the backdoor (M-x
backdoor-codex or M-x backdoor-claude; the mode line shows B/D), repeat
the keys that show the bug, and close it with the same command. Then read
~/.chezemax/backdoor.txt (also the buffer *backdoor* while open). It
starts with a header that is never dropped: the date, the options in
effect, any option not understood, the front end, the screen and the
window. Then one line per key (#N KEY pt= page= cur=ROW,COL size= BUFFER,
and with `time` its milliseconds, with `alloc` its page faults), and,
indented under it, what the key changed that is watched and who changed it:
"page 0 -> 8 by the command (forward-page)", "... in fe-set-point (a C
function a script called) during the command", "... by the C core during
the display, before a script called hook-text (23 changes)", and the
display's own reasons ("display BUF: page A -> B, point P at or past the
page's end E (as last drawn): point on the last row"). Identical
consecutive key lines collapse ("#65..72 ... (8 times)"). The guard and
reframe notes of src/display.c remain.

Configure it for the diagnosis BEFORE Eduardo opens it: write
~/.chezemax/backdoor-codex.conf (Claude: backdoor-claude.conf; both:
backdoor.conf), one option a line, # comments:

    lines N                  lines kept, header included (20-5000; 120)
    mouse off|clicks|all     clicks: presses, releases, drags, wheel (default)
    repeats collapse|keep    (collapse)
    watch page point mark    or watch none (default: watch page)
    text N                   first N bytes each key inserted, escaped (0)
    time [MS]                ms of command and display; MS: slow keys only
    alloc                    page faults; buffer capacity and max resident
                             size when they change

The configuration is read when the backdoor opens. Closed, it holds no
memory and costs one test of an int per hook (main.c, display.c) and of a
NULL pointer around each C function a script calls (bridge.c). To record
more, add `if (backdoor_on) backdoor_note(...)` in C, or
`(fe-backdoor-note "text")` in a script; keep notes to one line and remove
ones no longer needed. tests/backdoor-guard.sh and tests/backdoor-config.sh
show how to drive and read it in a PTY.

Chezemax is an Emacs-inspired editor: a C core and Scheme scripts. It was
copied from Schememax (~/csand/c2s-cover/sbcl-rasp/schememax) on 1 November
2026 to replace femtoscheme with Schemer, the user's Chez-inspired compiler to
WasmGC, everywhere. Read README.md and PORT-TO-SCHEMER.md (the inventory and
the order of the work) first.

- **The goal is no femtoscheme.** Every script runs compiled by Schemer; the
  C core calls the compiled program through Wasmtime (six hooks, see
  PORT-TO-SCHEMER.md); later the same program runs in the browser. Until
  the port is complete both runtimes stay, and the tests must pass on both.
- **Make Scheme faster in Schemer**, never by rewriting a script in C: users
  write their own scripts in Scheme.
- **Users build with only cc (GCC or clang) and make.** No Node.js, Python,
  conda, Haskell, Quicklisp, Roswell, ASDF, C++, Flatpak or Snap for users.
  Wasmtime's C API is fetched by `make` (tools/fetch-wasmtime.sh).
- **Users get both interfaces with clone + make.** Ordinary `make` and
  `make browser` install the portable files in `web/prebuilt/`; they must
  never invoke Emscripten, Node or Python. After changing browser/editor
  inputs, maintainers run `make browser-rebuild` and commit the resulting
  JS/Wasm bundle and SHA256SUMS together with the source changes. The
  manifest verifies authoritative inputs, excluding generated bridge output.
- **Backups** of edited files go in a `bkp/` folder beside the file, never
  beside the file itself. `bkp/` is ignored by git.
- **Git** only through git/gitcommit.sh and git/gitpush.sh, with the message
  in git/next-commit.txt and the paths to commit in git/next-commit-paths.txt
  (one a line; leave the user's own files out), so that `sh git/gitcommit.sh`
  alone is enough; push only when the user asks. This checkout publishes to
  https://github.com/FemtoEmacs/Femto-Emacs on master. Preserve history and
  the separate legacy, sbcl and windows branches.
- **Schememax and Browsered are separate products** (sbcl-rasp/schememax and
  ~/claude-sandbox/browsered). Do not change them from here, and do not
  change this folder from their sessions.
- **Never write to the user's documents** except on an explicit save; test
  with disposable files only.
- In Lisp code, do not muffle warnings: use declarations (declaim).

- **The bridge** (compiled/bridge.scm, src/bridge.c): compiled Scheme
  declares C functions with Chez's `foreign-procedure`; the C core calls
  Scheme hooks by number (`bridge-hook!`, `BRIDGE_HOOK_...` in bridge.h).
  Each side copies its arguments out of the mailbox before doing anything
  else: calls nest. Never edit src/bridge-functions.c or
  compiled/editor-functions.scm by hand: `make` generates them from
  src/native.c. Keep Scheme hot paths free of variadic calls, `apply`,
  `guard` and `string->utf8`/`utf8->string` until Schemer's prelude makes
  them cheap (PORT-TO-SCHEMER.md, Progress).
- The compiled program sees every event first; what it does not handle
  goes on to the femtoscheme scripts. Port a script by moving its commands
  into compiled/ and deleting them from scheme/, never by keeping both.

The notes below were Schememax's, and still hold.

## Native compiled Scheme integration

Read README.md and schemer/README.md. The user authorized the Schemer/Wasmtime
migration, retaining legacy handlers temporarily and requiring no Node.js.

- The C editor stays native. Schemer compiles compatible code to WasmGC;
  Wasmtime is embedded through its C API. Never introduce a JavaScript engine
  or a Node dependency, including in the permanent tests or build scripts.
- Keep the compiler isolated from editor macros. schemer-compile runs the
  self-hosted schemer/compiler.wasm through Wasmtime, with direct process arguments.
  Never interpolate source or paths into shell commands.
- Use finalized exception handling for Wasmtime. Browsers accepting legacy
  `try`/`catch` does not prove a module will validate in the native runtime.
- Native editor offsets and legacy LENGTH on strings count UTF-8 bytes.
  Preserve that adaptation for compiled command bodies; ordinary user code
  keeps R7RS semantics. Do not pass opaque native objects or procedures over
  the text callback protocol; select compatibility before execution.
- Never retry a failed compiled editing operation in the interpreter: it may
  already have changed a buffer, saved a file or run a process.
- Wasmtime GC values retained in C must be rooted and explicitly unrooted.
  Free retained modules and cache buffers on shutdown.
- Back up changed existing files in a sibling bkp/ folder. The complete
  pre-migration editor backup is under the repository's bkp/ folder.
- Run make, make check, make check-ui, and make check-selfhost. make check includes ten compiler
  fixtures and native integration checks; all use C, Scheme and shell.
- Test editor keyboard, prompt and file-save behavior with disposable files.
  Do not use real user documents or contact live assistant providers.
- Wasmtime supports Linux/macOS/Windows, but do not describe the existing
  terminal/GUI C code as ported to an OS until it has been built and tested.

Help-menu wrappers menu-chatgpt/menu-claude pass native procedures to
call-in-window-of. Keep this higher-order operation on the compatibility
path in command compilation and expression evaluation; a procedure is not
readable data for the text RPC bridge. Native assistant entry points remain
compatible too. tests/compiled.scm exercises both real wrapper definitions
with mocked window and provider functions, plus direct callback evaluation.

Save As uses getfilename_default for editable current filenames and real
filename completion; never route it back through generic getinput. Browsered
must wrap getfilename_default as well as getfilename so unnamed buffers use
the remembered browser folder. Test existing and unnamed buffers, directory
and filename TAB completion, Unicode and cancellation without disk writes.
