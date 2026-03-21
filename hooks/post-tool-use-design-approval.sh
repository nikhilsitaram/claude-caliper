#!/usr/bin/env bash
set -euo pipefail

input=$(cat)

tool_name=$(echo "$input" | jq -r '.tool_name // empty')
[[ "$tool_name" == "AskUserQuestion" ]] || exit 0

session_id=$(echo "$input" | jq -r '.session_id // empty')
[[ -n "$session_id" ]] || exit 0

metadata_source=$(echo "$input" | jq -r '.tool_input.metadata.source // empty')
question_text=$(echo "$input" | jq -r '.tool_input.questions[0].question // empty')

if [[ "$metadata_source" != "design-approval" ]]; then
  echo "$question_text" | grep -qF "Plan dir:" || exit 0
fi

tool_response=$(echo "$input" | jq -r '.tool_response // empty')
if [[ "$tool_response" == *"Needs changes"* ]] || [[ "$tool_response" != *"Approved"* ]]; then
  exit 0
fi

plan_dir=""
if echo "$question_text" | grep -qF "Plan dir:"; then
  plan_dir=$(echo "$question_text" | sed -n 's/.*Plan dir: *\(\/.*\)/\1/p' | sed 's/[[:space:]]*$//')
fi

if [[ -z "$plan_dir" ]]; then
  echo "ERROR: Could not extract plan dir path from question text" >&2
  exit 0
fi

mkdir -p "$plan_dir"
printf '%s' "$session_id" > "$plan_dir/.design-approved"
