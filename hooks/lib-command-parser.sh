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
  local var_subshell_re='^[A-Za-z_][A-Za-z0-9_]*="?\$\((.+)\)"?$'
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
    local val_start="${seg#*=}"
    local after_val=""
    if [[ "$val_start" == '"'* ]]; then
      local after_open="${val_start#\"}"
      if [[ "$after_open" == *'"'* ]]; then
        after_val="${after_open#*\"}"
      fi
    elif [[ "$val_start" == "'"* ]]; then
      local after_open="${val_start#\'}"
      if [[ "$after_open" == *"'"* ]]; then
        after_val="${after_open#*\'}"
      fi
    elif [[ "$val_start" == " "* || "$val_start" == "$( printf '\t' )"* ]]; then
      after_val="${val_start}"
    else
      local first_word="${val_start%% *}"
      if [[ "$first_word" != "$val_start" ]]; then
        after_val="${val_start#"$first_word" }"
      fi
    fi
    after_val="${after_val#"${after_val%%[![:space:]]*}"}"
    if [[ -n "$after_val" ]]; then
      local trailing_word="${after_val%% *}"
      outer_cmd="${trailing_word##*/}"
    else
      outer_cmd=""
    fi
  else
    local word="${seg%% *}"
    outer_cmd="${word##*/}"
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
