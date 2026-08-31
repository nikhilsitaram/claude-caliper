#!/usr/bin/env bash
set -euo pipefail

# SubagentStop hook: persist a subagent's memory: project writes past worktree
# cleanup. The subagent wrote .claude/agent-memory/<name>/ into its worktree (a
# real dir seeded by seed-agent-memory); this runs sync-agent-memory to merge
# those writes back into $MAIN_ROOT before the worktree is ever removed.
#
# Hooks run as external processes, so they are NOT caught by the worktree
# isolation guard that blocks the subagent's own out-of-worktree writes — which
# is why the persist step lives here rather than in the agent.
#
# Never blocks: any failure (non-git CWD, a transient sync error) is swallowed so
# the subagent stops normally. Worst case memory isn't persisted this once, which
# is no worse than before.

input="$(cat)"
# Swallow jq's non-zero exit on malformed stdin: under set -e it would otherwise
# propagate as exit 2 — the SubagentStop *blocking* code — breaking the
# never-blocks contract above.
cwd="$(echo "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"

[[ -n "$cwd" && -d "$cwd" ]] || exit 0

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
"$SCRIPT_DIR/../bin/sync-agent-memory" "$cwd" >/dev/null 2>&1 || true

exit 0
