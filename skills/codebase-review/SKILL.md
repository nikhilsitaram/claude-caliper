---
name: codebase-review
description: Use when asked to audit a codebase, find DRY/YAGNI/complexity issues repo-wide, or perform periodic code quality review
---

# Codebase Review

Periodic whole-repo audits catch issues that per-task reviews miss — cross-module duplication, accumulated complexity, and naming drift.

**Not for:** Branch reviews (use `implementation-review`), diff-only review (use `/simplify`).

## Invocation

- `/codebase-review` — review entire repo
- `/codebase-review path/to/dir` — review specified directory only

## Mode Detection

Two modes exist: `single` (per-directory parallel review + cross-scope reconciliation) and `team` (3 parallel full-codebase reviewers + peer cross-verification + lead synthesis with confidence tiers). Parse the user's slash-command arguments into structured tokens before invoking the helper — do NOT interpolate raw user input into the shell command, which would be a command-injection risk for inputs containing `;`, `&&`, `|`, or backticks. Procedure:

1. Identify the optional positional path argument and the optional `--mode=<value>` flag in the user's invocation.
2. Reject any `--mode` value other than `single` or `team` before invoking the helper (the helper also rejects, but early rejection keeps the shell call clean).
3. Invoke the helper with each parsed token wrapped in single quotes. Bash single quotes preserve literal characters with no expansion. If a token contains a literal single quote, escape it as `'\''` within its single-quoted wrapper.

Examples: `/codebase-review` → `./skills/codebase-review/mode-detect.sh`; `/codebase-review --mode=team` → `./skills/codebase-review/mode-detect.sh '--mode=team'`; `/codebase-review path/to/dir --mode=single` → `./skills/codebase-review/mode-detect.sh 'path/to/dir' '--mode=single'`.

Parse stdout — each line is `KEY=value`:

- `MODE=single` or `MODE=team` — resolved mode; carry forward to the branch step.
- `MODE=__ASK__` — no `--mode` was provided. Invoke `AskUserQuestion` with header `Mode` and body `Single agent or team review?`. Options:
  - **Single agent** — `One reviewer per top-level directory + cross-scope reconciliation. Faster and cheaper. Good for targeted audits where you already know which area is suspect.`
  - **Team (3-reviewer cross-verification)** — `Three independent full-codebase reviewers + peer cross-verification + lead synthesis with confidence tiers. ~3x token cost vs single, similar wall-clock. Surfaces findings any single reviewer would miss. Requires CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 (downgrades to single if not set).`

  Neither option is marked Recommended. Substitute the user's choice for `MODE` and continue.
- `SCOPE_PATH=<value>` — carry forward as the scope for Phase 1 (the helper resolves to an absolute path when one exists on disk, so team-mode reviewers in their own worktrees can read the same scope).

If the helper exit code is non-zero, the user passed an invalid `--mode` value: surface the helper's stderr (which names the valid values) and stop.

If the helper writes anything to stderr with exit code 0, that's the env-var downgrade warning (team-mode requested but `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` is unset); surface it to the user verbatim and proceed with the helper-emitted `MODE` (which will be `single`).

Branch on `MODE` for the remainder of Phases 1-3. Phase 4 is mode-agnostic.

## Single Mode (Phases 1-3)

### Phase 1 — Resolve Scope

1. Determine scope: path argument or `git rev-parse --show-toplevel`
2. Discover review units (top-level directories, excluding `.*`, `node_modules`, `vendor`, `__pycache__`)
3. Create one task per review unit via `TaskCreate`

### Phase 2 — Parallel Scope Reviews

Dispatch one **`claude-caliper:codebase-auditor`** subagent per review unit using `agents/reviewer.md` as the prompt body:
- `{SCOPE_PATH}` = directory to review

All subagents run in parallel. Each returns structured findings with category, severity, fix complexity.

### Phase 3 — Cross-Scope Reconciliation

After Phase 2 completes, dispatch one **`claude-caliper:codebase-auditor`** subagent using `agents/cross-scope-reviewer.md` as the prompt body:
- `{ALL_FINDINGS}` = concatenated Phase 2 findings
- `{FILE_MANIFEST}` = all files in repo
- `{SCOPE_PATH}` = root scope

This pass catches cross-directory DRY violations and naming drift that per-scope reviewers can't see.

## Team Mode (Phases 1-2 + lead synthesis)

Runs 3 independent full-codebase Opus reviewers in parallel, a peer cross-verification round, and lead synthesis. Built on the agent-teams substrate documented in `skills/codebase-review/agent-teams-substrate.md` (TeamCreate, named teammates, SendMessage mailbox, idle notifications).

### Init

Compute these absolute paths and create the artifact directory:

```bash
MAIN_ROOT="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')"
if [ -z "$MAIN_ROOT" ]; then
  echo "ERROR: codebase-review team mode must be run inside a git repository (MAIN_ROOT could not be resolved)." >&2
  exit 1
fi
REVIEW_ID="$(date -u +%Y%m%d-%H%M%S)"
ARTIFACT_DIR="$MAIN_ROOT/.claude/claude-caliper/codebase-review/$REVIEW_ID"
TEAM_NAME="cbr-$REVIEW_ID"
ESCALATION_FILE="$ARTIFACT_DIR/escalations.md"
mkdir -p "$ARTIFACT_DIR" "$MAIN_ROOT/docs/reviews"
```

`MAIN_ROOT` uses `--git-common-dir` because in a worktree, `--show-toplevel` returns the worktree, not the main repo. Artifacts must live in the main repo root so they survive worktree cleanup (per project `CLAUDE.md`).

### TeamCreate

Call `TeamCreate({team_name: "<value of $TEAM_NAME>"})` exactly once before spawning any teammates.

### Phase 1 spawn (parallel, single message)

Spawn all 3 reviewer teammates in a single message via three `Agent(...)` calls in the same turn:

```text
Agent({
  team_name: "<TEAM_NAME>",
  name: "cbr-rev-1",
  subagent_type: "claude-caliper:codebase-auditor",
  model: "opus",
  mode: "auto",
  description: "Team-mode reviewer 1 of 3",
  prompt: <contents of skills/codebase-review/agents/team-reviewer.md, with parameters
           REVIEWER_NUMBER=1, ARTIFACT_DIR=<value>, SCOPE_PATH=<value>,
           ESCALATION_FILE=<value>>
})
```

Repeat with `name: "cbr-rev-2"` / `REVIEWER_NUMBER=2` and `name: "cbr-rev-3"` / `REVIEWER_NUMBER=3`. All three in the same turn.

### Wait for Phase 1 completion

Wait for idle notifications (push-based, no polling). Track which reviewers are idle. While waiting, emit a non-blocking heartbeat to the chat every ~5 minutes:

```text
Phase 1 in progress: <N>/3 reviewers idle, <N>/3 artifact files present (waiting on: <list of teammate names>)
```

A medium repo (~100 files) on Opus typically completes in 5-15 minutes; consider asking the user to interrupt after ~30 minutes with no progress. The agent-teams runtime does not expose programmatic timers, so there is no hard wall-clock abort.

When all 3 are idle, check each artifact file:

- Failure signal A: reviewer is idle but `$ARTIFACT_DIR/reviewer_N.md` does not exist. A reviewer that fanned out to `Explore` subagents can look idle while its file is still pending, so idle-with-no-file is ambiguous. **Send one prose nudge DM** ("you appear idle but reviewer_N.md isn't written — finish and write it") and wait for it to go idle again. Only if the file is still absent after the nudge is it a real Phase 1 failure.
- Failure signal B: file exists but its first non-blank line begins with `ERROR:`.
- A literal `No findings.` file is NOT a failure — it is a valid empty result per the agent's quality bar.

Apply the degraded-run policy:

- 0 failures: proceed to Phase 2 trigger with all 3 reviewers.
- Exactly 1 failure: proceed to Phase 2 trigger with the 2 survivors; the master doc header will be annotated `Mode: team (degraded, 2/3)`.
- 2 or more failures: abort. Send `shutdown_request` to all 3 teammates (including any that succeeded), wait for each idle confirmation, call `TeamDelete()`, print a one-line failure summary and the exact re-run command (`/codebase-review --mode=team` plus any original scope path) to stdout, and stop. No `AskUserQuestion` — the user can re-invoke when ready.

### Phase 2 trigger

For each surviving reviewer N, send a **prose** message naming the OTHER two survivors' `reviewer_M.md` absolute paths as its peer files, e.g. `SendMessage({to: "cbr-rev-2", message: "Start Phase 2. Peer files: $ARTIFACT_DIR/reviewer_1.md and $ARTIFACT_DIR/reviewer_3.md"})`. Must be prose, not a structured object — the mailbox validator accepts only the shutdown/plan-approval protocol objects, and a bare JSON string is auto-parsed into an object and rejected too.

### Wait for Phase 2 completion

Same idle + file-existence + ERROR check as Phase 1, but on `$ARTIFACT_DIR/crosscheck_N.md`. Same heartbeat cadence. Same degraded-run thresholds: 1 failure proceeds with survivors; 2+ aborts via the shutdown/TeamDelete sequence above.

### Lead synthesis

Read all surviving `reviewer_N.md` and `crosscheck_N.md` files, plus `$ESCALATION_FILE` if it exists. Apply the aggregation rule:

| Final tier | Aggregation rule (3-of-3) |
|---|---|
| `[VERIFIED 3/3]` | Raised in Phase 1 by all 3 reviewers AND no reviewer marks it SOLO in their own crosscheck |
| `[MAJORITY 2/3]` | Raised by exactly 2 reviewers AND the third's crosscheck marks it MAJORITY-AGREE AND no originator downgrades to SOLO |
| `[CONFIRMED]` | Raised by exactly 1 reviewer AND >=1 peer marks MAJORITY-AGREE AND originator does not downgrade |
| `[SOLO]` | Raised by exactly 1 reviewer AND no peer marks MAJORITY-AGREE AND no peer marks MAJORITY-DISAGREE |
| `[DISPUTED]` | (a) 1 raised + >=1 peer MAJORITY-DISAGREE, OR (b) 2 raised + 3rd MAJORITY-DISAGREE, OR (c) 3 raised + any reviewer downgrades own mark to SOLO. Lead reads cited code and either resolves to a definite tier OR keeps `[DISPUTED]` with both views in *Lead Notes* |

Degraded 2-of-2 aggregation:

- `[VERIFIED 2/2]` — both survivors raised it AND neither downgrades own mark AND no MAJORITY-DISAGREE. If a survivor downgrades, treat as `[DISPUTED]`.
- `[MAJORITY 2/3]` no longer applies.
- A finding raised by only one survivor: `[CONFIRMED]` if the other agrees on re-read, else `[SOLO]`.
- `[DISPUTED]` covers downgrade-by-originator and MAJORITY-DISAGREE-by-peer cases.

Process escalations from `$ESCALATION_FILE`: read cited code, decide keep/drop, note the decision in the master doc *Lead Notes* section.

Write the master doc to `docs/reviews/YYYY-MM-DD-codebase-review.md` (UTC date) with this schema:

```text
# Codebase Review — YYYY-MM-DD
Mode: team [(degraded, 2/3)]
Scope: <path> | Review units: <list>
Summary: X findings (N Critical, N High, N Medium) | Y deferred → GH issues | Z inline → implementation

## Findings by Severity
| # | Tier | Category | Severity | File(s) | Description | Fix Complexity |

## Lead Notes
(omit this section entirely if no escalations and no [DISPUTED] resolutions occurred)

## Deferred Work
| # | Finding | Rationale | GitHub Issue # |
```

Sort findings by severity (Critical → Medium) with Tier as the secondary sort key (`[VERIFIED 3/3]` first within each severity). Omit zero-row tiers from the table entirely. The summary line is severity-only — tier counts are inferable from the table.

### Shutdown handshake

Send `SendMessage({to: "cbr-rev-N", message: {type: "shutdown_request"}})` to each of the 3 teammates. Wait for each teammate's idle notification confirming shutdown. Then call `TeamDelete()`. Teammates must fully terminate before team deletion (matches the `skills/codebase-review/agent-teams-substrate.md` substrate requirement).

### Artifact retention

`$ARTIFACT_DIR` is retained after synthesis — useful for debugging tier disputes and `[DISPUTED]` resolutions. No automated cleanup; manual `rm -rf .claude/claude-caliper/codebase-review/` is acceptable if it grows large.

## Phase 4 — Aggregate & Route

1. Acquire findings, deduplicate, and rank by severity (Tier is informational and does not affect ranking):
   - **Single mode:** collect findings from Phase 2's per-directory subagent returns and Phase 3's cross-scope reconciliation result.
   - **Team mode:** the master doc at `docs/reviews/YYYY-MM-DD-codebase-review.md` was already written during lead synthesis above; read the `Findings by Severity` table from it.
2. Write report to `docs/reviews/YYYY-MM-DD-codebase-review.md` (single mode only — team mode already wrote it during lead synthesis).
3. Group findings by overlapping file sets — findings that touch the same files belong in the same plan or issue
4. Route by fix complexity:

**Inline fixes** (1–5 line changes, no design decision — implement directly, no user prompt): the findings table *is* the plan — each row has an exact `file:line`, the problem, and a fix direction, cross-verified in Phase 2, already in your context. Skip `draft-plan`/`plan-review` (they'd re-derive that context at token cost); implement the grouped findings in a worktree and run the diff through the normal gates (`/code-review`, tests). Promote a finding to the complex path if opening the code reveals a design decision.

**Complex fixes** (multi-file refactors, or any fix needing a design decision — AskUserQuestion, pick one):
- **Create GitHub issues** — one issue per logical group → `gh issue create`
- **Write plans now** — `draft-plan` per group, then `plan-review`. A codebase-review-initiated plan has no design-review, so `draft-plan`'s entry gate fails unless you first write a `reviews.json` array with a design-review skip record: `[{"type":"design-review","scope":"design","verdict":"skip","reason":"codebase-review-initiated"}]` (the gate selects on both `type` and `scope`; a `skip` verdict needs a non-empty `reason`).

Route by fix COMPLEXITY, not severity: a Critical one-liner goes inline; a Medium 10-file refactor gets an issue/plan.

## Report Structure

Single mode uses the team-mode master-doc schema above, minus the `Tier` column and `Lead Notes` section, plus `N Low` in the summary counts.

## Categories

The five categories (DRY, YAGNI, Simplicity & Efficiency, Refactoring Opportunities, Consistency), their full definitions, the severity rubric, and the output Finding template live in the `claude-caliper:codebase-auditor` agent's system prompt — that agent is dispatched in both modes.
