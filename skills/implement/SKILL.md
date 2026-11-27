---
name: implement
description: Use when implementing a small or medium change directly in the current session, without a multi-task plan — via design's fast-path routing, or direct invocation ("/implement", "just implement this", "quick fix").
---

# Implement

The fast path for small/medium work: no plan.json, no per-task files, no orchestration. Implement inline in the current session, then hand off to one holistic review.

## Design Gate

If design's tier router already presented a mini-design (or short design doc) and got explicit approval for this exact request earlier in this session, that gate is satisfied — skip straight to Worktree Setup.

The same holds for a conversate hand-off: the user discussed the change with you and explicitly said to build it, and conversate passes the conversation summary, `$WORKTREE`, and workflow `pr-ready`. That go-ahead is the approval — don't re-present a design or re-ask.

A coordinate pane brief counts the same way: the coordinator settled the item's scope with the user before briefing, and the brief names workflow `pr-ready`. No `$WORKTREE` comes with it, so set one up as on direct invocation.

Otherwise, this is a direct invocation (the user asked for an implementation without going through design first) and the **Compressed Design Gate** below runs before any code is touched — no exceptions.

### Compressed Design Gate (direct invocation only)

The same wrong-assumption failures that unexamined plans cause on a large feature happen just as easily on a one-file fix that felt too trivial to plan. Size changes how much ceremony the gate needs, not whether it runs.

1. **Challenge the framing** — what problem does this solve, is there a simpler alternative? (mirrors design's Challenging Assumptions).
2. **Ask clarifying questions only if genuinely ambiguous** — don't manufacture questions for a request that's already clear.
3. **Present a mini-design in your response text**: 2-5 sentences covering what changes, where, and why this approach — no formal doc, no file written.
4. **Ask for approval in plain text, ending that same response** — not AskUserQuestion: its dialog can hide the text above it, so the user would approve a design they can't read. Settle the workflow in the same ask, so the choice is made before implementing instead of surfaced after the work is done. Run `caliper-settings get workflow`:
   - If a value is returned, note it ("Using your configured workflow: <value>") and ask "Approve, or what should change?"
   - If `PROMPT_REQUIRED`, also list the workflows — Create PR (default, `pr-create`) / Ready to merge (`pr-ready`) / Merge PR (`pr-merge`) / Orchestrate only (`orchestrate`, stop after review) — and ask the user to approve and name one; a bare approval means Create PR.

   Wait for the reply before writing any code. Requested changes loop back to step 3; the resolved workflow value carries forward to the review hand-off.

## Worktree Setup

If design already ran its own worktree setup before handing off — it does this for both Small and Medium tiers, passing `$WORKTREE` — reuse that worktree; the signal is whether `$WORKTREE` was passed in, not the tier name. Don't create a second one. On direct invocation, set one up:

- From the main checkout, create the worktree with git and register the main repo for permission-free access, then `EnterWorktree(path: "$WORKTREE")` — a path-entered worktree is never auto-removed by the harness. **See:** `skills/design/worktree-isolation.md` for the rules the session runs under once inside.

  ```bash
  MAIN_ROOT=$(caliper-main-root)
  WORKTREE="$MAIN_ROOT/.claude/worktrees/<feature>"
  git worktree add "$WORKTREE" -b <feature>
  mkdir -p "$WORKTREE/.claude" && jq -n --arg d "$MAIN_ROOT" '{permissions:{additionalDirectories:[$d]}}' > "$WORKTREE/.claude/settings.local.json"
  seed-agent-memory "$WORKTREE"
  ```
- Bootstrap dependencies — **See:** `skills/design/dependency-bootstrap.md` (lives in `skills/design/`; read it there rather than duplicating its content here)
- Run tests to establish a clean baseline before changing anything

## Inline TDD

Implement directly in the main session — no subagent dispatch for fast-path work. Follow the TDD cycle for test discovery, common failure modes, and boundary-test patterns at cross-component seams.

**See:** `./tdd.md`

## Commit Discipline

Commit frequently in small, logical, atomic units as work lands rather than batching the whole change into one commit at the end. Small commits keep the downstream review's diff easy to reason about and give you a clean rollback point if a later step reveals an earlier one was wrong.

## Chain to Implementation Review

**REQUIRED SUB-SKILL:** Use implementation-review — once the change is implemented and tests pass, invoke it in **standalone mode** over the feature branch diff. No `plan.json` exists on this path, so its mode-detection picks standalone automatically.

Map the `workflow` setting to implementation-review's continuation flag (all five schema values, exactly):

| `workflow` value | Continuation |
|---|---|
| `pr-create` | Chain `--pr-create` |
| `pr-ready` | Chain `--pr-review --automated-fix` |
| `pr-merge` | Chain `--pr-merge` |
| `orchestrate` | Stop after review passes; report the worktree path |
| `plan-only` | Contradictory on a plan-less path — there is no plan to stop after. Treat it as `orchestrate` (stop after review) and tell the user why: this fast path never produced a plan, so "plan only" has nothing further to do. |

Resolve the value:
- **Downstream of design:** the value is already resolved from design's workflow question earlier in this session — reuse it, don't re-prompt or re-read settings.
- **Conversate hand-off or coordinate brief:** always `pr-ready` — their fixed contract, regardless of the setting. The exception is a brief whose SOFT LINK rules name `orchestrate` for a soft dependent: the brief releases it to `pr-ready` once its dependency merges.
- **Direct invocation:** the Compressed Design Gate already resolved it (from settings, or the workflow named at approval) — reuse that value, don't re-prompt or re-read settings.

## Integration

**Workflow:** design (small/medium tier), conversate, or direct invocation → **this skill** → implementation-review (standalone) → pr-create/pr-review/pr-merge
