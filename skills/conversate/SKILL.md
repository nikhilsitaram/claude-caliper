---
name: conversate
description: Use when the user invokes /conversate, or asks to talk a change through with you — your recommendations, their decisions, open questions — before anything gets built.
---

# Conversate

An open-ended design conversation that ends in a ready-to-merge PR. The user sets the pace; you bring recommendations, questions, and pushback. The conversation *is* the design: when the user says they're satisfied, there is no separate approval gate — you summarize and build through to `pr-ready` (implementation-review → pr-create → pr-review in automated-fix mode, stopping before merge).

## The Conversation

Read-only until hand-off — explore code, docs, and history freely, but don't create a worktree or edit files yet; decisions are still moving.

- **Lead with a recommendation.** Explore enough to have a real opinion, then give it with its trade-offs. Challenge the framing first (what problem, for whom, is there a simpler alternative?) and recommend the simplest approach that meets the goal — if you recommend something more complex, name what the simpler one couldn't do. These are the checks design's gates would have run; this skill bypasses those gates, so the conversation has to carry them.
- **Ask in prose.** Questions belong in the flow of discussion. Use AskUserQuestion only for a crisp either/or the user can answer by picking; open questions lose nuance in an options list.
- **Keep a ledger.** Track **Decided** / **Open** / **Parked** and show it when it changes — not every turn. It's what the user scans to see where things stand, and it becomes the overview at hand-off.
- **Don't rush to close.** The user decides when the discussion is done. Raise intricacies and edge cases you notice, but don't steer toward wrapping up.

## Hand-off

**Trigger:** only an explicit statement from the user ("let's build it", "I'm satisfied", "go"). Never infer convergence yourself — that statement is what stands in for design approval, so it has to be theirs.

1. **Open items.** If the ledger still has **Open** entries, list them and ask. This is the only pause between the go-ahead and the PR. Parked items become non-goals.
2. **Size check.** `implement` handles small and medium work in one session. If the change looks large — genuine parallelism, dependency layers, or bulk beyond one sitting — ask before routing (AskUserQuestion: **Full workflow** — design doc, draft-plan, orchestrate / **Implement inline** — one session, accept the size). Don't route to the full workflow on your own judgment; it's a much heavier process the user should opt into.
3. **Overview.** Print a brief summary: problem, approach, key decisions, non-goals, expected files. Information only — no approval question; proceed immediately.
4. **Persist it.** Set up the plan dir and worktree (step 6 of the design skill — `$PLAN_DIR`, `$WORKTREE`, `EnterWorktree`, dependency bootstrap, baseline tests). Then `mkdir -p "$PLAN_DIR"` and write the overview to `$PLAN_DIR/conversation-<topic>.md` via `caliper-draft` (**See:** `skills/design/worktree-isolation.md`). A long conversation will be compacted before implementation finishes; this file is the durable record of what was decided, so re-read it whenever the context feels thin.

## Route

The workflow is always `pr-ready` — that's this skill's contract, so don't read or prompt for the `workflow` setting.

- **Inline (small/medium):** invoke the `implement` skill, passing `$PLAN_DIR/conversation-<topic>.md`, `$WORKTREE`, workflow `pr-ready`, and that this is a conversate hand-off (its design gate is satisfied).
- **Full workflow (large, user opted in):** turn the conversation file into a design doc per the design skill's format (**See:** `skills/design/design-spec.md`) at `$PLAN_DIR/design-<topic>.md`, then follow design step 8's Large route from "write design doc" onward — self-review, design-review, draft-plan, plan-review — with workflow `pr-ready`. Skip design steps 5 and 7: the conversation already settled the approach, tier, and approval. Design-review still runs; it's a fresh-eyes check rather than an approval, and `validate-plan --check-workflow` requires its record.

## Integration

**Workflow:** **this skill** → implement (inline) or draft-plan → orchestrate (large) → implementation-review → pr-create → pr-review --automated-fix
