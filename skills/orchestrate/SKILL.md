---
name: orchestrate
description: Use when executing implementation plans with independent tasks in the current session
---

# Orchestrate

Execute plan phase by phase: dispatch a fresh phase executor subagent per phase, then dispatch implementation-review from the orchestrate context, report phase completion, and advance. After all phases, auto-invoke ship.

**Core principle:** Phase executor handles implementation. Orchestrate context handles review, reporting, and phase advancement.

## When to Use

- Have an implementation plan with mostly independent tasks
- Don't use for tightly coupled tasks or when no plan exists

## The Process

**Per phase:** Record BASE_SHA → dispatch phase executor (all tasks + per-task reviews + completion report) → dispatch implementation-review → emit phase summary → fix issues → write handoff notes → advance

**After all phases:** Update plan status → auto-invoke ship.

## Prompt Templates

| Template | Purpose |
|----------|---------|
| `./phase-executor-prompt.md` | Dispatch phase executor subagent (sequential tasks + per-task reviews + completion report) |
| `./implementer-prompt.md` | Dispatch individual task implementer (used inside phase executor and for post-review fix work) |
| `./spec-reviewer-prompt.md` | Spec compliance reviewer (used inside phase executor) |
| `./code-quality-reviewer-prompt.md` | Code quality reviewer (used inside phase executor) |
| `skills/implementation-review/reviewer-prompt.md` | Holistic cross-task reviewer (dispatched from orchestrate context after each phase) |

## Example Workflow

```text
[Read plan, identify phases]

Phase 1 BASE_SHA = $(git rev-parse HEAD)
[Dispatch phase executor: Phase 1]
  Internal: Task 0 (integration tests) → Task 1 (hook install) → Task 2 (recovery modes)
  Each task: implementer → spec review → code review → mark complete
  Writes completion report. Returns summary + HEAD SHA.

[Dispatch implementation-review: PHASE_BASE_SHA..HEAD]
  Found: duplicated constant (Tasks 1+2), missing boundary test (Task 2)
  [Dispatch implementer fixes] → [Re-review: ✅]

Phase 1 summary: 3 tasks complete. Review: 2 issues, both fixed.
[Write handoff notes into plan doc]

[Dispatch phase executor: Phase 2]
  Internal: Task 3 → Task 4
  Writes completion report. Returns.

[Dispatch implementation-review: Phase 2 BASE_SHA..HEAD]
  Found: 0 issues

Phase 2 summary: 2 tasks complete. Review: 0 issues.
[Auto-invoke ship]
```

**Integration test levels:** Task 0 provides broad acceptance tests (Level 1). Implementers write boundary tests at cross-task seams (Level 2). Implementation-review verifies coverage (Level 3).

## Per-Phase Execution

For each phase:

1. `PHASE_BASE_SHA=$(git rev-parse HEAD)` — before dispatching executor
2. Dispatch phase executor (`./phase-executor-prompt.md`) with:
   - Phase number, name, full task text for this phase
   - PHASE_BASE_SHA
   - PHASE_CONTEXT from prior phase's handoff notes (empty for Phase 1)
3. After executor returns: dispatch implementation-review (`skills/implementation-review/reviewer-prompt.md`)
   - BASE_SHA = PHASE_BASE_SHA, HEAD_SHA = `git rev-parse HEAD`
   - PHASE_CONTEXT = what downstream phases expect (from plan); empty for final/single phase
4. Triage findings through deviation rules — dispatch implementer for Rule 1-3; Rule 4 → write BLOCKED to plan doc and terminate (see Rule 4 Handling)
5. Re-Review Gate: >5 issues → re-review after all fixes
6. Append to the phase completion report in plan doc:
   ```markdown
   ### Implementation Review Changes
   - [each fix: what changed and why]
   ```
   Omit section if no fixes were needed.
7. Emit phase summary: "Phase N complete. [N tasks]. Review: X issues — [brief list]. [All fixed / N deferred]."
8. Write handoff notes into plan doc (see format below)
9. Update phase status: `Complete (YYYY-MM-DD)`

Single-phase plans skip handoff notes — one iteration of the same loop.

After the final phase: update plan frontmatter `status: Complete`, then auto-invoke ship.

## Handoff Notes Format

Insert before the next phase's task checklist:

```markdown
### Phase N Handoff Notes

**Interface contracts:** [Function signatures, API shapes, config keys Phase N+1 depends on]
**Integration test status:** [Which pass, which are xfail for future phases, any flaky]
**Known issues:** [Anything deferred, workarounds, tech debt]
**Decisions made:** [Plan deviations approved or auto-fixed, with rationale]
```

Handoff notes reflect post-fix state — the next phase can proceed without re-reading the conversation.

## Re-Review Gate

Applies to all review stages (spec, code quality, implementation review):

If a reviewer finds **more than 5 fix-needed issues**, after all fixes are applied, dispatch a fresh same-scope reviewer to confirm clean. Bulk fixes risk introducing new issues or incomplete resolution.

Under 5 issues: orchestrator verifies fixes and proceeds.

## Deviation Rules

| Rule | Trigger | Action |
|------|---------|--------|
| **Rule 1: Auto-fix bugs** | Code doesn't work as intended | Fix inline, document |
| **Rule 2: Auto-add critical** | Missing error handling, validation, auth | Fix inline, document |
| **Rule 3: Auto-fix blockers** | Missing dep, broken import, wrong types | Fix inline, document |
| **Rule 4: STOP** | New DB table, library swap, breaking API | Write BLOCKED to plan → terminate |

**Scope:** Only auto-fix issues caused by current task. Pre-existing issues go to deferred list.

**Limit:** After 3 fix attempts on same issue, stop and document.

**Documentation:** Include what deviated, what was done, and which rule applied—so reviewers and future phases understand the decision without re-reading the conversation.

## Rule 4 Handling

When a phase executor reports a Rule 4 violation, orchestrate cannot ask the user (it runs as a subagent dispatched by draft-plan). Instead:

1. Update plan frontmatter:

```markdown
---
status: BLOCKED
blocked_by: "Rule 4 — [specific issue, e.g., Task 2 requires a new DB table not in the plan]"
blocked_at: "Phase N, Task M"
---
```

2. Append to the plan doc body:

```markdown
## Execution Blocked — [YYYY-MM-DD]

**Rule 4 violation:** [What architectural change would be required]
**Discovered at:** Phase N, Task M — [task title]
**Context:** [What the implementer tried to do and why the plan doesn't cover it]
**Options:**
- Update the plan to include the required change, then re-run orchestrate
- Adjust the task scope to avoid the architectural change
```

3. Terminate. Do not attempt subsequent tasks or phases.

The user sees the plan doc in a clean BLOCKED state and can resolve the conflict before re-invoking orchestrate.

## Plan Doc Updates

| When | Update |
|------|--------|
| First task starts | Frontmatter: `status: In Development` |
| Task completes (inside executor) | `- [ ] Task N` → `- [x] Task N` |
| Phase executor returns | Phase completion report written to plan doc by executor |
| Review fixes applied | Orchestrate context appends `### Implementation Review Changes` to completion report |
| Phase review passes | Phase status: `Complete (YYYY-MM-DD)` |
| All phases done | Frontmatter: `status: Complete` |
| Rule 4 violation | Frontmatter: `status: BLOCKED` + blocked_by + blocked_at |

## Key Constraints

| Constraint | Why |
|------------|-----|
| Record BASE_SHA before executor | Implementation-review needs the exact phase start SHA |
| Dispatch implementation-review from orchestrate context | Phase completion and any issues must be visible before advancing — this prevents bugs from compounding into the next phase |
| Fix review issues before next phase | Phase N bugs compound into Phase N+1 complexity |
| Escalate Rule 4 immediately | Architectural changes need user input, not guessing |

## Integration

**Workflow:** worktree setup (before) → draft-plan (creates plan) → **this skill** → ship (auto-invoked after final phase) → merge-pr (after CodeRabbit)

**See:** `tdd.md` — TDD reference (cycle, boundary tests, failure modes); content is embedded in implementer prompts
