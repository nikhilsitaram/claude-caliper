# Superpowers — Project Instructions

## What This Repo Is

A Claude Code plugin containing composable agent skills for software development workflows (TDD, design, implement, draft-plan, orchestrate, pr-create). Skills live in `skills/<name>/SKILL.md` with optional supporting files alongside.

## Skill Conventions

### Skill Testing

Use skill-eval for dedicated skill refactors or new skill creation where triggering accuracy and workflow correctness need validation. For routine skill edits (wording changes, model upgrades, adding a section), eval is overkill — manual review is sufficient.

### Token Efficiency

SKILL.md files are injected into context when the skill triggers. Every excess word displaces working memory. Budget: 1,500 words (hard cap 2,000). The more concise, the better.

Challenge every line: Does the agent already know this? Does this paragraph justify its token cost? Only add context Claude doesn't already have — library knowledge, common patterns, and standard practices are already in the model.

- Never use `@filename` references in SKILL.md — they force-load the file immediately into context
- Use `**See:** filename.md` for on-demand references the agent reads only when needed, but only when the content is truly conditional (not every invocation)
- One good example, not three. If the agent needs more examples, put them in a supporting file

### Cross-Referencing Syntax

```text
**REQUIRED SUB-SKILL:** Use skill-name
**REQUIRED BACKGROUND:** Read skill-name first
**See:** filename.md
```

### Skill Descriptions

Descriptions are the primary triggering mechanism — they determine whether a skill fires. Keep them trigger-condition-only: start with "Use when..." and never include workflow summaries, rationale, or what-the-skill-does content. Summaries after the trigger clause cause the model to shortcut the skill body.

### Explain the Why

Replace heavy-handed `MUST`/`NEVER`/`ALWAYS` patterns with reasoning that explains why the behavior matters. Today's models respond better to understanding the reasoning than to imperative commands.

## Repo Structure

```text
skills/           — One directory per skill (SKILL.md + optional supporting files)
docs/reviews/     — Codebase review reports
.claude-plugin/   — Plugin manifest and marketplace config
```

Plan artifacts (design docs, plan.json, task briefs) are created by the design/draft-plan skills under `$MAIN_ROOT/.claude/claude-caliper/` (main repo root, gitignored). They live in the main checkout — not the worktree — so they persist across worktree cleanup as a local record of design decisions and execution history.

## Testing

Bash test scripts live in `tests/`. Run with `bash tests/<dir>/<script>.sh`. Skill-eval is available for dedicated skill refactors — see Skill Testing above.

## Scripts

All shell scripts (`bin/*`, `tests/**/*.sh`) must have a `#!/usr/bin/env bash` shebang and the executable bit set (`chmod +x`). Dispatched subagents can't auto-approve `bash <script>` because `bash` is excluded from safe-commands — but `./script` resolves to the script's own path, which the hook can approve.

In `hooks/hooks.json`, `command`-type hooks always require a `command` string — even in exec form, where `command` is the *executable* and `args` is its argument vector (e.g. `"command": "bash", "args": ["${CLAUDE_PLUGIN_ROOT}/hooks/x.sh"]`). Putting the script path in `args` with no `command` fails schema validation (`command: expected string, received undefined`) and silently disables every hook.

### Platform-specific & externally-wired skills

`queue` and `usage-guard` use BSD `date` (`date -r <epoch>`, `date -j -f`) and are **macOS-only** — `date -r` reads a file mtime on GNU/Linux. Their tests guard with `date -r 0 >/dev/null 2>&1` and print `SKIP` rather than fail, so they are intentionally **not** wired into the Linux CI job; run them on macOS. They also depend on a statusline tap (`skills/queue/scripts/statusline-wrapper.sh`) the user must wire into `statusLine` themselves — a plugin can't auto-edit user settings. When a skill needs that kind of out-of-band setup, document it in the skill's `README.md` and gate the dependent path behind a clear error, as `queue` does.

## Development Workflow

This repo uses its own skills. The design skill routes work into one of three tiers by its actual shape, so ceremony scales with size:

- **Small** (≤~2 files, obvious approach) — in-conversation design + explicit approval, then the `implement` skill runs inline TDD in the main session. No plan artifacts.
- **Medium** (one coherent change, fits one context, no genuine parallelism; the default when in doubt) — a short design doc + one design-review pass, then `implement` inline TDD.
- **Large** (genuine parallelism, dependency layers, or bulk beyond one sitting) — full ceremony: design doc + design-review, then draft-plan -> orchestrate.

Every tier ends with one independent implementation-review over the integrated diff, then the PR chain (pr-create -> pr-review -> pr-merge) per the `workflow` setting.

Orchestrate (large tier only) dispatches each task as a parallel subagent with its own git worktree; file-set isolation keeps tasks in a phase conflict-free, and phases run sequentially so a later phase sees earlier phases' merged work. plan.json holds every task's metadata — there are no separate task `.md` files, and each task is not reviewed on its own; the per-phase implementation-review is the gate.

## Markdown

- Always add a language label to fenced code blocks (MD040) — CodeRabbit flags this on every PR

## Git

- Use `nikhil5890@gmail.com` for commits (personal repo)
- Feature branches, squash merge, delete branch after merge
- Bump `version` in `.claude-plugin/marketplace.json` in any PR that changes skill behavior — the plugin installer compares cached vs declared version, so without a bump users stay on stale cache
- After merging a PR that bumps the version, create a GitHub release (`gh release create vX.Y.Z --generate-notes`) so users can track changes
