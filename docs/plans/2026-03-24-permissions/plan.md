---
status: Complete
---

# Eliminate 7 observed permission prompt interruptions by adding missing safe commands, resolving shell interpreter script arguments, and denying variable-as-command with actionable feedback. Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use orchestrate

**Goal:** Eliminate 7 observed permission prompt interruptions by adding missing safe commands, resolving shell interpreter script arguments, and denying variable-as-command with actionable feedback.
**Architecture:** Three targeted changes to the existing pretooluse-safe-commands.sh hook: (1) expand safe-commands.txt with 5 standard Unix commands, (2) add shell interpreter resolution in extract_command_words_from_segment to resolve 'bash script.sh' to the script basename, (3) add variable-as-command detection that emits a deny with a feedback message. All changes propagate to PermissionRequest via the existing permission-request-safe-bash.sh delegation pattern.
**Tech Stack:** Bash (hooks), jq (JSON), bash test scripts

---

## Phase A — Safe commands, interpreter resolution, and variable deny
**Status:** Complete (2026-03-24) | **Rationale:** All changes form a single logical unit with no dependency layers. Tasks are split by file ownership to enable parallel execution: safe list, hook logic, tests, and a read-only verification.

- [x] A1: Add missing commands to safe-commands.txt — *safe-commands.txt contains ln, dirname, basename, [, command (64 entries total); marketplace.json version bumped to 1.15.0; all existing tests pass*
- [x] A2: Shell interpreter resolution and variable-as-command deny — *'bash scripts/validate-plan' resolves to 'validate-plan' (safe); 'bash -e scripts/validate-plan' resolves to 'validate-plan'; 'bash "$f"' emits deny with feedback; bare 'bash' falls through; $VAR/"$VAR"/${VAR} as command word produces deny with permissionDecisionReason; all existing tests still pass*
- [x] A3: Tests for all new behaviors — *16+ new tests cover: 5 new safe commands, 7 interpreter resolution cases, 4 variable-as-command deny cases; all tests green*
- [x] A4: Verify no dead permission-forwarding code — *Grep confirms no orphaned permission-prompt-forwarding code from the pre-agent-teams supervision loop in hooks/ or skills/orchestrate/*
