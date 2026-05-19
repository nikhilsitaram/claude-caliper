#!/usr/bin/env bash
set -euo pipefail

# mode-detect.sh — Resolve MODE and SCOPE_PATH for the codebase-review skill.
#
# Stdout (one key=value line per resolved variable):
#   MODE=single | MODE=team | MODE=__ASK__
#   SCOPE_PATH=<absolute or user-provided path>
#
# Stderr (informational):
#   - Env-var downgrade warning when --mode=team but
#     CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS != 1 (exit 0; helper downgrades)
#   - Invalid-value error naming valid modes (exit non-zero)
#
# Exit codes:
#   0 — success (MODE and SCOPE_PATH emitted)
#   1 — invalid --mode value (including empty or missing)

mode=""
mode_seen=0
scope_path=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode=*)
      mode="${1#--mode=}"
      mode_seen=1
      shift
      ;;
    --mode)
      # Bare --mode with no value — treat as invalid
      mode=""
      mode_seen=1
      shift
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

# Validate --mode value
if [[ "$mode_seen" -eq 1 ]]; then
  case "$mode" in
    single|team)
      ;;
    *)
      echo "ERROR: invalid --mode value '$mode'. Valid values: single, team." >&2
      exit 1
      ;;
  esac
fi

# Resolve SCOPE_PATH (path arg wins; fall back to git toplevel)
if [[ -z "$scope_path" ]]; then
  if scope_path="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    :
  else
    scope_path="."
  fi
fi

# Resolve MODE
if [[ "$mode_seen" -eq 0 ]]; then
  echo "MODE=__ASK__"
elif [[ "$mode" == "team" ]]; then
  if [[ "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-}" == "1" ]]; then
    echo "MODE=team"
  else
    echo "WARNING: team mode requires CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 — downgrading to single mode for this run. Set the env var to enable team mode next time." >&2
    echo "MODE=single"
  fi
else
  echo "MODE=single"
fi

echo "SCOPE_PATH=$scope_path"
