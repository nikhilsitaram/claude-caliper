---
status: Not Yet Started
---

# Auto-enable acceptEdits mode after design approval via Claude Code hooks Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use orchestrate

**Goal:** Auto-enable acceptEdits mode after design approval via Claude Code hooks
**Architecture:** Two-hook chain: a PostToolUse hook on AskUserQuestion creates a session-scoped .design-approved sentinel file when the user approves a design, then a PermissionRequest hook on Edit|Write finds that sentinel and returns an allow+setMode(acceptEdits) decision. The design skill is updated to swap worktree creation before approval and use a structured AskUserQuestion gate with metadata for hook identification.
**Tech Stack:** Bash, jq, Claude Code hooks API (hooks.json, PostToolUse, PermissionRequest)

---

## Phase A — Hook infrastructure and skill update
**Status:** Not Started | **Rationale:** Single phase because the hooks, config, skill update, and marketplace wiring are tightly coupled — no hook works without the others, and the skill change is the trigger for the entire chain. Small surface area (2 scripts, 1 config, 2 file edits, 1 version bump).

- [ ] A1: Write test suites for both hooks — *test_post_tool_use.sh has tests for: approval creates sentinel, rejection skips sentinel, metadata-based detection, text-fallback detection, session_id written correctly, non-AskUserQuestion ignored, missing plan dir ignored. test_permission_request.sh has tests for: matching sentinel returns allow+setMode JSON, mismatched session_id passes through, missing sentinel passes through, worktree search path works, direct cwd path works. All tests fail because hook scripts do not exist.*
- [ ] A2: Create PostToolUse hook script — *All PostToolUse tests pass. Hook reads stdin JSON, detects design approval via metadata.source or Plan dir: text fallback, checks tool_response for Approved, extracts absolute plan dir path from question text, creates .design-approved sentinel containing session_id.*
- [ ] A3: Create PermissionRequest hook script — *All PermissionRequest tests pass. Hook reads stdin JSON, searches $cwd/docs/plans/ and $cwd/.claude/worktrees/*/docs/plans/ for .design-approved sentinels, compares session_id, returns allow+setMode(acceptEdits,session) JSON on match, exits silently on no match.*
- [ ] A4: Create hooks.json and wire into marketplace.json — *hooks/hooks.json declares PostToolUse matcher for AskUserQuestion and PermissionRequest matcher for Edit|Write. marketplace.json claude-caliper and claude-caliper-workflow plugins have hooks field pointing to ./hooks/hooks.json. claude-caliper-tooling does NOT have hooks field. All existing hook tests still pass.*
- [ ] A5: Update design skill with structured approval gate — *Design skill checklist reordered: worktree setup at step 6 (before approval), structured AskUserQuestion approval gate at step 7 with metadata.source=design-approval and absolute Plan dir: path in question text. Old verbal approval step replaced. Steps 8-10 unchanged except renumbered.*
- [ ] A6: Version bump in marketplace.json — *All three plugin versions bumped from 1.6.0 to 1.7.0 in marketplace.json*
