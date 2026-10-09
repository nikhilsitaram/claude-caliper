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
is_caliper_file=0
if [[ "$file_path" != */../* && "$file_path" != */.. ]] \
    && target=$(physical_path "$file_path") \
    && [[ "${target##*/}" != .design-approved && "${target##*/}" != reviews.json ]]; then
  for d in "${find_args[@]}"; do
    if [[ "$target" == "$d"/* ]]; then
      is_caliper_file=1
      break
    fi
  done
fi

sentinel=""
while IFS= read -r f; do
  if [[ -n "$f" ]]; then
    sentinel="$f"
    break
  fi
done < <(find "${find_args[@]}" -maxdepth 2 -name .design-approved 2>/dev/null)

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
