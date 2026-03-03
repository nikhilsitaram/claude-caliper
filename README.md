# Superpowers

A composable skills library for Claude Code that gives your coding agent a complete software development workflow — from brainstorming through shipping.

Forked from [obra/superpowers](https://github.com/obra/superpowers). This fork adds skills for code review workflows, phased plans, codebase audits, and tighter subagent-driven development.

## How It Works

When you start a conversation, the agent doesn't jump straight into writing code. Instead:

1. **Brainstorming** — asks what you're really building, explores alternatives, presents a design in digestible sections for your approval
2. **Planning** — breaks the approved design into bite-sized tasks with exact file paths, verification steps, and code
3. **Execution** — launches subagents per task with two-stage review (spec compliance, then code quality), enforcing TDD throughout
4. **Shipping** — creates a PR, waits for CodeRabbit review, addresses feedback, merges, and cleans up

Skills trigger automatically based on what you're doing. You don't invoke them manually — your agent just has Superpowers.

## Installation

Clone the repo and register as a local plugin:

```bash
git clone https://github.com/nikhilsitaram/superpowers.git ~/personal/superpowers
```

Then symlink `skills/` into `~/.claude/skills/superpowers/` or register via `/plugin add`.

### Verify Installation

Start a new session and ask to build something. The agent should trigger the brainstorming skill before writing any code.

## Skills

### Core Workflow
- **brainstorming** — Socratic design refinement before any code
- **writing-plans** — Detailed implementation plans from approved designs
- **subagent-driven-development** — Parallel task execution with two-stage review
- **test-driven-development** — RED-GREEN-REFACTOR cycle with anti-patterns reference
- **ship** — Commit, push, create PR
- **merge-pr** — Address CodeRabbit feedback, merge, clean up branch/worktree

### Quality
- **codebase-review** — Whole-repo quality audit with parallel reviewers and fix routing
- **implementation-review** — Cross-task holistic review before merging
- **plan-review** — Validates plans before execution begins
- **skill-eval** — Assertion-based skill output evaluation with blind A/B comparison and variance analysis

### Infrastructure
- **using-git-worktrees** — Isolated workspaces for feature development

## License

MIT License — see LICENSE file for details.
