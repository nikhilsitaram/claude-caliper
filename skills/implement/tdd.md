# TDD Reference

## Test Discovery

If the task doesn't specify test patterns, find them:

```bash
ls -la tests/ || ls -la test/ || ls -la *_test.* || ls -la *.test.*
cat pytest.ini 2>/dev/null || cat pyproject.toml 2>/dev/null | grep -A10 tool.pytest
cat package.json 2>/dev/null | grep -A5 '"test"'
pytest --collect-only 2>/dev/null | head -20
```

Match existing patterns (runner, file structure, class vs function style).

## When Tests Fail Unexpectedly

**Test fails when you expected it to pass:**
1. Read the error message completely
2. Check path, function name, import
3. Check dependencies exist (prior task outputs, config files)
4. Fix the root cause, don't patch the test to pass

**Test passes when you expected it to fail:**
1. Assertion is wrong — doesn't test what you think
2. Implementation already exists (check git status)
3. Test is testing a mock, not real behavior

## Boundary Tests

Use real components at cross-task seams, not mocks:

```python
def test_auth_service_fetches_user_from_repository():
    repo = UserRepository(db_connection)  # Real component from Task 1
    auth = AuthService(repo)              # Component from Task 2
    result = auth.authenticate("valid_user", "valid_pass")
    assert result.user_id == expected_id
```

## Common Failure Modes

| Failure | Fix |
|---------|-----|
| Test passes before implementation | Assertion tests a mock — verify it tests real behavior |
| Test fails after "correct" implementation | Wrong import, path, or assumption — read error completely |
| Refactor breaks tests | Changed behavior, not structure — revert, make smaller changes |
| Tests pass but feature doesn't work | Using mocks at boundaries — use real components |
| Skipped "verify fail" step | Do it every time |
