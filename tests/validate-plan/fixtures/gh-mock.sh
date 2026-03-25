#!/usr/bin/env bash
if [[ "${1:-}" == "pr" && "${2:-}" == "list" ]]; then
  echo "${GH_MOCK_PR_COUNT:-0}"
  exit 0
fi
exit 1
