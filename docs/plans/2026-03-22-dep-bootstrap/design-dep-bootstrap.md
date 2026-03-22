# Design: Worktree Dependency Bootstrap

## Problem

Worktree dependency bootstrapping in the orchestrate skill has four gaps that cause silent failures or misconfigured environments:

1. **No monorepo support** — detection only checks the worktree root. Repos with manifests in subdirectories (e.g., `backend/pyproject.toml` + `frontend/package.json`) or workspace managers hit the symlink fallback and get no deps installed.
2. **No tool availability check** — Python install commands assume `uv` is available. The parenthetical fallback to `python3 -m venv` is prose, not conditional logic the agent would execute.
3. **No install failure handling** — if an install command exits non-zero, the bootstrap continues silently. Tasks then fail with cryptic import/module errors instead of a clear "deps failed" message.
4. **Design skill skips bootstrap entirely** — the design skill creates the integration worktree and runs tests as a baseline, but never installs dependencies. Tests fail immediately in any repo that needs deps.

These affect every repo that uses the orchestrate or design skills with worktrees.

## Goal

Make worktree dependency bootstrapping reliable across single-root repos, workspace-based monorepos, and multi-manifest repos, with clear failure reporting and tool availability fallbacks.

## Success Criteria

1. In a monorepo where manifests live only in subdirectories (no root manifest), worktree bootstrap detects and installs those dependencies without manual intervention.
2. An agent on a machine without `uv` falls back to `python3 -m venv + pip` without error.
3. When `npm ci` exits non-zero, the agent stops and escalates to the user instead of continuing with broken deps.
4. The design skill bootstraps dependencies before running baseline tests, using the same procedure as orchestrate.

## Architecture

Extract the bootstrap procedure to `skills/design/dependency-bootstrap.md` — a shared reference file read on-demand by both skills. The design skill is the natural owner because it creates the first worktree where bootstrap runs.

```text
skills/design/dependency-bootstrap.md  ← authoritative procedure (new)
skills/design/SKILL.md step 6          ← new sub-step: bootstrap deps, then run tests
skills/orchestrate/SKILL.md step 3     ← replaces inline table + symlink prose with
                                          one-line summary + **See:** reference
```

**What changes in each SKILL.md:**

- **design/SKILL.md step 6** currently reads: "Set up worktree — `git worktree add ...`; run tests to establish a clean baseline." It becomes two sub-steps: (a) create worktree, (b) bootstrap dependencies per `**See:** ./dependency-bootstrap.md`, (c) run tests. No new top-level step is added.
- **orchestrate/SKILL.md step 3** currently has the full install table (lines 72-86, ~180 words) and symlink fallback prose. These are replaced by a one-line summary ("Bootstrap dependencies in the phase worktree") with `**See:** skills/design/dependency-bootstrap.md` for the full procedure. This frees ~150 words of token budget.

### Detection Order

1. **Root manifests** — check worktree root for known lockfiles/manifests (existing behavior)
2. **Workspace indicators** — if no root manifest, check for `pnpm-workspace.yaml`, `nx.json`, `turbo.json`, `lerna.json`; if found, install at root using the lockfile present to determine the command (e.g., `pnpm-lock.yaml` → `pnpm install --frozen-lockfile`)
3. **Subdirectory scan** — if neither root manifest nor workspace indicator, scan immediate child directories for manifests; install in each that has one
4. **Symlink fallback** — if nothing detected, symlink `.venv`/`node_modules` from main repo root (existing behavior)

### Python Tool Fallback

```text
if command -v uv: uv-based commands
else: python3 -m venv + pip
```

### Failure Handling

Check exit code of every install command. Non-zero → log the error output and escalate to the user. Do not continue with a broken environment — tasks will fail with misleading errors.

## Alternatives Considered

1. **Extend the inline table in orchestrate SKILL.md** — simplest, but duplicates the procedure when design also needs it. Both skills would drift independently over time. Rejected.
2. **PreToolUse hook that auto-installs deps** — would run outside the agent's control, making failures harder to diagnose. Hooks can't escalate to the user. Rejected.
3. **Shared reference file (chosen)** — single source of truth, on-demand read via `**See:**`, no token cost when bootstrap isn't needed. The cross-skill reference (`orchestrate` → `skills/design/dependency-bootstrap.md`) follows the existing `**See:**` convention used elsewhere (e.g., `draft-plan` → `skills/plan-review/reviewer-prompt.md`) — the agent reads the file path at execution time, so cross-directory references work the same as local ones.

## Key Decisions

- **Reference file lives under `skills/design/`** — design creates the first worktree, making it the natural owner. Orchestrate references it via `**See:** skills/design/dependency-bootstrap.md`. Trade-off: if the design skill directory is renamed, orchestrate's reference breaks. Acceptable because skill directory renames are rare and grep-detectable.
- **Exit code check, not import validation** — if `npm ci` exits 0, deps are installed. No need for `python -c "import pkg"` which requires knowing package names and is fragile.
- **Subdirectory scan is one level deep** — deeply nested manifests are an edge case not worth the complexity. One level covers `backend/`, `frontend/`, `packages/foo/` patterns.
- **Workspace managers get root-level install** — `pnpm install`, `npm ci`, `yarn install` at root handle all packages in a workspace. No need to install per-package.

## Non-Goals

- Auto-detecting the correct Python version (pyenv, asdf) — out of scope
- Supporting Gradle, Maven, or other JVM build tools — can be added later to the table
- Nested monorepo structures (workspaces within workspaces)
- Caching or sharing deps across phase worktrees (symlink fallback partially covers this)

## Implementation Approach

Single phase — three tightly coupled files, all modifying skill text (no code):

1. Create `skills/design/dependency-bootstrap.md` — structured as: (a) detection order (4 tiers), (b) install command table with workspace-aware commands, (c) Python tool fallback logic, (d) failure handling procedure, (e) symlink fallback. Target: under 400 words.
2. Edit `skills/design/SKILL.md` step 6 — split into sub-steps: (a) create worktree, (b) bootstrap deps via `**See:** ./dependency-bootstrap.md`, (c) run tests.
3. Edit `skills/orchestrate/SKILL.md` step 3 — replace the inline install table and symlink prose (~180 words) with a one-line summary + `**See:** skills/design/dependency-bootstrap.md`.
