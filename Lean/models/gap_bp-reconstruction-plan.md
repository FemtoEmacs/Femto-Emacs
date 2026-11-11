# Reconstructing the two gap procedures

Read this together with `gap_bp-calculator.lean`. Supply both files to the AI,
plus the C framework and its `header.h`. The deleted bodies are not needed.
This is a reconstruction recipe. Do not generate or install C yet.

## Interface and representation

Keep these heads and the existing ABI:

```c
int growgap(buffer_t *bp, point_t n);
point_t movegap(buffer_t *bp, point_t offset);
```

Use the framework's `char_t` (unsigned char), `point_t` (signed long),
`MIN_GAP_EXPAND` (512), `MAX_SIZE_T`, `TRUE`, and `FALSE`.
Use its declarations of `fatal(f_alloc)` and `msg(m_alloc)`.
Include the standard declarations needed for allocation, limits and `memmove`.
Do not add fields to `buffer_t` or change other framework procedures.

The correspondence is:

```sexpr
(buffer
  (left  "bytes [b_buf,b_gap)")
  (gap   "b_egap - b_gap")
  (right "bytes [b_egap,b_ebuf)")
  (extra "every other buffer_t field; unchanged")
  (base "b_buf is the allocation base")
  (end  "b_ebuf is one past the allocation"))
```

Bytes are counted, including NUL and non-ASCII bytes. Never use `strlen`.
The gap's unused bytes have no specified value. Preserve text, not those bytes.
Valid allocated pointers belong to one allocation and satisfy
`b_buf <= b_gap <= b_egap <= b_ebuf`. The initial unallocated state has all
four pointers NULL. Handle that state before pointer subtraction or comparison.
Save numeric offsets before realloc; old pointers cannot be used afterward.

## Restore the allocation dummy

The dummy's three answers expand into six paths:

```sexpr
(allocation
  (initial
    (size-rejected "fatal(f_alloc); no allocation")
    (allocator-null "malloc(newlen); fatal(f_alloc)")
    (success "malloc(newlen); continue"))
  (existing
    (size-rejected "msg(m_alloc); return FALSE; bp unchanged")
    (allocator-null "realloc; msg(m_alloc); return FALSE; bp unchanged")
    (success "realloc preserves old allocation bytes; continue")))
```

Initial means old allocation length is zero, not merely empty text.
A textually empty buffer may already have an allocation.
Store malloc/realloc's result in a temporary. Never overwrite `b_buf` on failure.
Fatal terminates execution; FALSE returns normally. Do not merge these outcomes.
Check the requested sum against point_t's positive range and MAX_SIZE_T before
performing potentially overflowing arithmetic or narrowing to size_t.
Treat an unrepresentable request as size-rejected. This supplies a defined
failure policy where the old C arithmetic could overflow.

## Reconstruct growgap

1. Record old allocation length L, gap start G, gap end E, and suffix length R=L-E.
   For the initial NULL state these are all zero.
2. Calculate A=max(n,MIN_GAP_EXPAND). Negative n therefore still requests 512.
   A is additional space, not the desired total gap size.
3. Obtain L+A bytes using the allocation rules above. Do not change bp on failure.
4. Within the returned allocation, move R bytes from offset E to offset E+A.
   Use `memmove`, or copy backward from the suffix's end. These regions may overlap.
   Skip a zero-length move. Preserve the prefix at offsets [0,G).
5. Set the four pointers to new base, base+G, base+E+A, and base+L+A,
   assigning b_buf, b_gap, b_egap, and b_ebuf respectively. Return TRUE.

The resulting gap has its old size plus A. Logical text and gap position are
unchanged. No other buffer field, including the cursor, is updated.

## Reconstruct movegap

Accept a valid logical offset P in [0,text length]. The model's `none` represents
an invalid request; it is not a point_t return value. Do not silently translate
it into zero or an EOF clamp. An invalid-input C policy must be chosen separately
before integration; equivalence here concerns valid offsets.

Let G=b_gap-b_buf, E=b_egap-b_buf, and H=E-G.
For the all-NULL empty buffer, the only valid offset is zero: return zero unchanged.

```sexpr
(movement
  (P-less-than-G
    (count "G-P")
    (copy "memmove(base+P+H, base+P, count)"))
  (P-greater-than-G
    (count "P-G")
    (copy "memmove(base+G, base+E, count)"))
  (P-equals-G (copy none))
  (finish "b_gap=base+P; b_egap=base+P+H; return P"))
```

Copy before updating the boundaries. Keep b_buf, b_ebuf, all other fields and
allocation ownership unchanged. A zero-size gap is valid; its copy can be skipped.
No allocation, insertion, deletion, cursor update or editor callback belongs here.
This implements the calculator's take/drop transition without creating lists.
The retained framework's ptr and pos need not be called or rewritten.

## Restore assertions and check the translation

Restore growgap's three entry assertions and four success assertions, and
movegap's three exit assertions for allocated buffers. The predicates are the
pointer ordering above; growth additionally requires b_buf<b_ebuf and
b_gap<b_egap. Handle the initial NULL state explicitly rather than asserting
relational order between NULL pointers. Assertions do not replace overflow checks.

The calculator proves laws of the pure transition. The C translation must also
realize those transitions: matching signatures alone is insufficient.
Compare projected C results with the calculator for every small text, every gap
position and size, and every valid target. Compare all text bytes and unrelated
fields. Exercise both overlapping copy directions, zero gap, BOF, EOF, growth
with and without a suffix, negative n, and repeated growth/movement.
Inject all six allocation paths; check unchanged state on FALSE and fatal exit
in a separate process. Force realloc to move the allocation. Run memory and
undefined-behavior checks on disposable test buffers before replacing any module.
