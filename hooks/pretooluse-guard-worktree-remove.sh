#!/usr/bin/env bash
set -euo pipefail

# PreToolUse(Bash): deny `git worktree remove <path>` when the session's cwd is
# <path> or inside it (issue #317). Deleting the directory the session stands
# in leaves every later tool call in a deleted cwd, and the session is wedged
# until the user restarts it. Only the hook sees the *session* cwd: a `cd` chained
# into the same call (`cd <main> && git worktree remove <wt>`) moves the shell,
# not the session, so a check inside any script would miss it.
#
# This is a footgun guard, not a permission boundary: it denies only when a
# literal target resolves to an existing directory containing the cwd, and lets
# anything it can't resolve (variables, substitutions, globs) through.

input="$(cat)"
# Runs on every Bash call: bail before spawning jq unless removal is plausible.
[[ "$input" == *worktree*remove* ]] || exit 0
[[ "$(jq -r '.tool_name // empty' <<<"$input")" == "Bash" ]] || exit 0
cmd="$(jq -r '.tool_input.command // empty' <<<"$input")"
[[ "$cmd" == *worktree*remove* ]] || exit 0
cwd="$(jq -r '.cwd // empty' <<<"$input")"
[[ -n "$cwd" ]] || exit 0
CWD_P="$(cd "$cwd" 2>/dev/null && pwd -P)" || exit 0

# One shell word: single-quoted, double-quoted, or bare (not an option).
TOK="('[^']*'|\"[^\"]*\"|[^-[:space:];&|()<>][^[:space:];&|()<>]*)"
RM_RE="worktree[[:space:]]+remove(([[:space:]]+-[^[:space:]]*)*)[[:space:]]+$TOK"
# Last directory change before the removal (greedy .* finds the last one); its
# word and the text after it. CD_ARG_RE then parses `cd`/`pushd` options + dir.
DIRCHG_RE="^.*(^|[[:space:];&|(])(cd|pushd|popd)([[:space:]].*)?\$"
CD_ARG_RE="^([[:space:]]+-[LPe@]+)*([[:space:]]+--)?[[:space:]]+$TOK"
GITC_RE="-C[[:space:]]+$TOK[[:space:]]+\$"

# resolve_dir <base> <word> — print the physical path of an existing directory
# the word names, relative words resolved against <base>; fail if unresolvable.
resolve_dir() {
  local base="$1" w="$2" p
  case "$w" in
    \'*\') p="${w:1:${#w}-2}" ;;
    \"*\") p="${w:1:${#w}-2}"; [[ "$p" != *[\$\`\\]* ]] || return 1 ;;
    *)
      [[ "$w" != *[\$\`\\\*\?\[\{]* ]] || return 1
      case "$w" in
        "~") p="$HOME" ;;
        "~/"*) p="$HOME/${w#\~/}" ;;
        *) p="$w" ;;
      esac
      ;;
  esac
  [[ -n "$base" || "$p" == /* ]] || return 1
  [[ "$p" == /* ]] || p="$base/$p"
  [[ -d "$p" ]] || return 1
  (cd "$p" 2>/dev/null && pwd -P)
}

deny() {
  local target="$1"
  jq -nc --arg r "Refusing to remove $target: the session's working directory ($CWD_P) is inside the worktree being removed. Deleting it leaves every later tool call in a deleted cwd, and the session stays wedged until a restart. A cd chained into this same call moves only the shell, not the session. Leave first. If this is the worktree the session entered with EnterWorktree, use ExitWorktree (action keep if it refuses remove as not the owner). Otherwise run the cd to a directory outside it as its own Bash call with nothing chained after it. That covers a Bash-entered worktree, and a nested phase worktree whose parent session orchestrate still uses. Confirm the cwd with pwd in the next call, then retry the removal. If this command only quotes such a removal in text (a commit message or PR body), rephrase that text instead." '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $r
    }
  }'
  exit 0
}

consumed=""
rest="$cmd"
while [[ "$rest" =~ $RM_RE ]]; do
  full="${BASH_REMATCH[0]}"
  word="${BASH_REMATCH[3]}"
  before="$consumed${rest%%"$full"*}"
  consumed="$before$full"
  rest="${rest#*"$full"}"

  # Base for a relative target: the last chained cd/pushd, then a `git -C` dir.
  # A directory change it can't parse (popd, `cd -`, a variable) leaves the
  # base unknown, so relative targets fail open; absolute ones are still checked.
  base="$CWD_P"
  if [[ "$before" =~ $DIRCHG_RE ]]; then
    dc_word="${BASH_REMATCH[2]}"
    dc_rest="${BASH_REMATCH[3]}"
    base=""
    if [[ "$dc_word" != popd && "$dc_rest" =~ $CD_ARG_RE ]]; then
      base="$(resolve_dir "$CWD_P" "${BASH_REMATCH[3]}")" || base=""
    fi
  fi
  if [[ "$before" =~ $GITC_RE ]]; then
    base="$(resolve_dir "$base" "${BASH_REMATCH[1]}")" || base=""
  fi

  target="$(resolve_dir "$base" "$word")" || continue
  if [[ "$CWD_P" == "$target" || "$CWD_P" == "$target"/* ]]; then
    deny "$target"
  fi
done

exit 0
