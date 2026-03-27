#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

input=$(cat)

tool_name=$(echo "$input" | jq -r '.tool_name // empty')

case "$tool_name" in
  Read|Glob|Grep|Skill|WebFetch|WebSearch|ToolSearch)
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}\n'
    exit 0
    ;;
  Bash) ;;
  *) exit 0 ;;
esac

cmd=$(echo "$input" | jq -r '.tool_input.command // empty')
[[ -n "$cmd" ]] || exit 0

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

extract_segments() {
  local input_cmd="$1"
  local -a words=()
  local segment=""
  local i=0
  local len="${#input_cmd}"
  local in_single=0
  local in_double=0
  local paren_depth=0
  local char=""
  local next=""

  while [[ $i -lt $len ]]; do
    char="${input_cmd:$i:1}"
    next="${input_cmd:$((i+1)):1}"

    if [[ $in_single -eq 1 ]]; then
      if [[ "$char" == "'" ]]; then
        in_single=0
      fi
      segment+="$char"
      i=$((i+1))
      continue
    fi

    if [[ $in_double -eq 1 ]]; then
      if [[ "$char" == '"' ]]; then
        in_double=0
      fi
      segment+="$char"
      i=$((i+1))
      continue
    fi

    if [[ "$char" == "'" ]]; then
      in_single=1
      segment+="$char"
      i=$((i+1))
      continue
    fi

    if [[ "$char" == '"' ]]; then
      in_double=1
      segment+="$char"
      i=$((i+1))
      continue
    fi

    if [[ "$char" == "(" ]]; then
      paren_depth=$((paren_depth+1))
      segment+="$char"
      i=$((i+1))
      continue
    fi

    if [[ "$char" == ")" ]]; then
      if [[ $paren_depth -gt 0 ]]; then
        paren_depth=$((paren_depth-1))
      fi
      segment+="$char"
      i=$((i+1))
      continue
    fi

    if [[ $paren_depth -gt 0 ]]; then
      segment+="$char"
      i=$((i+1))
      continue
    fi

    if [[ "$char" == "|" || "$char" == ";" ]]; then
      if [[ -n "${segment// }" ]]; then
        words+=("$segment")
      fi
      segment=""
      i=$((i+1))
      continue
    fi

    if [[ "$char" == "&" && "$next" == "&" ]]; then
      if [[ -n "${segment// }" ]]; then
        words+=("$segment")
      fi
      segment=""
      i=$((i+2))
      continue
    fi

    segment+="$char"
    i=$((i+1))
  done

  if [[ -n "${segment// }" ]]; then
    words+=("$segment")
  fi

  SEGMENTS=("${words[@]+"${words[@]}"}")
}

extract_command_words_from_segment() {
  local seg="$1"
  local -a cmds=()

  seg="${seg#"${seg%%[![:space:]]*}"}"
  seg="${seg%"${seg##*[![:space:]]}"}"

  [[ "$seg" == "#"* ]] && return 0

  local outer_cmd=""
  local pure_subshell_re='^\$\((.+)\)$'
  local var_subshell_re='^[A-Za-z_][A-Za-z0-9_]*=\$\((.+)\)$'
  local var_literal_re='^[A-Za-z_][A-Za-z0-9_]*=[^$]'
  if [[ "$seg" =~ $pure_subshell_re ]]; then
    local inner="${BASH_REMATCH[1]}"
    inner="${inner#"${inner%%[![:space:]]*}"}"
    outer_cmd="${inner%% *}"
  elif [[ "$seg" =~ $var_subshell_re ]]; then
    local inner="${BASH_REMATCH[1]}"
    inner="${inner#"${inner%%[![:space:]]*}"}"
    outer_cmd="${inner%% *}"
  elif [[ "$seg" =~ $var_literal_re ]]; then
    local after_assign="${seg#*=[^ ]* }"
    if [[ "$after_assign" != "$seg" ]]; then
      after_assign="${after_assign#"${after_assign%%[![:space:]]*}"}"
      local trailing_word="${after_assign%% *}"
      outer_cmd="${trailing_word##*/}"
    else
      outer_cmd=""
    fi
  else
    local word="${seg%% *}"
    outer_cmd="${word##*/}"
    # Shell interpreter resolution: bash/sh/zsh script.sh -> script.sh
    if [[ "$outer_cmd" == "bash" || "$outer_cmd" == "sh" || "$outer_cmd" == "zsh" ]]; then
      local rest="${seg#"${seg%% *}" }"
      rest="${rest#"${rest%%[![:space:]]*}"}"
      local script_token=""
      while [[ -n "$rest" ]]; do
        local token="${rest%% *}"
        if [[ "$token" == "--" ]]; then
          rest="${rest#"$token"}"
          rest="${rest#"${rest%%[![:space:]]*}"}"
          if [[ -n "$rest" ]]; then
            script_token="${rest%% *}"
          fi
          break
        elif [[ "$token" == "-c" ]]; then
          break
        elif [[ "$token" == -* ]]; then
          rest="${rest#"$token"}"
          rest="${rest#"${rest%%[![:space:]]*}"}"
          continue
        else
          script_token="$token"
          break
        fi
      done

      if [[ -n "$script_token" ]]; then
        script_token="${script_token#\"}"
        script_token="${script_token%\"}"
        script_token="${script_token#\'}"
        script_token="${script_token%\'}"
        outer_cmd="${script_token##*/}"
      fi
    fi
  fi

  [[ -n "$outer_cmd" ]] && cmds+=("$outer_cmd")

  local remaining="$seg"
  local subshell_re='\$\(([^)]+)\)'
  while [[ "$remaining" =~ $subshell_re ]]; do
    local subshell_content="${BASH_REMATCH[1]}"
    local sub_trimmed="${subshell_content#"${subshell_content%%[![:space:]]*}"}"
    local sub_cmd="${sub_trimmed%% *}"
    sub_cmd="${sub_cmd##*/}"
    if [[ -n "$sub_cmd" ]]; then
      cmds+=("$sub_cmd")
    fi
    remaining="${remaining#*"${BASH_REMATCH[0]}"}"
  done

  for c in "${cmds[@]+"${cmds[@]}"}"; do
    echo "$c"
  done
}

mapfile -t safe_list < "$SAFE_FILE"

is_safe() {
  local word="$1"
  [[ -z "$word" ]] && return 0
  local entry
  for entry in "${safe_list[@]}"; do
    [[ "$word" == "$entry" ]] && return 0
  done
  return 1
}

extract_segments "$cmd"
segments=("${SEGMENTS[@]+"${SEGMENTS[@]}"}")

# Pre-check: deny bash/sh/zsh used as script runners or with -c
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
        # If compound flag ends with 'o' (e.g. -euo), next token is -o's argument (e.g. pipefail)
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

count=0
all_safe=1
variable_as_command=0
declare -a non_matching=()

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
      non_matching+=("$word")
      continue
    fi
    count=$((count+1))
    if ! is_safe "$word"; then
      all_safe=0
      non_matching+=("$word")
    fi
  done
done

if [[ $all_safe -eq 1 ]]; then
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}\n'
elif [[ $variable_as_command -eq 1 ]]; then
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Command word is a shell variable — the safe commands hook cannot verify safety. Use the literal command/path instead of variable indirection."}}\n'
  for nm in "${non_matching[@]}"; do
    printf '%s\n' "$nm" >> "$LOG_FILE"
  done
else
  for nm in "${non_matching[@]}"; do
    printf '%s\n' "$nm" >> "$LOG_FILE"
  done
fi

exit 0
