# Design: Phase PR External Review Gate

Add a polling-based review gate after each phase PR so external AI reviewers (CodeRabbit, Gemini) can post feedback before the orchestrator merges and advances.

## Problem

The orchestrate skill creates a phase PR and immediately squash-merges it into the integration branch. This skips external code review entirely — CodeRabbit, Gemini Code Assist, and other AI reviewers never get a window to post comments. The external review step is where fresh-eyes catch gaps that the built-in implementation-review misses, and auto-merging bypasses it.

## Goal

After creating each phase PR, wait for external reviewers to finish, address their feedback, then merge. Preserve end-to-end automation — no user intervention required between phases unless a reviewer surfaces something the review-pr skill can't resolve.

## Success Criteria

1. After a phase PR is created, the orchestrator waits for all GitHub checks to reach a terminal state before proceeding.
2. The wait has a configurable cap (default 10 minutes) — if checks haven't completed by then, the orchestrator proceeds with a warning.
3. After checks complete, the orchestrator invokes review-pr to read and address all reviewer comments before merging.
4. The same poll + review-pr gate applies to the final PR (integrate/<feature> -> main).
5. The final PR uses `--rebase` merge for multi-phase plans (preserving per-phase commit history) and `--squash` for single-phase plans.
6. Parallel phase waits overlap — creating PRs for phases B and C does not serialize their check-waiting periods.

## Architecture

### Polling Mechanism

After `create-pr` returns the PR URL/number, poll GitHub checks:

```bash
gh pr checks <NUMBER> --json name,state,status --jq \
  '[.[] | select(.status != "COMPLETED" and .state != "SUCCESS" and .state != "SKIPPED")] | length'
```

- Returns `0` when all checks (CI, CodeRabbit, Gemini) have finished
- Poll every 60 seconds
- Max wait: 10 minutes (configurable via `review_wait_minutes` in plan.json, default 10)
- On timeout: proceed with warning log, do not block the pipeline

### Review-PR Integration

Once checks complete (or timeout), invoke review-pr:

1. review-pr reads all PR comments and review threads
2. Addresses feedback by pushing fix commits to the phase branch
3. If fixes were pushed, external reviewers may re-review — but we do NOT re-poll (one pass is sufficient to avoid infinite loops)

### Phase PR Flow (updated steps 14-17)

```text
14. Create phase PR: invoke create-pr with --base integrate/<feature>
15. Poll checks: gh pr checks every 60s, max review_wait_minutes (default 10)
16. Review feedback: invoke review-pr to read and address all comments
17. Merge phase PR: gh pr merge --squash
18. Update integration worktree: git pull in .claude/worktrees/<feature>/
19. Clean up phase worktree and branch
```

### Final PR Flow (updated)

```text
1. Create final PR: integrate/<feature> → main
2. Poll checks: same mechanism
3. Review feedback: invoke review-pr
4. Merge strategy:
   - Multi-phase: gh pr merge --rebase (preserves per-phase commits on main)
   - Single-phase: gh pr merge --squash (one phase = one commit)
```

### Parallel Phase Timing

For phases B and C dispatched in parallel:

```text
B dispatcher running ──────────────────┐
C dispatcher running ─────────────────────────────┐
                                       │          │
B: create PR ─── poll checks (60s intervals) ─── review-pr ─── merge
                                       C: create PR ─── poll checks ─── review-pr ─── rebase ─── merge
```

Completions are still processed serially (one merge at a time to avoid integration branch conflicts), but the check-waiting periods overlap with ongoing work.

### Wave Loop Summary (updated)

```text
LOOP until all phases complete:
  a. Ready phases: depends_on all in completed set
  b. Reconciliation (non-root phases)
  c. Dispatch ready phases IN PARALLEL
  d. Process completions SERIALLY: review → triage → rebase → create-pr → poll checks → review-pr → merge → mark complete
  e. Repeat
```

## Key Decisions

1. **Poll checks (Option A) over fixed wait** — CodeRabbit finishes in 2-3 min on small diffs, 8-10 on large. Polling avoids wasting time on small PRs while ensuring large ones get full coverage.
2. **No re-poll after review-pr fixes** — Prevents infinite review loops. One pass of external review + fix is sufficient; the built-in implementation-review already caught the structural issues.
3. **Rebase for multi-phase, squash for single-phase** — Multi-phase plans produce one commit per phase on the integration branch (from squash-merging each phase PR). Rebase preserves this history on main. Single-phase has no phase history worth preserving.
4. **10 minute default cap** — Observed CodeRabbit completing in ~2 min on a 4-line PR. 10 min provides headroom for large diffs without stalling the pipeline indefinitely.
5. **plan.json `review_wait_minutes` override** — Plans with known-slow CI or many reviewers can increase the cap. Plans with no external reviewers can set 0 to skip polling entirely.

## Non-Goals

- Re-polling after review-pr pushes fixes (avoids infinite loops)
- Configuring which specific reviewers to wait for (we wait for all checks generically)
- Changing the phase-level review flow (implementation-review is unchanged)
- Adding CodeRabbit configuration beyond what `.coderabbit.yaml` already provides

## Implementation Approach

Single phase — the changes are confined to orchestrate SKILL.md and merge-pr SKILL.md:

1. **orchestrate SKILL.md**: Insert poll + review-pr steps between create-pr and merge in the per-phase loop. Update wave loop summary and continuity note. Add `review_wait_minutes` to plan.json schema reference.
2. **merge-pr SKILL.md**: Add conditional merge strategy (`--rebase` for multi-phase, `--squash` for single-phase) when merging the final PR.
3. **draft-plan SKILL.md**: Add `review_wait_minutes` as optional field in plan.json schema.
