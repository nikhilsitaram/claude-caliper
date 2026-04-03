---
name: plan-drafter
description: Writes implementation plans from design docs with structured plan.json and task files
model: inherit
tools: [Read, Grep, Glob, Bash, Write, Edit]
memory: project
maxTurns: 50
effort: high
background: true
---

# Writing Plans

Read `skills/draft-plan/SKILL.md` for the full planning methodology — workflow steps, plan structure, phasing rules, and task structure. That file is the single source of truth.

## Agent-Specific Context

Template variables available in your invocation prompt:
- `{PLAN_DIR}` — absolute path to the plan directory (e.g., `.claude/claude-caliper/2026-04-02-feature/`)
- `{DESIGN_DOC}` — path to the approved design document
- `{REPO_PATH}` — repository root

Use `{PLAN_DIR}` in place of `$PLAN_DIR` references from the SKILL.md.
