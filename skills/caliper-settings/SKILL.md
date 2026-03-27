---
name: caliper-settings
description: Use when the user wants to view, change, or reset their persistent preferences, or when triggered by "/caliper-settings", "my settings", "change defaults".
---

# Caliper Settings

View and manage persistent user preferences. Settings follow 3-tier precedence: CLI flag > user setting > shipped default.

## Commands

Run the settings script to manage preferences:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/caliper-settings list
${CLAUDE_PLUGIN_ROOT}/scripts/caliper-settings get <key>
${CLAUDE_PLUGIN_ROOT}/scripts/caliper-settings set <key> <value>
${CLAUDE_PLUGIN_ROOT}/scripts/caliper-settings reset [key]
```

### List all settings
Shows each setting with its current value (user override or default), the shipped default, and a description.

### Get a setting
Returns the merged value (user override if set, otherwise default). Other skills call this as a fallback when no CLI flag is passed.

### Set a setting
Persists a user override. The script validates the value against the setting's type (bool, enum, int) and rejects invalid values with a clear error.

### Reset a setting (or all)
Removes a user override so the setting falls back to its shipped default. With no key argument, resets all settings.

## Available Settings

| Key | Type | Default | Used by |
|-----|------|---------|---------|
| `skip_tests` | bool | `false` | pr-create |
| `review_mode` | enum | `deliberate` | pr-review |
| `skip_review` | bool | `false` | pr-review |
| `merge_strategy` | enum | `squash` | pr-merge |
| `workflow` | enum | `pr-create` | design, orchestrate |
| `execution_mode` | enum | `subagents` | design, orchestrate |
| `review_wait_minutes` | int | `10` | orchestrate, pr-review |
| `re_review_threshold` | int | `5` | design, orchestrate, review skills |

## How Settings Are Used

Other skills check settings as fallbacks when no CLI flag is provided. For example, pr-create checks `skip_tests` only when `--skip-tests` wasn't passed. CLI flags always win — settings are tier 2, flags are tier 1.
