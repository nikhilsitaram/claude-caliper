# Design: codebase-review Skill

**Date:** 2026-03-02
**Issue:** #15
**Status:** Draft

## Problem

There's no systematic way to audit a codebase for code quality issues beyond what `/simplify` (built-in, scoped to changed files) and `implementation-review` (scoped to a feature branch) provide. Periodic whole-repo health checks require manual effort and miss cross-module issues.

## Solution

A `codebase-review` skill that:
1. Scans an entire repo (or user-specified directory) using parallel subagents
2. Checks 5 categories of code quality issues
3. Runs a cross-scope reconciliation pass to catch cross-module problems
4. Produces a ranked, persistent markdown report
5. Creates GitHub issues for complex findings that need their own planning cycle
6. Transitions remaining fixes into the normal superpowers pipeline (writing-plans -> execution)

## Scope & Invocation

**Trigger:** `/codebase-review` or `/codebase-review path/to/dir`

- No argument: review entire repository (git root)
- With path argument: review only that directory
- Discovers top-level directories and partitions into parallel review units

## Review Categories

| Category | What it checks | Criticality Range |
|----------|---------------|-------------------|
| **DRY** | Duplicated code blocks, repeated constants/magic numbers, copy-pasted logic with minor variations | Medium - High |
| **YAGNI** | Unused exports/functions, dead code paths, speculative features, unnecessary config options | Low - High |
| **Simplicity & Efficiency** | Over-abstracted code, unnecessary indirection, verbose implementations that could be simpler, premature generalization, redundant operations, O(n^2) where O(n) suffices, suboptimal data structures | Medium - Critical |
| **Refactoring Opportunities** | SRP violations, deep nesting, long parameter lists, God objects, missing abstractions that would simplify multiple callers | Low - High |
| **Consistency** | Naming drift (camelCase vs snake_case mixed), inconsistent error handling, style divergence across modules | Low - Medium |

**Criticality levels (4-tier):**
- **Critical** — Active bug risk or severe performance issue
- **High** — Significant maintenance burden or correctness risk
- **Medium** — Code smell that makes the codebase harder to work with
- **Low** — Minor style/convention issue

## Execution Architecture

### Phase 1 — Parallel Scope Review

- Discover review units (top-level directories, or user-specified path as single unit)
- Dispatch one Explore subagent per unit
- Each subagent runs the 5-category checklist on its assigned scope
- Each returns structured findings: category, criticality, file(s), line(s), description, recommended action

### Phase 2 — Cross-Scope Reconciliation

- One additional subagent receives all Phase 1 findings + a file manifest
- Looks specifically for:
  - Cross-directory DRY violations (same logic in different modules)
  - Naming inconsistencies across modules
  - Duplicated patterns that individual reviewers couldn't see
- Merges findings into the main list

### Phase 3 — Aggregate, Report & Triage

- Deduplicate findings
- Rank: Critical > High > Medium > Low, then by category
- For each finding, classify fix complexity:
  - **Inline fix** — can be fixed in a few lines, no separate planning needed
  - **Needs a plan** — multi-file change, architectural decision, or requires its own context window and full brainstorming/design process
- Write report to `docs/reviews/YYYY-MM-DD-codebase-review.md`
- Present findings in conversation

### Phase 4 — Triage & Transition

- Present "needs a plan" items to user via AskUserQuestion
- User selects which become GitHub issues
- Create GH issues for deferred complex work (these go through brainstorming later)
- Remaining fixes (inline complexity) → invoke writing-plans → normal pipeline (plan-review → subagent-driven-development → implementation-review → ship → merge-pr)

## Report Format

```markdown
# Codebase Review — YYYY-MM-DD
**Scope:** <repo root or specified path>
**Review units:** <list of directories reviewed>

## Summary
- X findings total (N Critical, N High, N Medium, N Low)
- Y items need a separate plan (deferred to GH issues)
- Z items fixable inline (proceeding to implementation)

## Findings

### Critical
| # | Category | File(s) | Description | Fix Complexity |
|---|----------|---------|-------------|----------------|
| 1 | Simplicity & Efficiency | src/foo.ts:42 | ... | Inline |

### High
...

### Medium
...

### Low
...

## Deferred Work (GitHub Issues)
| # | Finding | Rationale for deferral | GitHub Issue |
|---|---------|----------------------|--------------|
| 3 | Refactor auth module (SRP) | Touches 5 files, needs design decision | #42 |

## Methodology
Categories: DRY, YAGNI, Simplicity & Efficiency, Refactoring Opportunities, Consistency
Approach: Parallel scope review + cross-scope reconciliation
```

## Relationship to Existing Skills

| Existing | Scope | This skill's differentiation |
|----------|-------|------------------------------|
| `/simplify` (built-in) | Changed files only | Whole-repo, more categories, persistent report |
| `implementation-review` | Feature branch (cross-task) | Repo-wide, not tied to a feature |
| `requesting-code-review` | Per-task during development | Periodic audit, not per-task |

## Implementation Approach

Single-phase implementation. The skill includes one SKILL.md file plus two prompt templates (`reviewer-prompt.md` and `cross-scope-reviewer-prompt.md`), with supporting trigger-test and README updates. No dependency layers — all components are part of the same skill directory.

## Decisions Made

- **Independent of /simplify**: Standalone skill with similar principles but broader scope, doesn't invoke /simplify
- **Complexity-based triage (not severity-based)**: GH issues created for findings that need their own planning cycle, regardless of criticality level
- **Parallel + reconciliation**: Hybrid approach for best coverage of both within-scope and cross-scope issues
- **Full pipeline transition**: Non-deferred fixes flow through writing-plans → full superpowers pipeline, not just ad-hoc fixes
