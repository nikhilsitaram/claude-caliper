# Hooks

Hook scripts and configuration for the claude-caliper plugin.

## Files

| File | Purpose |
|------|---------|
| `hooks.json` | Hook registry — wired automatically by the plugin system |
| `pretooluse-deny-plan-md.sh` | PreToolUse(Edit/Write/MultiEdit): denies hand-edits to a rendered `plan.md`, pointing Claude at the `validate-plan` command that mutates `plan.json` instead |
| `permission-request-accept-edits.sh` | PermissionRequest(Edit/Write): consumes the `.design-approved` sentinel to enable acceptEdits mode for the session; auto-allows writes into a `.claude/claude-caliper/` plan dir of the cwd, the main checkout, or a worktree nested under either. The target is checked with symlinks resolved; a path containing `..`, a symlink that doesn't resolve to an existing directory, the steering files `.design-approved` and `reviews.json`, or anything outside those dirs falls through to the normal prompt (#307). All fallthrough paths emit `{"continue": true}` to avoid [anthropics/claude-code#12070](https://github.com/anthropics/claude-code/issues/12070) (silent fallthrough = deny). |
| `subagentstop-sync-agent-memory.sh` | SubagentStop: syncs a worktree subagent's `memory: project` writes back to the main repo's `.claude/agent-memory/` |

## Architecture

- **PreToolUse** — fires on every tool call. Used only for **deny** decisions (with `permissionDecisionReason` visible to Claude for self-correction). Never returns allow.
- **PermissionRequest** — fires only when a permission prompt would appear (or a call that can't prompt would be auto-denied), so auto-mode classifier approvals never reach it. Used only for Edit/Write: the design-approval → acceptEdits handoff, and auto-allowing writes into the session's own plan dirs.

## Bash permissions are not caliper's job

caliper ships no Bash allow- or deny-list. Both used to exist and both were retired: a deny hook that scanned command text false-denied heredoc data lines (#294), and an allow hook that parsed commands against a safe-command list could be bypassed by trivial wrapping — `if true; then <cmd>; fi`, `X=$HOME <cmd>`, `true & <cmd>`, backticks — so it could auto-approve arbitrary code (#302). A bash parser written in bash can't be made a security boundary.

Use Claude Code's own mechanisms instead — they parse commands with a real shell parser:

- **Auto mode** (`permissions.defaultMode: "auto"`) — the classifier approves routine commands, including in background subagents. Recommended for the large tier: background subagents (orchestrate's task implementers, the plan drafter) can't answer a prompt, so in default mode any call that would prompt is denied. Rules can cover the plan drafter: it moves its draft into `.claude/claude-caliper/` with `caliper-draft` (below), and its Writes to `.caliper-draft/` fall under acceptEdits, which design approval switches on. They can't cover task implementers, which run whatever commands their task's tests need.
- **Native allow rules** to cut prompts in default-mode sessions. Rules covering caliper's own tooling:

  ```json
  {
    "permissions": {
      "allow": [
        "Bash(validate-plan:*)", "Bash(validate-design:*)", "Bash(caliper-settings:*)", "Bash(caliper-main-root:*)",
        "Bash(seed-agent-memory:*)", "Bash(sync-agent-memory:*)", "Bash(clear-worktree-scratch:*)",
        "Bash(caliper-draft:*)", "Bash(jq:*)",
        "Glob", "Grep", "Skill"
      ]
    }
  }
  ```

  Avoid rules for commands that run code from their arguments (`python -c`, `node -e`, `npx`, `env`, `xargs`, `find -exec`, `awk` `system()`, `git -c core.fsmonitor=…`, `gh alias set --shell`, `gh extension`): in auto mode an allow rule also bypasses the classifier. That rules out blanket `Bash(git:*)` and `Bash(gh:*)`; allow specific subcommands instead (`Bash(git status:*)`).

The retired hook also read `~/.claude/safe-commands.txt` (or `$CLAUDE_SAFE_COMMANDS_FILE`) and allowed Read, Glob, Grep, Skill, WebFetch, WebSearch and ToolSearch for any path or domain. Neither applies any more: move entries you still want into `permissions.allow`, leaving out exec-capable ones and any-path `Read` / any-domain `WebFetch`.

## Coexistence with Personal Hooks

Multiple hooks of the same event type run independently. If you have personal hooks for domain-specific tools, they coexist without conflict.
