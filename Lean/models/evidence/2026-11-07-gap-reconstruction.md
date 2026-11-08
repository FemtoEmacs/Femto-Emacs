# Gap reconstruction verification — 7 November 2026

Source: `src/stub-gap.c`. Output: `src/reconstructed-gap.c`.
Only the two procedure declarations were replaced by definitions; `<stdint.h>`
was added for checked size arithmetic. The rest of the template is identical.
Production `src/gap.c`, the template, and `cp-of-gap.c` were not edited.

- Lean calculator: eight theorems and eleven simulations pass.
- C: 297,297 buffer checks pass under AddressSanitizer and UndefinedBehaviorSanitizer.
- Exhaustive small layouts: text length 0–24, gap size 0–12, every gap position
  and valid destination. Growth is checked before and after returning to the
  original position; realloc is forced to return a different allocation.
- A 10,000-step deterministic sequence covers all 256 byte values and repeated growth.
- Allocation failures, unchanged metadata, unchanged failed-allocation contents,
  overflow rejection, NULL initial state and all six allocation paths are checked.
- A disposable source copy overrides MAX_SIZE_T with test_limit to reach initial
  size rejection without requesting huge memory. The production output has no override.
- All 43 defined observations in the earlier C comparison suite match byte for
  byte, including callers that save, load, insert, and calculate line information.
- Compilation emits three sign-comparison warnings in untouched template code;
  none originates in the two reconstructed bodies.

Run the saved focused test on macOS from the repository root:

```sh
cc -std=c11 -g -fsanitize=address,undefined -ffunction-sections -fdata-sections \
  -Isrc Lean/models/evidence/gap_bp-reconstruction-check.c \
  -Wl,-dead_strip -o /tmp/gap-bp-check
/tmp/gap-bp-check
```

The test's zero-length allocated fixture is moved but not grown; allocation
starts from the all-NULL state. Growth otherwise assumes a positive-length owned
allocation. This matches the editor's initial allocation convention.
Invalid movement offsets assert in debug builds. In release builds they leave
the buffer unchanged and return its current gap position (zero for NULL state).
This explicitly extends the calculator's none case. Overflow requests similarly
use the existing allocation-failure outcomes rather than overflowing C arithmetic.

This saves a candidate module; the editor build still uses its existing src/gap.c.

SHA-256 reconstructed-gap.c: 375a8efe2e3fb0f66f6d1b022fe49186fbaf57f06000d327683ac2e94f27fd0e
