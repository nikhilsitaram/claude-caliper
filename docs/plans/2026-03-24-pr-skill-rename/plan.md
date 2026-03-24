---
status: Not Yet Started
---

# Rename PR skills to pr-* namespace and fix review-to-merge pipeline flow Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use orchestrate

**Goal:** Rename PR skills to pr-* namespace and fix review-to-merge pipeline flow
**Architecture:** Rename all three PR skill directories from verb-pr to pr-verb pattern, update workflow enum values from create-pr/merge-pr to pr-create/pr-merge, add rebase-before-review to pr-review, add merge continuation prompt to pr-review, remove redundant confirmation from pr-merge, update all cross-references across skills, scripts, tests, and docs.
**Tech Stack:** Bash, Markdown, JSON, git

---

## Phase A — Rename and pipeline fixes
**Status:** Not Started | **Rationale:** All changes are tightly coupled — the rename affects every file the other two issues touch. Single phase keeps the rename atomic.

- [ ] A1: Rename PR skill directories and update their SKILL.md files — *Old directories gone, new directories exist with updated SKILL.md files containing: new frontmatter names/descriptions, pr-review has rebase step between Setup and PR Review, pr-review Step 6 has merge continuation AskUserQuestion, pr-merge Step 2 confirmation removed, all cross-references use new pr-* names*
- [ ] A2: Update cross-references in non-PR skills — *All references to create-pr, review-pr, merge-pr in design, orchestrate, draft-plan, and implementation-review SKILL.md files replaced with pr-create, pr-review, pr-merge respectively. Workflow enum values in design SKILL.md and draft-plan SKILL.md updated from create-pr/merge-pr to pr-create/pr-merge.*
- [ ] A3: Update marketplace.json, CLAUDE.md, and README.md — *marketplace.json skill paths point to ./skills/pr-create, ./skills/pr-review, ./skills/pr-merge. CLAUDE.md workflow description uses new names. README.md mermaid diagram, skill table, and all prose references updated. Version bumped in marketplace.json.*
- [ ] A4: Update validate-plan workflow enum values — *validate-plan case statement accepts pr-create, pr-merge, plan-only (rejects create-pr, merge-pr). do_check_workflow references updated to match.*
- [ ] A5: Update test fixtures and test scripts — *All test fixtures use pr-create/pr-merge instead of create-pr/merge-pr. Test descriptions and assertions updated. Tests for old enum values (create-pr, merge-pr) added as invalid_workflow rejection tests. All test scripts pass.*
