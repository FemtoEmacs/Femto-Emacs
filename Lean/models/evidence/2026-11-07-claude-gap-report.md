# How good were the instructions? (gap reconstruction, 7 November 2026)

Claude rebuilt growgap and movegap into src/claudes-reconstructed-gap.c from
gap_bp-calculator.lean, gap_bp-reconstruction-plan.md and src/stub-gap.c
only. It did not read src/cp-of-gap.c, src/reconstructed-gap.c, the other
reconstruction notes or chezmoi's src/gap.c.

## Result

- evidence/04-simgap-c-check.c: output identical to
  evidence/2026-11-06-04-simgap-c.sexp, all 41 cases, on the first build,
  under AddressSanitizer and UBSan.
- evidence/claudes-gap-exhaustive-check.c, written from the plan's last
  section: 18,302 checks against the calculator's rules, 0 failures; three
  deliberately broken versions are caught.

## Verdict: very good; enough to write the code without the original

- The plan answers the questions an implementer would otherwise guess:
  the pointer/offset correspondence, initial = allocation length zero (not
  empty text), the six allocation paths and which are fatal, a temporary for
  realloc, saving offsets before realloc, the exact memmove source,
  destination and count for both directions, copy before updating
  boundaries, and the assertions to restore.
- The Lean file is small and its theorems (text preserved, gap position
  kept, rejection leaves the buffer intact, movement composes) translate
  directly into test properties.

## Gaps

1. Offsets outside [0, length] are explicitly left undecided. The C code
   therefore does nothing about them; a negative or past-EOF offset reaches
   memmove out of bounds.
2. A non-NULL allocation of length zero (as 04-simgap-c-check.c builds) is
   "initial": malloc gets a new block and the old one is abandoned. Neither
   file says so; it leaks unless the caller frees it.
3. The framework to compile against is underspecified: header.h needs
   screen.h, public.h and the other src/*.h, and the stub calls functions
   (screen_save_file, screen_backend) that only this framework has.
4. The test conventions live only in the test's comment: the plan does not
   mention 04-simgap-c-check.c, its expected .sexp, or that a test copy must
   replace MAX_SIZE_T by test_size_max.
5. The plan's verification section asks for exhaustive comparison but
   supplies no harness; writing one is real work (Claude's own harness had
   three bugs of its own before it agreed with itself).
6. The plan opens with "Do not generate or install C yet", which contradicts
   the task it was given for.
