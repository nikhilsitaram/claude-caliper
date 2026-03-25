# A3 Completion: Wire gh mock into test_check_workflow.sh

## Changes

Modified `tests/validate-plan/test_check_workflow.sh`:

1. **Mock PATH setup (preamble):** Added `MOCK_BIN` temp directory, symlinked `gh-mock.sh` as `gh`, prepended to PATH. Updated trap to clean up both `TMPDIR` and `MOCK_BIN`.

2. **Test 7 (pr-merge):** Removed `command -v gh` skip guard. Now runs unconditionally with `GH_MOCK_PR_COUNT=0` prefix so the mock returns zero PRs.

3. **Test 9 (single-phase pr-create):** Removed `command -v gh` skip guard. Preserved git init/pushd/popd/cleanup logic. Added `GH_MOCK_PR_COUNT=0` prefix.

## Test Results

All 11 tests pass, 0 failures, no SKIP lines, zero network calls.

```
Results: 11 passed, 0 failed
```

## Files Changed

- `tests/validate-plan/test_check_workflow.sh` (21 insertions, 26 deletions)
