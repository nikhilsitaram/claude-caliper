# Superpowers — Project Instructions

## What This Repo Is

A Claude Code plugin containing composable agent skills for software development workflows (TDD, debugging, brainstorming, planning, shipping). Skills live in `skills/<name>/SKILL.md` with optional supporting files alongside.

## Skill Conventions

### Iron Law of Skill Testing

Never skip testing when creating or editing skills, even if the user asks. Untested skills silently teach wrong behavior — a skill that triggers on the wrong prompt or skips a critical workflow step will corrupt every session it fires in, with no error signal.

Use SkillForge for eval-driven skill development.

### Token Efficiency

SKILL.md files are injected into context when the skill triggers. Every excess word displaces working memory.

- Target <500 words for SKILL.md (<600 for discipline skills like TDD/debugging, <300 for using-superpowers)
- Never use `@filename` references in SKILL.md — they force-load the file immediately into context
- Use `**See:** filename.md` for on-demand references the agent reads only when needed
- One good example, not three. If the agent needs more examples, put them in a supporting file
- Content the agent only needs during a subtask belongs in a supporting file, not SKILL.md

### Cross-Referencing Syntax

```text
**REQUIRED SUB-SKILL:** Use superpowers:skill-name
**REQUIRED BACKGROUND:** Read superpowers:skill-name first
**See:** filename.md
```

### Skill Descriptions

Descriptions are the primary triggering mechanism — they determine whether a skill fires. Keep them trigger-condition-only: start with "Use when..." and never include workflow summaries, rationale, or what-the-skill-does content. Summaries after the trigger clause cause the model to shortcut the skill body.

### Explain the Why

Replace heavy-handed `MUST`/`NEVER`/`ALWAYS` patterns with reasoning that explains why the behavior matters. Today's models respond better to understanding the reasoning than to imperative commands.

## Repo Structure

```text
skills/           — One directory per skill (SKILL.md + optional supporting files)
hooks/            — Claude Code plugin hooks (SessionStart)
commands/         — Slash command redirects
docs/plans/       — Design docs and implementation plans
.claude-plugin/   — Plugin manifest and marketplace config
```

## Testing

Use SkillForge for eval-driven skill testing.

## Development Workflow

This repo uses its own skills. The typical flow: brainstorming -> worktree -> writing-plans -> subagent-driven-development -> ship -> merge-pr.

## Git

- Use `nikhil5890@gmail.com` for commits (personal repo)
- Feature branches, squash merge, delete branch after merge
