# codebase-review

Whole-repo code quality audit. Catches DRY violations, dead code, over-abstraction, and naming drift that per-task reviews miss because they only see one branch at a time.

**Not for:** Branch reviews (use `implementation-review`), diff-only review (use `/simplify`).

## When to use

- Periodic audits (monthly, quarterly) to catch accumulated debt
- Before a major refactoring to know where the real problems are
- After a long development phase when code quality may have drifted

## How it works

```text
Phase 1: Resolve scope → discover review units (top-level directories)
         |
         v
Phase 2: Parallel scope reviews (one Explore subagent per directory)
         |
         v
Phase 3: Cross-scope reconciliation (one Explore subagent, sees all findings)
         |
         v
Phase 4: Aggregate + route (write report, create issues, or hand off to draft-plan)
```

### Phase 1 — Resolve Scope

Determines the review boundary: either a path argument or the git root. Discovers review units by listing top-level directories (excluding `.*`, `node_modules`, `vendor`, `__pycache__`).

### Phase 2 — Parallel Scope Reviews

One `agents/reviewer.md` subagent per review unit, all dispatched in parallel. Each reads every file in its directory and reports findings across 5 categories with criticality and fix complexity classifications.

### Phase 3 — Cross-Scope Reconciliation

A single `agents/cross-scope-reviewer.md` subagent reads all Phase 2 findings plus the full file manifest. It looks for issues that individual reviewers couldn't detect from within a single directory: cross-module duplication, naming drift between directories, and inconsistent patterns across module boundaries. It also deduplicates findings flagged independently by multiple reviewers.

### Phase 4 — Aggregate & Route

Merges all findings, deduplicates, and ranks by criticality. Writes a report to `docs/reviews/YYYY-MM-DD-codebase-review.md`. Groups findings by overlapping file sets — findings that touch the same files are handled together.

Routes by **fix complexity** (not severity):

- **Inline fixes** — automatically invokes `draft-plan` on the grouped findings, then `plan-review`, then proceeds to execution. No user prompt.
- **Complex fixes** — `AskUserQuestion`: create GitHub issues (one per group) or write plans now. User chooses.

A Critical one-liner goes inline; a Medium refactoring across 10 files gets an issue or plan.

## Review categories

| Category | What it catches |
|----------|----------------|
| **DRY** | Duplicated code blocks, repeated constants, copy-pasted logic |
| **YAGNI** | Unused exports, dead code paths, speculative features |
| **Simplicity & Efficiency** | Over-abstraction, unnecessary indirection, redundant operations |
| **Refactoring Opportunities** | SRP violations, God objects, deep nesting, long parameter lists |
| **Consistency** | Naming drift, inconsistent error handling, style divergence |

Cross-scope reviewers additionally check: Cross-Directory DRY, Cross-Directory Naming, and Cross-Directory Pattern Divergence.

## Criticality levels

| Level | Meaning |
|-------|---------|
| **Critical** | Active bug risk or severe performance issue |
| **High** | Significant maintenance burden or correctness risk |
| **Medium** | Code smell that makes the codebase harder to work with |
| **Low** | Minor style/convention issue |

## Output report structure

```text
# Codebase Review — YYYY-MM-DD
Scope: [path] | Review units: [list]
Summary: X findings (N Critical, N High, N Medium, N Low) | Y deferred → GH issues | Z inline → implementation

## Findings by Criticality
| # | Category | File(s) | Description | Fix Complexity |

## Deferred Work
| # | Finding | Rationale | GitHub Issue # |
```

## Files reference

| File | Purpose |
|------|---------|
| `SKILL.md` | Skill trigger and execution instructions |
| `agents/reviewer.md` | Per-directory scope reviewer instructions |
| `agents/cross-scope-reviewer.md` | Cross-directory reconciliation reviewer instructions |
