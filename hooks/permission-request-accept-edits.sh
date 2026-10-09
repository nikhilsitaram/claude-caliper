#!/usr/bin/env bash
set -euo pipefail

input=$(cat)

cwd=$(echo "$input" | jq -r '.cwd // empty')

if [[ "$cwd" != /* ]]; then
  printf '{"continue": true}\n'
  exit 0
fi

# physical_path <absolute path>
# Print the path with symlinks resolved through its deepest existing directory.
# The rest may not exist yet (a Write creates it), so realpath -e won't do.
# Fails on a symlink below that directory (to a file, or dangling): left
# unresolved, it would let a write follow it out of where the path says.
physical_path() {
  [[ "$1" == /* ]] || return 1
  local dir="$1" tail=""
  until [[ -d "${dir:-/}" ]]; do
    [[ -L "$dir" ]] && return 1
    tail="/${dir##*/}$tail"
    dir="${dir%/*}"
  done
  dir=$(cd -P "${dir:-/}" && pwd -P) || return 1
  printf '%s%s\n' "${dir%/}" "$tail"
}

cwd_phys=$(physical_path "$cwd") || { printf '{"continue": true}\n'; exit 0; }

# Plan dirs live in the main checkout; empty outside a repo.
MAIN_ROOT=$("$(dirname "$0")/../bin/caliper-main-root" "$cwd" 2>/dev/null || true)

# Every plan dir is a physical base plus a literal suffix, so a write target
# with its symlinks resolved can be compared against it directly.
find_args=("$cwd_phys/.claude/claude-caliper")
for d in "$cwd_phys/.claude/worktrees"/*/.claude/claude-caliper; do
  [[ -e "$d" ]] && find_args+=("$d")
done
# MAIN_ROOT is physical (pwd -P) too, so a symlinked cwd doesn't search the
# same plan dirs twice.
if [[ -n "$MAIN_ROOT" && "$MAIN_ROOT" != "$cwd_phys" ]]; then
  find_args+=("$MAIN_ROOT/.claude/claude-caliper")
  for d in "$MAIN_ROOT/.claude/worktrees"/*/.claude/claude-caliper; do
    [[ -e "$d" ]] && find_args+=("$d")
  done
fi

# Auto-allow a write only when its target, symlinks resolved, sits under one of
# those plan dirs (#307). A `..` is refused rather than collapsed: the Write
# tool may resolve it lexically or through a symlink, and the two can land in
# different places. So is a newline, which command substitution would drop from
# the path's end. The files that steer caliper always prompt: an auto-allowed
# .design-approved would flip the next prompt to acceptEdits, and reviews.json
# holds the review gates.
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty | select(contains("\n") | not)')
target=""
if [[ "$file_path" != */../* && "$file_path" != */.. ]]; then
  target=$(physical_path "$file_path") || target=""
fi
is_caliper_file=0
if [[ -n "$target" && "${target##*/}" != .design-approved && "${target##*/}" != reviews.json ]]; then
  for d in "${find_args[@]}"; do
    if [[ "$target" == "$d"/* ]]; then
      is_caliper_file=1
      break
    fi
  done
fi

# An ordinary file sits under the cwd with no dot-named segment below it. That
# rules out every path Claude Code protects (.claude/, .git/, shell rc files)
# without copying its list. Caliper's draft dir (#306) is the one exception.
# Relative to the cwd, because caliper's worktrees live under .claude/worktrees/
# and design enters one before approval. A session still at the main checkout
# doesn't count its worktree's files as ordinary, and gets no mode switch from
# them.
is_ordinary_file=0
if [[ -n "$target" && "$target" == "$cwd_phys"/* ]]; then
  rel="${target#"$cwd_phys"/}"
  rel="${rel#.caliper-draft/}"
  [[ "/$rel" != */.* ]] && is_ordinary_file=1
fi

# The sentinel's allow lands on whichever Edit/Write prompts first, and a
# PermissionRequest allow skips Claude Code's protected-path check (#311). So
# it waits for a target acceptEdits would pass anyway: a plan-dir file or an
# ordinary one. Until then it stays put for the next edit.
#
# The design skill writes the session id into the sentinel, so only this
# session's approval counts. A sentinel committed to a repo or left by another
# session can't name an unguessable id. Code the session runs can read the id
# from its environment, but all it gains is a mode switch on a target
# acceptEdits would pass anyway. Only a regular file is read, since a symlink
# could lead anywhere. A mismatch isn't ours to delete.
#
# LOAD-BEARING ASSUMPTIONS (verified on v2.1.296 with a headless probe):
#   - The payload's session_id equals $CLAUDE_CODE_SESSION_ID in the session's
#     Bash. skills/queue/scripts/resolve-state.sh relies on the same equality.
#   - Every path Claude Code protects has a dot-named segment.
# If either breaks, approval stops switching the mode, or the ordinary-file
# gate lets a newly protected path through.
session_id=$(echo "$input" | jq -r '.session_id // empty')
sentinel=""
if [[ -n "$session_id" ]] && (( is_caliper_file || is_ordinary_file )); then
  while IFS= read -r f; do
    if [[ -n "$f" && "$(head -c 128 "$f" 2>/dev/null)" == "$session_id" ]]; then
      sentinel="$f"
      break
    fi
  done < <(find "${find_args[@]}" -maxdepth 2 -name .design-approved -type f 2>/dev/null)
fi

if [[ -n "$sentinel" ]]; then
  rm -f "$sentinel"
  cat << 'HOOKJSON'
{
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": {
      "behavior": "allow",
      "updatedPermissions": [
        { "type": "setMode", "mode": "acceptEdits", "destination": "session" }
      ]
    }
  }
}
HOOKJSON
  exit 0
fi

if [[ $is_caliper_file -eq 1 ]]; then
  cat << 'HOOKJSON'
{
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": { "behavior": "allow" }
  }
}
HOOKJSON
  exit 0
fi

# Bug #12070: silent exit on PermissionRequest is treated as deny and bypasses
# acceptEdits mode. Output {"continue": true} so the harness defers to the
# session's permission mode and configured allow rules.
printf '{"continue": true}\n'
exit 0
