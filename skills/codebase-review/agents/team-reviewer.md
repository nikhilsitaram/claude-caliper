# Team-Reviewer Dispatch (team mode, both phases)

Dispatch body for the `claude-caliper:codebase-auditor` agent in team-mode Phases 1 and 2. The agent definition supplies the 5 review categories, severity definitions, output Finding template, quality bar, and hard rules — this file holds only team-mode specifics (phase instructions, mailbox protocol, dispute ordering, ERROR convention).

Each of the 3 named teammates (`cbr-rev-1`, `cbr-rev-2`, `cbr-rev-3`) reads this same prompt and persists across both phases.

## Inputs

- **SCOPE_PATH** — absolute path to the directory being reviewed
- **REVIEWER_NUMBER** — your reviewer index: `1`, `2`, or `3`
- **ARTIFACT_DIR** — absolute path to the per-run artifact directory (`$MAIN_ROOT/.claude/claude-caliper/codebase-review/$REVIEW_ID/`)
- **ESCALATION_FILE** — absolute path: `$ARTIFACT_DIR/escalations.md` (you append to this only if you need lead arbitration)

## Phase 1 — Independent Full-Codebase Review

1. Read the full scope at `SCOPE_PATH` top-down. For a scope small enough to hold in your own context, read every file directly. For a larger scope, fan out context-gathering to **`Explore` subagents on the `haiku` model** (`Agent({subagent_type: "Explore", model: "haiku", ...})`) — they read excerpts and return conclusions, which is what you need to locate issues. **Do NOT dispatch inherited/default-model general-purpose subagents for exploration:** they in turn spawn their own subagents and token usage spirals recursively. The independent judgment that makes team mode valuable is *yours* — what you flag from the gathered context — not the reading itself, so cheap haiku readers cost you nothing in review quality.
2. Apply the 5 categories and severity definitions from your system prompt.
3. Mark **Critical / High / Medium only** — team mode drops Low findings (override of the agent's default severity set).
4. Use the Finding output format from your system prompt for each finding. Cite `file:line` for every one.
5. Write your findings to `$ARTIFACT_DIR/reviewer_$REVIEWER_NUMBER.md`. If you have nothing that meets the bar, write the literal line `No findings.` as the entire file contents (the agent's quality bar — do not invent findings).
6. **Only after `reviewer_$REVIEWER_NUMBER.md` is written**, go idle. If you dispatched `Explore` subagents, wait for them to return and finish your findings first — do not go idle while children are still running. **Do NOT send a completion DM.** File existence plus your idle notification is the lead's signal that Phase 1 is done for you; going idle with children still working makes that signal ambiguous.

**If you cannot proceed** (e.g., `SCOPE_PATH` inaccessible, `ARTIFACT_DIR` not writable), write `ERROR: <one-line reason>` as the first non-blank line of `$ARTIFACT_DIR/reviewer_$REVIEWER_NUMBER.md` and go idle. The lead treats this as a Phase 1 failure per the degraded-run rules.

## Phase 2 — Peer Cross-Verification

You wake from idle when the lead DMs you a **prose** Phase 2 start message naming the two peer files — the absolute paths of the other reviewers' Phase 1 artifacts. (The message is prose, not a structured object: the mailbox validator only accepts the shutdown/plan-approval protocol objects, and a bare JSON string gets auto-parsed into an object and rejected too — so the lead sends this instruction as plain text.) Follow this strict ordering to avoid races:

1. **Read both peer files** at the two absolute paths from the Phase 2 start message.
2. **Re-verify each peer finding against the code.** Open the cited files and check whether the finding holds.
3. **Send disputes** (if any) directly to the originating peer via peer-to-peer DM. The originator is identified by their reviewer number, which appears in the filename (e.g., `reviewer_1.md` was written by `cbr-rev-1`):
    - DM target: `cbr-rev-N` (where N is the originator's reviewer number)
    - Message: `{type: "dispute", finding_id: "<id from peer file>", reasoning: "<one-paragraph rationale>"}`
4. **Process inbound disputes** addressed to you from peers. For each inbound dispute, re-read the cited code; if the dispute is convincing, downgrade your own mark for that finding in your draft crosscheck (e.g., flip `CONFIRMED` to `SOLO`). You CANNOT retract or edit your original Phase 1 file in `$ARTIFACT_DIR/reviewer_$REVIEWER_NUMBER.md` — that file is locked once you went idle for Phase 1.
5. **Write your crosscheck** to `$ARTIFACT_DIR/crosscheck_$REVIEWER_NUMBER.md` with your final marks (see *Marks* below). Cite `file:line` for each mark. **You MUST emit one mark row for EVERY finding** that appears in any of the three reviewer files (yours and both peers') — including peer findings you didn't raise yourself. Omitting a peer finding from your crosscheck causes the lead to silently misclassify it (a missing MAJORITY-AGREE mark looks like a SOLO finding to the aggregator). If you find a peer's finding inapplicable, mark it `MAJORITY-DISAGREE` explicitly rather than omitting.
6. **Go idle.** Once idle, neither reading nor sending disputes is possible — late-arriving disputes are dropped and the lead aggregates from your on-disk crosscheck file.

**If you cannot complete cross-verification** (e.g., peer files unreadable), write `ERROR: <one-line reason>` as the first non-blank line of `$ARTIFACT_DIR/crosscheck_$REVIEWER_NUMBER.md` and go idle. The lead treats this as a Phase 2 failure per the degraded-run rules.

### Marks

Mark each finding from your own perspective:

- **VERIFIED** — you flagged it in Phase 1 AND both peers also flagged it independently in Phase 1
- **CONFIRMED** — you flagged it in Phase 1 AND at least one peer agrees on re-read
- **SOLO** — you flagged it in Phase 1 AND no peer agrees, OR a peer's dispute convinced you to downgrade your own finding
- **MAJORITY-AGREE** — you did NOT flag it in Phase 1 but agree with the peer on re-read
- **MAJORITY-DISAGREE** — you did NOT flag it in Phase 1 AND still disagree on re-read

The lead aggregates these marks across all 3 crosscheck files into the final confidence tiers (`[VERIFIED 3/3]`, `[MAJORITY 2/3]`, `[CONFIRMED]`, `[SOLO]`, `[DISPUTED]`).

### Escalations

If you believe the lead must arbitrate something the dispute-with-peer path cannot resolve (e.g., a finding the user previously dismissed but is recurring, or a substantive disagreement neither side will concede), append a Markdown subsection to `$ESCALATION_FILE` BEFORE going idle. Format:

```text
### Reviewer $REVIEWER_NUMBER escalation: <topic>

<paragraph of detail>

Citation: <file:line>
```

Escalations are rare. Use them only when peer-to-peer dispute cannot resolve.

## Mailbox Protocol

Message types you receive and may send during Phase 2 (the window between the Phase 2 start message arriving and your Phase 2 idle):

| Direction | Type | Payload | When |
|---|---|---|---|
| lead → you | Phase 2 start | **prose** naming the two peer-file absolute paths | Phase 2 start signal |
| peer → you | `dispute` | `{finding_id, reasoning}` | Sent within the dispute window only |
| you → peer | `dispute` | `{finding_id, reasoning}` | Sent within the dispute window only |
| lead → you | `shutdown_request` | `{}` | After lead synthesis; respond by going idle |

The Phase 2 start signal arrives as prose (see Phase 2 intro for why). The `dispute` and `shutdown_request` message types are structured objects. Do not invent message types. Anything else inbound: ignore.
