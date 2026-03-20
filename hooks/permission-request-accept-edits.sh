#!/usr/bin/env bash
set -euo pipefail

input=$(cat)

session_id=$(echo "$input" | jq -r '.session_id // empty')
cwd=$(echo "$input" | jq -r '.cwd // empty')

[[ -n "$session_id" ]] || exit 0
[[ -n "$cwd" ]] || exit 0

sentinels=()
while IFS= read -r f; do
  [[ -n "$f" ]] && sentinels+=("$f")
done < <(find "$cwd/docs/plans" "$cwd/.claude/worktrees"/*/docs/plans -maxdepth 3 -name .design-approved 2>/dev/null)

for sentinel in "${sentinels[@]}"; do
  stored_session=$(cat "$sentinel" 2>/dev/null) || continue
  if [[ "$stored_session" == "$session_id" ]]; then
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
    exit 0
  fi
done

exit 0
