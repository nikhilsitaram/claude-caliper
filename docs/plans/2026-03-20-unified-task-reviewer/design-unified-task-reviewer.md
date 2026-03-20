# Design: Unified Task Reviewer

## Problem

The orchestrate pipeline runs two separate per-task review agents after each implementer completes: a spec compliance reviewer and a code quality reviewer. Both are Sonnet subagents inherited from an upstream fork that predate the repo's current review framework.

Three issues:

1. **Redundancy with self-review.** The implementer prompt already includes a thorough self-review checklist covering completeness, quality, and YAGNI. The spec reviewer's adversarial framing ("finished suspiciously quickly — don't trust the report") was written before this self-review existed. With TDD enforced, the red→green cycle itself proves spec compliance for every requirement that has a test.

2. **Overlap between the two reviewers.** A missing error handler is both a spec issue (if specified) and a quality issue. Over-engineering is both a spec issue (extra features) and a quality issue (unnecessary complexity). The clean separation sounds good but blurs in practice, and the code quality reviewer overlaps heavily with the Opus implementation review that runs afterward.

3. **Framework inconsistency.** Every other reviewer in this repo (design-review, plan-review, implementation-review) uses Opus with a numbered checklist, structured PASS/FAIL assessment table, and specific "Flag:" triggers. The per-task reviewers are freeform Sonnet prompts with no checklist structure.

**Cost:** For a 6-task plan, the two reviewers add 12 subagent dispatches (plus fix cycles) — roughly doubling per-task overhead for catches that are largely covered by self-review and implementation-review.

**Who's affected:** Every orchestrated plan pays this cost.

## Goal

Replace the two per-task reviewers with a single Opus reviewer that follows the repo's checklist-driven review framework, cutting per-task review dispatches in half while maintaining or improving catch quality.

## Success Criteria

1. Each task gets exactly one post-implementation review dispatch (not two)
2. The reviewer catches spec deviations, code quality issues, and security problems in a single pass
3. The reviewer's output includes a PASS/FAIL assessment table and clear verdict, matching other reviewers
4. The reviewer's checklist has zero overlap with implementation-review's 8 cross-task categories
5. The phase dispatcher's per-task flow is simpler (one review step instead of two sequential steps with a gate between them)

## Architecture

Single file replacement within the orchestrate skill:

```text
skills/orchestrate/
├── task-reviewer-prompt.md      ← NEW (replaces both below)
├── spec-reviewer-prompt.md      ← DELETE
├── code-quality-reviewer-prompt.md  ← DELETE
├── phase-dispatcher-prompt.md   ← MODIFY (one reviewer dispatch instead of two)
├── SKILL.md                     ← MODIFY (hierarchy diagram, template table)
├── implementer-prompt.md        (unchanged)
└── tdd.md                       (unchanged)
```

Plus:
- `README.md` — update mermaid diagram and orchestrate description
- `.claude-plugin/marketplace.json` — version bump

### 6-Point Checklist

Scoped exclusively to single-task concerns. Cross-task issues (inconsistencies, duplication, integration gaps) are implementation-review's domain.

| # | Check | What It Catches |
|---|-------|-----------------|
| 1 | **Spec Fidelity** | Missing requirements, extra features, misinterpretations — compare diff to task spec line by line |
| 2 | **TDD Discipline** | Commit history shows red→green→refactor, tests exist before implementation, no skipped verification steps |
| 3 | **Test Quality** | Tests verify behavior not implementation, edge cases covered, no mocking the thing under test, boundary tests present for cross-task seams |
| 4 | **Code Correctness** | Logic bugs, off-by-ones, unhandled errors, race conditions, incorrect assumptions |
| 5 | **Security** | Injection risks, missing input validation at boundaries, hardcoded secrets, unsafe deserialization |
| 6 | **Simplicity** | Over-engineering, YAGNI violations, not following codebase patterns, unnecessary abstraction |

### Reviewer Dispatch

```text
Agent tool (general-purpose):
  model: "opus"
  description: "Review Task {TASK_ID}"
```

Variables provided by phase dispatcher:

| Variable | Source |
|----------|--------|
| `{TASK_ID}` | Task identifier (A1, B2, etc.) |
| `{TASK_SPEC}` | Full task block from plan |
| `{IMPLEMENTER_REPORT}` | What the implementer claimed |
| `{BASE_SHA}` / `{HEAD_SHA}` | Diff range for this task only |
| `{REPO_PATH}` | Working directory |

### Phase Dispatcher Flow (simplified)

Before (per task):
1. Dispatch implementer
2. Dispatch spec reviewer → issues? → fix → re-review
3. Dispatch code quality reviewer → issues? → fix → re-review
4. Mark task complete

After (per task):
1. Dispatch implementer
2. Dispatch task reviewer → issues? → fix → re-review
3. Mark task complete

## Key Decisions

**Opus instead of Sonnet.** Every other reviewer in this repo uses Opus. The per-task reviewers were the only Sonnet reviewers — an artifact of the upstream fork optimizing for cost over quality. A single Opus dispatch replaces two Sonnet dispatches, so the net cost change is roughly neutral (one Opus ≈ two Sonnet in token cost) while catch quality improves.

**6-point checklist, not 4 or 8.** The 6 checks cover everything the two old reviewers checked (spec compliance + code quality + testing + security) without overlapping with implementation-review's cross-task categories. Fewer checks would miss security or TDD discipline; more would start encroaching on cross-task territory.

**No conditional review.** Every task gets reviewed regardless of perceived complexity. Simple tasks are cheap to review; the cost of a missed issue on a "simple" task compounds through later tasks and phases. The dispatcher shouldn't be making risk judgments.

## Non-Goals

- Changing implementation-review (stays as-is)
- Adding conditional review based on task complexity
- Changing the re-review gate threshold (>5 issues)
- Modifying the implementer prompt or self-review checklist
