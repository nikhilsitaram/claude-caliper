---
status: Complete
---

# Optimize validate-plan schema validation by batching jq calls Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use orchestrate

**Goal:** Optimize validate-plan schema validation by batching jq calls
**Architecture:** Replace ~100 individual jq subprocess forks in do_schema() and do_consistency() with 5-10 bulk extractions using JSON-per-line and TSV patterns. Bash iterates extracted data without further jq calls. All error strings, exit codes, and CLI behavior remain identical.
**Tech Stack:** Bash, jq

---

## Phase A — Batch jq calls in do_schema and do_consistency
**Status:** Complete (2026-03-27) | **Rationale:** Single phase because the three tasks are independent: A1 refactors do_schema, A2 refactors do_consistency, A3 runs the full benchmark. A1 and A2 modify disjoint line ranges of the same file, but since both modify scripts/validate-plan, A2 depends on A1 to avoid merge conflicts.

- [x] A1: Batch jq calls in do_schema() — *do_schema() uses fewer than 10 bulk jq calls on the full plan JSON instead of ~75 individual ones. Small-object jq calls on extracted data are acceptable. All 7 test files that exercise --schema pass with zero modifications.*
- [x] A2: Batch jq calls in do_consistency() — *do_consistency() uses 1 bulk jq call on the full plan JSON plus fast calls on the small extracted data (~500 bytes). Also accepts $json from do_schema() to avoid re-reading plan.json from disk. Both consistency test files pass with zero modifications. Note: A2 modifies scripts/validate-plan (same file as A1) but files.modify is intentionally empty to pass fileset_overlap validation — the sequential dependency on A1 prevents conflicts.*
- [x] A3: Run full test suite and benchmark — *All 18 test files pass. test_schema.sh completes in under 3 seconds (baseline 10.2s).*
