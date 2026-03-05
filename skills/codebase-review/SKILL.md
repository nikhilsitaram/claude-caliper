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

Dispatch **Explore** subagent per review unit using `agents/reviewer.md` instructions:
- `{SCOPE_PATH}` = directory to review

All subagents run in parallel. Each returns structured findings with category, criticality, fix complexity.

### Phase 3 — Cross-Scope Reconciliation

After Phase 2 completes, dispatch one **Explore** subagent using `agents/cross-scope-reviewer.md` instructions:
- `{ALL_FINDINGS}` = concatenated Phase 2 findings
- `{FILE_MANIFEST}` = all files in repo
- `{SCOPE_PATH}` = root scope

This pass catches cross-directory DRY violations and naming drift that per-scope reviewers can't see.

### Phase 4 — Aggregate & Route

1. Merge findings (Phase 2 + Phase 3), deduplicate, rank by criticality
2. Write report to `docs/reviews/YYYY-MM-DD-codebase-review.md`
3. Group findings by overlapping file sets — findings that touch the same files belong in the same plan or issue
4. Route by fix complexity:

**Inline fixes** (automatically, no user prompt):
- Invoke `draft-plan` with the grouped inline findings as requirements
- Invoke `plan-review` on the resulting plan
- Proceed to execution

**Complex fixes** (AskUserQuestion — pick one):
- **Create GitHub issues** — one issue per logical group → `gh issue create`
- **Write plans now** — invoke `draft-plan` per group, then `plan-review`

Routing is based on fix COMPLEXITY, not severity. A Critical one-liner goes inline; a Medium refactoring across 10 files gets an issue or plan.

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

**See:** agents/reviewer.md

- **DRY** — duplicated logic, repeated constants
- **YAGNI** — unused code, dead paths, speculative features
- **Simplicity & Efficiency** — over-abstraction, unnecessary indirection
- **Refactoring Opportunities** — SRP violations, God objects, deep nesting
- **Consistency** — naming drift, style divergence
