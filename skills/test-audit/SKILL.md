---
name: test-audit
description: Use when asked to audit unit tests, check test quality/health, find flaky or weak tests, or review the test suite for smells — repo-wide or on changed tests
---

# Test Audit

Audits a test suite for quality problems — false-pass risk, flakiness, weak assertions, poor isolation, and maintainability smells — surfaces findings, then offers to fix them and to record the repo's testing conventions.

**Not for:** auditing production code (use `codebase-review`), or reviewing a branch's whole implementation (use `implementation-review`). This skill judges whether the *tests* would catch regressions.

The audit itself is read-only. Fixes happen only after you approve them, via separate implementers.

## Invocation

- `/test-audit` — audit all tests in the repo
- `/test-audit path/to/dir` — limit to a directory
- `/test-audit --diff` — audit only tests changed vs the default branch
- `/test-audit --diff --base=<ref>` — diff against a specific ref

## Phase 1 — Resolve Scope

Parse the user's arguments into structured tokens before calling the helper — do NOT interpolate raw user input into the shell, which is a command-injection risk for inputs containing `;`, `&&`, `|`, or backticks. Wrap each parsed token in single quotes; escape any literal single quote as `'\''`.

Run `./skills/test-audit/scope-detect.sh '<tokens…>'`. Parse stdout (`KEY=value` per line): `SCOPE_MODE` (`full`|`diff`), `SCOPE_PATH`, and in diff mode `BASE_REF`. A non-zero exit means bad arguments — surface stderr and stop.

Discover the test files:

- **full:** find test files under `SCOPE_PATH` using the repo's conventions (e.g. `*_test.*`, `test_*.*`, `*.test.*`, `*.spec.*`, files under `tests/`/`__tests__/`/`spec/`). Confirm the framework from config (`package.json`, `pyproject.toml`/`pytest.ini`, `go.mod`, `*.csproj`, etc.).
- **diff:** `git diff --name-only "$BASE_REF"... -- <test-path-globs>` to get changed test files only. If none changed, report that and stop.

If the test set is empty, say so and stop — there is nothing to audit.

## Phase 2 — Dispatch the Auditor

Group the test files by top-level test directory (or logical module). Dispatch one **`claude-caliper:test-auditor`** subagent per group, all in parallel in a single message. Each dispatch prompt provides:

- The exact list of test files (or the directory) that subagent owns
- `SCOPE_MODE` and, in diff mode, the `BASE_REF` so it can read the diff

The agent definition supplies the five categories, severity rubric, disposition values, falsification gate, output format, and the `json audit-summary` block — do not restate them. For a small suite (one directory, few files), a single subagent is fine.

## Phase 3 — Aggregate & Surface

Collect each subagent's findings and parse its `json audit-summary` block. Merge into one list, deduplicate, and sort by severity (Critical → Low). Also collect the **Observed Conventions** sections.

**Suite-health synthesis (full mode only).** After the per-file audits return, dispatch one more **`claude-caliper:test-auditor`** subagent in *suite-health synthesis* mode. Give it the test-file inventory grouped by layer (unit / component / integration / e2e, inferred from paths), the aggregated findings, and any CI config you can see. It returns the suite-level problems (pyramid balance, cross-layer duplication, happy-path skew, lost protection, risk-coverage gaps) and an A–F grade with one-line evidence. Skip this in diff mode — a changed-tests gate isn't a suite assessment.

Present a report to the user:

```text
# Test Audit — <scope> (<full | diff vs BASE_REF>)
Audited: <N> test files | Findings: <C> Critical, <H> High, <M> Medium, <L> Low
Suite health: <grade A–F> — <one-line evidence>   (full mode only)

## Findings by Severity
| # | Severity | Disposition | Category | File:line | Problem (incl. the bug it misses) | Recommended fix |

## Suite Health   (full mode only)
<pyramid / duplication / happy-path / lost-protection / risk-coverage problems>
```

If there are zero findings, say so plainly and skip to Phase 5 (the conventions offer still applies).

## Phase 4 — Offer to Fix

Most test fixes are directly implementable — they don't need their own design cycle. Use `AskUserQuestion` (header `Fix tests`) to let the user choose which findings to fix:

- **All findings**
- **Critical + High only**
- **Let me pick** — then list findings by id and take their selection
- **None** — skip to Phase 5

Route each approved finding by its **disposition** — they are not all "edit a test":

- **monitor** findings are *not* dispatched to an implementer (the remedy is a runtime monitor/alert, not a test edit). Collect them into a "Monitoring gaps" note shown to the user instead.
- **move-level** findings carry an instruction to rewrite the behavior at the correct layer (and delete the misplaced test), not just tweak it.
- **strengthen / add-missing / remove** are ordinary test edits (remove = delete the net-negative test).

For the implementable findings, group them **by file** (so no two implementers touch the same file), then dispatch one **`claude-caliper:task-implementer`** subagent per file group, in parallel. Each task brief contains, per finding: the `file:line`, the disposition, the problem (including the bug it currently misses), and the recommended fix — plus this verification instruction:

> Apply each fix per its disposition. Then run the affected test(s) and confirm they still pass and now actually assert the intended behavior — specifically, that the test would now fail for the bug named in the finding (a fix that makes a test meaningfully *able to fail* is correct even if it reveals a real bug — in that case, report the bug rather than weakening the test back). Do not change production code to make a test pass; if a corrected test exposes a production defect, report it.

These implementers work on the current branch — they are not creating a new feature, so no per-task worktree is needed. After they return, show a short summary of what changed, the test results, and any deferred monitoring gaps.

## Phase 5 — Offer Testing Conventions

From the merged **Observed Conventions**, check whether the repo's `CLAUDE.md` (or `AGENTS.md`) already documents testing conventions. If it has no testing section, or the audit revealed a convention worth codifying (a dominant framework/layout/assertion style, or a recurring smell worth a "don't do X" rule), offer to add one.

Draft a concise **Testing Conventions** section — framework & runner, file/naming layout, assertion and fixture style, and any "avoid <smell>" rules the findings justify. Show the exact proposed text and use `AskUserQuestion` (header `Conventions`) to confirm before writing. On yes, append it to the repo's `CLAUDE.md` (create the file only if the user agrees). On no, leave `CLAUDE.md` untouched.

Keep the section short and specific to what the audit actually observed — do not pad it with generic testing advice the model already knows.
