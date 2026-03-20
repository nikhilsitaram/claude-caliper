# Safe Commands Hook + Auto Mode Permission Migration

## Problem

All five subagent prompt files use `bypassPermissions`, which runs every command without oversight — no prompt injection safeguards, no visibility into what commands are executed, and no mechanism to build a curated allowlist over time. Meanwhile, users who run the plugin in safer permission modes (like `acceptEdits`) get friction from perfectly safe commands (e.g., `stat`, `brew`) that aren't pre-approved.

There's no middle ground: either everything is auto-approved or common dev commands trigger manual prompts. There's also no feedback mechanism to grow the safe list from actual usage, so the initial list either under-covers (causing repeated friction) or over-covers (reducing security).

## Goal

Layer three permission mechanisms — auto mode, a safe commands hook, and a learning loop — so subagents run with oversight while common dev commands execute without friction, and the safe list grows over time based on actual usage.

## Success Criteria

1. Subagents run under Claude's auto mode permission evaluation rather than unrestricted bypass, providing prompt injection safeguards for all commands not on the safe list
2. Commands matching the curated safe list are approved instantly without per-command AI evaluation overhead (once the user has wired the hook per setup instructions)
3. Commands not in the safe list are captured for review, so users can decide whether to add them
4. After each task completes, the user is prompted with any non-safe commands and can approve additions that take effect immediately for subsequent tasks
5. Existing pipeline behavior (TDD, review gates, commit workflow) is unchanged

## Architecture

### Layer 1: Auto Mode (base permission mode)

All subagent prompt files switch from `mode: "bypassPermissions"` to `mode: "auto"`. Auto mode lets Claude evaluate each permission request with built-in prompt injection safeguards. Edits, reads, and safe-looking commands are approved automatically; risky operations are flagged or blocked.

**Files changed:**
- `skills/orchestrate/implementer-prompt.md`
- `skills/orchestrate/phase-dispatcher-prompt.md`
- `skills/orchestrate/task-reviewer-prompt.md`
- `skills/implementation-review/reviewer-prompt.md`
- `skills/merge-pr/reviewer-prompt.md`

### Layer 2: Safe Commands Hook (deterministic pre-approval)

A PreToolUse hook intercepts every Bash command before auto mode evaluates it. If the command matches a prefix in `hooks/safe-commands.txt`, the hook returns `permissionDecision: allow` — zero token cost, instant approval. If no match, the hook logs the command to a temp file and falls through to auto mode.

```text
hooks/
  safe-commands.txt              # One prefix per line, version-controlled
  pretooluse-safe-commands.sh    # PreToolUse hook script
```

**safe-commands.txt** ships with ~35 common dev workflow prefixes. Destructive commands (`rm`) and data-exfiltration vectors (`curl`, `bash`) are intentionally excluded — auto mode evaluates those per-invocation, and users can add them via the learning loop if their workflow requires it:

```text
awk
cat
cd
chmod
cp
diff
du
echo
env
file
find
git
grep
head
jq
ls
mkdir
mv
node
npm
npx
pytest
python
python3
pwd
readlink
realpath
ruff
sed
sort
stat
tail
test
touch
uv
uvx
wc
which
xargs
```

**Hook flow:**

```text
Bash command arrives
  → Hook parses command words (split on &&, ;, |, $())
  → Check each command word against safe-commands.txt prefixes
  → ALL match → return { permissionDecision: "allow" }
  → ANY non-match → log non-matching commands to $TMPDIR/claude-safe-cmds-nonmatch.log
                   → return nothing (fall through to auto mode)
```

**Parsing rules:**
- Split on `&&`, `;`, `|` to extract command segments
- Extract command words from variable assignments: `VAR=$(cmd)` → `cmd`
- Respect quoted strings — do not split inside single or double quotes (`echo "hello && world"` → only `echo` is the command word)
- For subshells `$(...)`, extract the inner command word
- Check both the full command path and its basename (`./node_modules/.bin/jest` → also check `jest`)
- Limit to first 20 command words per input to bound processing
- When parsing is ambiguous (heredocs, process substitution, complex nesting), fall through to auto mode — false negatives (prompting for a safe command) are acceptable, false positives (auto-approving an unsafe command) are not

### Layer 3: Learning Loop (per-task surfacing)

After each task's implementer + reviewer cycle, the phase dispatcher reads the non-safe commands log. If entries exist, it asks the user via AskUserQuestion whether to add them to `safe-commands.txt`. Approved additions are appended immediately — subsequent tasks benefit.

**Phase dispatcher additions:**
- After task reviewer completes, before starting next task:
  1. Read `$TMPDIR/claude-safe-cmds-nonmatch.log`
  2. If non-empty, deduplicate and present via AskUserQuestion (multiSelect)
  3. User selects which to add → append to `hooks/safe-commands.txt`
  4. Truncate the log for the next task

## Key Decisions

### Auto mode as base instead of acceptEdits
Auto mode provides prompt injection safeguards that `acceptEdits` lacks, and handles the long tail of commands the safe list doesn't cover. The safe commands hook reduces auto mode's per-evaluation token overhead for common commands.

### Phase dispatcher owns per-task user communication
Per-task granularity requires the dispatcher to call AskUserQuestion directly because the orchestrator only sees phase-level results and cannot intervene between tasks. Trade-off: the user interacts with a subagent rather than the main context, so they can't escalate pipeline-level decisions from this prompt. This is acceptable because the question is narrowly scoped (approve/reject specific command prefixes) and doesn't require pipeline-level context. The typical scenario — the same non-safe command appearing repeatedly across tasks — makes immediate addition more valuable than batching at phase boundaries.

### Deterministic safe list alongside auto mode
Auto mode's judgments are probabilistic. The safe list provides a deterministic fast-path for known commands — predictable, zero token cost, and version-controlled so teams share the same baseline.

### Dev workflow commands only
The safe list ships with ~35 common dev prefixes. Domain-specific tools (MCP servers, Dataiku, Tableau) are left to users' personal hooks. This keeps the plugin generic.

### Destructive commands excluded from default safe list
`rm`, `curl`, and `bash` are intentionally not in the default safe list. `rm` is destructive, `curl` can exfiltrate data, and `bash` can execute arbitrary scripts. Auto mode evaluates these per-invocation, which is the right trade-off for a default config. Users who trust their environment can add them via the learning loop — the first time one triggers, the dispatcher asks and it's one click to permanently allow. `mv` and `cp` are included despite being potentially destructive because they're essential for refactoring workflows — they move/copy rather than delete, and git provides recovery.

### Coexistence with personal hooks
Multiple PreToolUse hooks run independently — if any returns `permissionDecision: allow`, the command is approved. The repo hook covers dev workflow commands; users keep personal hooks for domain-specific MCP tools (Dataiku, Tableau, Slack, etc.). Overlapping commands are harmless — the first hook to match wins.

### Hook distribution gap
Hook scripts ship with the plugin (files in `hooks/`), but `settings.json` hook config doesn't auto-install via the plugin system. Users must manually wire the hook. The setup path will be documented; a setup skill may follow later.

## Alternatives Considered

### Auto mode alone (no safe commands hook)
Auto mode handles all commands, including safe ones. But it evaluates each one with an LLM call — adding token cost and latency for commands like `git status` that are always safe. The hook eliminates this overhead for the common case while auto mode handles the long tail.

### `settings.json` allowedTools patterns instead of custom hook
Claude Code's `permissions.allow` can pre-approve specific Bash patterns. But it doesn't support logging non-matches for the learning loop, and pattern syntax is limited compared to a shell script that can parse compound commands. The hook gives us both deterministic approval and observability.

### acceptEdits + safe commands hook (no auto mode)
Simpler — `acceptEdits` auto-approves file operations, hook auto-approves safe Bash. But non-safe commands would prompt the user directly with no AI evaluation, and there are no prompt injection safeguards. Auto mode adds a meaningful security layer for the long tail.

## Non-Goals

- MCP tool auto-approval (users extend with personal hooks)
- Automatic additions without user confirmation
- Replacing users' personal safe commands hooks
- Solving the plugin hook distribution gap in this PR (document-only for now)

## Implementation Approach

**Single phase** — no dependency layers. All changes are tightly coupled (permission mode + hook + dispatcher integration).

### Tasks

1. **Create hook infrastructure** — `hooks/safe-commands.txt` (prefixes) + `hooks/pretooluse-safe-commands.sh` (PreToolUse script that reads the list, auto-approves matches, logs non-matches)
2. **Switch permission modes** — Update all 5 prompt files from `bypassPermissions` to `auto`
3. **Update phase dispatcher** — Add per-task non-safe command check after task reviewer: read log, AskUserQuestion (multiSelect) for additions, append approved commands, truncate log
4. **Update orchestrate SKILL.md** — Document the hook requirement and safe commands workflow in the orchestrate skill instructions
5. **Test hook** — Shell tests for the hook: matching commands, non-matching commands, compound commands, log file behavior
6. **Documentation** — Setup instructions for wiring the hook into settings.json
