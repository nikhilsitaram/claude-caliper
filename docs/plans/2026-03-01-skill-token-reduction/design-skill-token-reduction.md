# Skill Token Reduction — Design Doc

## Problem

Every skill SKILL.md is 2-4x over the word count targets in writing-skills guidance:

| Target | Guidance | Actual Range |
|--------|----------|-------------|
| Frequently-loaded (using-superpowers) | <200 words | 621 words (3.1x) |
| Other skills | <500 words | 366–1803 words |

Only 1 of 16 skills (requesting-code-review at 366 words) meets the <500 target. The 15 others collectively burn ~16,800 excess words of context per full skill load.

**Why it matters:** Skills are injected into context. Every excess word displaces working memory the agent could use for the actual task. The most-loaded skills (using-superpowers, brainstorming, TDD) impose the highest tax because they fire on nearly every conversation.

## Current State

| Skill | Words | Target | Over By |
|-------|------:|-------:|--------:|
| subagent-driven-development | 1803 | 500 | 1303 |
| test-driven-development | 1655 | 500 | 1155 |
| systematic-debugging | 1504 | 500 | 1004 |
| writing-plans | 1494 | 500 | 994 |
| brainstorming | 1120 | 500 | 620 |
| implementation-review | 976 | 500 | 476 |
| dispatching-parallel-agents | 975 | 500 | 475 |
| receiving-code-review | 929 | 500 | 429 |
| using-git-worktrees | 782 | 500 | 282 |
| finishing-a-development-branch | 675 | 500 | 175 |
| verification-before-completion | 668 | 500 | 168 |
| plan-review | 667 | 500 | 167 |
| using-superpowers | 621 | 200 | 421 |
| requesting-code-review | 366 | 500 | -134 (OK) |

## Reduction Techniques

The writing-skills guidance prescribes four techniques. Here's how they map to each skill:

### Technique 1: Move details to supporting files

Content that the agent only needs when actively performing a subtask (not when deciding whether/how to follow the skill) can move to a supporting `.md` file in the skill directory. The SKILL.md keeps a one-line reference.

**Candidates:**
- **subagent-driven-development** — The example workflow (lines 98-187, ~400 words) is reference material. Move to `example-workflow.md`.
- **systematic-debugging** — The multi-component evidence gathering example (lines 76-108, ~150 words) and "your human partner's Signals" section (lines 234-244, ~80 words) could move to supporting file.
- **test-driven-development** — The "Why Order Matters" section (lines 206-254, ~300 words) is persuasion material agents don't need once compliant. The rationalization table (lines 256-270) covers the same ground. Keep the table, move the prose to a supporting file.
- **writing-plans** — The full task structure template (lines 84-131, ~250 words) and .tasks.json example (lines 207-233, ~150 words) are reference material. Move to `task-template.md`.
- **dispatching-parallel-agents** — The "Real Example from Session" (lines 131-156, ~150 words) duplicates the pattern already shown above it. Remove or move to supporting file.

### Technique 2: Compress examples

Replace verbose multi-line examples with minimal ones. One good example, not three.

**Candidates:**
- **receiving-code-review** — Four "Real Examples" (lines 177-201, ~120 words) when one would suffice.
- **brainstorming** — The "Challenging Product Assumptions" example (lines 66-82, ~100 words) could be compressed to 2-3 lines.
- **using-git-worktrees** — Creation Steps section (lines 77-99, ~130 words) repeats what the bash examples already show.

### Technique 3: Eliminate redundancy

Content duplicated across skills or restating what's obvious from the skill name/structure.

**Candidates:**
- **implementation-review** — Integration Test Verification section (lines 46-65, ~150 words) restates what subagent-driven-development already describes. Compress to "Verify Task 0 tests pass, spot-check Level 2 boundary tests, fill gaps."
- **brainstorming** — Native Task Integration section (lines 126-133, ~80 words) restates generic TaskCreate/TaskUpdate usage that any skill can figure out.
- **finishing-a-development-branch** — Common Mistakes section (lines 162-178, ~100 words) restates the Red Flags section immediately below it.

### Technique 4: Cross-reference instead of repeat

Use `**REQUIRED SUB-SKILL:** Use superpowers:X` pattern to point agents at other skills rather than embedding their content.

**Already done well by:** plan-review, implementation-review, finishing-a-development-branch.

**Needs improvement:**
- **subagent-driven-development** — Embeds deviation rules and plan doc update instructions that could move to a supporting file.

## Approach

### Tier 1: High-frequency skills (do first)

These load in nearly every conversation. Target: get each under 400 words.

| Skill | Current | Reduction Strategy | Target |
|-------|--------:|--------------------|---------:|
| using-superpowers | 621 | Remove Red Flags table rows (agent has internalized after months of use); compress Skill Types section | <300 |
| brainstorming | 1120 | Move product assumptions example to supporting file; compress Native Task Integration to 1 line; compress Process section | <450 |
| test-driven-development | 1655 | Move "Why Order Matters" prose to supporting file (keep rationalization table); compress Good/Bad examples | <500 |

### Tier 2: Execution pipeline skills (do second)

These load during plan execution. Target: get each under 500 words.

| Skill | Current | Reduction Strategy | Target |
|-------|--------:|--------------------|---------:|
| subagent-driven-development | 1803 | Move example workflow to supporting file; move deviation rules + plan doc updates to supporting files | <500 |
| writing-plans | 1494 | Move task template + .tasks.json example to supporting files; compress header template | <500 |
| systematic-debugging | 1504 | Move multi-component example to supporting file; compress Phase 2-4 (keep Phase 1 detailed) | <500 |

### Tier 3: Review/finishing skills (do last)

These load less frequently. Target: get each under 500 words.

| Skill | Current | Reduction Strategy | Target |
|-------|--------:|--------------------|---------:|
| implementation-review | 976 | Compress integration test verification to 3 lines; tighten "What It Catches" table | <500 |
| dispatching-parallel-agents | 975 | Remove session example (redundant); compress Agent Prompt Structure | <500 |
| receiving-code-review | 929 | Remove 3 of 4 real examples; compress Source-Specific Handling | <500 |
| using-git-worktrees | 782 | Compress Creation Steps (bash speaks for itself); remove Example Workflow | <500 |
| plan-review | 667 | Compress "What It Catches" table (10 rows is excessive) | <500 |
| finishing-a-development-branch | 675 | Merge Common Mistakes into Red Flags; compress option details | <500 |
| verification-before-completion | 668 | Compress Key Patterns section | <500 |

### Supporting files

Move heavy reference content from subagent-driven-development to supporting files in its directory:

1. **`skills/subagent-driven-development/deviation-rules.md`** — the deviation rules table + scope boundary + fix attempt limit + documentation requirement.

2. **`skills/subagent-driven-development/plan-doc-updates.md`** — the plan document lifecycle update instructions.

## Constraints

- **No behavioral changes.** The reduced skills must produce identical agent behavior. This is a content-only refactor.
- **TDD applies.** Per writing-skills Iron Law, each skill edit needs testing. For token reduction specifically: verify the agent still follows the skill correctly with less text. Lightweight pressure test per tier.
- **One tier at a time.** Complete and verify one tier before starting the next.
- **Preserve discipline content.** Rationalization tables, Red Flags lists, and Iron Laws are the highest-value content per word. These get compressed last (or not at all).

## Success Criteria

- All 15 over-target skills under 500 words (using-superpowers under 300)
- No skill behavioral regressions in pressure tests
- Shared supporting files eliminate cross-skill duplication
- Total context budget across all skills reduced by ~50%

## Open Questions

1. **Is the <500 word target realistic for discipline skills (TDD, systematic-debugging)?** These are long because they need rationalization tables + Red Flags + examples. Might need to relax to <600 for the most discipline-heavy skills.
2. **Should `_shared/` be the convention for cross-skill supporting files?** Alternative: always put shared content in the "primary" skill's directory and cross-reference. `_shared/` is cleaner but adds a new convention.
3. **Is using-superpowers's Red Flags table still earning its context cost?** It was written when skills were new. After months of use, the agent may have internalized the patterns. Could be moved to a supporting file loaded only when violations are detected.
