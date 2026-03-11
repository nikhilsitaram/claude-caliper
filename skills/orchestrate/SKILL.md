---
name: orchestrate
description: Use when executing implementation plans with independent tasks in the current session
---

# Orchestrate

Execute plan phase by phase: dispatch a fresh phase dispatcher subagent per phase, then dispatch implementation-review from the orchestrate context, report phase completion, and advance. After all phases, auto-invoke ship.

**Core principle:** Every level is a dispatcher. Orchestrate dispatches phase dispatchers. Phase dispatchers dispatch implementers and reviewers. No level writes application code itself — only the implementer subagent touches code.

## When to Use

- Have an implementation plan with mostly independent tasks
- Don't use for tightly coupled tasks or when no plan exists

## Subagent Hierarchy

```text
Orchestrate (you)           — 1 per plan
├── Phase Dispatcher        — 1 per phase (dispatches implementers + reviewers, never writes code)
│   ├── Implementer         — 1 per task (fresh context, writes code via TDD)
│   ├── Spec Reviewer       — 1 per task (evaluates code cold)
│   └── Code Quality Rev.   — 1 per task (evaluates code cold)
└── Implementation Review   — 1 per phase (cross-task holistic, dispatched by you)
```

Why separate subagents per task: each implementer starts with fresh context, preventing quality degradation as tasks accumulate. Each reviewer evaluates code without having seen the implementation rationale.

## Prompt Templates

| Template | Purpose |
|----------|---------|
| `./phase-dispatcher-prompt.md` | Dispatch phase dispatcher subagent |
| `./implementer-prompt.md` | Dispatch individual task implementer (used inside phase dispatcher and for post-review fixes) |
| `./spec-reviewer-prompt.md` | Spec compliance reviewer (used inside phase dispatcher) |
| `./code-quality-reviewer-prompt.md` | Code quality reviewer (used inside phase dispatcher) |
| `skills/implementation-review/reviewer-prompt.md` | Holistic cross-task reviewer (dispatched from orchestrate context) |

## Per-Phase Execution

For each phase (letter A, B, C...):

1. `PHASE_BASE_SHA=$(git rev-parse HEAD)` — before dispatching
2. Create phase branch:
   - Phase A: `git checkout -b phase-a` (from current HEAD)
   - Phase B+: `git checkout -b phase-{letter}` (from prior phase tip)
3. Extract context for dispatcher:
   - Concatenate all `### Phase X Completion Notes` sections from prior phases (in order)
   - Extract current phase section (from `## Phase X` through end of that phase's tasks, before next `## Phase`)
   - Dispatcher does NOT receive the plan header/goal/architecture or other phases' task details — context isolation prevents the dispatcher from being overwhelmed by irrelevant details
4. Dispatch phase dispatcher (`./phase-dispatcher-prompt.md`) with: prior completion notes as PRIOR_COMPLETION_NOTES, current phase section (checklist + tasks), PHASE_BASE_SHA
5. After dispatcher returns: dispatch implementation-review (`skills/implementation-review/reviewer-prompt.md`)
   - BASE_SHA = PHASE_BASE_SHA, HEAD_SHA = `git rev-parse HEAD`
6. Triage findings through deviation rules (see `./phase-dispatcher-prompt.md` for full table) — dispatch implementer for Rule 1-3. Rule 4 violations: dispatcher writes BLOCKED to plan, orchestrator terminates.
7. Re-Review Gate: >5 issues from any reviewer → re-review after all fixes applied
8. Append implementation review changes to `### Phase X Completion Notes` (dispatcher already wrote its summary there; orchestrator appends review fixes below it)
9. Emit phase summary: "Phase A complete. [N tasks]. Review: X issues — [brief list]. [All fixed / N deferred]."
10. Update phase status: `Complete (YYYY-MM-DD)`
11. Ship phase PR: invoke ship, which creates PR with `--base phase-{prior-letter}` (or `--base main` for Phase A)

Single-phase plans: one iteration of the same loop. Skip handoff notes.

After the final phase: update plan frontmatter `status: Complete`, then auto-invoke ship.

## Example Workflow

```text
[Read plan, identify phases]

git checkout -b phase-a
Phase A BASE_SHA = $(git rev-parse HEAD)
[Extract Phase A section from plan]
[Dispatch dispatcher: Phase A section only, no prior context]
  ...returns with completion notes written to plan...
[Dispatch implementation-review: PHASE_BASE_SHA..HEAD]
[Append review fixes to Phase A Completion Notes]
[Ship PR: --base main]

git checkout -b phase-b  (from phase-a tip)
Phase B BASE_SHA = $(git rev-parse HEAD)
[Extract Phase A Completion Notes + Phase B section]
[Dispatch dispatcher: completion notes as context + Phase B section]
  ...
[Ship PR: --base phase-a]
```

**Integration test levels:** First task (when broad tests exist) provides acceptance tests (Level 1). Implementers write boundary tests at cross-task seams (Level 2). Implementation-review verifies coverage (Level 3).

## Inline Handoff Notes

Handoff notes live as blockquotes on individual tasks, not as separate sections. The plan author places placeholders on target tasks (e.g., `> **Handoff from A2:** [TBD]` on B2). The Phase A dispatcher fills in actual details (real function signatures, file paths, config keys) after completing the producing task. The orchestrator does not write separate handoff notes sections.

## Plan Doc Updates

| When | Update |
|------|--------|
| First task starts | Frontmatter: `status: In Development` |
| Task completes (inside dispatcher) | `- [ ] A1` → `- [x] A1` |
| Phase dispatcher returns | Dispatcher writes summary to `### Phase X Completion Notes` |
| Review fixes applied | Orchestrator appends review changes to `### Phase X Completion Notes` |
| Phase review passes | Phase status: `Complete (YYYY-MM-DD)` |
| Phase PR shipped | Ship creates PR with stacked base branch |
| All phases done | Frontmatter: `status: Complete` |
| Rule 4 violation | Frontmatter: `status: BLOCKED` + blocked_by + blocked_at |

## Key Constraints

| Constraint | Why |
|------------|-----|
| Record BASE_SHA before dispatcher | Implementation-review needs the exact phase start SHA |
| Extract only completion notes + current phase for dispatcher | Context isolation prevents dispatcher from being overwhelmed by irrelevant phase details |
| Dispatch implementation-review from orchestrate context | Phase completion and any issues must be visible before advancing — prevents bugs compounding |
| Fix review issues before next phase | Phase N bugs compound into Phase N+1 complexity |
| Ship per-phase PR with stacked base | Each PR shows only its phase's diff, making review manageable |
| Escalate Rule 4 immediately | Architectural changes need user input, not guessing |

## Integration

**Workflow:** worktree setup (before) → draft-plan (creates plan) → **this skill** → ship (auto-invoked after final phase) → merge-pr (after CodeRabbit)

**See:** `tdd.md` — TDD reference (cycle, boundary tests, failure modes); content is embedded in implementer prompts
