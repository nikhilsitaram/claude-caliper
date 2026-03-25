# Design: Improve validate-plan test suite speed

## Problem

The validate-plan test suite has two performance bottlenecks:

1. **Nested regression suites** — `test_check_review.sh` (Test 12) and `test_review_gates.sh` (Test 11) each re-run entire other test suites (`test_schema.sh`, `test_update_status.sh`) as "still passes" regression checks. This doubles process forks and is redundant when CI already runs all test files independently.

2. **Network calls in workflow tests** — `test_check_workflow.sh` hits GitHub's API via `gh pr list` for PR existence checks (Tests 7, 9), adding ~4-5s of network latency and making tests flaky when auth/network is unavailable.

**Who's affected:** Anyone iterating locally on validate-plan — the full suite takes ~42s sequentially, with ~16s attributable to these two issues.

**Consequences of not solving:** Slower local iteration loops. Tests 7/9 in `test_check_workflow.sh` silently skip when `gh` isn't available, meaning those code paths go untested in some environments.

## Goal

Reduce total test suite runtime by ~40% and eliminate network dependencies, making all tests run unconditionally in any environment.

## Success Criteria

1. `test_check_review.sh` no longer invokes `test_schema.sh` or `test_update_status.sh` — its runtime drops from ~11s to <1s.
2. `test_review_gates.sh` no longer invokes `test_update_status.sh` — its runtime drops from ~1.6s to <1.2s.
3. `test_check_workflow.sh` makes zero network calls — runs with a `gh` mock stub that returns controlled responses.
4. Tests 7 and 9 in `test_check_workflow.sh` run unconditionally (no `command -v gh` skip guards).
5. All 14 test files still pass after changes.

## Architecture

### Change 1: Remove nested regression checks

Delete:
- `test_check_review.sh` lines 125-127 (Test 12: re-runs `test_schema.sh` and `test_update_status.sh`)
- `test_review_gates.sh` lines 153-154 (Test 11: re-runs `test_update_status.sh`)

No replacement needed — CI runs all test files independently.

### Change 2: Mock `gh` in workflow tests

Create a stub script `tests/validate-plan/fixtures/gh-mock.sh` that:
- Intercepts `gh pr list` calls (recognized = `$1` is `pr` and `$2` is `list`; all other args ignored)
- Reads `GH_MOCK_PR_COUNT` env var (default: `0`) to control the return value
- Returns the count as bare integer on stdout (mimicking `--jq 'length'` output)
- Returns exit 0 on recognized commands, exit 1 on unrecognized (any non-`pr list` invocation)

`test_check_workflow.sh` will:
1. Create a temp directory with a symlink `gh` → `gh-mock.sh`
2. Prepend that directory to `PATH` so `gh` resolves to the mock
3. Remove all `command -v gh` skip guards — tests run unconditionally
4. Set `GH_MOCK_PR_COUNT` per-test to control PR existence scenarios

**Note:** Test 9 (lines 207-222) wraps a temporary git repo setup inside the skip guard block — this controls the branch name for `validate-plan`'s `git rev-parse`. Only the `command -v gh` conditional and SKIP echo should be removed; the git init, pushd/popd, and cleanup logic must be preserved.

## Key Decisions

1. **Stub script vs inline function** — A separate stub script is cleaner than exporting a bash function, since `gh` is invoked as a subprocess by validate-plan. The stub must be an executable file on `PATH`.
2. **Environment variable control** — `GH_MOCK_PR_COUNT` is the simplest interface. Tests that need "PR exists" set it to `1`; tests that need "no PR" use the default `0`.
3. **No changes to validate-plan itself** — The script under test doesn't change. Only test files and fixtures change.

## Non-Goals

- Speeding up `test_schema.sh` itself (it's legitimately ~10s due to 27 tests with jq invocations — a separate optimization)
- Parallelizing the test suite (could use `xargs -P` but that's a different issue)
- Adding a CI runner or test harness

## Implementation Approach

Single phase — three independent tasks:
1. Remove nested regression tests from `test_check_review.sh` and `test_review_gates.sh`
2. Create `gh` mock stub fixture
3. Update `test_check_workflow.sh` to use the mock and remove skip guards
