# codebase-review

Whole-repo code quality audit. Catches DRY violations, dead code, over-abstraction, and naming drift that per-task reviews miss because they only see one branch at a time.

**Not for:** Branch reviews (use `implementation-review`), diff-only review (use `/simplify`).

## When to use

- Periodic audits (monthly, quarterly) to catch accumulated debt
- Before a major refactoring to know where the real problems are
- After a long development phase when code quality may have drifted

## Modes

Two execution modes:

- **Single agent** — one reviewer per top-level directory + cross-scope reconciliation. Faster and cheaper. Good for targeted audits when you already know which area is suspect.
- **Team** — three independent full-codebase reviewers + peer cross-verification + lead synthesis with confidence tiers. Roughly 3x the token cost of single mode, but parallelism keeps wall-clock similar. Surfaces findings any single reviewer would miss.

| | Single | Team |
|---|---|---|
| Reviewer count | 1 per directory | 3 (full repo each) |
| Token cost | ~1x | ~3x |
| Wall-clock | Parallel per directory | Parallel across 3 reviewers + Phase 2 cross-verification |
| Confidence tiers | None | `[VERIFIED 3/3]`, `[MAJORITY 2/3]`, `[CONFIRMED]`, `[SOLO]`, `[DISPUTED]` |
| When to use | Targeted audits, suspected area known | High-confidence audits where missing a Critical finding is expensive |
| Env-var required | None | `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` |

### Selecting a mode

- Run `/codebase-review` with no flag — the skill asks which mode to use.
- Run `/codebase-review --mode=single` or `/codebase-review --mode=team` to pick directly without being prompted.
- Run `/codebase-review path/to/dir --mode=team` to scope team mode to a subdirectory.

Team mode without `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` set in the environment downgrades to single mode with a one-line warning (the run proceeds — no error).

## How it works

```text
Phase 1: Resolve scope → discover review units (top-level directories)
         |
         v
Phase 2: Parallel scope reviews (one claude-caliper:codebase-auditor subagent per directory)
         |
         v
Phase 3: Cross-scope reconciliation (one claude-caliper:codebase-auditor subagent, sees all findings)
         |
         v
Phase 4: Aggregate + route (write report, create issues, or hand off to draft-plan)
```

### Team mode flow

```text
Mode detection → Init (artifact dir, team name) → TeamCreate
         |
         v
Phase 1: 3 parallel reviewers (full repo each) → write reviewer_N.md → idle
         |
         v
Phase 2: Lead DMs phase2_start → each reviewer reads 2 peer files,
         re-verifies, disputes peer-to-peer, writes crosscheck_N.md → idle
         |
         v
Lead synthesis: read 6 files + escalations.md, apply aggregation rule,
         write master doc with Mode: team header and Tier column
         |
         v
Shutdown handshake → TeamDelete → Phase 4 (shared with single mode)
```

Same Phase 4 routing as single mode — both modes converge on the master doc at `docs/reviews/YYYY-MM-DD-codebase-review.md`.

### Phase 1 — Resolve Scope

Determines the review boundary: either a path argument or the git root. Discovers review units by listing top-level directories (excluding `.*`, `node_modules`, `vendor`, `__pycache__`).

### Phase 2 — Parallel Scope Reviews

One `claude-caliper:codebase-auditor` subagent dispatch per review unit, using `agents/reviewer.md` as the prompt body, all dispatched in parallel. Each reads every file in its directory and reports findings across 5 categories with severity and fix complexity classifications.

### Phase 3 — Cross-Scope Reconciliation

A single `claude-caliper:codebase-auditor` dispatch using `agents/cross-scope-reviewer.md` as the prompt body reads all Phase 2 findings plus the full file manifest. It looks for issues that individual reviewers couldn't detect from within a single directory: cross-module duplication, naming drift between directories, and inconsistent patterns across module boundaries. It also deduplicates findings flagged independently by multiple reviewers.

### Phase 4 — Aggregate & Route

Merges all findings, deduplicates, and ranks by severity. Writes a report to `docs/reviews/YYYY-MM-DD-codebase-review.md`. Groups findings by overlapping file sets — findings that touch the same files are handled together.

Routes by **fix complexity** (not severity):

- **Inline fixes** — automatically invokes `draft-plan` on the grouped findings, then `plan-review`, then proceeds to execution. No user prompt.
- **Complex fixes** — `AskUserQuestion`: create GitHub issues (one per group) or write plans now. User chooses.

A Critical one-liner goes inline; a Medium refactoring across 10 files gets an issue or plan.

## Review categories

| Category | What it catches |
|----------|----------------|
| **DRY** | Duplicated code blocks, repeated constants, copy-pasted logic |
| **YAGNI** | Unused exports, dead code paths, speculative features |
| **Simplicity & Efficiency** | Over-abstraction, unnecessary indirection, redundant operations |
| **Refactoring Opportunities** | SRP violations, God objects, deep nesting, long parameter lists |
| **Consistency** | Naming drift, inconsistent error handling, style divergence |

Cross-scope reviewers additionally check: Cross-Directory DRY, Cross-Directory Naming, and Cross-Directory Pattern Divergence.

## Severity levels

| Level | Meaning |
|-------|---------|
| **Critical** | Active bug risk or severe performance issue |
| **High** | Significant maintenance burden or correctness risk |
| **Medium** | Code smell that makes the codebase harder to work with |
| **Low** | Minor style/convention issue |

## Output report structure

```text
# Codebase Review — YYYY-MM-DD
Scope: [path] | Review units: [list]
Summary: X findings (N Critical, N High, N Medium, N Low) | Y deferred → GH issues | Z inline → implementation

## Findings by Severity
| # | Category | Severity | File(s) | Description | Fix Complexity |

## Deferred Work
| # | Finding | Rationale | GitHub Issue # |
```

## Files reference

| File | Purpose |
|------|---------|
| `SKILL.md` | Skill trigger and execution instructions |
| `agents/codebase-auditor.md` (plugin root) | Plugin-root agent definition for `claude-caliper:codebase-auditor` — centralizes review categories, severity, output format, and quality bar |
| `skills/codebase-review/agents/cross-scope-reviewer.md` | Cross-directory reconciliation dispatch prompt (single mode Phase 3) |
| `skills/codebase-review/agents/reviewer.md` | Per-directory scope dispatch prompt (single mode Phase 2) |
| `skills/codebase-review/agents/team-reviewer.md` | Team-mode dispatch prompt — Phase 1 + Phase 2 + dispute protocol |
