#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-command-parser.sh
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

# Fast path: deny for-loops that trip Claude Code's tree-sitter parser before
# extract_segments runs. The parser surfaces "Unhandled node type: string" /
# "Contains for_statement" as a generic permission prompt without our deny
# message — guide the agent to a non-loop pattern with a clear reason.
# Match `for VAR in` anywhere in the command (loops can follow leading
# variable assignments like FAIL=0; for f in ...).
if [[ "$cmd" =~ (^|[^a-zA-Z0-9_])for[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]+in[[:space:]] ]]; then
  _loop_var="${BASH_REMATCH[2]}"
  _bash_pat='bash[[:space:]]+"\$'"$_loop_var"'"'
  _kw_pat='(do|then)[[:space:]]+"\$'"$_loop_var"'"'
  _sep_pat='(;|!|&&|\|\||\||&|\{)[[:space:]]*"\$'"$_loop_var"'"'

  if [[ "$cmd" =~ $_bash_pat ]]; then
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"for-loop with bash \"$%s\" detected. Invoke test scripts directly without bash: ./$%s"}}\n' "$_loop_var" "$_loop_var"
    exit 0
  fi

  if [[ "$cmd" =~ $_kw_pat ]] || [[ "$cmd" =~ $_sep_pat ]]; then
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"for-loop invoking \"$%s\" as a command trips Claude Code'"'"'s tree-sitter parser. Chain invocations with ; or && instead, or wrap them in a runner script."}}\n' "$_loop_var"
    exit 0
  fi
fi

extract_segments "$cmd"
# shellcheck disable=SC2153
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
          printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Do not use %s to run scripts. Ensure the script has a shebang (#!/usr/bin/env bash) and executable bit (chmod +x), then invoke it directly: %s/%s"}}\n' "$_first_word" "$PWD" "$_script"
          exit 0
        fi
        break
      else
        printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Do not use %s to run scripts. Ensure the script has a shebang (#!/usr/bin/env bash) and executable bit (chmod +x), then invoke it directly: %s/%s"}}\n' "$_first_word" "$PWD" "$_token"
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
