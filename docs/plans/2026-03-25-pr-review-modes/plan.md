---
status: Complete
---

# Add automated vs deliberate mode selection, background subagent dispatch, poll-based bot readiness detection, and two-wave fixing to pr-review Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use orchestrate

**Goal:** Add automated vs deliberate mode selection, background subagent dispatch, poll-based bot readiness detection, and two-wave fixing to pr-review
**Architecture:** Rewrite skills/pr-review/SKILL.md to restructure the workflow into 9 steps: setup, mode selection (automated/deliberate prompt, skipped when --automated flag), rebase, background subagent dispatch, external feedback with poll-based bot readiness detection, subagent results with two-wave fixing, deliberate-only present+confirm, deliberate-only fix/test/push, and PR comment. Bump version in marketplace.json.
**Tech Stack:** Markdown, JSON

---

## Phase A — Rewrite pr-review SKILL.md and bump version
**Status:** Complete (2026-03-25) | **Rationale:** Single file rewrite plus a version bump — no dependency layers or natural cut points.

- [x] A1: Rewrite pr-review SKILL.md with mode selection and restructured workflow — *SKILL.md has 9 steps matching the design: setup, mode selection, rebase, background subagent dispatch, external feedback with polling, subagent results with two-wave fixing, present+confirm (deliberate only), fix/test/push (deliberate only), comment on PR. Word count under 2,000.*
- [x] A2: Bump version in marketplace.json — *All three version fields in marketplace.json bumped from 1.16.1 to 1.17.0.*
