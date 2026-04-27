# Hooks and Safe Commands

Hook scripts and configuration for the claude-caliper plugin.

## Files

| File | Purpose |
|------|---------|
| `hooks.json` | Hook registry — wired automatically by the plugin system |
| `lib-command-parser.sh` | Shared library: segment extraction, command word parsing, safe-commands loading |
| `pretooluse-deny-patterns.sh` | PreToolUse(Bash): denies `bash -c`, `bash script.sh`, `$VAR` commands with feedback to Claude |
| `permission-request-allow.sh` | PermissionRequest(Read/Glob/.../Bash): auto-allows safe tools/commands with session-scoped caching |
| `permission-request-accept-edits.sh` | _Currently unwired_ — PermissionRequest(Edit/Write) hook for enabling acceptEdits mode after design approval. Disabled pending upstream fix to [anthropics/claude-code#12070](https://github.com/anthropics/claude-code/issues/12070), which causes Edit/Write to be denied in dispatched subagents even with `mode: "acceptEdits"`. |
| `safe-commands.txt` | Bundled default safe command prefixes (~57 common dev tools) |

## Architecture

Hooks are split by lifecycle event:

- **PreToolUse** — fires on every tool call. Used only for **deny** decisions (with `permissionDecisionReason` visible to Claude for self-correction). Never returns allow.
- **PermissionRequest** — fires only when a permission prompt would appear. Used for **allow** decisions. Returns `updatedPermissions` with session-scoped rules so the hook self-caches (first allow adds a rule, subsequent identical patterns skip the hook entirely).

## Safe Commands: Override Model

The hook checks for a **user file first**, falling back to bundled defaults:

- If `~/.claude/safe-commands.txt` exists, **only** that file is used (full user control)
- If it doesn't exist, `hooks/safe-commands.txt` (bundled defaults) is used

This means you can remove commands from the defaults by creating your own file.

## Coexistence with Personal Hooks

Multiple hooks of the same event type run independently. If you have personal hooks for domain-specific tools, they coexist without conflict.
