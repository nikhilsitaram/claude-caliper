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
6. **Get verbal approval** — explicit "yes" before proceeding
7. **Set up worktree** — `git worktree add .worktrees/<branch-name> -b <branch-name>`; run tests to establish a clean baseline
8. **Write design doc** — `docs/plans/YYYY-MM-DD-<topic>/design-<topic>.md`, commit
9. **Dispatch draft-plan subagent** — fresh Opus agent with design doc path and worktree path (zero design context)

```text
Agent(
  subagent_type: "general-purpose",
  model: "opus",
  prompt: "Read the design doc at docs/plans/<folder>/design-<topic>.md and write
    an implementation plan using the draft-plan skill.
    Working directory: <absolute-worktree-path>"
)
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
- Include: goal, architecture approach, key decisions, non-goals
- If multi-phase: add **Implementation Approach** section with phase rationale
