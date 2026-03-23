# Superpowers — Project Instructions

## What This Repo Is

A Claude Code plugin containing composable agent skills for software development workflows (TDD, design, draft-plan, orchestrate, create-pr). Skills live in `skills/<name>/SKILL.md` with optional supporting files alongside.

## Skill Conventions

### Iron Law of Skill Testing

Never skip testing when creating or editing skills, even if the user asks. Untested skills silently teach wrong behavior — a skill that triggers on the wrong prompt or skips a critical workflow step will corrupt every session it fires in, with no error signal.

Use the skill-eval skill for eval-driven skill development.

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
docs/plans/       — Design docs and implementation plans
docs/reviews/     — Codebase review reports
.claude-plugin/   — Plugin manifest and marketplace config
```

## Testing

Use the skill-eval skill for eval-driven skill testing.

## Development Workflow

This repo uses its own skills. The typical flow: design -> worktree -> draft-plan -> orchestrate -> create-pr -> review-pr -> merge-pr.

## Markdown

- Always add a language label to fenced code blocks (MD040) — CodeRabbit flags this on every PR

## Git

- Use `nikhil5890@gmail.com` for commits (personal repo)
- Feature branches, squash merge, delete branch after merge
- Bump `version` in `.claude-plugin/marketplace.json` in any PR that changes skill behavior — the plugin installer compares cached vs declared version, so without a bump users stay on stale cache
- After merging a PR that bumps the version, create a GitHub release (`gh release create vX.Y.Z --generate-notes`) so users can track changes
