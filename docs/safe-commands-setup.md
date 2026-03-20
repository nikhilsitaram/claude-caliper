# Safe Commands Hook Setup

The PreToolUse safe commands hook auto-approves Bash commands matching `config/safe-commands.txt` prefixes, eliminating per-command AI evaluation overhead for common dev tools.

## Automatic Setup (Plugin Install)

If you installed via the plugin system, the hook is wired automatically through `config/hooks.json`. No manual configuration needed.

## Manual Setup (settings.json)

If the hook isn't firing (common dev commands still prompt for approval), add the PreToolUse hook to your Claude Code settings:

**File:** `~/.claude/settings.json`

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/claude-caliper/config/pretooluse-safe-commands.sh"
          }
        ]
      }
    ]
  }
}
```

Replace `/path/to/claude-caliper` with the actual path to your plugin installation.

## Coexistence with Personal Hooks

Multiple PreToolUse hooks run independently. If you have personal hooks for domain-specific tools (MCP servers, internal CLIs), they coexist without conflict. The first hook to return `permissionDecision: allow` wins.

## Customizing the Safe List

Edit `config/safe-commands.txt` to add or remove command prefixes. One prefix per line. Changes take effect immediately for new commands.

The phase dispatcher also surfaces non-safe commands after each task during orchestrated execution, letting you approve additions interactively.
