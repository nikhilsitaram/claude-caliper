#!/usr/bin/env bash
set -euo pipefail

# Skill and agent snippets get copied into Bash calls that often run under
# Claude Code's worktree-isolation guard, which refuses $(git …) anywhere but a
# bare unquoted assignment — quoted "$(git …)" and $(git …) inside a test both
# fail (skills/design/worktree-isolation.md, gh #288). Pin that no snippet
# reintroduces those forms.
#
# A narrow backstop, not proof: the guard also refuses forms a grep can't see
# (a substitution result reused as a standalone word, a test on a derived var,
# any quoted "$(…)" in a call naming git — and "naming git" includes the word
# inside a message string). Probe rewritten snippets verbatim from an isolated
# session (gh #295).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
REFERENCE="skills/design/worktree-isolation.md"  # documents the refused forms

# Known offenders awaiting a dedicated fix: "<file>:<substring>". Drop an entry
# once its snippet is rewritten.
ALLOWLIST=()

REFUSED='"\$\(git |\[\[? +\$\(git '

declare -A USED=()

# Sets MATCHED to the allowlist entry covering the hit, if any.
allowed() {
  local hit="$1" entry
  MATCHED=""
  for entry in "${ALLOWLIST[@]}"; do
    if [[ "$hit" == "${entry%%:*}:"* && "$hit" == *"${entry#*:}"* ]]; then
      MATCHED="$entry"
      return 0
    fi
  done
  return 1
}

cd "$REPO_ROOT"
FAIL=0
while IFS= read -r hit; do
  [[ -z "$hit" || "$hit" == "$REFERENCE:"* ]] && continue
  if allowed "$hit"; then
    USED["$MATCHED"]=1
    echo "ALLOWLISTED: $hit"
  else
    echo "FAIL: guard-refused \$(git …) form: $hit"
    FAIL=1
  fi
done < <(grep -rnE "$REFUSED" skills agents --include='*.md' || true)

# An entry that excused no refused line is stale — keeping it would silently
# exempt a reintroduced refused form on any line sharing its substring.
echo "=== every allowlist entry excuses a refused line ==="
for entry in "${ALLOWLIST[@]}"; do
  if [[ -n "${USED[$entry]:-}" ]]; then
    echo "PASS: in use: $entry"
  else
    echo "FAIL: stale allowlist entry (fixed? drop it): $entry"
    FAIL=1
  fi
done

[[ $FAIL -eq 0 ]] && echo "PASS: no guard-refused \$(git …) forms in skill/agent markdown"
exit "$FAIL"
