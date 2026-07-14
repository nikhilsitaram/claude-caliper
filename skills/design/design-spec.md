# Design Doc Reference Specification

## Purpose and Audience

A design doc is the **intent contract** between the user and the plan-drafter. It captures what problem is being solved, why, what success looks like, and how the solution is structured — at a level that lets a fresh agent produce a correct implementation plan with zero conversation context.

A design doc is **not**:
- A plan (no task graphs, verification commands, or step-by-step implementation code)
- Code (no implementation logic — file paths and structural descriptions are fine)
- A requirements list (it includes architectural judgment, alternatives, and scope decisions)

The plan-drafter reads the design doc and nothing else. Every assumption, file reference, and scope boundary must be explicit.

---

## File Convention

```text
$MAIN_ROOT/.claude/claude-caliper/YYYY-MM-DD-<topic>/design-<topic>.md
```

Where `$MAIN_ROOT` is the main repo root (resolved from `git rev-parse --git-common-dir`). Plans live in the main repo so they survive worktree cleanup. Example: `/Users/you/repo/.claude/claude-caliper/2026-04-11-auth-redesign/design-auth-redesign.md`

---

## Required Sections

All 9 sections are required, in this order. No section may be empty.

### 1. `## Problem`

**What to include:** What is broken or missing, who is affected, and what happens if the problem is not solved.

**Constraint:** Must answer "why act now" — not just describe the desired feature. A problem statement that describes the solution instead of the impact will produce a plan-drafter who doesn't understand what they're optimizing for.

**Example anti-pattern:** "We need a caching layer." (describes solution)
**Correct form:** "API response times exceed 2s for 40% of requests during peak load, causing user drop-off. Without caching, adding more instances won't help — the bottleneck is database read latency."

---

### 2. `## Goal`

**What to include:** One sentence. The concrete, measurable objective this design achieves.

**Constraint:** One sentence only. If the goal needs multiple sentences, the scope is too broad — split into phases.

---

### 3. `## Success Criteria`

**What to include:** Behavioral outcomes a human can verify by observing the system. Each criterion is independently checkable.

**Constraints:**
- **Human-verifiable:** A person can confirm yes/no by observing behavior or outcomes (not by reading code or running tests)
- **Implementation-independent:** No references to specific code, tests, tools, or deployment steps ("users can log in" not "the middleware passes" or "jest suite passes")
- **Collectively complete:** If every criterion passes, the Goal is fully met — no gap
- **Individually necessary:** Removing any single criterion would leave a part of the Goal uncovered

**Flag in design review:** "Tests pass" or "the script runs" are implementation-dependent and should be rewritten as the user-visible behavior those tests verify.

---

### 4. `## Architecture`

**What to include:** Components, relationships, and data flow. File paths and code snippets are allowed — they describe structure, not implementation logic. Include enough detail that the plan-drafter knows what to build and how pieces connect.

**Cross-reference rule:** Every file path mentioned here must also appear in `## Implementation Approach` (and vice versa). Inconsistency between these two sections is the most common cause of plan-drafter confusion.

**Constraint:** Every architectural component must trace to a part of the Problem. Components with no problem-driven reason signal scope creep.

---

### 5. `## Test Strategy`

**What to include:** For every cross-module data flow named in `## Architecture` (producer module → consumer module), name a single test that exercises the flow **without mocking at the seam under test**. If the test does not yet exist, name where it will live (file path) and one specific failure mode it would catch that a mock-everything test would not.

**Required form per seam:** producer → consumer → test path → named failure mode. Example: `kv_launcher → kv_fetch → tests/test_kv_integration.py::test_launcher_invokes_real_fetch → "env-var prefix drift between launcher emission and fetch consumption"`.

**Single-module designs:** Write a brief note explaining why no cross-module seam exists (e.g., "single-file change to validate-design — no cross-module data flow").

**Cross-reference rule:** Every test path listed here must also appear in `## Implementation Approach`'s file change table or test impact note. Test Strategy is the contract; Implementation Approach is how the contract gets built.

**Why this matters:** Per-task TDD locks in module boundaries — each implementer's tests mock the next module, and once landed, those mocks are the only thing exercising the seam. Naming the non-mocking test up front prevents the mock-stacking pattern: every test passes against the same mock, while the real boundary stays untested. See gh issue #243 for the original incident.

---

### 6. `## Key Decisions`

**What to include:** The significant trade-off decisions made during design. For each decision: what was chosen, what was gained, what was given up, and what alternatives were considered with their rejection reasons.

**Why this matters:** This section prevents the plan-drafter from re-exploring rejected paths. It also surfaces the reasoning that would otherwise live only in the conversation and be lost after design approval.

**Minimum per decision:**
- What was chosen
- Why (what the choice gains)
- At least one named alternative and why it was rejected

---

### 7. `## Non-Goals`

**What to include:** Explicit boundaries — things that are plausibly in scope given the Problem but are intentionally excluded.

**Constraint:** Each non-goal requires a rationale of at least 10 words explaining why it is excluded. A bare phrase ("No i18n support") leaves agents free to build it anyway. An explained non-goal ("No i18n support — current user base is English-only; adding i18n multiplies translation maintenance indefinitely") signals an active decision.

**Why this matters:** Agents build plausible things. Non-goals prevent the plan-drafter from adding "helpful" features that the user explicitly does not want.

---

### 8. `## Implementation Approach`

**What to include:** How the solution gets built — file paths, change descriptions, test impact, and any migration or operational steps.

**Cross-reference rule:** Every file path here must also appear in `## Architecture` (and vice versa). Gaps mean the architecture section is missing a component or the implementation section has undocumented changes.

**Required sub-elements:**
- **File change table** — list of files created or modified, with one-line descriptions of the change
- **Test impact** — for every behavior change, note what tests are affected or added
- **Migration/operational steps** — if the change touches data, configuration, or deployment, capture what needs to happen beyond the code change

---

### 9. `## Scope Estimate`

**What to include:** How big is this work? Enough information for the user to decide whether to proceed and how to execute it.

**Required elements:**
- Phase count (single phase or multi-phase, with brief rationale)
- Rough task count per phase
- Recommended tier: `Small` (≤~2 files, obvious approach), `Medium` (one coherent change, fits one context, no genuine parallelism — default when in doubt), or `Large` (genuine parallelism, dependency layers, or bulk beyond one sitting)

**Why this matters:** This is the user's primary decision point for scope and how it gets executed before the plan is drafted. It must appear in the design doc — not just in conversation — so the plan-drafter has it as a calibration anchor.

---

## Cross-Reference Rules

These three rules prevent the most common handoff failure:

1. **Architecture ↔ Implementation Approach:** Every file path that appears in `## Architecture` must appear in `## Implementation Approach`, and every file path in `## Implementation Approach` must appear in `## Architecture`. The `validate-design` script enforces this mechanically.

2. **Non-Goals ↔ Success Criteria:** A non-goal must not contradict or exclude something that a success criterion requires. If a success criterion says "users can export to CSV" and a non-goal says "no CSV export," the design is internally inconsistent.

3. **Test Strategy ↔ Implementation Approach:** Every test path named in `## Test Strategy` must appear in `## Implementation Approach`'s file change table or test impact note. A seam declared in Test Strategy without a corresponding test artifact in Implementation Approach means the contract has nowhere to land. The `validate-design` script enforces this mechanically.

---

## Design vs Plan Boundary

| Belongs in Design | Belongs in Plan |
|---|---|
| Problem statement and who is affected | Task graph with dependencies |
| Goal and success criteria | Exact verification commands |
| Architectural components and relationships | Step-by-step implementation instructions |
| File paths (describing "what changes") | File paths (describing "how to change them") |
| Trade-off decisions and alternatives rejected | Code snippets that implement the change |
| Non-goals and scope boundaries | Test fixture content |
| Scope estimate and phase rationale | Per-task status tracking |
| Tier recommendation | Completion notes format |

File paths and structural code snippets can appear in both — the design describes **what** changes and **why**, the plan describes **how** to change it.

---

## Writing Guidance

**Length:** Design docs longer than 3,000 words are usually carrying plan-level detail that should be removed, or architecture prose that should be moved to a table.

**Use explicit structure over prose.** The plan-drafter reads literally. Headers, bullet points, and tables are parsed more reliably than paragraphs. Avoid "as mentioned above" — the plan-drafter may not have that context anchored.

**Alternatives-considered is the highest-value section** for downstream agents. A plan-drafter who doesn't see the rejected alternatives may independently re-explore them, wasting tokens and time. Every significant decision in `## Key Decisions` should name at least one alternative and the rejection reason.

**Non-goals prevent scope creep more reliably than any other section.** Agents fill gaps by building plausible features. An explicit non-goal with rationale is an active constraint; its absence is an implicit invitation.

**Success criteria calibration:** Write each criterion as a sentence starting with "A user can..." or "The system..." and test it against: "Can a person verify this without reading code?" If the answer is no, rewrite it.

**Architecture prose should describe structure, not mechanism.** "The validator reads the design doc, extracts H2 headings with grep, and returns a list of missing sections" is plan-level. "The validator checks that all 9 required H2 headings are present, in order, with content" is architecture-level.
