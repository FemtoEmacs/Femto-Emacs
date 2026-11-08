# Gap buffer calculator

1. Study `growgap`, `movegap`, `ptr`, and `pos` in `src/cp-of-gap.c`.
2. Model the allocated bytes and four buffer pointers as bytes and offsets.
3. Keep unrelated `buffer_t` fields unchanged; state valid-input conditions.
4. Define the text as the bytes before the gap followed by those after it.
5. Write pure `ptr` and `pos` calculations for logical and physical positions.
6. Write `growgap_model(bp, n)` returning a result and a new buffer state.
7. Write `movegap_model(bp, offset)` returning a position and a new buffer state.
8. Keep the input state unchanged; represent allocation success or failure explicitly.
9. Separate allocation outcomes from the calculation that relocates the suffix.
10. Prove pointer ordering, text preservation, and preservation of unrelated fields.
11. Prove growth preserves the gap position and increases its size as requested.
12. Prove movement preserves gap size and places it at the requested valid offset.
13. Explain each definition, proof, and simulation in short English comments.
14. Simulate empty buffers, boundary positions, both movement directions, and growth.
15. Exclude insertion, deletion, file handling, undo, and terminal behavior.
16. Postpone destructive C translation and macros until the calculator is sound.
