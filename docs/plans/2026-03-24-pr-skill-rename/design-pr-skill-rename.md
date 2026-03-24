# Design: PR Skill Rename + Review Flow Improvements

## Problem

Three related issues in the PR skill family:

1. **#112 — Name collision:** `/review-pr` collides with Claude Code's built-in `/review` slash command. Tab-completion or partial matching triggers the wrong command. All three PR skills (`create-pr`, `review-pr`, `merge-pr`) use a `verb-pr` naming pattern that risks future collisions.

2. **#120 — Broken pipeline continuity:** After `review-pr` finishes and posts its assessment, the workflow stops. The user must manually remember to invoke `merge-pr` (and `cd` out of the worktree first). Meanwhile, `merge-pr` has a redundant confirmation prompt — the user already confirmed intent either by explicitly typing `/merge-pr` or by selecting "Merge PR" from review-pr.

3. **#122 — Stale diff review:** `review-pr` dispatches the fresh-eyes reviewer against `$DEFAULT_BRANCH..HEAD` without ensuring the branch is up-to-date. When the PR branch is behind, the diff includes unrelated changes from commits merged to the default branch after the branch was created, leading to incorrect review findings.

## Goal

Rename all three PR skills to a `pr-*` namespace and fix the review-to-merge pipeline flow in a single coordinated change.

## Success Criteria

1. `/pr-review` triggers the review skill; `/review-pr` does not
2. `/pr-create` triggers the create skill; `/create-pr` does not
3. `/pr-merge` triggers the merge skill; `/merge-pr` does not
4. Plan workflows using old enum names (`create-pr`, `merge-pr`) are rejected with an error indicating valid values
5. pr-review rebases onto default branch before dispatching the fresh-eyes reviewer when the branch is behind
6. pr-review offers "Merge PR" / "Not yet" after posting its assessment comment
7. pr-merge merges immediately after setup with no confirmation AskUserQuestion
8. Cross-references in all skill SKILL.md files, CLAUDE.md, and README.md use the new names

## Architecture

### Rename: `pr-create`, `pr-review`, `pr-merge`

**Directory renames:**
- `skills/create-pr/` → `skills/pr-create/`
- `skills/review-pr/` → `skills/pr-review/`
- `skills/merge-pr/` → `skills/pr-merge/`

**Frontmatter updates:** Each skill's `name:` and `description:` fields use new names. Trigger strings update accordingly.

**Workflow enum rename:** plan.json `workflow` field changes from `create-pr`/`merge-pr`/`plan-only` to `pr-create`/`pr-merge`/`plan-only`.

**Cross-reference updates (blast radius).** All skill paths below reflect post-rename state:
- `marketplace.json` — skill paths in all 3 plugin bundles
- `skills/design/SKILL.md` — workflow options, enum mapping
- `skills/orchestrate/SKILL.md` — workflow routing, integration section
- `skills/draft-plan/SKILL.md` — workflow enum docs
- `skills/pr-create/SKILL.md` — cross-refs to pr-review, pr-merge
- `skills/pr-review/SKILL.md` — cross-refs to pr-create, pr-merge
- `skills/pr-merge/SKILL.md` — cross-refs to pr-review
- `skills/implementation-review/SKILL.md` — cross-ref to create-pr in Integration section
- `CLAUDE.md` — workflow description
- `README.md` — mermaid diagram, skill table
- `scripts/validate-plan` — workflow enum case statements
- `tests/validate-plan/` — test fixtures with hardcoded workflow values

### Rebase Before Review (#122)

pr-create already rebases in Step 6, so bots (CodeRabbit, Greptile) see a clean diff from the start. The problem is drift: other PRs merge to the default branch between PR creation and review. The fix adds a second rebase in pr-review to catch this drift.

**pr-review Step 1.5: Rebase onto default branch** (insert between Setup and PR Review):

```bash
git fetch origin $DEFAULT_BRANCH
if ! git merge-base --is-ancestor origin/$DEFAULT_BRANCH HEAD; then
  git rebase origin/$DEFAULT_BRANCH
  git push -u origin HEAD --force-with-lease
fi
```

If rebased, log: "Branch was behind `$DEFAULT_BRANCH` — rebased and force-pushed to ensure the review covers only this PR's changes."

If rebase has conflicts, stop and ask the user to resolve.

**Bot comment freshness:** Force-pushing after rebase invalidates existing bot review comments (GitHub marks them "outdated"). pr-review Step 3 (Collect & Assess All Feedback) should only process comments posted *after* the rebase push. Record the push timestamp and filter `gh pr` comment results accordingly, or wait for fresh bot comments if the PR was just rebased.

pr-merge's existing rebase check (Step 3) stays as-is — it catches drift between review and merge, not just standalone invocations. All three rebase points serve distinct windows: pr-create (bots see clean code), pr-review (review sees clean diff), pr-merge (merge is against latest base).

### Review → Merge Continuation (#120)

**pr-review Step 6:** After posting the PR comment, add AskUserQuestion:
- **Merge PR** — invoke pr-merge via Skill tool. pr-merge's Step 1 worktree guard detects and `cd`s out of worktrees, so no additional handling is needed in the Skill tool call.
- **Not yet** — stop as today

**pr-merge Step 2:** Remove AskUserQuestion confirmation. Three invocation paths all represent confirmed intent: (1) user explicitly types `/pr-merge`, (2) user selects "Merge PR" from pr-review's prompt, (3) orchestrate auto-invokes in `pr-merge` workflow mode. Branch protection check remains as the real gate for PRs that require human approval.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Rename scope | All three skills | Consistent `pr-*` namespace, no partial migration |
| Workflow enum | Rename to match | `pr-create`/`pr-merge` keeps enum aligned with skill names |
| Merge confirmation | Remove entirely | All three invocation paths (explicit `/pr-merge`, review continuation, orchestrate auto-invoke) represent confirmed intent; branch protection is the real gate |
| Rebase notification | Log message, not prompt | Keeps pipeline flowing; conflicts still stop for user |
| Backward compat | None | plan.json files are transient per-session, not persisted across versions |

## Alternatives Considered

### Three-dot diff instead of rebase (#122)

Using `$DEFAULT_BRANCH...HEAD` (three-dot) computes `git diff $(git merge-base $DEFAULT_BRANCH HEAD) HEAD`, showing only the PR's changes without rebasing. This avoids the force-push side effects (re-triggers CI, invalidates GitHub review comments).

**Why rebase is still the right choice:** Three-dot diff only fixes the *review's view* — the branch remains behind the default branch. This means: (a) the reviewed code may not compile or pass tests against the latest base, (b) merge-pr would still need to rebase before merging, changing the code *after* review. Rebasing in pr-review ensures the reviewer evaluates code that actually integrates with the current state of the default branch, and eliminates the need for a post-review rebase in merge-pr.

### Rename only `review-pr` (#112)

Only the colliding skill would be renamed, minimizing churn. Rejected because a mixed namespace (`create-pr` + `pr-review` + `merge-pr`) is confusing — consistent naming is worth the one-time migration cost.

### `--no-confirm` flag instead of removing confirmation (#120)

pr-review would pass `--no-confirm` to pr-merge; standalone invocations keep the gate. Rejected because the explicit act of typing `/pr-merge` is sufficient intent — an extra confirmation adds friction without safety value. Branch protection is the real gate for PRs requiring human approval.

## Non-Goals

- Backward compatibility shims for old names
- Changing skill directory discovery mechanism
- Modifying orchestrate's workflow routing logic beyond updating enum names

## Implementation Approach

Single phase — all changes are tightly coupled. The rename affects every file the other two issues touch. Tasks:

1. Rename skill directories (`git mv`)
2. Update skill frontmatter and SKILL.md content (all three skills)
3. Add rebase step to pr-review
4. Add merge continuation prompt to pr-review Step 6
5. Remove confirmation gate from pr-merge Step 2
6. Update cross-references in design, orchestrate, draft-plan, create-pr skills
7. Update marketplace.json skill paths
8. Update CLAUDE.md and README.md
9. Update scripts/validate-plan enum values
10. Update test fixtures
