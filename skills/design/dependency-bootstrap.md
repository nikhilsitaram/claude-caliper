# Dependency Bootstrap

Install dependencies in a worktree so tests and tools work. Run once per worktree; tasks inherit the environment.

## Detection Order

Check tiers in order and stop at the first that matches, installing every matching manifest within it:

1. **Root manifests** — check worktree root for lockfiles/manifests in the table below. If found, run the matching install command at the root.
2. **Workspace indicators** — if no root manifest, check for `pnpm-workspace.yaml`, `nx.json`, `turbo.json`, `lerna.json`. If found, determine the package manager from the lockfile present (`pnpm-lock.yaml` → pnpm, `yarn.lock` → yarn, `package-lock.json` → npm) and run the matching install command at the root. If no lockfile is found alongside the indicator, try `npm install` as the default.
3. **Subdirectory scan** — if neither root manifest nor workspace indicator, scan immediate child directories (one level deep) for manifests. Install in each directory that has one.
4. **Symlink fallback** — if nothing detected, check the main repo root for `.venv` or `node_modules`. If found, symlink into the worktree (`ln -s /abs/path/.venv .venv`). If neither exists, log a warning and continue.

## Install Commands

| Detected file | Command |
|---------------|---------|
| `package-lock.json` | `npm ci` |
| `yarn.lock` | `yarn install --frozen-lockfile` |
| `pnpm-lock.yaml` | `pnpm install --frozen-lockfile` |
| `pyproject.toml` with `[project]` | Python install (see fallback below) |
| `requirements.txt` | Python install with `-r requirements.txt` (see fallback below) |
| `Cargo.toml` | `cargo fetch` |
| `go.mod` | `go mod download` |

## Python Tool Fallback

Check tool availability before running Python install commands:

```bash
if command -v uv >/dev/null 2>&1; then
  uv venv && uv pip install -e '.[dev]'
else
  python3 -m venv .venv && .venv/bin/pip install -e '.[dev]'
fi
```

For `requirements.txt`, replace `-e '.[dev]'` with `-r requirements.txt`.

## Failure Handling

If any install command exits non-zero, log its output and escalate to the user rather than continuing: a broken environment surfaces later as misleading import/module errors instead of a clear 'deps failed'.
