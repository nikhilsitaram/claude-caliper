#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib-command-parser.sh"

input="$(cat)"
tool_name="$(echo "$input" | jq -r '.tool_name // empty')"

if [[ "$tool_name" != "Bash" ]]; then
  exit 0
fi

cmd="$(echo "$input" | jq -r '.tool_input.command // empty')"
if [[ -z "$cmd" ]]; then
  exit 0
fi

extract_segments "$cmd"
segments=("${SEGMENTS[@]+"${SEGMENTS[@]}"}")

for seg in "${segments[@]+"${segments[@]}"}"; do
  _trimmed="${seg#"${seg%%[![:space:]]*}"}"
  _first_word="${_trimmed%% *}"
  _first_word="${_first_word##*/}"
  if [[ "$_first_word" == "bash" || "$_first_word" == "sh" || "$_first_word" == "zsh" ]]; then
    if [[ "$_trimmed" == "$_first_word" ]]; then continue; fi
    _rest="${_trimmed#"${_trimmed%% *}" }"
    _rest="${_rest#"${_rest%%[![:space:]]*}"}"
    while [[ -n "$_rest" ]]; do
      _token="${_rest%% *}"
      if [[ "$_token" == "-c" ]]; then
        printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Do not use %s -c. Run the actual command directly."}}\n' "$_first_word"
        exit 0
      elif [[ "$_token" == -* && "$_token" != "--" ]]; then
        _skip_next=0
        if [[ "$_token" =~ o$ ]]; then _skip_next=1; fi
        _rest="${_rest#"$_token"}"
        _rest="${_rest#"${_rest%%[![:space:]]*}"}"
        if [[ $_skip_next -eq 1 && -n "$_rest" ]]; then
          _token="${_rest%% *}"
          _rest="${_rest#"$_token"}"
          _rest="${_rest#"${_rest%%[![:space:]]*}"}"
        fi
        continue
      elif [[ "$_token" == "--" ]]; then
        _rest="${_rest#"$_token"}"
        _rest="${_rest#"${_rest%%[![:space:]]*}"}"
        if [[ -n "$_rest" ]]; then
          _script="${_rest%% *}"
          printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Do not use %s to run scripts. Ensure the script has a shebang (#!/usr/bin/env bash) and executable bit (chmod +x), then invoke it directly: ./%s"}}\n' "$_first_word" "$_script"
          exit 0
        fi
        break
      else
        printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Do not use %s to run scripts. Ensure the script has a shebang (#!/usr/bin/env bash) and executable bit (chmod +x), then invoke it directly: ./%s"}}\n' "$_first_word" "$_token"
        exit 0
      fi
    done
  fi
done

for seg in "${segments[@]+"${segments[@]}"}"; do
  mapfile -t seg_cmds < <(extract_command_words_from_segment "$seg")
  for word in "${seg_cmds[@]+"${seg_cmds[@]}"}"; do
    [[ -z "$word" ]] && continue
    stripped="$word"
    stripped="${stripped#\"}"
    stripped="${stripped%\"}"
    stripped="${stripped#\'}"
    stripped="${stripped%\'}"
    if [[ "$stripped" == \$* ]]; then
      printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Variable expansion as command word (%s) cannot be verified. Use the literal command instead."}}\n' "$stripped"
      exit 0
    fi
  done
done

exit 0
