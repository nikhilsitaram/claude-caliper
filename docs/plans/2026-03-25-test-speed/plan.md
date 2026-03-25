---
status: Complete
---

# Reduce validate-plan test suite runtime by ~40% by removing nested regression checks and mocking gh CLI calls Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use orchestrate

**Goal:** Reduce validate-plan test suite runtime by ~40% by removing nested regression checks and mocking gh CLI calls
**Architecture:** Remove redundant nested test suite invocations from test_check_review.sh and test_review_gates.sh (CI already runs all files independently). Create a gh mock stub fixture that intercepts `gh pr list` calls and returns controlled responses via GH_MOCK_PR_COUNT env var. Update test_check_workflow.sh to use the mock and remove skip guards so PR-related tests run unconditionally.
**Tech Stack:** Bash

---

## Phase A — Remove nested regressions and mock gh CLI
**Status:** Complete (2026-03-25) | **Rationale:** All three tasks modify disjoint files and can execute in parallel within a single phase.

- [x] A1: Remove nested regression test invocations — *test_check_review.sh has 11 tests (Test 12 removed), test_review_gates.sh has 11 tests (Test 11 removed, Tests 1-10 + 5b remain), both pass in under 2s each*
- [x] A2: Create gh mock stub fixture — *gh-mock.sh is executable, returns GH_MOCK_PR_COUNT value (default 0) on stdout for `pr list` commands, exits 0 for recognized commands, exits 1 for unrecognized commands*
- [x] A3: Wire gh mock into test_check_workflow.sh and remove skip guards — *Tests 7 and 9 run unconditionally (no `command -v gh` guards), test uses PATH-prepended mock directory, all tests pass with zero network calls*
