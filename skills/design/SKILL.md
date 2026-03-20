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
4. **Propose 2-3 approaches** — trade-offs and your recommendation
5. **Present design** — sections scaled to complexity, approval after each
6. **Set up worktree** — `git worktree add -b integrate/<feature> .claude/worktrees/<feature>`; run tests to establish a clean baseline. This is the integration branch — phase worktrees are created by orchestrate as siblings.
7. **Design approval gate** — use AskUserQuestion with options `["Approved", "Needs changes"]`, include `metadata: { source: "design-approval" }` and absolute plan dir path in question text (format: `Plan dir: /absolute/path/.claude/worktrees/<feature>/docs/plans/YYYY-MM-DD-topic`). If "Needs changes," return to step 5. The PostToolUse hook creates a `.design-approved` sentinel enabling auto-approved edits for the rest of the session.
8. **Write design doc** — `docs/plans/YYYY-MM-DD-<topic>/design-<topic>.md`, commit
9. **Dispatch design-review subagent** — fresh Opus agent validates design before planning (hard gate)
10. **Dispatch draft-plan subagent** — fresh Opus agent with design doc path and worktree path (zero design context)
11. **Route workflow** — After draft-plan returns, ask the user:

    AskUserQuestion (header: "Workflow"):
    - **Ship** — Full auto: orchestrate executes, reviews, and ships
    - **Review only** — Orchestrate executes and reviews, creates final PR but doesn't merge
    - **Plan only** — Stop here. Plan is written and reviewed.

    Map the chosen label to the schema enum value (`Ship` → `ship`, `Review only` → `review-only`, `Plan only` → `plan-only`), then write: `jq --arg w "<mapped-value>" '.workflow = $w' plan.json > tmp && mv tmp plan.json`

    For **Ship** or **Review only**: invoke orchestrate.
    For **Plan only**: report the plan file path and stop.

```text
Agent(
  subagent_type: "general-purpose",
  model: "opus",
  prompt: "Review the design doc at docs/plans/<folder>/design-<topic>.md
    using the design-review skill.
    Working directory: .claude/worktrees/<feature>"
)
```

If design-review finds issues, present them to the user, collaboratively fix the design doc, and re-dispatch design-review until clean. Only dispatch draft-plan after design-review passes.

```text
Agent(
  subagent_type: "general-purpose",
  model: "opus",
  prompt: "Read the design doc at docs/plans/<folder>/design-<topic>.md and write
    an implementation plan using the draft-plan skill.
    Working directory: .claude/worktrees/<feature>"
)
```

**Approval gate format:**

```json
{
  "questions": [{
    "question": "Design approved? Plan dir: <absolute-worktree-path>/docs/plans/YYYY-MM-DD-topic",
    "options": [
      { "label": "Approved", "description": "Write design doc and proceed to review" },
      { "label": "Needs changes", "description": "Continue iterating on the design" }
    ]
  }],
  "metadata": { "source": "design-approval" }
}
```

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

**Phasing** (after all sections):
- Simple: "Single phase, no dependency layers. Sound right?"
- Complex: "N dependency layers. Phase 1 — [name], Phase 2 — ... Adjust?"

Use AskUserQuestion with "Looks good" / "Adjust phases" options.

## Design Doc Contents

When writing the design doc (`docs/plans/YYYY-MM-DD-<topic>/design-<topic>.md`):
- Sections in order: Problem, Goal, Success Criteria, Architecture, Key Decisions, Non-Goals, Implementation Approach
- **Problem** — what's broken, who's affected, consequences of not solving
- **Success Criteria** — human-verifiable behavioral statements (not "tests pass"); collectively complete (all pass = goal met), individually necessary
- If multi-phase: **Implementation Approach** includes phase rationale
