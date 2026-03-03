---
name: codebase-review
description: Use when asked to audit a codebase, find DRY/YAGNI/complexity issues repo-wide, or perform periodic code quality review
---

# Codebase Review

Periodic whole-repo audits catch issues that per-task reviews miss — cross-module duplication, accumulated complexity, and naming drift.

**Not for:** Branch reviews (use `implementation-review`), diff-only review (use `/simplify`).

## Invocation

- `/codebase-review` — review entire repo
- `/codebase-review path/to/dir` — review specified directory only

## Execution

### Phase 1 — Resolve Scope

1. Determine scope: path argument or `git rev-parse --show-toplevel`
2. Discover review units (top-level directories, excluding `.*`, `node_modules`, `vendor`, `__pycache__`)
3. Create one task per review unit via `TaskCreate`

### Phase 2 — Parallel Scope Reviews

Dispatch **Explore** subagent per review unit using `reviewer-prompt.md` template:
- `{SCOPE_PATH}` = directory to review

All subagents run in parallel. Each returns structured findings with category, criticality, fix complexity.

### Phase 3 — Cross-Scope Reconciliation

After Phase 2 completes, dispatch one **Explore** subagent using `cross-scope-reviewer-prompt.md`:
- `{ALL_FINDINGS}` = concatenated Phase 2 findings
- `{FILE_MANIFEST}` = all files in repo
- `{SCOPE_PATH}` = root scope

This pass catches cross-directory DRY violations and naming drift that per-scope reviewers can't see.

### Phase 4 — Aggregate & Route

1. Merge findings (Phase 2 + Phase 3), deduplicate, rank by criticality
2. Classify each finding's fix complexity:
   - **Inline** — few lines, no planning needed
   - **Needs own plan** — multi-file, architectural, or requires design cycle
3. Write report to `docs/reviews/YYYY-MM-DD-codebase-review.md`
4. Route outputs:
   - **Inline fixes** → transition to `writing-plans` → normal pipeline
   - **Needs own plan** → `AskUserQuestion` to select which become GitHub issues → `gh issue create`

Issue creation is based on fix COMPLEXITY, not severity. A Critical one-liner doesn't need an issue; a Medium refactoring across 10 files does.

## Report Structure

```text
# Codebase Review — YYYY-MM-DD
Scope: [path] | Review units: [list]
Summary: X findings (N Critical, N High, N Medium, N Low) | Y deferred → GH issues | Z inline → implementation

## Findings by Criticality
| # | Category | File(s) | Description | Fix Complexity |

## Deferred Work
| # | Finding | Rationale | GitHub Issue # |
```

## Categories

See `reviewer-prompt.md` for full definitions. Summary:
- **DRY** — duplicated logic, repeated constants
- **YAGNI** — unused code, dead paths, speculative features
- **Simplicity & Efficiency** — over-abstraction, unnecessary indirection
- **Refactoring Opportunities** — SRP violations, God objects, deep nesting
- **Consistency** — naming drift, style divergence
