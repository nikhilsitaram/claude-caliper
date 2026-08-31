---
name: design
description: Use when creating features, building components, adding functionality, or modifying behavior - before any creative or implementation work begins
---

# Design: Ideas Into Plans

Turn ideas into validated designs through collaborative dialogue before any code is written.

<HARD-GATE>
Do NOT invoke implementation skills, write code, or scaffold projects until you have presented a design and the user has explicitly approved it. Skipping design validation is the #1 cause of wasted work in AI-assisted sessions. This applies to EVERY project regardless of perceived simplicity.
</HARD-GATE>

## Anti-Pattern: "Too Simple to Need a Design"

A todo list, a utility function, a config change — all go through this process. "Simple" projects are where unexamined assumptions cause the most wasted work. The design can be a few sentences, but you must present it and get approval.

## Checklist

Complete in order:

1. **Explore context** — files, docs, recent commits
2. **Challenge assumptions** — question the framing before accepting it
3. **Ask clarifying questions** — smart batches (see below)
4. **Propose 2-3 approaches** — trade-offs and your recommendation. Include the simplest viable option (reuse or extend existing code before adding new), and recommend the simplest approach that meets the success criteria; if your recommendation isn't the simplest, name what the simpler one couldn't do
5. **Recommend a tier, then present the design** — sections scaled to complexity, approval after each. Recommend a tier from these signals (default to **Medium** when in doubt — the cheapest tier with an audit trail):
   - **Small** — ≤~2 files, obvious approach. No design doc, no plan artifacts; approved in conversation.
   - **Medium** — one coherent change, fits one context, no genuine parallelism. Short design doc + one design-reviewer pass.
   - **Large** — genuine parallelism, dependency layers, or bulk beyond one sitting. Full ceremony: design-review loop, draft-plan, plan-review, orchestrate.
6. **Set up worktree** — `EnterWorktree` enables session-aware cleanup via `ExitWorktree`:
   - `EnterWorktree(name: "<feature>")` — creates `.claude/worktrees/<feature>` with branch `<feature>`
   - Resolve persistent path variables (plans live in main repo, code work happens in worktree):

     ```bash
     MAIN_ROOT="$(git rev-parse --path-format=absolute --git-common-dir | sed 's|/\.git$||')"
     PLAN_DIR="$MAIN_ROOT/.claude/claude-caliper/YYYY-MM-DD-<topic>"
     WORKTREE="$MAIN_ROOT/.claude/worktrees/<feature>"
     mkdir -p "$WORKTREE/.claude" && jq -n --arg d "$MAIN_ROOT" '{permissions:{additionalDirectories:[$d]}}' > "$WORKTREE/.claude/settings.local.json"
     seed-agent-memory "$WORKTREE"
     ```

     `$PLAN_DIR` lives in the main repo (gitignored) so plan artifacts survive worktree cleanup. Use `$PLAN_DIR` and `$WORKTREE` — not relative paths — in every dispatch prompt and `jq` write below; subagents inherit worktree CWD and relative `.claude/claude-caliper/...` won't resolve. The `settings.local.json` write registers `$MAIN_ROOT` as an additional directory so future sessions started inside the worktree (e.g. a fresh `claude` launched there) don't trigger per-command permission prompts when reading/writing `$PLAN_DIR`. `seed-agent-memory` copies `$MAIN_ROOT/.claude/agent-memory` into `$WORKTREE` as a real dir so subagents with `memory: project` (design-reviewer, plan-drafter, plan-reviewer, task-implementer, implementation-reviewer) read accumulated memory and write locally; the `SubagentStop` hook syncs their writes back to `$MAIN_ROOT` before cleanup. (A symlink can't be used — since the v2.1.251 harness fix, a subagent's writes resolving out of its worktree through a symlink are blocked.)
   - Multi-phase (large tier only): rename to integration branch: `git branch -m integrate/<feature>` — phase worktrees created by orchestrate as siblings
   - Single-phase: branch name `<feature>` is correct as-is; execution works here directly, PRs to main
   1. Bootstrap dependencies per **See:** ./dependency-bootstrap.md
   2. Run tests to establish a clean baseline
7. **Configure and approve** — single AskUserQuestion with 3 questions:

    **Q1 — Workflow** (header: "Workflow"):
    Run `caliper-settings get workflow`.
    - If a value is returned (e.g. `pr-create`): skip this question. Message: "Using your configured workflow: <value>".
    - If `PROMPT_REQUIRED`: options depend on the tier recommended in step 5 (mark the recommended option "(Recommended)"):
      - **Small or Medium tier:** `Plan only` is meaningless on the plan-less fast path — omit it:
        - **Create PR** — Implement → pr-create (Recommended)
        - **Merge PR** — Implement → pr-create → pr-review → pr-merge
        - **Orchestrate only** — Implement → stop after implementation review (work stays in worktree)
      - **Large tier:** all four options:
        - **Create PR** — Orchestrate → pr-create (Recommended)
        - **Merge PR** — Orchestrate → pr-create → pr-review → pr-merge
        - **Orchestrate only** — Orchestrate → stop after implementation review (work stays in worktree)
        - **Plan only** — Stop after plan is reviewed

    **Q2 — Tier** (header: "Tier"):
    Mark the tier recommended in step 5 "(Recommended)". Options:
    - **Small** — no design doc; approve now, hand off straight to `implement`
    - **Medium** — short design doc + one design-reviewer pass, then hand off to `implement`
    - **Large** — full ceremony: design-review, draft-plan, plan-review, orchestrate

    If the answer moves the tier across the small/medium ↔ large boundary from what Q1's options assumed, ask one quick follow-up AskUserQuestion to confirm the workflow choice with the corrected option set before proceeding.

    **Q3 — Approval** (header: "Approval"):
    - **Approve design (auto turn on acceptEdits)**
    - **Needs changes**

    If "Needs changes" on Q3, return to step 5.

    On approval, create sentinel: `mkdir -p "$PLAN_DIR" && touch "$PLAN_DIR/.design-approved"` (this enables `acceptEdits` for the session regardless of tier; see `hooks/permission-request-accept-edits.sh`).
8. **Route by tier:**

   - **Small:** No design doc, no design-review dispatch. Invoke the `implement` skill directly in this session, passing `$WORKTREE` and the mapped workflow value (see Route Workflow below). The design already presented and approved in step 5/7 stands in for `implement`'s own compressed design gate.
   - **Medium:** Write the design doc (below), self-review it, then dispatch design-review with the **Review Loop Protocol** (below). No draft-plan, no plan.json, no plan-review. Once design-review passes, invoke the `implement` skill directly, passing `$PLAN_DIR/design-<topic>.md`, `$WORKTREE`, and the mapped workflow value.
   - **Large:** Write the design doc, self-review it, dispatch design-review with the **Review Loop Protocol**, dispatch draft-plan, then dispatch plan-review with the same protocol. Then **Route Workflow** (below).

**Write design doc** (Medium/Large only) — `$PLAN_DIR/design-<topic>.md` (no commit — gitignored transient state, lives in main repo)

Before dispatching design-review, verify the doc satisfies this quality checklist (catches the most common reviewer findings on first pass):
- Success criteria are behavioral outcomes, not implementation details ("users can log in" not "tests pass" or "middleware installed")
- Non-goals each include a brief rationale for why they're excluded
- Every file mentioned in the implementation approach is covered in the architecture section (and vice versa)
- Test Strategy names a non-mocking integration test for every cross-module data flow (or explicitly notes "no cross-module seam" for single-module designs)
- Test impact is noted for every behavior change
- Migration/operational steps are captured if the change touches data or config
- The recommended approach is the simplest that meets the success criteria — a more complex choice names what a simpler alternative (fewer moving parts, reuse over new code) couldn't do

Run `validate-design --check <path>` and fix any errors before proceeding to self-review.

**Self-review pass** (Medium/Large only) — before dispatching the external reviewer, read through the design doc yourself against the 9-point checklist in `agents/design-reviewer.md`. Fix any issues you find. Goal: catch obvious gaps so the external reviewer surfaces only non-obvious ones. This is an inline check, not a subagent dispatch — no output format required, just fix what you find.

## Review Loop Protocol (two-pass cap)

Shared by the design-review dispatch (Medium/Large) and the plan-review dispatch (Large): pass 1 is discovery. The lead fixes all findings and verifies each fix inline (grep/read). A delta pass 2 is dispatched only if pass 1 found critical or high issues; after pass 2, any remaining findings are fixed inline and the loop records pass — never a third dispatch.

**Pass 1:**
1. Dispatch the reviewer (prompt shown at each call site below).
2. Extract the `json review-summary` block from the response.
3. Present all issues for visibility, then make triage decisions (fix vs dismiss with reasoning) autonomously — do not stop to ask the user. The user sees the issues and your decisions but the workflow continues without blocking on user input.
4. Apply all fixes and dismissals in a single editing pass, verifying each fix inline (grep/read the changed file) — do not dispatch a reviewer between individual fixes.
5. Initialize `reviews.json` with `[]` if it doesn't exist, then write the pass-1 record: `jq --argjson entry '{"type":"<design-review|plan-review>","scope":"<design|plan>","iteration":1,"issues_found":N,"severity":{"critical":C,"high":H,"medium":M,"low":L},"actionable":N,"dismissed":D,"dismissals":[{"id":ID,"reasoning":"..."}],"fixed":F,"remaining":0,"verdict":"<pass|delta>","timestamp":"<ISO8601>"}' '. += [$entry]' "$PLAN_DIR/reviews.json" > "$PLAN_DIR/reviews.json.tmp" && mv "$PLAN_DIR/reviews.json.tmp" "$PLAN_DIR/reviews.json"` — `verdict` is `"pass"` if zero `critical`/`high` were found (no pass 2 needed), `"delta"` if a pass 2 follows.
6. If zero `critical`/`high` remain: done, proceed to the next checklist step.

**Pass 2 (only if pass 1 found critical or high):**
7. Re-dispatch the same reviewer subagent type with `## Prior Issues` appended after the context lines in the prompt: a JSON array of the prior issues, each enriched with `resolution` (`"fixed"` or `"dismissed"`) and `dismissal_reason` (present only when dismissed).
8. Repeat triage + inline fix/verify (steps 3–4) for any newly reported issues.
9. Write the final `reviews.json` record (`"iteration":2`, `"verdict":"pass"`, `"remaining":0`) — no further dispatch regardless of what remains.

**Design-review dispatch** (Medium/Large):

Read the design reviewer model: `DESIGN_REVIEWER_MODEL=$(caliper-settings get design_reviewer_model)`

```text
Agent(
  subagent_type: "claude-caliper:design-reviewer",
  model: "$DESIGN_REVIEWER_MODEL",
  prompt: "Review the design doc at $PLAN_DIR/design-<topic>.md

    Codebase root: $WORKTREE"
)
```

**Draft-plan dispatch** (Large only, after design-review passes):

Read the planner model: `PLANNER_MODEL=$(caliper-settings get planner_model)`

```text
Agent(
  subagent_type: "claude-caliper:plan-drafter",
  model: "$PLANNER_MODEL",
  mode: "acceptEdits",
  prompt: "Read the design doc at $PLAN_DIR/design-<topic>.md and write
    an implementation plan.

    Working directory: $WORKTREE
    Plan directory: $PLAN_DIR/"
)
```

**Plan-review dispatch** (Large only, after draft-plan returns), same Review Loop Protocol as design-review:

Read the plan reviewer model: `PLAN_REVIEWER_MODEL=$(caliper-settings get plan_reviewer_model)`

```text
Agent(
  subagent_type: "claude-caliper:plan-reviewer",
  model: "$PLAN_REVIEWER_MODEL",
  prompt: "Review the implementation plan at $PLAN_DIR/plan.json

    Design doc: $PLAN_DIR/design-<topic>.md
    Codebase root: $WORKTREE"
)
```

## Route Workflow

Map the Q1 answer to a schema value: `Create PR` → `pr-create`, `Merge PR` → `pr-merge`, `Orchestrate only` → `orchestrate`, `Plan only` → `plan-only` (large tier only).

- **Small/Medium:** No plan.json exists. Invoke the `implement` skill directly, passing the mapped workflow value so it knows how to chain after implementation-review.
- **Large:** Write `.workflow` into plan.json: `jq --arg w "<workflow>" '.workflow = $w' "$PLAN_DIR/plan.json" > "$PLAN_DIR/plan.json.tmp" && mv "$PLAN_DIR/plan.json.tmp" "$PLAN_DIR/plan.json"`

  For multi-phase plans, also write the integration branch name:
  `jq --arg ib "integrate/<feature>" '.integration_branch = $ib' "$PLAN_DIR/plan.json" > "$PLAN_DIR/plan.json.tmp" && mv "$PLAN_DIR/plan.json.tmp" "$PLAN_DIR/plan.json"`

  For **Create PR**, **Merge PR**, or **Orchestrate only**: invoke orchestrate, passing `$PLAN_DIR/plan.json` as the absolute plan path (orchestrate's CWD is the worktree, where plan.json does not exist).
  For **Plan only**: run `validate-plan --check-workflow "$PLAN_DIR/plan.json"` to verify design-review and plan-review passed. Report the plan file path and stop.

## Challenging Assumptions

Before clarifying questions, challenge the framing like a senior PM:

- "What problem does this solve, and for whom?"
- "What would users actually do with this?"
- "Is there a simpler alternative?"

**Example:** User: "All users should have public pages." Challenge: "A public page needs content to show. What would a non-creator put there?" — may surface that the feature isn't needed yet.

## Smart Question Batching

- **Text questions** (word-described choices): batch up to 4 per AskUserQuestion
- **Visual questions** (need ASCII mockups): one at a time, use `markdown` preview
- Text first, visual last
- Each question gets its own options — never "all correct / not correct" toggles
- Ambiguous concepts: explain the difference, offer interpretations as options

## Presenting the Design

- Scale sections to complexity (few sentences to 200-300 words)
- Ask after each section: "Does this look right?"
- Cover: architecture, components, data flow, error handling, testing
- Note shared foundations as **phasing candidates**

**Phasing** (after all sections, large tier only):
- Simple: "Single phase, no dependency layers. Sound right?"
- Complex: "N dependency layers. Phase 1 — [name], Phase 2 — ... Adjust?"

Use AskUserQuestion with "Looks good" / "Adjust phases" options.

## Design Doc Contents

**See:** ./design-spec.md

That file is the authoritative format definition. Required sections in order: Problem, Goal, Success Criteria, Architecture, Test Strategy, Key Decisions, Non-Goals, Implementation Approach, Scope Estimate.
