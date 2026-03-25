---
status: In Development
---

# Add pipeline enforcement gates to validate-plan Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use orchestrate

**Goal:** Add pipeline enforcement gates to validate-plan
**Architecture:** Three new validate-plan modes (--consistency, --check-entry, --check-base) plus an integration_branch schema field. Consistency rules move from --schema to a dedicated function that --schema chains to. Entry gates check reviews.json for prerequisite reviews before work begins. Base-branch checks prevent dispatch from the wrong worktree. Skill docs updated to call the new gates at startup.
**Tech Stack:** Bash, jq, git

---

## Phase A — Pipeline Gates
**Status:** Not Started | **Rationale:** Single phase — all changes target one script with test and doc tasks radiating from it. No dependency layers between the three gate features.

- [ ] A1: Implement all validate-plan script changes — *do_consistency() function exists with all 6 rules, do_check_entry() and do_check_base() implemented, --consistency/--check-entry/--check-base CLI flags wired, integration_branch validated in do_schema(), --schema chains to do_consistency(), all existing tests pass*
- [ ] A2: Write consistency mode tests — *All 6 consistency rules tested (positive and negative cases), all tests pass*
- [ ] A3: Write check-entry mode tests — *Both stages tested (draft-plan and execution), missing/present review combinations covered, plan.json-not-required case for draft-plan stage tested, all tests pass*
- [ ] A4: Write check-base mode tests — *Integration branch match/mismatch tested, main/master rejection for single-phase tested, missing integration_branch fallback tested, all tests pass*
- [ ] A5: Update orchestrate skill docs with gate calls — *Orchestrate SKILL.md setup section includes --check-entry, --check-base, --consistency calls. Per-phase section re-runs --check-base (multi-phase) and --consistency after status updates. Dispatch docs note that --check-base runs at startup and before each phase.*
- [ ] A6: Update draft-plan skill doc with entry gate — *draft-plan SKILL.md workflow section includes --check-entry call at startup (step between Initialize and Explore)*
- [ ] A7: Update design skill doc to write integration_branch — *Design SKILL.md worktree setup step writes integration_branch to plan.json for multi-phase plans*
- [ ] A8: Bump plugin version — *All three plugin versions bumped from 1.17.0 to 1.18.0*
