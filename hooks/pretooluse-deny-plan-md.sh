#!/usr/bin/env bash
set -euo pipefail

input="$(cat)"
tool_name="$(echo "$input" | jq -r '.tool_name // empty')"

case "$tool_name" in
  Edit|Write|MultiEdit) ;;
  *) exit 0 ;;
esac

file_path="$(echo "$input" | jq -r '.tool_input.file_path // empty')"
if [[ -z "$file_path" ]]; then
  exit 0
fi

normalized_path="${file_path#./}"

case "$normalized_path" in
  .claude/claude-caliper/*/plan.md|*/.claude/claude-caliper/*/plan.md)
    reason="plan.md is a deterministic render of plan.json — direct edits are silently overwritten on the next validate-plan run. To change file lists, run: validate-plan --add-file <plan.json> --task <ID> --kind <create|modify|test> --path <FILE> (or --remove-file). To change task/phase status, run: validate-plan --update-status. To add a dependency, run: validate-plan --add-dep. After mutating plan.json, validate-plan re-renders plan.md automatically; if you need a manual re-render, run: validate-plan --render <plan.json>."
    jq -nc --arg r "$reason" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $r
      }
    }'
    exit 0
    ;;
esac

exit 0
