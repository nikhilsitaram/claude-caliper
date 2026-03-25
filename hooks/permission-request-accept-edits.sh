#!/usr/bin/env bash
set -euo pipefail

input=$(cat)

cwd=$(echo "$input" | jq -r '.cwd // empty')

[[ -n "$cwd" ]] || exit 0

sentinel=""
while IFS= read -r f; do
  if [[ -n "$f" ]]; then
    sentinel="$f"
    break
  fi
done < <(find "$cwd/docs/plans" "$cwd/.claude/worktrees"/*/docs/plans -maxdepth 3 -name .design-approved 2>/dev/null)

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
