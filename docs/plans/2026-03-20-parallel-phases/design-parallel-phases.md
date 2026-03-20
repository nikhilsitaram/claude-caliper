# Design: Parallel Phase Execution with Integration Branches

## Problem

Three gaps in the current orchestration system:

1. **No workflow routing.** After draft-plan returns, the user has no structured way to choose between full auto-ship, review-only, or stopping at the plan. PR #77 attempted this with an implicit "note in context" signal from the design skill to orchestrate — fragile because the signal depends on the agent correctly conveying a prose instruction through a prompt boundary.

2. **Sequential phase execution.** All phases run one at a time in a single worktree, even when phases are independent. A diamond plan (A→B, A→C, B+C→D) takes 4 serial steps instead of 3 (A, then B+C parallel, then D).

3. **Stacked PRs can't support parallelism.** The current model branches `phase-b` from `phase-a` tip, with each PR targeting the prior phase. This requires strict merge ordering and blocks concurrent phases.

**Who's affected:** Any plan with independent phases pays a sequential time penalty. The lack of workflow routing forces users to manually intervene after every plan to control shipping behavior.

**Consequences of not solving:** Features with 4-5 phases take N× longer than necessary. The implicit signal mechanism will continue causing silent failures where orchestrate auto-ships when the user intended review-only.

## Goal

Enable parallel phase execution via per-phase worktrees and an integration branch, with explicit workflow routing through a structured field in plan.json.

## Success Criteria

1. Given a plan with independent phases (e.g., B and C both depend only on A), orchestrate dispatches B and C concurrently rather than waiting for B to complete before starting C
2. A `workflow` field in plan.json controls whether orchestrate auto-ships, stops after review, or stops after planning — no implicit signal passing
3. Phase PRs target the integration branch; one final PR merges integration → main
4. Fully sequential plans (A→B→C) degrade gracefully to current behavior — one phase at a time, each in its own worktree
5. Plans with invalid workflow values, missing phase dependency declarations, or circular phase dependencies are rejected before execution begins

## Architecture

### Branch Topology

```text
main
 └── integrate/<feature>              (created by design skill, has design doc + plan)
      ├── phase-a  (worktree)         → PR into integrate/<feature>
      ├── phase-b  (worktree)         → PR into integrate/<feature>, after A merges
      ├── phase-c  (worktree)         → PR into integrate/<feature>, parallel with B
      └── phase-d  (worktree)         → PR into integrate/<feature>, after B+C merge

Final: integrate/<feature> → main    (single squash-merge PR)
```

### Worktree Layout

```text
main repo (on main)
├── .claude/worktrees/<feature>/                 (integrate/<feature> — design doc, plan)
├── .claude/worktrees/<feature>-phase-a/         (phase-a worktree)
├── .claude/worktrees/<feature>-phase-b/         (phase-b worktree)
├── .claude/worktrees/<feature>-phase-c/         (phase-c worktree)
```

Multiple features can coexist — each has its own integration branch and phase worktrees with namespaced paths. The worktree root changes from `.worktrees/` (current SKILL.md text) to `.claude/worktrees/` — namespacing under `.claude/` keeps plugin-managed worktrees separate from any user-created worktrees.

`<feature>` is the kebab-case topic name derived from the plan directory (e.g., `docs/plans/2026-03-20-parallel-phases/` yields `parallel-phases`). The design skill uses this as both the integration branch name (`integrate/parallel-phases`) and the worktree directory name (`.claude/worktrees/parallel-phases/`).

### Orchestrator Execution Flow

```text
1. Read plan.json, extract phase DAG and workflow field
2. Push integration branch to remote
3. PLAN_BASE_SHA = git rev-parse HEAD (in integration worktree)

4. LOOP until all phases complete:
   a. Identify ready phases (all depends_on satisfied)
   b. For each ready phase, create worktree:
      git worktree add .claude/worktrees/<feature>-phase-{letter} \
        -b phase-{letter} integrate/<feature>
   c. Dispatch phase dispatchers IN PARALLEL (one Agent per ready phase)
   d. Post-completion steps are serialized — the orchestrator processes one
      completing phase at a time, even when multiple phases finish concurrently.
      This prevents race conditions on the integration branch.
      As each phase returns:
      - Dispatch implementation review (from orchestrate context)
      - Triage findings, fix issues
      - Rebase phase on latest integration (picks up parallel phases that merged first)
      - Resolve conflicts: if `git rebase` succeeds without conflict markers,
        treat as trivial — verify tests pass and continue. If conflict markers
        appear, treat as non-trivial — pause and present both versions to the user.
      - Ship phase PR (--base integrate/<feature>)
      - Merge phase PR into integration (gh pr merge)
      - Update integration worktree (git pull in integration worktree)
      - Run phase criteria
      - Mark phase complete, clean up phase worktree
   e. Repeat: check for newly ready phases

5. All phases done:
   - Final cross-phase review (PLAN_BASE_SHA..HEAD on integration branch)
   - Run plan criteria
   - If workflow == "ship": create + merge final PR (integration → main), clean up
   - If workflow == "review-only": create final PR, stop. User reviews and merges manually.
```

### Context Flow

Context isolation is preserved. Each phase dispatcher receives only:
- Prior completion notes (from phases this phase depends on, not all prior phases)
- Current phase tasks JSON
- Cross-phase handoff targets

The key difference from current: "prior" means the transitive closure of `depends_on`, not "all earlier letters." Phase D (depends_on: [B, C]) receives completions from A, B, and C (since B and C both depend on A) — no context is lost when the dependency chain is deeper than one level. Phase C (depends on A only) receives Phase A completion notes but not Phase B notes — B is not a dependency.

## Key Decisions

### 1. Integration branch replaces stacked PRs

**Current:** `phase-b` branches from `phase-a` tip, PR targets `phase-a`. Strict merge ordering required.

**New:** `integrate/<feature>` branch created by design skill. Each phase branches from integration and PRs back into it. One final PR merges integration → main.

**Why:** Stacked PRs require strict ordering and block parallel work. An integration branch lets any ready phase merge independently. The tradeoff is the final PR into main is larger, but per-phase PRs into integration still provide incremental review.

### 2. Phase dependency graph in plan.json

```json
"phases": [
  { "letter": "A", "name": "Foundation", "depends_on": [] },
  { "letter": "B", "name": "API layer", "depends_on": ["A"] },
  { "letter": "C", "name": "CLI", "depends_on": ["A"] },
  { "letter": "D", "name": "Integration", "depends_on": ["B", "C"] }
]
```

Orchestrate builds a DAG and dispatches phases in waves. All phases whose dependencies are satisfied run concurrently.

**Why phases and not tasks:** Phases may touch overlapping files for different purposes (e.g., Phase B adds API routes, Phase C adds CLI commands, both modify the main entry point). Separate worktrees per phase provide git-level isolation. Tasks within a phase touch disjoint files, so they run sequentially in the same worktree without conflicts.

### 3. Workflow field in plan.json

```json
{
  "schema": 1,
  "workflow": "ship",
  ...
}
```

Values:
- `"ship"` — orchestrate executes all phases, ships per-phase PRs into integration, ships final PR to main
- `"review-only"` — same execution, but creates final PR without merging. User reviews and merges manually.
- `"plan-only"` — design skill stops after plan creation. Orchestrate never invoked.

**Why in plan.json:** The signal needs to survive the prompt boundary between design and orchestrate. A structured field in the plan manifest is explicit, validated by schema, and inspectable. This replaces the implicit "note in context" approach from PR #77. `"plan-only"` is included in plan.json (rather than being a design-skill-only instruction) so the intent is inspectable by any tool or human reading the plan, without relying on session context.

### 4. Rebase before merge for parallel phases

When parallel phases both complete and need to merge into integration, the second phase to merge must rebase on the updated integration branch first. This handles the case where parallel phases touched overlapping files.

Example (diamond: A→B+C→D):
1. A merges into integration
2. B and C run in parallel, both branched from integration (containing A)
3. B finishes first, merges into integration. Integration now has A+B.
4. C finishes. Rebase C on updated integration (A+B), resolve conflicts, then merge. Integration now has A+B+C.
5. D branches from updated integration, starts with everything.

**Why rebase not merge commit:** Rebase keeps history linear and phase diffs clean, at the cost of potentially more complex conflict resolution when parallel phases touch overlapping files. Merge commits would simplify conflicts but produce a tangled history on the integration branch. Since phase PRs are typically small (one phase of work), rebase conflicts are manageable, and linear history is worth the cost.

### 5. Design worktree = integration branch worktree

The design skill creates `.claude/worktrees/<feature>` on branch `integrate/<feature>`. Design doc and plan are committed here. Orchestrate creates phase worktrees as siblings. After all phases merge back, the integration worktree has the complete feature.

**Why:** Avoids an extra branch. The user can `cd .claude/worktrees/<feature>` at any time to see the combined state.

### 6. Tasks stay sequential within phases

Tasks within a phase run sequentially in the same worktree (current behavior). Parallel task execution would require either per-task worktrees (heavy) or coordinated commits (complex git index management). Phase-level parallelism captures the bigger win — a 4-phase diamond goes from 4 serial steps to 3.

## Non-Goals

- Task-level parallelism within phases
- Changes to implementer, reviewer, or TDD workflows (they operate within a single worktree)
- Migration of existing plans to the new schema fields
- Changes to the design-review or plan-review skills

## What Changes Per Skill

| Skill | Change Summary |
|-------|----------------|
| `skills/design/SKILL.md` | Update worktree path from `.worktrees/<branch-name>` to `.claude/worktrees/<feature>/`; branch becomes `integrate/<feature>`; add workflow routing question after draft-plan; write `workflow` to plan.json |
| `skills/draft-plan/SKILL.md` | Add phase-level `depends_on` to plan.json output; document `workflow` field |
| `skills/orchestrate/SKILL.md` | Integration branch flow; phase DAG; parallel phase dispatch; per-phase worktrees; rebase-before-merge; read `workflow` for ship behavior |
| `skills/orchestrate/phase-dispatcher-prompt.md` | `{REPO_PATH}` is phase worktree path; PR targets `integrate/<feature>`; prior completions scoped to dependency chain |
| `skills/ship/SKILL.md` | Add `--base <branch>` argument to ship's PR creation step and Arguments table (currently ship always targets the default branch). When provided, `gh pr create --base <branch>` uses this as the base branch. Defaults to `$DEFAULT_BRANCH` when omitted, preserving backward compatibility. |
| `skills/merge-pr/SKILL.md` | Final integration→main merge (squash); multi-worktree cleanup |
| `scripts/validate-plan` | Schema validation for `workflow` (enum) and phase `depends_on` (array of letters); circular dependency detection |

## Implementation Approach

**Phase A — Schema + routing + integration branch (sequential):** Add `workflow` and phase `depends_on` to plan.json schema. Update validate-plan with new field validation and cycle detection. Update design skill with routing question and integration branch naming. Update orchestrate to use integration branch model with sequential phase dispatch (one at a time, each in own worktree). Update phase-dispatcher PR base. Update ship for integration branch base.

**Phase B — Parallel dispatch + merge flow:** Add DAG logic to orchestrate for wave-based parallel phase dispatch. Add rebase-before-merge step for parallel phases. Update merge-pr for final integration→main merge and multi-worktree cleanup. End-to-end validation with a diamond dependency plan.
