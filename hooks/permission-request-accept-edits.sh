#!/usr/bin/env bash
set -euo pipefail

input=$(cat)

cwd=$(echo "$input" | jq -r '.cwd // empty')

if [[ -z "$cwd" ]]; then
  printf '{"continue": true}\n'
  exit 0
fi

file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')
is_caliper_file=0
if [[ -n "$file_path" && "$file_path" == *"/.claude/claude-caliper/"* ]]; then
  is_caliper_file=1
fi

# Plan dirs live in the main checkout; empty outside a repo.
MAIN_ROOT=$("$(dirname "$0")/../bin/caliper-main-root" "$cwd" 2>/dev/null || true)

find_args=("$cwd/.claude/claude-caliper")
for d in "$cwd/.claude/worktrees"/*/.claude/claude-caliper; do
  [[ -e "$d" ]] && find_args+=("$d")
done
# MAIN_ROOT is physical (pwd -P); compare it to the physical cwd so a symlinked
# cwd doesn't search the same plan dirs twice.
if [[ -n "$MAIN_ROOT" && "$MAIN_ROOT" != "$(cd "$cwd" && pwd -P)" ]]; then
  find_args+=("$MAIN_ROOT/.claude/claude-caliper")
  for d in "$MAIN_ROOT/.claude/worktrees"/*/.claude/claude-caliper; do
    [[ -e "$d" ]] && find_args+=("$d")
  done
fi

sentinel=""
while IFS= read -r f; do
  if [[ -n "$f" ]]; then
    sentinel="$f"
    break
  fi
done < <(find "${find_args[@]}" -maxdepth 2 -name .design-approved 2>/dev/null)

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
  exit 0
fi

if [[ $is_caliper_file -eq 1 ]]; then
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

# Bug #12070: silent exit on PermissionRequest is treated as deny and bypasses
# acceptEdits mode. Output {"continue": true} so the harness defers to the
# session's permission mode and configured allow rules.
printf '{"continue": true}\n'
exit 0
