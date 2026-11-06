# Optional research tooling; ordinary editor make does not invoke Lean.
LEAN ?= lean
LEANC ?= leanc
.PHONY: all proof check clean
all: chez-tester
proof:
	$(LEAN) rdonly-tester.lean
	$(LEAN) mv-cp-mv-paste-undo.lean
	$(LEAN) search-return.lean
.build/chez-tester.c: rdonly-tester.lean
	mkdir -p .build
	$(LEAN) -c $@ $<
chez-tester: .build/chez-tester.c
	$(LEANC) -O2 -o $@ $<
check: proof chez-tester
	sh tests/check.sh
clean:
	rm -rf .build chez-tester
.PHONY: native-check audit
native-check: chez-tester
	sh tests/native.sh
audit:
	mkdir -p .build
	cat rdonly-tester.lean > .build/audit.lean
	printf '\n#print axioms ChezTester.complete_sound\n#print axioms ChezTester.batch_append\n#print axioms ChezTester.feed_preserves\n#print axioms ChezTester.fixed_disk_bound\n#print axioms ChezTester.recycle_requires_ack\n#print axioms ChezTester.text_step_sound\n#print axioms ChezTester.text_progress\n#print axioms ChezTester.text_pass_requires_eof\n#print axioms ChezTester.text_feed_pending_bound\n'  >> .build/audit.lean
	$(LEAN) .build/audit.lean

.PHONY: edit-audit edit-check
edit-audit:
	mkdir -p .build
	cat mv-cp-mv-paste-undo.lean > .build/edit-audit.lean
	printf '\n#print axioms EditStress.movement_in_file\n#print axioms EditStress.byte_position_in_file\n#print axioms EditStress.selection_bound\n#print axioms EditStress.paste_undo_identity\n#print axioms EditStress.thousands_preserve_text\n#print axioms EditStress.any_schedule_preserves\n#print axioms EditStress.small_region_bytes\n#print axioms EditStress.checker_sound\n' >> .build/edit-audit.lean
	$(LEAN) .build/edit-audit.lean
edit-check: proof edit-audit
	sh tests/edit.sh

.PHONY: search-audit search-check
search-audit:
	mkdir -p .build
	cat search-return.lean > .build/search-audit.lean
	printf '\n#print axioms SearchReturn.movement_in_file\n#print axioms SearchReturn.byte_position_in_file\n#print axioms SearchReturn.substring_in_file\n#print axioms SearchReturn.query_nonempty\n#print axioms SearchReturn.query_bytes_bounded\n#print axioms SearchReturn.reference_hit_matches\n#print axioms SearchReturn.search_position_in_file\n#print axioms SearchReturn.any_schedule_preserves\n#print axioms SearchReturn.checker_sound\n#print axioms SearchReturn.accepted_preserves\n#print axioms SearchReturn.fixed_report_bound\n' >> .build/search-audit.lean
	$(LEAN) .build/search-audit.lean
search-check: proof search-audit
	sh tests/search.sh
