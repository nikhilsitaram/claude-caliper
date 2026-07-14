---
name: implement
description: Use when implementing a small or medium change directly in the current session, without a multi-task plan — via design's fast-path routing, or direct invocation ("/implement", "just implement this", "quick fix").
---

# Implement

The fast path for small/medium work: no plan.json, no per-task files, no orchestration. Implement inline in the current session, then hand off to one holistic review.

## Design Gate

If design's tier router already presented a mini-design (or short design doc) and got explicit approval for this exact request earlier in this session, that gate is satisfied — skip straight to Worktree Setup.

Otherwise, this is a direct invocation (the user asked for an implementation without going through design first) and the **Compressed Design Gate** below runs before any code is touched — no exceptions.

### Compressed Design Gate (direct invocation only)

The same wrong-assumption failures that unexamined plans cause on a large feature happen just as easily on a one-file fix that felt too trivial to plan. Size changes how much ceremony the gate needs, not whether it runs.

1. **Challenge the framing** — what problem does this solve, is there a simpler alternative? (mirrors design's Challenging Assumptions).
2. **Ask clarifying questions only if genuinely ambiguous** — don't manufacture questions for a request that's already clear.
3. **Present a mini-design**: 2-5 sentences covering what changes, where, and why this approach — no formal doc, no file written.
4. **Wait for explicit approval** (AskUserQuestion: "Approve" / "Needs changes") before writing any code. "Needs changes" loops back to step 3.

## Worktree Setup

If design already ran its own worktree setup before handing off — it does this for both Small and Medium tiers, passing `$WORKTREE` — reuse that worktree; the signal is whether `$WORKTREE` was passed in, not the tier name. Don't create a second one. On direct invocation, set one up:

- `EnterWorktree(name: "<feature>")` — creates `.claude/worktrees/<feature>` with branch `<feature>`
- Resolve paths and register the main repo for permission-free access:

  ```bash
  MAIN_ROOT="$(git rev-parse --path-format=absolute --git-common-dir | sed 's|/\.git$||')"
  WORKTREE="$MAIN_ROOT/.claude/worktrees/<feature>"
  mkdir -p "$WORKTREE/.claude" && jq -n --arg d "$MAIN_ROOT" '{permissions:{additionalDirectories:[$d]}}' > "$WORKTREE/.claude/settings.local.json"
  link-agent-memory "$WORKTREE"
  ```
- Bootstrap dependencies — **See:** `skills/design/dependency-bootstrap.md` (lives in `skills/design/`; read it there rather than duplicating its content here)
- Run tests to establish a clean baseline before changing anything

## Inline TDD

Implement directly in the main session — no subagent dispatch for fast-path work. Follow the TDD cycle for test discovery, common failure modes, and boundary-test patterns at cross-component seams.

**See:** `./tdd.md`

## Commit Discipline

Commit frequently in small, logical, atomic units as work lands rather than batching the whole change into one commit at the end. Small commits keep the downstream review's diff easy to reason about and give you a clean rollback point if a later step reveals an earlier one was wrong.

## Chain to Implementation Review

Once the change is implemented and tests pass, invoke `skills/implementation-review/SKILL.md` in **standalone mode** over the feature branch diff — no `plan.json` exists on this path, so the mode-detection in that skill picks standalone automatically.

Map the `workflow` setting to implementation-review's continuation flag (all four schema values, exactly):

| `workflow` value | Continuation |
|---|---|
| `pr-create` | Chain `--pr-create` |
| `pr-merge` | Chain `--pr-merge` |
| `orchestrate` | Stop after review passes; report the worktree path |
| `plan-only` | Contradictory on a plan-less path — there is no plan to stop after. Treat it as `orchestrate` (stop after review) and tell the user why: this fast path never produced a plan, so "plan only" has nothing further to do. |

Resolve the value:
- **Downstream of design:** the value is already resolved from design's workflow question earlier in this session — reuse it, don't re-prompt or re-read settings.
- **Direct invocation:** run `caliper-settings get workflow`. If a value is returned, use it silently. If `PROMPT_REQUIRED`, ask via AskUserQuestion: **Create PR** / **Merge PR** / **Stop after review** (mirrors design's Q1, minus "Plan only" — meaningless when there's no plan).

## Integration

**Workflow:** design (small/medium tier) or direct invocation → **this skill** → implementation-review (standalone) → pr-create/pr-review/pr-merge
**See:** `./tdd.md`
