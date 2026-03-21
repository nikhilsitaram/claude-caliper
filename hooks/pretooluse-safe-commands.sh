#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

input=$(cat)

tool_name=$(echo "$input" | jq -r '.tool_name // empty')

case "$tool_name" in
  Read|Glob|Grep|Skill|WebFetch|WebSearch|ToolSearch)
    printf '{"permissionDecision":"allow"}\n'
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

  for seg in "${words[@]+"${words[@]}"}"; do
    echo "$seg"
  done
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

mapfile -t segments < <(extract_segments "$cmd")

count=0
all_safe=1
declare -a non_matching=()

for seg in "${segments[@]+"${segments[@]}"}"; do
  [[ $count -ge 20 ]] && break
  mapfile -t seg_cmds < <(extract_command_words_from_segment "$seg")
  for word in "${seg_cmds[@]+"${seg_cmds[@]}"}"; do
    [[ $count -ge 20 ]] && break
    [[ -z "$word" ]] && continue
    count=$((count+1))
    if ! is_safe "$word"; then
      all_safe=0
      non_matching+=("$word")
    fi
  done
done

if [[ $all_safe -eq 1 ]]; then
  printf '{"permissionDecision":"allow"}\n'
else
  for nm in "${non_matching[@]}"; do
    printf '%s\n' "$nm" >> "$LOG_FILE"
  done
fi

exit 0
