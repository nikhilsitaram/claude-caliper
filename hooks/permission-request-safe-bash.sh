#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

input=$(cat)

tool_name=$(echo "$input" | jq -r '.tool_name // empty')
[[ "$tool_name" == "Bash" ]] || exit 0

result=$(echo "$input" | bash "$SCRIPT_DIR/pretooluse-safe-commands.sh" 2>/dev/null || true)

if echo "$result" | grep -qF '"permissionDecision":"allow"'; then
  cat << 'HOOKJSON'
{
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": {
      "behavior": "allow"
    }
  }
}
HOOKJSON
fi

exit 0
