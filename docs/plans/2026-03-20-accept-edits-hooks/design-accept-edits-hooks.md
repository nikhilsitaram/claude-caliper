# Auto-Enable acceptEdits After Design Approval

## Problem

When using the design skill in default permission mode, every Edit/Write operation after design approval requires manual user confirmation. This creates unnecessary friction — the user already approved the design, signaling intent to proceed with file creation. The repeated permission dialogs slow down the workflow (design doc writing, design-review, draft-plan, orchestration) without adding safety value.

## Goal

Automatically switch the Claude Code session to acceptEdits mode when the user approves a design, so all subsequent file operations proceed without permission dialogs.

## Success Criteria

1. After a user approves a design, all subsequent file-creation and file-editing operations in that session proceed without manual permission confirmation
2. Without a current-session `.design-approved` sentinel file, file edit permission dialogs behave normally (no false positives)
3. After installing or updating the plugin, the auto-approval behavior works without any manual configuration by the user
4. If a user rejects the design ("Needs changes"), no sentinel is created and file permissions remain in default mode

## Alternatives Considered

1. **Single PermissionRequest hook with transcript inspection** — the PermissionRequest hook could read the transcript JSONL (available via `transcript_path` in stdin) to check whether a design-approval AskUserQuestion was answered with "Approved." Eliminates the PostToolUse hook and sentinel file. Rejected because transcript parsing is fragile across compactions and slower than a file existence check.

2. **PreToolUse hook with `allow` decision** — PreToolUse fires on every tool call (not just permission dialogs) and can return `allow`. But PreToolUse cannot return `updatedPermissions` with `setMode` (per Claude Code hooks API), so it can't flip the session to acceptEdits — it would need to allow every individual Edit/Write, firing on every call for the rest of the session. Less efficient than a one-time mode switch.

3. **Native plan mode (EnterPlanMode/ExitPlanMode)** — ExitPlanMode triggers accept-edits on approval. But it hijacks the UX with its own plan review interface, conflicting with the design skill's collaborative dialogue flow. Also errors if called without entering plan mode first.

## Architecture

Two-hook chain triggered by design approval:

```text
AskUserQuestion (design approval)
    ↓ PostToolUse hook
Creates <worktree>/docs/plans/YYYY-MM-DD-topic/.design-approved (contains session_id)
    ↓ Skill calls Write (design doc)
    ↓ PermissionRequest hook
Finds sentinel with matching session_id → allows Write + sets acceptEdits mode (session)
    ↓
All subsequent Edit/Write: auto-approved
```

### Hook 1: PostToolUse on AskUserQuestion

**Script:** `hooks/post-tool-use-design-approval.sh`

**Trigger:** `tool_input.metadata.source == "design-approval"` (primary), with fallback to matching `"Plan dir:"` prefix in question text if metadata is not forwarded to PostToolUse.

**Risk:** The AskUserQuestion schema defines a `metadata` field with a `source` property, but whether this field is forwarded verbatim to PostToolUse's `tool_input` is unverified. The hook implements both detection paths: metadata check first, then text-based fallback. If both paths fail, the hook exits silently and permission dialogs continue normally — safe degradation with no user-visible change. The hook logs to stderr when neither path matches an AskUserQuestion that contains "Plan dir:" text, so the failure is diagnosable. Verify metadata forwarding during implementation with a manual integration test.

**Logic:**
1. Read stdin JSON, extract `session_id`, `tool_name`, `tool_input`, and `tool_response`
2. Bail if `tool_name != "AskUserQuestion"`
3. Check `tool_input.metadata.source == "design-approval"` (primary) OR question text contains `"Plan dir:"` (fallback)
4. Bail if neither matches
5. Check `tool_response` for approval — bail if response contains "Needs changes" or does not contain "Approved". The `tool_response` for AskUserQuestion with options is expected to be a plain string matching the selected option label (e.g., `"Approved"`). Verify this format during implementation; if it's a JSON object, adjust the matching logic accordingly
6. Parse absolute plan directory path from question text (format: `Plan dir: /absolute/path/to/worktree/docs/plans/YYYY-MM-DD-topic`)
7. `mkdir -p` the plan directory
8. Write `session_id` to `.design-approved` inside the plan directory

**Output:** None (hook creates files as side effect, no decision to return).

### Hook 2: PermissionRequest on Edit|Write

**Script:** `hooks/permission-request-accept-edits.sh`

**Trigger:** Permission dialog about to show for Edit or Write tool.

**CWD mismatch resolution:** The session CWD is typically the project root, not the worktree. The sentinel lives in the worktree at `<worktree>/docs/plans/YYYY-MM-DD-topic/.design-approved`. Since worktrees are created under `$cwd/.claude/worktrees/`, the hook searches both the main repo and all worktree locations:

```bash
find "$CWD/docs/plans" "$CWD/.claude/worktrees/*/docs/plans" -maxdepth 3 -name .design-approved 2>/dev/null
```

**Logic:**
1. Read stdin JSON, extract `session_id` and `cwd`
2. Search for `.design-approved` in `$cwd/docs/plans/` (direct) and `$cwd/.claude/worktrees/*/docs/plans/` (worktrees)
3. For each found sentinel: read contents and compare to `session_id`
4. If session IDs match: return structured JSON decision
5. If no match or not found: `exit 0` (passthrough, normal permission dialog shows)

**Exact output when sentinel matches:**
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": {
      "behavior": "allow",
      "updatedPermissions": [
        { "type": "setMode", "mode": "acceptEdits", "destination": "session" }
      ]
    }
  }
}
```

### Design Skill Changes

Steps 6 (verbal approval) and 7 (worktree setup) are swapped, and the former step 6 verbal approval is replaced with a structured AskUserQuestion gate at its new position (step 7), including metadata for hook identification:

**Reordered checklist:**

1. Explore context
2. Challenge assumptions
3. Ask clarifying questions
4. Propose 2-3 approaches
5. Present design (section by section)
6. Set up worktree (moved from step 7 to step 6)
7. Design approval AskUserQuestion — replaces verbal approval with structured gate; includes `metadata: { source: "design-approval" }` and absolute plan dir path in question text
8. Write design doc (auto-approved via hooks)
9. Dispatch design-review subagent
10. Dispatch draft-plan subagent

**CWD assumption:** The session CWD may remain at the project root after worktree creation (step 6). The skill embeds the **absolute** worktree path in the question text so the PostToolUse hook creates the sentinel in the correct location regardless of CWD.

**AskUserQuestion format:**
```json
{
  "questions": [{
    "question": "Design approved? Plan dir: /abs/path/.claude/worktrees/branch/docs/plans/2026-03-20-topic",
    "header": "Approval",
    "options": [
      { "label": "Approved", "description": "Write design doc and proceed to review" },
      { "label": "Needs changes", "description": "Continue iterating on the design" }
    ],
    "multiSelect": false
  }],
  "metadata": { "source": "design-approval" }
}
```

### Plugin Hook Configuration

Create `hooks/hooks.json` with the hook declarations. Add `"hooks": "./hooks/hooks.json"` to the `claude-caliper` and `claude-caliper-workflow` plugin entries in `marketplace.json` (not `claude-caliper-tooling`, which does not include the design skill and has no mechanism to trigger sentinel creation).

**Risk:** `${CLAUDE_PLUGIN_ROOT}` is assumed to be set by the plugin loader at hook execution time. If not available, hook commands fail to resolve. Verify during implementation; fallback is to use a relative path from the hook config location.

**hooks/hooks.json:**
```json
{
  "PostToolUse": [{
    "matcher": "AskUserQuestion",
    "hooks": [{
      "type": "command",
      "command": "${CLAUDE_PLUGIN_ROOT}/hooks/post-tool-use-design-approval.sh"
    }]
  }],
  "PermissionRequest": [{
    "matcher": "Edit|Write",
    "hooks": [{
      "type": "command",
      "command": "${CLAUDE_PLUGIN_ROOT}/hooks/permission-request-accept-edits.sh"
    }]
  }]
}
```

## Key Decisions

1. **metadata.source with text fallback for identification** — metadata.source is the preferred signal (structured, stable, invisible to user). If AskUserQuestion doesn't forward metadata to PostToolUse, the hook falls back to matching "Plan dir:" prefix in the question text. Both paths are implemented. If both fail, the hook exits silently — permission dialogs continue normally (safe degradation). Log to stderr for diagnosability.

2. **Absolute path in question text** — the skill embeds the full absolute worktree path (e.g., `/Users/me/project/.claude/worktrees/branch/docs/plans/2026-03-20-topic`). This eliminates CWD ambiguity — the PostToolUse hook creates the sentinel at the exact path regardless of where the session is running.

3. **Session-scoped sentinel** — the `.design-approved` file contains the `session_id`. The PermissionRequest hook only triggers if the sentinel's session_id matches the current session. Stale sentinels from previous sessions are ignored. The file is not cleaned up — it's removed when the worktree is cleaned up after ship/merge, and doubles as an audit trail. If the design skill is run without a worktree (non-standard), the sentinel persists in `docs/plans/` as an inert hidden file with no behavioral effect after the session ends (acceptEdits is session-scoped).

4. **Session-scoped mode change** — `destination: "session"` means acceptEdits resets on next session. No permanent settings modification.

5. **Worktree before approval** — worktree must exist before the AskUserQuestion so the PostToolUse hook can create files in it. The worktree is lightweight and safe to create before final approval.

6. **Separate hooks.json** — hook configuration lives in `hooks/hooks.json`, referenced from marketplace.json. This follows the plugin convention of separating hook config from the manifest.

7. **Worktree search in PermissionRequest hook** — the hook searches both `$cwd/docs/plans/` and `$cwd/.claude/worktrees/*/docs/plans/` to find sentinels regardless of whether the session CWD is the project root or the worktree itself.

## Non-Goals

- No Bash command auto-approval (only Edit|Write)
- No sentinel cleanup mechanism (worktree cleanup handles it)
- No retroactive activation for existing sessions
- No plan mode integration (native plan mode UX conflicts with design skill's collaborative flow)
- Stale sentinels from previous sessions in non-worktree setups persist as inert files (session_id mismatch prevents false activation)

## Implementation Approach

Single phase — small surface area (2 scripts, 1 config, 2 file edits):

**Phase A: Hook infrastructure + skill update**
1. Create `hooks/post-tool-use-design-approval.sh`
2. Create `hooks/permission-request-accept-edits.sh`
3. Create `hooks/hooks.json`
4. Update `skills/design/SKILL.md` (swap steps 6/7, replace verbal approval with structured AskUserQuestion gate)
5. Update `.claude-plugin/marketplace.json` (add hooks reference to claude-caliper and claude-caliper-workflow plugins)
6. Version bump
