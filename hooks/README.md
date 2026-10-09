# Hooks and Safe Commands

Hook scripts and configuration for the claude-caliper plugin.

## Files

| File | Purpose |
|------|---------|
| `hooks.json` | Hook registry — wired automatically by the plugin system |
| `lib-command-parser.sh` | Shared library: segment extraction, command word parsing, safe-commands loading |
| `pretooluse-deny-plan-md.sh` | PreToolUse(Edit/Write/MultiEdit): denies hand-edits to a rendered `plan.md`, pointing Claude at the `validate-plan` command that mutates `plan.json` instead |
| `permission-request-allow.sh` | PermissionRequest(Read/Glob/.../Bash): auto-allows safe tools/commands with session-scoped caching |
| `permission-request-accept-edits.sh` | PermissionRequest(Edit/Write): consumes the `.design-approved` sentinel to enable acceptEdits mode for the session; auto-allows writes to `.claude/claude-caliper/` plan dirs. All fallthrough paths emit `{"continue": true}` to avoid [anthropics/claude-code#12070](https://github.com/anthropics/claude-code/issues/12070) (silent fallthrough = deny). |
| `safe-commands.txt` | Bundled default safe command prefixes (~60 common dev tools). Deliberately excludes anything that runs code from its arguments — inline interpreters (`python`, `node`), package runners (`npx`, `uvx`), exec wrappers (`env`, `xargs`, `command`), `find` (`-exec`), `awk` (`system()`) — since a safe-listed first word would auto-approve arbitrary code (#302). Kept for usability despite narrower exec paths: `npm`/`uv`/`pytest` (run project-defined scripts, like tests), `git` (`-c alias`), `gh` (shell aliases), `sed` (GNU `e`). |

## Architecture

Hooks are split by lifecycle event:

- **PreToolUse** — fires on every tool call. Used only for **deny** decisions (with `permissionDecisionReason` visible to Claude for self-correction). Never returns allow. There is deliberately no Bash deny hook: one that scanned command text for risky shapes fired in every permission mode and false-denied heredoc data lines (#294). In auto mode the classifier covers it; in default and acceptEdits sessions an unlisted command simply prompts, and the allow hook never auto-approves a shell interpreter (`bash`/`sh`/`zsh …`) — run scripts by path (`./script`).
- **PermissionRequest** — fires when a permission prompt would appear (or a call that can't prompt would be auto-denied), so classifier approvals in auto mode never reach it; it remains the fallback for default-mode sessions, whose background subagents can't answer prompts. Used for **allow** decisions. Returns `updatedPermissions` with session-scoped rules so the hook self-caches (first allow adds a rule, subsequent identical patterns skip the hook entirely).

## Safe Commands: Override Model

The hook checks for a **user file first**, falling back to bundled defaults:

- If `~/.claude/safe-commands.txt` exists, **only** that file is used (full user control)
- If it doesn't exist, `hooks/safe-commands.txt` (bundled defaults) is used

This means you can remove commands from the defaults by creating your own file.

## Coexistence with Personal Hooks

Multiple hooks of the same event type run independently. If you have personal hooks for domain-specific tools, they coexist without conflict.
