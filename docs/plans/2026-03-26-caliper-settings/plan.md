---
status: In Development
---

# Add /caliper-settings skill and script for persistent user-configurable defaults with 3-tier precedence (CLI flag > user setting > shipped default) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use orchestrate

**Goal:** Add /caliper-settings skill and script for persistent user-configurable defaults with 3-tier precedence (CLI flag > user setting > shipped default)
**Architecture:** A defaults.json schema at the repo root defines 8 settings with types and metadata. A bash script (scripts/caliper-settings) handles get/set/reset/list operations against CLAUDE_PLUGIN_DATA/settings.json, merging user overrides over defaults. A thin SKILL.md wraps the script for /caliper-settings invocation. Each consuming skill (pr-create, pr-review, pr-merge, design, orchestrate, design-review, plan-review, implementation-review) adds a one-liner fallback per setting: check CLI flag first, then call the script.
**Tech Stack:** Bash, jq, SKILL.md (markdown)

---

## Phase A — Settings Infrastructure and Consumer Integrations
**Status:** In Progress | **Rationale:** Single phase — foundation tasks (1-4) are sequential, consumer integrations (5-11) are parallel and independent. No natural phase boundary since consumers are one-liner additions that don't depend on each other.

- [x] A1: Create defaults.json schema — *defaults.json exists at repo root with all 8 settings (skip_tests, review_mode, skip_review, merge_strategy, workflow, execution_mode, review_wait_minutes, re_review_threshold), each with type/default/description/used_by fields, types validated as bool/enum/int*
- [x] A2: Implement scripts/caliper-settings bash script — *Script supports get/set/reset/list subcommands, validates types (bool/enum/int), merges user settings.json over defaults.json, handles all error cases (missing env vars, unknown keys, corrupted JSON, missing settings.json), exit codes correct*
- [x] A3: Write test suite for caliper-settings script — *Test script covers: get (default fallback, user override), set (valid bool/enum/int, invalid type rejection, unknown key rejection), reset (single key, all keys), list (shows all 8 settings with correct columns), error handling (missing CLAUDE_PLUGIN_ROOT, missing CLAUDE_PLUGIN_DATA, corrupted settings.json, unknown key), all tests pass*
- [x] A4: Create caliper-settings skill SKILL.md — *SKILL.md has frontmatter with name and description (trigger: /caliper-settings), documents list/set/reset subcommands, shows how to invoke the script via ${CLAUDE_PLUGIN_ROOT}/scripts/caliper-settings, stays under 1500 words*
- [x] A5: Integrate skip_tests into pr-create — *Step 4 (Run Tests) has a fallback line: if --skip-tests/-T not passed, check caliper-settings get skip_tests; if true, skip tests*
- [ ] A6: Integrate review_mode, skip_review, and review_wait_minutes into pr-review — *Step 2 (Mode Selection): if --automated not passed, check caliper-settings get review_mode; if 'automated', use automated mode (skip prompt). Step 4 (Dispatch): if --skip-review not passed, check caliper-settings get skip_review; if true, skip dispatch. Step 5 (External Feedback): use caliper-settings get review_wait_minutes as poll timeout instead of hardcoded 10 minutes.*
- [ ] A7: Integrate merge_strategy into pr-merge — *Step 2 (Merge) merge strategy section: if no --rebase flag and not integration branch and not phase PR, check caliper-settings get merge_strategy to determine squash vs rebase*
- [ ] A8: Integrate workflow, execution_mode, and re_review_threshold into design — *Step 7 Q1 (Workflow): default option pulled from caliper-settings get workflow. Step 7 Q2 (Exec mode): default option pulled from caliper-settings get execution_mode. Re-review gate (step 9 design-review dispatch and step 10 plan-review dispatch): use caliper-settings get re_review_threshold instead of hardcoded 5.*
- [ ] A9: Integrate workflow, execution_mode, review_wait_minutes, and re_review_threshold into orchestrate — *Review Loop Protocol: use caliper-settings get re_review_threshold instead of hardcoded 5 for re-dispatch gate. pr-merge workflow routing: use caliper-settings get review_wait_minutes for external review timeout. Note: workflow and execution_mode are read from plan.json (written by design skill), not from caliper-settings at runtime — add a note clarifying this.*
- [ ] A10: Integrate re_review_threshold into design-review, plan-review, and implementation-review — *All three review skills: replace hardcoded 'more than 5' re-review gate with caliper-settings get re_review_threshold*
- [ ] A11: Register skill and bump plugin version — *All three plugin versions bumped from 1.18.2 to 1.19.0, caliper-settings skill path added to claude-caliper and claude-caliper-workflow plugin skill arrays*
