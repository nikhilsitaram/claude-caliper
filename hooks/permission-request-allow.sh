#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib-command-parser.sh"

input=$(cat)

tool_name=$(echo "$input" | jq -r '.tool_name // empty')

allow_with_rules() {
  local rules_json="$1"
  printf '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","updatedPermissions":[{"type":"addRules","rules":%s,"behavior":"allow","destination":"session"}]}}}\n' "$rules_json"
}

case "$tool_name" in
  Read|Glob|Grep|Skill|WebFetch|WebSearch|ToolSearch)
    allow_with_rules "[{\"toolName\":\"$tool_name\"}]"
    exit 0
    ;;
  Bash) ;;
  *) exit 0 ;;
esac

cmd=$(echo "$input" | jq -r '.tool_input.command // empty')
[[ -n "$cmd" ]] || exit 0

extract_segments "$cmd"
segments=("${SEGMENTS[@]+"${SEGMENTS[@]}"}")

if [[ ${#segments[@]} -gt 0 ]]; then
  caliper_only=true
  for _seg in "${segments[@]}"; do
    _seg="${_seg#"${_seg%%[![:space:]]*}"}"
    [[ -z "$_seg" ]] && continue
    if [[ "$_seg" != *"/.claude/claude-caliper/"* ]]; then
      caliper_only=false
      break
    fi
  done
  if [[ "$caliper_only" == "true" ]]; then
    printf '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}\n'
    exit 0
  fi
fi

BUNDLED_SAFE_FILE="$SCRIPT_DIR/safe-commands.txt"
USER_SAFE_FILE="${CLAUDE_SAFE_COMMANDS_FILE:-$HOME/.claude/safe-commands.txt}"
LOG_FILE="${CLAUDE_SAFE_CMDS_LOG:-${TMPDIR:-/tmp}/claude-safe-cmds-nonmatch.log}"

if [[ -f "$USER_SAFE_FILE" ]]; then
  SAFE_FILE="$USER_SAFE_FILE"
elif [[ -f "$BUNDLED_SAFE_FILE" ]]; then
  SAFE_FILE="$BUNDLED_SAFE_FILE"
else
  exit 0
fi

load_safe_commands "$SAFE_FILE"

count=0
all_safe=1
variable_as_command=0
declare -a non_matching=()
declare -A first_words=()

for seg in "${segments[@]+"${segments[@]}"}"; do
  [[ $count -ge 20 ]] && break
  mapfile -t seg_cmds < <(extract_command_words_from_segment "$seg")
  for word in "${seg_cmds[@]+"${seg_cmds[@]}"}"; do
    [[ $count -ge 20 ]] && break
    [[ -z "$word" ]] && continue
    stripped="$word"
    stripped="${stripped#\"}"
    stripped="${stripped%\"}"
    stripped="${stripped#\'}"
    stripped="${stripped%\'}"
    if [[ "$stripped" == \$* ]]; then
      variable_as_command=1
      all_safe=0
      continue
    fi
    count=$((count+1))
    if is_safe "$stripped"; then
      first_words["$stripped"]=1
    else
      all_safe=0
      non_matching+=("$stripped")
    fi
  done
done

if [[ $all_safe -eq 1 ]]; then
  rules="["
  first=true
  for w in "${!first_words[@]}"; do
    if [[ "$first" == "true" ]]; then
      first=false
    else
      rules+=","
    fi
    rules+="{\"toolName\":\"Bash\",\"ruleContent\":\"$w *\"}"
  done
  rules+="]"
  allow_with_rules "$rules"
elif [[ $variable_as_command -eq 1 ]]; then
  exit 0
else
  for nm in "${non_matching[@]}"; do
    printf '%s\n' "$nm" >> "$LOG_FILE"
  done
fi

exit 0
