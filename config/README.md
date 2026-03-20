# Config — Hooks and Safe Commands

Hook scripts and configuration for the claude-caliper plugin.

## Files

| File | Purpose |
|------|---------|
| `hooks.json` | Hook registry — wired automatically by the plugin system |
| `pretooluse-safe-commands.sh` | Auto-approves Bash commands matching safe list prefixes |
| `safe-commands.txt` | Bundled default safe command prefixes (~57 common dev tools) |
| `post-tool-use-design-approval.sh` | Creates sentinel after design approval |
| `permission-request-accept-edits.sh` | Enables acceptEdits mode after design approval |

## Safe Commands: Override Model

The hook checks for a **user file first**, falling back to bundled defaults:

- If `~/.claude/safe-commands.txt` exists, **only** that file is used (full user control)
- If it doesn't exist, `config/safe-commands.txt` (bundled defaults) is used

This means you can remove commands from the defaults by creating your own file. The learning loop copies bundled defaults to the user file before the first append, so you start with the full default list.

To customize:

```bash
cp "$(dirname "$(which claude)")/../config/safe-commands.txt" ~/.claude/safe-commands.txt
# Now edit ~/.claude/safe-commands.txt to add/remove commands
```

## Coexistence with Personal Hooks

Multiple PreToolUse hooks run independently. If you have personal hooks for domain-specific tools (MCP servers, internal CLIs), they coexist without conflict. The first hook to return `permissionDecision: allow` wins.
