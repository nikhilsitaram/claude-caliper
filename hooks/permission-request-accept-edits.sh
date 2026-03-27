#!/usr/bin/env bash
set -euo pipefail

input=$(cat)

cwd=$(echo "$input" | jq -r '.cwd // empty')

[[ -n "$cwd" ]] || exit 0

file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')
if [[ -n "$file_path" && "$file_path" == *"/.claude/claude-caliper/"* ]]; then
  cat << 'HOOKJSON'
{
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": { "behavior": "allow" }
  }
}
HOOKJSON
  exit 0
fi

sentinel=""
while IFS= read -r f; do
  if [[ -n "$f" ]]; then
    sentinel="$f"
    break
  fi
done < <(find "$cwd/.claude/claude-caliper" "$cwd/.claude/worktrees"/*/.claude/claude-caliper -maxdepth 2 -name .design-approved 2>/dev/null)

if [[ -n "$sentinel" ]]; then
  rm -f "$sentinel"
  cat << 'HOOKJSON'
{
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": {
      "behavior": "allow",
      "updatedPermissions": [
        { "type": "setMode", "mode": "acceptEdits", "destination": "session" }
      ]
    }
  }
}
HOOKJSON
fi

exit 0
