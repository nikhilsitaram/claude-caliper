# A1 Completion Notes

## What was implemented

1. **Extracted `do_consistency()` from `do_schema()`** — Moved the two existing status consistency checks (phase-complete-with-incomplete-tasks, plan-complete-with-incomplete-phases) into a new `do_consistency()` function. Added 4 new rules:
   - Rule 1: Phase "Not Started" but has tasks in_progress/complete
   - Rule 3: Task complete but dependency is pending/in_progress
   - Rule 4: Plan "Not Yet Started" but has phases In Progress/Complete
   - Rule 6: Phase Complete without passing impl-review record

2. **`integration_branch` schema validation** — Optional field; validated as non-empty string if present.

3. **`do_check_entry()`** — Stage entry gate checking design-review (draft-plan) or both design+plan reviews (execution).

4. **`do_check_base()`** — Branch validation: with integration_branch, current branch must match; without, rejects main/master.

5. **CLI wiring** — `--consistency`, `--check-entry`, `--check-base`, `--stage` flags with case dispatch.

6. **`--schema` chains to `do_consistency()`** — Existing callers get full coverage.

## Test changes

- Updated `test_status_consistency.sh` tests 1, 3, 5, 8 to set consistent plan/phase statuses and provide reviews.json where needed (new consistency rules exposed previously-implicit state inconsistencies in test fixtures).
- Created 4 new test files: `test_consistency.sh` (10 tests), `test_check_entry.sh` (8 tests), `test_check_base.sh` (5 tests), `test_integration_branch.sh` (4 tests).

## Deviations

None. Implementation matches spec exactly.
