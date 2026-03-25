# A1 Completion Notes

**Summary:** Removed nested regression test invocations from test_check_review.sh (Test 12, which re-ran test_schema.sh and test_update_status.sh) and test_review_gates.sh (Test 11, which re-ran test_update_status.sh). Both files now run only their own tests.
**Deviations:** None — plan followed exactly.
**Files Changed:** tests/validate-plan/test_check_review.sh, tests/validate-plan/test_review_gates.sh
**Test Results:** test_check_review.sh: 11 passed, 0 failed. test_review_gates.sh: 11 passed, 0 failed.
**Deferred Issues:** None.
