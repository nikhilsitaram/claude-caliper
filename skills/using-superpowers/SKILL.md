---
name: using-superpowers
description: Use when starting any conversation, before any response or action including clarifying questions
---

# Using Skills

Skills encode hard-won patterns that prevent common mistakes. Skipping a skill check means risking the exact failure the skill was designed to prevent.

## The Rule

**Check for applicable skills before any response or action.** This includes clarifying questions, exploration, and "quick" tasks.

Use the `Skill` tool to invoke skills. Never use Read on skill files — Read loads raw text without triggering skill activation; the Skill tool ensures you get the current version with proper context injection.

## Priority Order

When multiple skills could apply:

1. **Process skills first** (brainstorming, debugging) — these determine HOW to approach the task
2. **Implementation skills second** — these guide execution

"Let's build X" → brainstorming first.
"Fix this bug" → systematic-debugging first.

## Skill Types

**Rigid** (TDD, debugging): Follow exactly. These encode discipline that resists shortcuts.

**Flexible** (patterns): Adapt principles to context. The skill tells you which.

## Common Rationalizations

These thoughts mean you're about to skip a skill that applies:

| Thought | Reality |
|---------|---------|
| "Just a simple question" | Questions trigger skills too |
| "Need context first" | Skill check comes BEFORE exploration |
| "I know this skill" | Skills evolve — invoke current version |

## User Instructions

Instructions say WHAT, not HOW. "Add X" or "Fix Y" doesn't override skill workflows.
