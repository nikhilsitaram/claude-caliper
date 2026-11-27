#!/usr/bin/env bash
set -euo pipefail

# Pin the plugin manifest to what claude.ai accepts and keep every name-coupled
# reference in sync with it (gh #344):
#   - claude.ai and `claude plugin validate` reject plugin names that pass as
#     Anthropic's own (claude-*, anthropic-*, ...), so the plugins never install
#     in cloud sessions or routines.
#   - Claude Code namespaces plugin agents as <plugin>:<agent> and won't resolve a
#     bare agent name, so every dispatch must use the manifest's plugin name — and
#     there must be exactly one plugin, or a partial bundle's agents carry a
#     different prefix than the skills hardcode.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MANIFEST="$REPO_ROOT/.claude-plugin/marketplace.json"

FAILURES=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILURES=$((FAILURES + 1)); }

MARKETPLACE=$(jq -r '.name' "$MANIFEST")
PLUGIN_COUNT=$(jq '.plugins | length' "$MANIFEST")
PLUGIN=$(jq -r '.plugins[0].name' "$MANIFEST")

echo "=== manifest shape ==="
if [[ "$PLUGIN_COUNT" -eq 1 ]]; then pass "one plugin ($PLUGIN)"; else fail "expected 1 plugin, found $PLUGIN_COUNT"; fi

if [[ -n "$(jq -r '.description // empty' "$MANIFEST")" ]]; then pass "marketplace description set"; else fail "marketplace description missing"; fi

# The validator's reserved-name rule, copied from its error message (Claude Code
# 2.1.332). CI has no claude CLI, so this copy is the only guard there and can
# drift if the rule changes; the `claude plugin validate` check below is the real
# one wherever the CLI is installed.
reserved() {
  local n="$1"
  [[ "$n" =~ ^(claude|anthropic|anthropics|cc-plugin)- ]] && return 0
  [[ "$n" =~ ^(claude|anthropic|anthropics|claude-code|claude-mods)$ ]] && return 0
  [[ "$n" =~ (claude|anthropic)-official|official-(claude|anthropic) ]] && return 0
  return 1
}
while IFS= read -r name; do
  if reserved "$name"; then fail "plugin name '$name' is reserved"; else pass "plugin name '$name' not reserved"; fi
done < <(jq -r '.plugins[].name' "$MANIFEST")

# The one plugin must ship every skill, since there's no other bundle to carry it.
listed=$(jq -r '.plugins[0].skills[]' "$MANIFEST" | sort)
on_disk=$(find "$REPO_ROOT/skills" -mindepth 2 -maxdepth 2 -name SKILL.md | sed "s#^$REPO_ROOT/#./#; s#/SKILL.md\$##" | sort)
if [[ "$listed" == "$on_disk" ]]; then pass "plugin lists every skill dir"; else fail "skills list differs from skills/*: $(diff <(echo "$listed") <(echo "$on_disk") | grep '^[<>]' | tr '\n' ' ')"; fi

echo "=== README badges ==="
SKILL_COUNT=$(jq '.plugins[0].skills | length' "$MANIFEST")
README="$REPO_ROOT/README.md"
if grep -qF "badge/$SKILL_COUNT%20skills-" "$README"; then pass "skills badge is $SKILL_COUNT"; else fail "README skills badge != $SKILL_COUNT skills"; fi
if grep -qF "installs $SKILL_COUNT skills" "$README"; then pass "README skill count is $SKILL_COUNT"; else fail "README 'installs N skills' != $SKILL_COUNT"; fi

echo "=== agent dispatch namespace ==="
SEARCH=("$REPO_ROOT/skills" "$REPO_ROOT/agents" "$REPO_ROOT/README.md" "$REPO_ROOT/CLAUDE.md" "$REPO_ROOT/hooks" "$REPO_ROOT/bin" "$REPO_ROOT/.github")
for agent_file in "$REPO_ROOT"/agents/*.md; do
  agent=$(basename "$agent_file" .md)
  # Any <ns>:<agent> whose namespace isn't the plugin name, or a bare-name dispatch.
  stale=$(grep -rnoE "[A-Za-z0-9_-]+:$agent\b" "${SEARCH[@]}" | grep -vE ":$PLUGIN:$agent\$" || true)
  stale+=$(grep -rnE "subagent_type: *\"$agent\"" "${SEARCH[@]}" || true)
  if [[ -z "$stale" ]]; then pass "$agent dispatched as $PLUGIN:$agent"; else fail "$agent with wrong or missing namespace: $stale"; fi
done

echo "=== skill invocation namespace ==="
stale=""
for skill_dir in "$REPO_ROOT"/skills/*/; do
  skill=$(basename "$skill_dir")
  # Slash command (/ns:skill) or Skill-tool name (ns:skill).
  stale+=$(grep -rnoE "/?[A-Za-z0-9_-]+:$skill\b" "${SEARCH[@]}" | grep -vE "[:/]$PLUGIN:$skill\$" || true)
done
if [[ -z "$stale" ]]; then pass "every namespaced skill invocation is /$PLUGIN:<skill>"; else fail "wrong skill namespace: $stale"; fi

echo "=== install ids ==="
# Migration notes name a retired id right after `/plugin uninstall`; that token is the one allowed use.
stale=""
while IFS= read -r hit; do
  hit=$(sed -E 's#/plugin uninstall [A-Za-z0-9_@-]+##g' <<<"$hit")
  bad=$(grep -oE "[A-Za-z0-9_-]+@$MARKETPLACE\b" <<<"$hit" | grep -vxE "$PLUGIN@$MARKETPLACE" || true)
  [[ -n "$bad" ]] && stale+="${hit%%:*}: $bad; "
done < <(grep -rnE "@$MARKETPLACE\b" "${SEARCH[@]}" || true)
if [[ -z "$stale" ]]; then pass "every install id is $PLUGIN@$MARKETPLACE"; else fail "stale install ids: $stale"; fi

echo "=== claude plugin validate ==="
if command -v claude >/dev/null 2>&1; then
  if out=$(cd "$REPO_ROOT" && claude plugin validate . 2>&1); then pass "claude plugin validate"; else fail "claude plugin validate: $out"; fi
else
  echo "SKIP: claude CLI not installed"
fi

if [[ "$FAILURES" -gt 0 ]]; then echo "$FAILURES failure(s)"; exit 1; fi
echo "All plugin manifest checks passed"
