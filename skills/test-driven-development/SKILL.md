---
name: test-driven-development
description: Use when implementing any feature or bugfix, before writing implementation code
---

# Test-Driven Development

Write tests first, then make them pass. The cycle: Red (failing test) → Green (minimal code to pass) → Refactor (clean up).

**Why TDD for LLMs:** You optimize for coherent, plausible-looking code. Tests catch when plausible isn't correct. Without the red-before-green discipline, you'll write tests that confirm whatever you already wrote.

## The Cycle

```text
1. Write a failing test
2. Run it — verify it FAILS (red)
3. Write minimal code to pass
4. Run it — verify it PASSES (green)
5. Refactor if needed
6. Commit
```

**Step 2 matters most.** If you skip "verify it fails," you might write a test that passes regardless of implementation. That test protects nothing.

## Working With Plan Tasks

Tasks from writing-plans already embed TDD structure. Your job is to execute it faithfully:

```markdown
**Step 1: Write the failing test**
[test code from plan]

**Step 2: Run test to verify it fails**
`pytest tests/path/test.py::test_name -v` — expect FAIL

**Step 3: Write minimal implementation**
[implementation code from plan]

**Step 4: Run test to verify it passes**
`pytest tests/path/test.py::test_name -v` — expect PASS

**Step 5: Commit**
```

Execute each step. Don't batch steps 1-4 into one action. The value is in verifying each transition.

## Test Discovery

If the task doesn't specify test patterns, find them:

```bash
# Find existing test files
ls -la tests/ || ls -la test/ || ls -la *_test.* || ls -la *.test.*

# Find test runner config
cat pytest.ini 2>/dev/null || cat pyproject.toml 2>/dev/null | grep -A10 tool.pytest
cat package.json 2>/dev/null | grep -A5 '"test"'

# Run existing tests to understand patterns
pytest --collect-only 2>/dev/null | head -20
npm test -- --listTests 2>/dev/null | head -20
```

Match existing patterns. If tests use `pytest`, use `pytest`. If tests use class-based structure, use classes.

## What to Test

Test **behavior**, not implementation:

| Good (behavior) | Bad (implementation) |
|-----------------|---------------------|
| `login_returns_token_for_valid_credentials` | `login_calls_database_once` |
| `expired_token_returns_401` | `token_validator_internal_state` |
| `retry_succeeds_after_transient_failure` | `retry_loop_increments_counter` |

One behavior per test. If a test name has "and" in it, split it.

## When Tests Fail Unexpectedly

If a test fails when you expected it to pass:

1. Read the error message completely
2. Check if you're testing the right thing (path, function name, import)
3. Check if dependencies exist (prior task outputs, config files)
4. Fix the root cause, don't patch the test to pass

If a test passes when you expected it to fail:

1. Your test doesn't test what you think — the assertion is wrong
2. The implementation already exists (check git status)
3. The test is testing a mock, not real behavior

## Refactoring

Refactor only after green. Refactoring means changing structure without changing behavior.

**Refactor when:**
- Duplication appeared (extract function)
- Names don't match what things do
- Function does multiple things (split)

**Don't refactor:**
- Before tests pass (you might break something)
- Code outside your task scope (create a separate task)
- Working code that's "not how I'd write it"

Run tests after each refactor step. If tests fail, you changed behavior — revert and try again.

## Boundary Tests

If your task consumes output from a prior task (imports a module, calls an API), write a boundary integration test:

```python
# Test that auth_service (Task 2) integrates with user_repository (Task 1)
def test_auth_service_fetches_user_from_repository():
    repo = UserRepository(db_connection)  # Real component from Task 1
    auth = AuthService(repo)              # Component from Task 2

    result = auth.authenticate("valid_user", "valid_pass")

    assert result.user_id == expected_id  # Tests the seam
```

Use real components at boundaries, not mocks. Mocks at boundaries hide integration bugs.

## Common Failure Modes

| Failure | Why It Happens | Fix |
|---------|---------------|-----|
| Test passes before implementation | Assertion is wrong or tests a mock | Verify assertion tests real behavior |
| Test fails after "correct" implementation | Wrong import, path, or assumption | Read error completely, fix root cause |
| Refactor breaks tests | Changed behavior, not just structure | Revert, make smaller changes |
| Tests pass but feature doesn't work | Testing mocks instead of real code | Use real components, especially at boundaries |
| Skipped "verify fail" step | Feels redundant | It's not. Do it every time. |

## Integration

**Called by:** superpowers:orchestrating (implementer subagents)

**Works with:** Plans from superpowers:writing-plans (tasks have TDD structure embedded)
