# Design Review Prompt Template

Dispatch a reviewer subagent to validate a design doc before planning begins.

**Only dispatch after the design doc is fully written and saved.**

```yaml
Agent tool (general-purpose):
  model: "{DESIGN_REVIEWER_MODEL}"
  description: "Design doc review"
  prompt: |
    You are reviewing a design doc BEFORE any planning or implementation begins.
    Find every spec gap, unmeasurable criterion, unconsidered alternative, and
    implicit assumption that would cause problems downstream.

    ## Inputs

    **Design doc:** {DESIGN_DOC_PATH}
    **Codebase:** {REPO_PATH} (read existing files to verify paths, check for existing patterns)

    ## 8-Point Checklist

    Work through each systematically. Read the FULL design doc first, then evaluate.

    ### 1. Problem Clarity
    Verify the Problem section:
    - States a specific problem (not vague dissatisfaction)
    - Identifies who is affected
    - States consequences of not solving (what happens if we do nothing)

    - Flag: "We need X" without saying why
    - Flag: Problem statement that describes the solution instead of the problem
    - Flag: Missing "who is affected" — can't verify success without knowing the user

    ### 2. Success Criteria Quality
    For each criterion in the Success Criteria section:
    - Human-verifiable: a person can confirm yes/no by observing behavior or outcomes
    - Implementation-independent: doesn't reference specific code, tests, or tools (e.g., "pytest passes" is implementation-dependent; "users can log in" is not)
    - Collectively complete: if ALL criteria pass, the Goal is fully met
    - Individually necessary: removing any single criterion would leave a gap

    - Flag: "Tests pass" or "middleware installed" (implementation-dependent)
    - Flag: Criterion that can't be verified without reading code
    - Flag: Goal mentions X but no criterion covers X (collectively incomplete)
    - Flag: Two criteria that say the same thing differently (redundant, not necessary)
    - Flag: Missing Success Criteria section entirely

    ### 3. Architecture-Problem Fit
    Verify the architecture addresses the stated problem:
    - Each architectural component traces to a part of the problem
    - No component exists without a problem-driven reason
    - Scope is appropriate (not over-engineered, not under-specified)
    - Feasibility: are there technical risks or unproven assumptions?

    - Flag: Architecture component with no connection to the problem
    - Flag: Problem aspect with no architectural response
    - Flag: Unproven assumption stated as fact (e.g., "X library supports Y" without verification)
    - Flag: Technical risk not acknowledged

    ### 4. Alternative Assessment
    Check whether the design considered alternatives:
    - Does an existing skill already partially cover this functionality?
    - Does the codebase have a similar pattern that could be extended?
    - Are there established approaches in the problem domain?
    - Is the chosen approach the most effective path to meeting success criteria?

    - Flag: No alternatives section or discussion
    - Flag: Alternatives dismissed without trade-off analysis
    - Flag: Existing codebase pattern could be extended but isn't mentioned
    - Flag: Chosen approach is more complex than an alternative with equivalent effectiveness

    ### 5. Scope Alignment
    Verify the design solves the stated problem and not more:
    - Every change is justified by the problem statement
    - Features beyond what the problem requires are flagged as potential scope creep
    - Non-goals are correctly scoped with rationale
    - Non-goals don't exclude things that the problem actually requires

    - Flag: Change that doesn't trace back to the problem
    - Flag: Missing non-goals section when the design touches multiple systems
    - Flag: Non-goal that contradicts a success criterion
    - Flag: Scope creep — feature/complexity beyond what the problem demands

    ### 6. Decision Justification
    For each key decision:
    - Trade-off analysis present (what was gained, what was given up)
    - Alternatives considered and reasons for rejection
    - Decision is consistent with success criteria

    - Flag: Decision stated without alternatives considered
    - Flag: Decision contradicts a success criterion
    - Flag: "We chose X" without explaining why not Y

    ### 7. Internal Consistency
    Cross-reference across all sections:
    - Names, paths, and concepts used identically everywhere
    - Architecture section matches the file change table
    - No contradictions between sections
    - Section references are accurate

    - Flag: Same concept with different names in different sections
    - Flag: File path in architecture differs from file change table
    - Flag: Architecture says X, key decisions says Y (contradiction)
    - Flag: Section references something not present in the referenced section

    ### 8. Handoff Quality
    Evaluate whether a plan drafter with zero conversation context can produce a correct plan:
    - No implicit assumptions left uncaptured
    - File paths and change descriptions are specific enough
    - Architecture is concrete, not hand-wavy
    - Implementation approach gives clear direction

    - Flag: "Modify the handler" without specifying which file
    - Flag: Architecture describes behavior but not structure
    - Flag: Implicit knowledge required (e.g., assumes reader knows the codebase convention)
    - Flag: File change table missing or incomplete

    ## Output

    ### Issues Found

    For each issue:
    - **Category** (1-8)
    - **Problem** (specific, quote the design doc)
    - **Fix** (what to change, with specific text suggestions)

    ### Assessment

    | Check | Status |
    |-------|--------|
    | Problem clarity | PASS/FAIL |
    | Success criteria quality | PASS/FAIL |
    | Architecture-problem fit | PASS/FAIL |
    | Alternative assessment | PASS/FAIL |
    | Scope alignment | PASS/FAIL |
    | Decision justification | PASS/FAIL |
    | Internal consistency | PASS/FAIL |
    | Handoff quality | PASS/FAIL |

    **Issues:** [count]
    **Severity:** Critical (blocks planning) / High (likely causes plan failure) / Medium (may cause confusion) / Low (cosmetic)
    **Ready for planning?** Yes / Yes after fixes / No, needs rework

    ### Review Summary (Machine-Readable)

    After the human-readable output above, emit a fenced code block with the info string `json review-summary`. This block is parsed by the controlling agent to enforce review gates — if it is missing or malformed, the review is treated as failed and a fresh reviewer is dispatched.

    Severity mapping for design-review:
    - "Critical (blocks planning)" → critical
    - "High (likely causes plan failure)" → high
    - "Medium (may cause confusion)" → medium
    - "Low (cosmetic)" → low

    ```json review-summary
    {
      "issues_found": 7,
      "severity": { "critical": 1, "high": 2, "medium": 3, "low": 1 },
      "verdict": "fail",
      "issues": [
        { "id": 1, "severity": "critical", "category": "Problem clarity", "file": "N/A", "problem": "Problem statement describes solution not problem", "fix": "Rewrite problem statement to focus on user impact" }
      ]
    }
    ```

    Rules for the summary block:
    - `verdict`: "pass" when zero issues remain actionable, "fail" otherwise
    - `issues_found`: total count (including low/informational)
    - `severity`: counts per level (critical, high, medium, low)
    - `issues[]`: one entry per issue with id (sequential integer), severity, category (from checklist section name), file (path:line or "N/A"), problem, fix
    - If zero issues: `{"issues_found": 0, "severity": {"critical": 0, "high": 0, "medium": 0, "low": 0}, "verdict": "pass", "issues": []}`
    - This block must be the LAST fenced code block in your response — the controller uses the last `json review-summary` block if multiple appear

    ## Rules

    - This is a DESIGN QUALITY check, not a code review or style review
    - Be specific: quote design doc text, reference section names
    - If zero issues, say so — don't invent problems
    - READ-ONLY: Do not modify any files
    - DO check codebase when design references existing files or patterns
    - Success criteria are about outcomes, not implementation — flag any criterion that references code, tests, or tools
```
