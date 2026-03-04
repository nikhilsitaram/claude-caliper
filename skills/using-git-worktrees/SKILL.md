---
name: using-git-worktrees
description: Use when starting feature work that needs isolation from current workspace or before executing implementation plans
---

# Using Git Worktrees

Git worktrees create isolated workspaces sharing the same repository, allowing work on multiple branches simultaneously without switching.

**Core principle:** Systematic directory selection + safety verification = reliable isolation.

## Workflow

### 1. Find or Create Worktree Directory

Follow this priority — never assume a location:

1. **Check for `.worktrees/`** in the repo root
2. **Check CLAUDE.md** for a worktree directory preference
3. **Ask the user** which location to use

### 2. Create Worktree

```bash
git worktree add <path>/<branch-name> -b <branch-name>
```

Use the absolute path for all subsequent commands — `cd` in Claude Code's bash tool does not persist across calls.

### 4. Run Project Setup

Auto-detect from project files:

| File | Command |
|------|---------|
| `package.json` | `npm install` |
| `requirements.txt` | `pip install -r requirements.txt` |
| `pyproject.toml` | `poetry install` or `pip install -e .` |
| `Cargo.toml` | `cargo build` |
| `go.mod` | `go mod download` |

### 5. Verify Clean Baseline

Run the project's test suite. If tests fail, report failures and ask whether to proceed or investigate — don't silently continue, because you won't be able to tell later whether failures are pre-existing or caused by your changes.

### 6. Report Ready

```
Worktree ready at <full-path>
Tests passing (<N> tests, 0 failures)
Ready to implement <feature-name>
```

## Quick Reference

| Situation | Action |
|-----------|--------|
| `.worktrees/` exists | Use it |
| `.worktrees/` missing | Check CLAUDE.md → Ask user |
| Tests fail during baseline | Report failures + ask |
| No package.json/Cargo.toml | Skip dependency install |

## Integration

**Called by:**
- **brainstorming** — after design approval, before implementation begins
- **orchestrating** — before executing any tasks

**Pairs with:**
- **ship** — commits, pushes, creates PR after work complete
- **merge-pr** — addresses review feedback, merges PR, cleans up worktree and branch
