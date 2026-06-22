#!/usr/bin/env bash
set -euo pipefail

# scope-detect.sh — Resolve audit scope for the test-audit skill.
#
# Usage: scope-detect.sh [path] [--diff] [--base=<ref>]
#   path        Optional directory to limit the audit to (full mode only).
#   --diff      Audit only test files changed vs the base ref.
#   --base=REF  Base ref for --diff (default: merge-base with the default branch).
#
# The skill passes each user-supplied token single-quoted, so this script never
# interpolates raw input into a shell expansion (no command-injection surface).
#
# Stdout (one key=value line per resolved variable):
#   SCOPE_MODE=full | diff
#   SCOPE_PATH=<absolute path>          (repo root, or the path arg if given)
#   BASE_REF=<ref>                      (diff mode only)
#
# Exit codes:
#   0 — success
#   1 — invalid arguments or not a git repo (diff mode)

mode="full"
scope_path=""
base_ref=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --diff)
      mode="diff"
      shift
      ;;
    --base=*)
      base_ref="${1#--base=}"
      shift
      ;;
    --base)
      echo "ERROR: --base requires a value, e.g. --base=main." >&2
      exit 1
      ;;
    --*)
      # Unknown flag — skip silently (forward compatibility)
      shift
      ;;
    *)
      if [[ -z "$scope_path" ]]; then
        scope_path="$1"
      fi
      shift
      ;;
  esac
done

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"

# Resolve SCOPE_PATH (path arg wins; fall back to git toplevel, then cwd)
if [[ -z "$scope_path" ]]; then
  scope_path="${repo_root:-.}"
fi
if [[ -e "$scope_path" ]]; then
  scope_path="$(cd "$scope_path" && pwd -P)"
fi

echo "SCOPE_MODE=$mode"
echo "SCOPE_PATH=$scope_path"

if [[ "$mode" == "diff" ]]; then
  if [[ -z "$repo_root" ]]; then
    echo "ERROR: --diff requires a git repository." >&2
    exit 1
  fi
  if [[ -z "$base_ref" ]]; then
    # Default base: the default branch's merge-base, falling back to HEAD~1.
    default_branch="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' || true)"
    default_branch="${default_branch:-main}"
    if base_ref="$(git merge-base "origin/$default_branch" HEAD 2>/dev/null)"; then
      :
    elif base_ref="$(git merge-base "$default_branch" HEAD 2>/dev/null)"; then
      :
    else
      base_ref="HEAD~1"
    fi
  fi
  echo "BASE_REF=$base_ref"
fi
