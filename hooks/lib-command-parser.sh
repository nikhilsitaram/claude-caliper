# shellcheck shell=bash
# Sourced by permission-request-allow.sh — not executed directly.

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

    if [[ "$char" == $'\n' ]]; then
      if [[ -n "${segment// }" ]]; then
        words+=("$segment")
      fi
      segment=""
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

  # Exported to caller via nameref-like convention (sourced library)
  # shellcheck disable=SC2034
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
  local var_subshell_re='^[A-Za-z_][A-Za-z0-9_]*="?\$\((.+)\)"?$'
  local var_literal_re='^[A-Za-z_][A-Za-z0-9_]*=[^$]'
  local var_ref_re='^[A-Za-z_][A-Za-z0-9_]*=\$'
  local array_assign_re='^[A-Za-z_][A-Za-z0-9_]*=\('
  if [[ "$seg" =~ $pure_subshell_re ]]; then
    local inner="${BASH_REMATCH[1]}"
    inner="${inner#"${inner%%[![:space:]]*}"}"
    outer_cmd="${inner%% *}"
    outer_cmd="${outer_cmd##*/}"
  elif [[ "$seg" =~ $var_subshell_re ]]; then
    local inner="${BASH_REMATCH[1]}"
    inner="${inner#"${inner%%[![:space:]]*}"}"
    outer_cmd="${inner%% *}"
    outer_cmd="${outer_cmd##*/}"
  elif [[ "$seg" =~ $var_ref_re ]]; then
    : # VAR=$other/path — variable reference assignment, not a command
  elif [[ "$seg" =~ $array_assign_re ]]; then
    : # VAR=(item item ...) — bash array literal, not a command
  elif [[ "$seg" =~ $var_literal_re ]]; then
    local current="$seg"
    outer_cmd=""
    while true; do
      local val_start="${current#*=}"
      local after_val=""
      if [[ "$val_start" == '"'* ]]; then
        local after_open="${val_start#\"}"
        if [[ "$after_open" == *'"'* ]]; then
          after_val="${after_open#*\"}"
        else
          break
        fi
      elif [[ "$val_start" == "'"* ]]; then
        local after_open="${val_start#\'}"
        if [[ "$after_open" == *"'"* ]]; then
          after_val="${after_open#*\'}"
        else
          break
        fi
      elif [[ "$val_start" == " "* || "$val_start" == $'\t'* ]]; then
        after_val="${val_start}"
      else
        local first_word="${val_start%%[[:space:]]*}"
        if [[ "$first_word" != "$val_start" ]]; then
          after_val="${val_start#"$first_word"}"
        else
          break
        fi
      fi
      if [[ -n "$after_val" && "$after_val" != [[:space:]]* ]]; then
        if [[ "$after_val" == *[[:space:]]* ]]; then
          after_val="${after_val#*[[:space:]]}"
        else
          break
        fi
      fi
      after_val="${after_val#"${after_val%%[![:space:]]*}"}"
      if [[ -z "$after_val" ]]; then
        break
      fi
      if [[ "$after_val" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
        current="$after_val"
        continue
      fi
      local trailing_word="${after_val%%[[:space:]]*}"
      outer_cmd="${trailing_word##*/}"
      break
    done
  else
    local word="${seg%% *}"
    # An interpreter (bash/sh/zsh) stays the command word: resolving its script or
    # inline `-c`/`-s` argument to a safe-listed name would auto-approve arbitrary
    # code (`bash -lc 'git status; …'`). Scripts are approved when run by path.
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

load_safe_commands() {
  local safe_file="$1"
  exact_list=()
  prefix_list=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if [[ "$line" == *'*' ]]; then
      prefix="${line%\*}"
      [[ -z "$prefix" ]] && continue
      prefix_list+=("$prefix")
    else
      exact_list+=("$line")
    fi
  done < "$safe_file"
}

is_safe() {
  local word="$1"
  [[ -z "$word" ]] && return 0
  local entry
  for entry in "${exact_list[@]}"; do
    [[ "$word" == "$entry" ]] && return 0
  done
  for entry in "${prefix_list[@]}"; do
    [[ "$word" == "$entry"* ]] && return 0
  done
  return 1
}
