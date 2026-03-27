# Design: Settings Self-Sufficiency, Plans Directory, Test Prefix

## Problem

Three related friction points in the claude-caliper plugin:

1. **caliper-settings env var fragility (#148):** The `scripts/caliper-settings` script hard-requires `CLAUDE_PLUGIN_ROOT` and `CLAUDE_PLUGIN_DATA` env vars via `${VAR:?}` guards. These aren't reliably available in the Bash tool's shell environment, so every skill invocation becomes a 3-part incantation: `PLUGIN_ROOT=... PLUGIN_DATA=... .../caliper-settings get <key>`. Additionally, the design skill always prompts for workflow/execution_mode even when the user has explicitly set a preference.

2. **Plans directory location (#147):** Plan artifacts live in `docs/plans/` — a tracked, committed directory. These files are transient workflow state (design docs, plan.json, task prose, review records), not deliverables. They clutter PRs with plan-file commits and pollute the repo with 29 historical plan directories.

3. **Test script naming (#149):** 18 individual `test_*.sh` entries in safe-commands.txt is verbose. The `test_` prefix is too generic for prefix matching (would auto-approve any `test_*` from any repo). All 22 test scripts need a project-scoped prefix.

## Goal

- caliper-settings works with zero env var dependencies — self-locating from its filesystem path
- User-overridden settings skip interactive prompts (design skill uses them directly with notification)
- Plan artifacts are transient (gitignored under `.claude/claude-caliper/`)
- Test scripts use `caliper-test_*` prefix with glob matching in safe-commands hook

## Success Criteria

1. `scripts/caliper-settings get workflow` succeeds without any env vars set
2. `scripts/caliper-settings source workflow` returns `"default"` when no user override exists
3. `scripts/caliper-settings source workflow` returns `"user"` after `caliper-settings set workflow pr-merge`
4. Running any `caliper-test_*.sh` script is auto-approved by the safe-commands hook via the single `caliper-test_*` glob entry
5. All existing tests pass after rename (same assertions, new filenames)
6. Plan artifacts are created under `.claude/claude-caliper/YYYY-MM-DD-<topic>/` and are gitignored
7. Design skill skips workflow/exec_mode prompts when `source` returns `"user"`, showing a notification instead
8. The `.design-approved` sentinel hook finds sentinels under the new `.claude/claude-caliper/` path

## Architecture

### caliper-settings self-location

Replace the `${VAR:?}` guards with auto-derivation:

```bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
CLAUDE_PLUGIN_DATA="${CLAUDE_PLUGIN_DATA:-$CLAUDE_PLUGIN_ROOT/data}"
```

The script sits at `$ROOT/scripts/caliper-settings`, so `dirname` + `..` resolves to plugin root. `CLAUDE_PLUGIN_DATA` defaults to `$ROOT/data/` (matching the actual layout). Env vars still win if set.

### caliper-settings `source` subcommand

New subcommand: `caliper-settings source <key>`
- Check if key exists in `$CLAUDE_PLUGIN_DATA/settings.json` (user overrides)
- Return `"user"` if present, `"default"` otherwise
- Reuses existing `validate_key` for input validation

### Safe-commands prefix/glob matching

Extend `is_safe()` in `pretooluse-safe-commands.sh`:
- Entries ending in `*` use prefix matching (strip the `*`, check if command starts with the prefix)
- All other entries use exact matching (backward-compatible)
- At load time, split safe_list into `exact_list` and `prefix_list` for O(n) matching

### Plans directory

New location: `.claude/claude-caliper/YYYY-MM-DD-<topic>/` (within the worktree working directory). Already gitignored via `.claude/*` in `.gitignore`.

Changes:
- Design skill: create plan dir under new path, remove `git add`/`git commit` of plan files
- Draft-plan skill: write to new path, move schema reference doc into `skills/draft-plan/schema-reference.md`
- Design-review, plan-review: update path references
- Sentinel hook: search `.claude/claude-caliper/` instead of `docs/plans/`
- Delete `docs/plans/` from repo (recoverable from git history)

### Design skill settings-aware prompting

Step 7 changes for Q1 (workflow) and Q2 (execution_mode):
- Call `caliper-settings source <key>`
- If `"user"`: skip that question, use the value directly, message: "Using your configured <setting>: <value>"
- If `"default"`: include in AskUserQuestion with recommended option first, labeled "(Recommended)" — no "(default)" label
- Q3 (approval) always asked regardless

## Key Decisions

1. **No plan.json flag for settings source** — downstream skills already read values from plan.json (written by design), not from caliper-settings. The `source` check is design-time only.
2. **Glob syntax uses trailing `*`** — intuitive, backward-compatible, and entries without `*` remain exact-match.
3. **Plans are per-worktree, not centralized** — each worktree has its own `.claude/claude-caliper/` directory. Plans are destroyed when worktrees are cleaned up after merge, which is acceptable for transient workflow state.
4. **All 22 test scripts renamed** — includes 18 validate-plan, 3 hooks, 1 caliper-settings. Consistent `caliper-test_*` prefix across the project.
5. **Schema reference doc moved to skill directory** — `docs/plans/2026-03-19-structured-plans/design-structured-plans.md` moves to `skills/draft-plan/schema-reference.md` since draft-plan is its only consumer.

## Non-Goals

- Changing the caliper-settings `list` output format
- Adding new settings
- Migrating existing plan history (git history is sufficient)
- Changing how downstream skills (orchestrate, pr-create, etc.) consume settings — they already read from plan.json

## Implementation Approach

**Two phases** based on dependency layers:

### Phase A — Infrastructure (scripts + hooks + test renames)

| Task | Description | Depends |
|------|-------------|---------|
| A1 | caliper-settings: self-location + `source` subcommand | — |
| A2 | Safe-commands: prefix/glob matching for `*` entries | — |
| A3 | Rename all 22 test scripts + update safe-commands.txt + add tests for source & prefix matching | A1, A2 |

A1 and A2 are parallel (disjoint file sets). A3 depends on both.

### Phase B — Consumers + cleanup (depends on Phase A)

| Task | Description | Depends |
|------|-------------|---------|
| B1 | Design skill: new plan path + settings-aware prompting | — |
| B2 | Draft-plan skill: new plan path + move schema reference doc | — |
| B3 | Design-review + plan-review: new plan path references | — |
| B4 | Sentinel hook: update search path + hook test references | — |
| B5 | Delete `docs/plans/` directory | B1, B2, B3, B4 |

B1–B4 are parallel (disjoint file sets). B5 waits for all path updates.

**Phase rationale:** Phase A changes the infrastructure that Phase B consumes (the `source` subcommand, renamed test files, prefix matching). Phase B updates all consumers to use the new infrastructure and paths.
