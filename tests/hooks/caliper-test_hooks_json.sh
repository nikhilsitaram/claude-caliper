#!/usr/bin/env bash
set -euo pipefail

# hooks/hooks.json wiring: every command hook needs a string `command` (exec
# form puts the script in `args`, never in place of `command` — a missing one
# fails schema validation and silently disables every hook), and every
# ${CLAUDE_PLUGIN_ROOT} script it names must exist and be executable.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOKS_JSON="$REPO_ROOT/hooks/hooks.json"
PASS=0
FAIL=0

pass() { echo "PASS: $1"; ((PASS++)) || true; }
fail() { echo "FAIL: $1"; ((FAIL++)) || true; }

if jq -e . "$HOOKS_JSON" >/dev/null 2>&1; then pass "hooks.json parses"; else fail "hooks.json parses"; fi

bad="$(jq -r '.hooks | to_entries[] | .key as $ev | .value[] | .hooks[]
  | select(.type != "command" or (.command | type) != "string")
  | "\($ev): \(tojson)"' "$HOOKS_JSON")"
if [[ -z "$bad" ]]; then pass "every hook is type command with a string command"; else fail "malformed hooks: $bad"; fi

while IFS= read -r arg; do
  path="${arg/\$\{CLAUDE_PLUGIN_ROOT\}/$REPO_ROOT}"
  if [[ -f "$path" && -x "$path" ]]; then pass "script exists and is executable: $arg"; else fail "missing or not executable: $arg"; fi
done < <(jq -r '.hooks[][] | .hooks[] | (.args // [])[], .command | select(startswith("${CLAUDE_PLUGIN_ROOT}"))' "$HOOKS_JSON")

for script in "$REPO_ROOT"/hooks/*.sh; do
  rel="hooks/$(basename "$script")"
  if grep -qF "\${CLAUDE_PLUGIN_ROOT}/$rel" "$HOOKS_JSON"; then pass "registered: $rel"; else fail "not registered in hooks.json: $rel"; fi
done

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
