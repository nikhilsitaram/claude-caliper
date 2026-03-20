# Config — Hooks and Safe Commands

Hook scripts and configuration for the claude-caliper plugin.

## Files

| File | Purpose |
|------|---------|
| `hooks.json` | Hook registry — wired automatically by the plugin system |
| `pretooluse-safe-commands.sh` | Auto-approves Bash commands matching safe list prefixes |
| `safe-commands.txt` | Bundled default safe command prefixes (~35 common dev tools) |
| `post-tool-use-design-approval.sh` | Creates sentinel after design approval |
| `permission-request-accept-edits.sh` | Enables acceptEdits mode after design approval |

## Safe Commands: Two-File Model

The hook reads from **two files**:

1. **Bundled defaults** (`config/safe-commands.txt`) — ships with the plugin, covers common dev tools (git, npm, pytest, jq, etc.). Don't edit this directly — updates overwrite it.

2. **User additions** (`~/.claude/safe-commands.txt`) — your personal additions that survive plugin updates. The learning loop in the phase dispatcher appends here when you approve new commands.

To add a command manually:

```bash
echo "cargo" >> ~/.claude/safe-commands.txt
```

## Coexistence with Personal Hooks

Multiple PreToolUse hooks run independently. If you have personal hooks for domain-specific tools (MCP servers, internal CLIs), they coexist without conflict. The first hook to return `permissionDecision: allow` wins.
