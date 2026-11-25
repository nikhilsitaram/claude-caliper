#!/usr/bin/env bash
# gh pr list stub: prints GH_MOCK_PR_COUNT, or GH_MOCK_MERGED_COUNT (when set)
# for a --state merged query, so a test can model "PR open but not merged".
# GH_MOCK_ONLY_BRANCH (when set) scopes PRs to one branch: a query whose
# --head or --base isn't that branch prints 0, so a test can tell which branch
# the caller asked about.
if [[ "${1:-}" == "pr" && "${2:-}" == "list" ]]; then
  if [[ -n "${GH_MOCK_ONLY_BRANCH:-}" && " $* " != *" --head $GH_MOCK_ONLY_BRANCH "* \
        && " $* " != *" --base $GH_MOCK_ONLY_BRANCH "* ]]; then
    echo 0
  elif [[ -n "${GH_MOCK_MERGED_COUNT:-}" && " $* " == *" --state merged "* ]]; then
    echo "$GH_MOCK_MERGED_COUNT"
  else
    echo "${GH_MOCK_PR_COUNT:-0}"
  fi
  exit 0
fi
exit 1
