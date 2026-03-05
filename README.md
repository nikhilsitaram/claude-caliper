<div align="center">

# claude-caliper

**Measure twice, cut once.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-plugin-6E40C9?logo=anthropic&logoColor=white)](https://claude.ai/code)
[![Skills](https://img.shields.io/badge/9%20skills-included-2ea44f)](skills/)

</div>

---

Claude wants to write code immediately — before the design is agreed on, before the plan accounts for edge cases, before tests exist. When it does plan, the plans are too vague to execute without guessing.

claude-caliper installs a complete development workflow as skills that fire automatically at the right moment. Design before plan. Plan before code. Test before merge. Every time.

```mermaid
flowchart LR
    A([Idea]) --> B[Brainstorm]
    B --> C[Plan]
    C --> D[Plan Review]
    D --> E[Build + TDD]
    E --> F[Impl Review]
    F --> G[Ship PR]
    G --> H[Merge]

    style D fill:#fef3c7,stroke:#d97706,color:#000
    style F fill:#fef3c7,stroke:#d97706,color:#000
```

Yellow nodes are quality gates — the workflow pauses here until the stage is solid.

---

## Installation

```
/plugin add claude-caliper
```

Or via the CLI:

```bash
claude plugin marketplace add https://github.com/nikhilsitaram/claude-caliper
claude plugin install claude-caliper@claude-caliper
```

**Verify:** Start a new session and describe something you want to build. Claude should trigger the brainstorming skill before writing a single line of code.

---

## The Pipeline

Skills fire automatically as your work progresses through each stage.

| Skill | Triggers when | Does |
|-------|---------------|------|
| [brainstorming](skills/brainstorming/) | You describe something to build | Challenges assumptions, proposes 2-3 approaches, gets design sign-off before any code |
| [writing-plans](skills/writing-plans/) | Design is approved | Produces a task checklist with exact file paths, TDD steps, and runnable verification commands |
| [plan-review](skills/plan-review/) | Plan is written | Validates completeness — catches vague steps and missing paths before execution starts |
| [orchestrating](skills/orchestrating/) | Plan passes review | Dispatches parallel subagents per task, each running full RED→GREEN→REFACTOR; spec + code review after every task |
| [implementation-review](skills/implementation-review/) | All tasks complete | Cross-task holistic review — catches inconsistencies a per-task reviewer can't see |
| [ship](skills/ship/) | Implementation passes review | Commits, pushes, opens PR with summary |
| [merge-pr](skills/merge-pr/) | PR is reviewed | Addresses feedback, merges, cleans up branch and worktree |

---

## Differentiators

### Codebase Review

Most review tools look at diffs. `codebase-review` audits the whole repo in parallel — one Explore subagent per top-level directory, then a cross-scope reconciliation pass that catches duplication and naming drift the per-directory reviewers couldn't see.

Findings are triaged by fix complexity, not severity: a critical one-liner goes straight to `writing-plans`; a medium refactor across 10 files becomes a GitHub issue. No manual sorting.

```
/codebase-review          # entire repo
/codebase-review src/     # scoped to a directory
```

Categories: DRY · YAGNI · Simplicity & Efficiency · Refactoring Opportunities · Consistency

### Skill Eval

Skills degrade silently. A prompt tweak that looks like an improvement might drop pass rates on adversarial scenarios. `skill-eval` measures before you ship.

- **Assertion-based grading** — each eval defines expected behaviors; a grader subagent checks them with cited evidence, not keyword matching
- **Blind A/B comparison** — before/after outputs scored on Content + Structure without knowing which is which
- **Adversarial scenarios** — deadline pressure, "skip this step" prompts; these surface enforcement gaps that positive evals miss entirely
- **Variance analysis** — 3 runs per scenario, mean ± stddev; distinguishes real improvements from noise

```
/skill-eval               # interactive: picks skill, runs evals, reports delta
```

---

## Design Principles

**Lean by default.** Each skill is under 1,000 words. Skills teach Claude what it doesn't already know — workflow gates, project conventions, quality thresholds — not things it can reason from first principles.

**Eval-driven.** Every skill change runs through `skill-eval` before shipping. Pass rate + blind comparison + variance. No guessing whether the rewrite is better.

**Quality gates, not suggestions.** The workflow stops at design review, plan review, and implementation review. These aren't optional checkpoints — they're the moments that prevent the most rework.

---

## License

MIT
