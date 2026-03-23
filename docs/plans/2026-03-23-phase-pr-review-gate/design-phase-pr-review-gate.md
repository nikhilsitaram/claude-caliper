# Design: Phase PR External Review Gate

Add a polling-based review gate after each phase PR so external AI reviewers (CodeRabbit, Gemini) can post feedback before the orchestrator merges and advances. Also standardize the final PR merge strategy to preserve per-phase commit history on main.

## Problem

The orchestrate skill creates a phase PR and immediately squash-merges it into the integration branch. This has two consequences:

1. **No external review window** — CodeRabbit, Gemini Code Assist, and other AI reviewers never get a chance to post comments. The external review step is where fresh-eyes catch gaps that the built-in implementation-review misses, and auto-merging bypasses it.
2. **Lost phase history** — The final PR from `integrate/<feature>` to `main` is also squash-merged, collapsing all per-phase commits into one. This makes it harder to trace which phase introduced a change.

## Goal

After creating each phase PR, wait for external reviewers to finish, address their feedback, then merge. Preserve end-to-end automation — no user intervention required between phases unless a reviewer surfaces something the review-pr skill can't resolve. For multi-phase plans, preserve per-phase commit history on main.

## Success Criteria

1. External AI reviewers (CodeRabbit, Gemini) have posted their feedback on each phase PR before the orchestrator merges it.
2. The wait has a configurable cap (default 10 minutes) — if checks haven't completed by then, the orchestrator proceeds with a warning.
3. After checks complete, the orchestrator invokes review-pr to read and address all reviewer comments before merging.
4. The same poll + review-pr gate applies to the final PR (integrate/<feature> → main).
5. The final PR uses `--rebase` merge for multi-phase plans (preserving per-phase commit history on main) and `--squash` for single-phase plans.

## Architecture

### Polling Mechanism

After `create-pr` returns the PR URL/number, poll GitHub checks:

```bash
elapsed=0; max=$((review_wait_minutes * 60))
while [ $elapsed -lt $max ]; do
  pending=$(gh pr checks <NUMBER> --json bucket --jq '[.[] | select(.bucket == "pending")] | length')
  [ "$pending" -eq 0 ] && break
  sleep 60; elapsed=$((elapsed + 60))
done
```

- `bucket` field values: `pass`, `fail`, `pending`, `skipping`, `cancel`
- Returns `0` pending when all checks (CI, CodeRabbit, Gemini) have finished
- Poll every 60 seconds
- Max wait: `review_wait_minutes` from plan.json (default 10)
- On timeout: proceed with warning log, do not block the pipeline

Custom polling over `gh pr checks --watch` — the `--watch` flag blocks until completion but has no timeout mechanism, and the `timeout` coreutils command is not available on macOS without `brew install coreutils`. A custom loop with `sleep` is dependency-free and portable.

### Review-PR Integration

Once checks complete (or timeout), invoke review-pr:

1. review-pr reads all PR comments and review threads
2. Addresses feedback by pushing fix commits to the phase branch
3. If fixes were pushed, external reviewers may re-review — but we do NOT re-poll (one pass is sufficient to avoid infinite loops)

### Phase PR Flow

Replaces current orchestrate SKILL.md steps 14-16 with expanded steps 14-19:

```text
14. Create phase PR: invoke create-pr with --base integrate/<feature>
15. Poll checks: every 60s, max review_wait_minutes (default 10). Read wait from plan.json: jq -r '.review_wait_minutes // 10' plan.json
16. Review feedback: invoke review-pr to read and address all comments
17. Merge phase PR: gh pr merge --squash
18. Update integration worktree: git pull in .claude/worktrees/<feature>/
19. Clean up phase worktree and branch
```

### Final PR Flow

```text
1. Create final PR: integrate/<feature> → main
2. Poll checks: same mechanism as phase PRs
3. Review feedback: invoke review-pr
4. Merge strategy:
   - Multi-phase: gh pr merge --rebase (preserves per-phase commits on main)
   - Single-phase: gh pr merge --squash (one phase = one commit)
```

### Parallel Phase Timing

Phases are dispatched in parallel but completions (including poll + review-pr + merge) are processed serially to avoid integration branch conflicts. For phases B and C dispatched in parallel:

```text
B dispatcher running ──────────────────┐
C dispatcher running ─────────────────────────────┐
                                       │          │
                          B completes  │  C completes
                                       ▼          │
                    B: create PR → poll → review-pr → merge
                                                   ▼
                                   C: create PR → poll → review-pr → rebase → merge
```

The check-waiting time for each phase overlaps with the other phase's dispatcher execution, but the poll-review-merge sequence itself is serial.

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

1. **Custom polling over fixed wait** — CodeRabbit finishes in 2-3 min on small diffs, 8-10 on large. Polling avoids wasting time on small PRs while ensuring large ones get full coverage.
2. **Custom polling over `gh pr checks --watch`** — The `--watch` flag has no timeout mechanism, and the `timeout` coreutils command is unavailable on macOS without additional dependencies. A `sleep`-based loop is portable and explicit.
3. **No re-poll after review-pr fixes** — Prevents infinite review loops. One pass of external review + fix is sufficient; the built-in implementation-review already caught the structural issues.
4. **Rebase for multi-phase, squash for single-phase** — Multi-phase plans produce one commit per phase on the integration branch (from squash-merging each phase PR). Rebase preserves this history on main. Single-phase has no phase history worth preserving.
5. **10 minute default cap** — Observed CodeRabbit completing in ~2 min on a 4-line PR. 10 min provides headroom for large diffs without stalling the pipeline indefinitely.
6. **plan.json `review_wait_minutes` override** — Plans with known-slow CI or many reviewers can increase the cap. Plans with no external reviewers can set 0 to skip polling entirely.

## Non-Goals

- Re-polling after review-pr pushes fixes (avoids infinite loops)
- Configuring which specific reviewers to wait for (we wait for all checks generically)
- Changing the phase-level review flow (implementation-review is unchanged)
- Adding CodeRabbit configuration beyond what `.coderabbit.yaml` already provides

## Implementation Approach

Single phase — the changes are confined to orchestrate SKILL.md and merge-pr SKILL.md:

1. **orchestrate SKILL.md**: Insert after current step 14 (create phase PR, line 96). New step 15: poll checks using `review_wait_minutes` from plan.json (read via `jq -r '.review_wait_minutes // 10' plan.json`). New step 16: invoke review-pr with the phase PR number. Renumber current step 15 (merge) to step 17, current step 16 (cleanup) to steps 18-19. Update wave loop summary line 61 and continuity note line 116.
2. **merge-pr SKILL.md**: Add conditional merge strategy — `--rebase` when plan.json has >1 phase, `--squash` otherwise — for the final PR (integrate/<feature> → main). Phase PRs remain `--squash`.
3. **draft-plan SKILL.md**: Add `review_wait_minutes` as optional field in plan.json schema (integer, default 10).
