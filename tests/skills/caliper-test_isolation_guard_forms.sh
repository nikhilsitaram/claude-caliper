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
# any quoted "$(…)" in a call naming git). Probe rewritten snippets verbatim
# from an isolated session; gh #295 tracks the remaining snippets.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
REFERENCE="skills/design/worktree-isolation.md"  # documents the refused forms

# Known offenders awaiting a dedicated fix: "<file>:<substring>". Drop an entry
# once its snippet is rewritten.
ALLOWLIST=(
  'skills/pr-merge/SKILL.md:git ls-remote origin'  # gh #295 — #285 branch-delete containment guard
)

REFUSED='"\$\(git |\[\[? +\$\(git '

allowed() {
  local hit="$1" entry
  for entry in "${ALLOWLIST[@]}"; do
    [[ "$hit" == "${entry%%:*}:"* && "$hit" == *"${entry#*:}"* ]] && return 0
  done
  return 1
}

cd "$REPO_ROOT"
FAIL=0
while IFS= read -r hit; do
  [[ -z "$hit" || "$hit" == "$REFERENCE:"* ]] && continue
  if allowed "$hit"; then
    echo "ALLOWLISTED: $hit"
  else
    echo "FAIL: guard-refused \$(git …) form: $hit"
    FAIL=1
  fi
done < <(grep -rnE "$REFUSED" skills agents --include='*.md' || true)

echo "=== allowlist entries still match something ==="
for entry in "${ALLOWLIST[@]}"; do
  if grep -qF "${entry#*:}" "${entry%%:*}"; then
    echo "PASS: ${entry%%:*} still holds '${entry#*:}'"
  else
    echo "FAIL: stale allowlist entry (fixed? drop it): $entry"
    FAIL=1
  fi
done

[[ $FAIL -eq 0 ]] && echo "PASS: no guard-refused \$(git …) forms in skill/agent markdown"
exit "$FAIL"
