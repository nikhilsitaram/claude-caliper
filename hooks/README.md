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
| `safe-commands.txt` | Bundled default safe command prefixes (~57 common dev tools) |

## Architecture

Hooks are split by lifecycle event:

- **PreToolUse** — fires on every tool call. Used only for **deny** decisions (with `permissionDecisionReason` visible to Claude for self-correction). Never returns allow. There is deliberately no Bash deny hook: one that scanned command text for risky shapes fired in every permission mode, false-denied heredoc data lines (#294), and is redundant with auto mode's classifier.
- **PermissionRequest** — fires only when a permission prompt would appear, so it is inert under auto mode and remains a fallback for default-mode sessions, whose background subagents can't answer prompts. Used for **allow** decisions. Returns `updatedPermissions` with session-scoped rules so the hook self-caches (first allow adds a rule, subsequent identical patterns skip the hook entirely).

## Safe Commands: Override Model

The hook checks for a **user file first**, falling back to bundled defaults:

- If `~/.claude/safe-commands.txt` exists, **only** that file is used (full user control)
- If it doesn't exist, `hooks/safe-commands.txt` (bundled defaults) is used

This means you can remove commands from the defaults by creating your own file.

## Coexistence with Personal Hooks

Multiple hooks of the same event type run independently. If you have personal hooks for domain-specific tools, they coexist without conflict.
