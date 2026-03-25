# A2: Create gh mock stub fixture — Completion

## What was done

Created `tests/validate-plan/fixtures/gh-mock.sh` — an executable mock for `gh` that handles `pr list` subcommands by echoing `GH_MOCK_PR_COUNT` (default 0) and exits 1 for unrecognized commands.

## Files changed

- **Created:** `tests/validate-plan/fixtures/gh-mock.sh` (executable, 6 lines)

## Verification

Script matches spec exactly. Manual verification commands:

```bash
GH_MOCK_PR_COUNT=0 bash tests/validate-plan/fixtures/gh-mock.sh pr list --base main --head test --json number --jq 'length'
GH_MOCK_PR_COUNT=1 bash tests/validate-plan/fixtures/gh-mock.sh pr list --base main --head test --json number --jq 'length'
bash tests/validate-plan/fixtures/gh-mock.sh version
```
