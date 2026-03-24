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
4. `scripts/validate-plan` accepts `pr-create`/`pr-merge`/`plan-only` and rejects old names
5. All existing tests pass with updated enum values
6. pr-review rebases onto default branch before dispatching the fresh-eyes reviewer when the branch is behind
7. pr-review offers "Merge PR" / "Not yet" after posting its assessment comment
8. pr-merge merges immediately after setup with no confirmation AskUserQuestion
9. Cross-references in all skill SKILL.md files, CLAUDE.md, and README.md use the new names

## Architecture

### Rename: `pr-create`, `pr-review`, `pr-merge`

**Directory renames:**
- `skills/create-pr/` → `skills/pr-create/`
- `skills/review-pr/` → `skills/pr-review/`
- `skills/merge-pr/` → `skills/pr-merge/`

**Frontmatter updates:** Each skill's `name:` and `description:` fields use new names. Trigger strings update accordingly.

**Workflow enum rename:** plan.json `workflow` field changes from `create-pr`/`merge-pr`/`plan-only` to `pr-create`/`pr-merge`/`plan-only`.

**Cross-reference updates (blast radius):**
- `marketplace.json` — skill paths in all 3 plugin bundles
- `skills/design/SKILL.md` — workflow options, enum mapping
- `skills/orchestrate/SKILL.md` — workflow routing, integration section
- `skills/draft-plan/SKILL.md` — workflow enum docs
- `skills/pr-create/SKILL.md` — cross-refs to pr-review, pr-merge
- `skills/pr-review/SKILL.md` — cross-refs to pr-create, pr-merge
- `skills/pr-merge/SKILL.md` — cross-refs to pr-review
- `CLAUDE.md` — workflow description
- `README.md` — mermaid diagram, skill table
- `scripts/validate-plan` — workflow enum case statements
- `tests/validate-plan/` — test fixtures with hardcoded workflow values

### Rebase Before Review (#122)

Insert between pr-review Step 1 (Setup) and Step 2 (PR Review):

**Step 1.5: Rebase onto default branch**

```bash
git fetch origin $DEFAULT_BRANCH
if ! git merge-base --is-ancestor origin/$DEFAULT_BRANCH HEAD; then
  git rebase origin/$DEFAULT_BRANCH
  git push -u origin HEAD --force-with-lease
fi
```

If rebased, log: "Branch was behind `$DEFAULT_BRANCH` — rebased and force-pushed to ensure the review covers only this PR's changes."

If rebase has conflicts, stop and ask the user to resolve.

merge-pr's existing rebase check (Step 3) stays as a safety net for standalone invocations.

### Review → Merge Continuation (#120)

**pr-review Step 6:** After posting the PR comment, add AskUserQuestion:
- **Merge PR** — invoke pr-merge via Skill tool (worktree guard in pr-merge handles cd)
- **Not yet** — stop as today

**pr-merge Step 2:** Remove AskUserQuestion confirmation. The user has either explicitly typed `/pr-merge` or selected "Merge PR" from pr-review. Branch protection check remains as the real gate.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Rename scope | All three skills | Consistent `pr-*` namespace, no partial migration |
| Workflow enum | Rename to match | `pr-create`/`pr-merge` keeps enum aligned with skill names |
| Merge confirmation | Remove entirely | Explicit invocation = sufficient intent; branch protection is the real gate |
| Rebase notification | Log message, not prompt | Keeps pipeline flowing; conflicts still stop for user |
| Backward compat | None | plan.json files are transient per-session, not persisted across versions |

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
