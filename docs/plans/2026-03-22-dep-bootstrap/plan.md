---
status: Complete
---

# Make worktree dependency bootstrapping reliable across single-root repos, workspace-based monorepos, and multi-manifest repos, with clear failure reporting and tool availability fallbacks Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use orchestrate

**Goal:** Make worktree dependency bootstrapping reliable across single-root repos, workspace-based monorepos, and multi-manifest repos, with clear failure reporting and tool availability fallbacks
**Architecture:** Extract the bootstrap procedure to skills/design/dependency-bootstrap.md as a shared reference file. The design skill step 6 gains a sub-step that bootstraps deps via See reference before running tests. The orchestrate skill step 3 replaces its inline install table (~180 words) with a one-line summary plus a See reference to the same file, freeing token budget.
**Tech Stack:** Markdown skill files, Claude Code See-reference convention, jq for version bump

---

## Phase A — Shared bootstrap procedure and skill integration
**Status:** Complete (2026-03-22) | **Rationale:** Single phase because the three deliverables are tightly coupled: the reference file must exist before either SKILL.md can reference it, and both SKILL.md edits are textual changes with no independent verification gate between them.

- [x] A1: Create dependency-bootstrap.md reference file — *dependency-bootstrap.md exists under skills/design/ with all 5 sections: (a) detection order (4 tiers: root manifests, workspace indicators, subdirectory scan, symlink fallback), (b) install command table with entries for pyproject.toml, requirements.txt, package-lock.json, yarn.lock, pnpm-lock.yaml, Cargo.toml, go.mod, (c) Python tool fallback (uv -> python3 -m venv + pip), (d) failure handling (check exit code, escalate on non-zero), (e) symlink fallback. Under 400 words.*
- [x] A2: Add bootstrap sub-step to design SKILL.md step 6 — *Step 6 in design SKILL.md is split into three sub-steps: (a) create worktree, (b) bootstrap dependencies per See reference to ./dependency-bootstrap.md, (c) run tests to establish a clean baseline. No new top-level step added. Total SKILL.md word count stays under 1000.*
- [x] A3: Replace orchestrate inline install table with See reference — *Orchestrate SKILL.md step 3 no longer contains the inline install table (lines with pyproject.toml, requirements.txt, package-lock.json, etc.) or the symlink fallback prose. Replaced with a one-line summary ('Bootstrap dependencies in the phase worktree') plus **See:** skills/design/dependency-bootstrap.md. Net word reduction of ~150 words. Total SKILL.md word count stays under 1000.*
- [x] A4: Bump version in marketplace.json — *All three plugin versions in marketplace.json bumped to 1.9.7 (from 1.9.6). Single consistent version across all three plugins.*
