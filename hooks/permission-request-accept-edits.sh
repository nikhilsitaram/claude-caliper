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

git_common_dir=$(git -C "$cwd" rev-parse --git-common-dir 2>/dev/null || true)
if [[ -n "$git_common_dir" && "$git_common_dir" != /* ]]; then
  git_common_dir="$cwd/$git_common_dir"
fi
MAIN_ROOT="${git_common_dir%/.git}"

find_args=("$cwd/.claude/claude-caliper")
for d in "$cwd/.claude/worktrees"/*/.claude/claude-caliper; do
  [[ -e "$d" ]] && find_args+=("$d")
done
if [[ -n "$MAIN_ROOT" && "$MAIN_ROOT" != "$cwd" ]]; then
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
