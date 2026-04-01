# Plan Review Prompt Template

Dispatch a reviewer subagent to validate a plan before execution.

**Only dispatch after the plan is fully written and saved.**

```yaml
Agent tool (general-purpose):
  model: "{PLAN_REVIEWER_MODEL}"
  description: "Plan consistency review"
  prompt: |
    You are reviewing an implementation plan BEFORE any code is written.
    Find every inconsistency, missing dependency, and design mismatch
    that would cause problems during implementation.

    ## Inputs

    **Plan directory:** {PLAN_DIR} (contains plan.json + phase-{letter}/{task_id_lower}.md files)
    **Design doc:** {DESIGN_DOC_PATH} (if "None", skip design checks)
    **Codebase:** {REPO_PATH} (read existing files to verify paths/imports)

    Read {PLAN_DIR}/plan.json for structured metadata (goal, architecture, tech_stack,
    dependencies, file paths). Read individual task files for prose (steps, avoid, verification).

    **Note:** Structural validation (missing fields, dependency cycles, duplicate IDs, file
    existence, H1 headers) already completed by validate-plan --schema. Focus on prose quality,
    design alignment, and Different Claude Test.

    ## 7-Point Checklist

    Work through each systematically. Read ALL tasks and cross-reference.

    ### 1. Dependency Ordering
    **Structural validation already verified:** Task dependency graph is acyclic, all depends_on
    references are backward-only (no forward dependencies), all referenced task IDs exist.

    **LLM reviewer checks:** Semantic coherence — do the task steps actually use what the
    dependencies claim? Are there implicit dependencies not declared in depends_on? Does the
    prose reference artifacts that don't exist or aren't created by prior tasks?

    - Flag: A2 depends_on A1 but steps don't use any A1 output (over-specified dependency)
    - Flag: A2 imports X but no depends_on declaration and X not in codebase (under-specified)
    - Flag: B1 consumes output from Phase A but has no handoff placeholder

    ### 2. Artifact Consistency
    **Structural validation already verified:** H1 headers in task files match task names from plan.json.

    **LLM reviewer checks:** Extract every file path, function name, and variable across all task
    prose. Verify the same artifact is referenced consistently everywhere.

    - Flag: Same file with different paths (`utils.ts` vs `helpers.ts`)
    - Flag: Same concept with different names (`UserService` vs `userService`)
    - Flag: Path doesn't match codebase conventions

    ### 3. Design Doc Alignment (skip if no design doc)
    Compare plan scope against design requirements:
    - Every requirement maps to at least one task
    - Architecture matches (REST vs GraphQL, etc.)
    - Tech stack consistent
    - Data models match

    - Flag: Design specifies X but no task implements it
    - Flag: Plan uses approach A but design specifies B

    ### 4. Test-Implementation Coherence
    For each task with test steps:
    - Test imports from correct path?
    - Function signatures match between test and implementation?
    - Return values consistent?
    - TDD 5-step cycle present? (write fail, verify fail, implement, verify pass, commit)

    For multi-task plans with cross-task data flow:
    - First task (e.g., A1) as broad integration tests present?
    - Integration tests reference modules that later tasks create?
    - Skip justification if no broad tests? (single-module, no cross-task flow)

    - Flag: Test expects `fn(a, b)` but implementation defines `fn(a, b, c)`
    - Flag: Multi-task plan with cross-task flow missing broad integration tests

    ### 5. Completeness
    **Structural validation already verified:** plan.json contains all required fields (goal,
    architecture, tech_stack, phases array with tasks). Each task has id, name,
    status, depends_on, files (create/modify/test), verification, done_when. Task files exist at
    phase-{letter}/{task_id_lower}.md. Phase completion files exist at phase-{letter}/completion.md.
    Success criteria have non-empty run commands and expect fields.

    **LLM reviewer checks:** Are task steps detailed enough to execute? Is verification runnable
    and <60s? Is done_when measurable? Do avoid sections include reasoning (not just "don't use X")?
    Are steps complete code (not "add validation")? Do commands reference correct paths and match
    project tooling?

    - Flag: Steps say "add validation" without showing the validation code
    - Flag: Verification says "check it works" (not runnable)
    - Flag: Done when says "authentication complete" (not measurable)
    - Flag: Avoid says "don't use X" without explaining why
    - Flag: Command uses `npm test` but project uses `yarn`
    - Flag: File in "Modify" doesn't exist or wrong line range

    ### 6. Different Claude Test
    For each task: Could a fresh Claude with ZERO conversation history
    execute this task unambiguously?

    Check for:
    - Vague references ("the handler", "the config")
    - Missing file paths or partial paths
    - Context from conversation not written in plan
    - Done criteria that aren't measurable

    - Flag: "modify the auth handler" without specifying file
    - Flag: Done says "auth works" (not measurable)
    - Flag: References conversation context not in plan

    ### 7. Success Criteria Coverage (skip if no design doc)
    Read the Success Criteria section from the design doc at {DESIGN_DOC_PATH}.
    For each criterion, verify it maps to at least one task's "Done when" field.

    A criterion is covered if one or more tasks' "done when" fields collectively
    satisfy the criterion's behavioral intent. The mapping need not be 1:1 —
    a criterion like "users can log in" might be covered by Task A2's "login
    endpoint returns JWT" plus Task A3's "login form submits and redirects."

    - Flag: Criterion has no matching "done when" in any task (orphaned)
    - Flag: "Done when" references a criterion but doesn't actually satisfy it
    - Flag: Design doc has Success Criteria section but plan has no tasks covering them

    ### Phase & Parallelism Checks
    **Structural validation already verified:** phase-{letter}/completion.md files exist.
    File-set overlap within phases (no two tasks in the same phase share create/modify/test paths).

    **File-set isolation (single and multi-phase):**
    - Do any tasks in the same phase logically need to modify the same module? (Indicates bad decomposition even if paths are technically different)
    - Are shared utilities or config files properly assigned to one task, with other tasks only consuming them?

    - Flag: Two tasks modify different functions in the same file (should be one task or file should be split)
    - Flag: Task A creates a utility that Task B also needs to modify (should consolidate)

    **LLM reviewer checks:** If plan has multiple phases:
    - Phase boundaries at meaningful verification points?
    - Each phase ends with verification task?
    - Complexity gates: 8+ tasks in single-phase → should have phases
    - Complexity gates: 7+ tasks per phase → examine cut points
    - Interface-first: Contracts defined before implementations?
    - Inline handoff placeholders exist in task prose for tasks that consume prior phase output?

    - Flag: 10 tasks with no phases
    - Flag: Phase B task consumes Phase A output but prose has no handoff placeholder
    - Flag: Phase B starts without Phase A verification complete

    ## Output

    ### Issues Found

    For each issue:
    - **Category** (1-7 or Phase)
    - **Tasks** (which tasks involved)
    - **Problem** (specific, quote the plan)
    - **Fix** (what to change)

    ### Assessment

    | Check | Status |
    |-------|--------|
    | Dependency ordering | PASS/FAIL |
    | Artifact consistency | PASS/FAIL |
    | Design doc alignment | PASS/FAIL/SKIP |
    | Test-implementation coherence | PASS/FAIL |
    | Completeness | PASS/FAIL |
    | Different Claude test | PASS/FAIL |
    | Success criteria coverage | PASS/FAIL/SKIP |
    | Phase boundaries | PASS/FAIL/N/A |

    **Issues:** [count]
    **Severity:** Critical (blocks execution) / High (likely causes failure) / Medium (may cause confusion) / Low (cosmetic)
    **Ready for execution?** Yes / Yes after fixes / No, needs rework

    ### Review Summary (Machine-Readable)

    After the human-readable output above, emit a fenced code block with the info string `json review-summary`. This block is parsed by the controlling agent to enforce review gates — if it is missing or malformed, the review is treated as failed and a fresh reviewer is dispatched.

    Severity mapping for plan-review:
    - "Critical (blocks execution)" → critical
    - "High (likely causes failure)" → high
    - "Medium (may cause confusion)" → medium
    - "Low (cosmetic)" → low

    ```json review-summary
    {
      "issues_found": 3,
      "severity": { "critical": 0, "high": 1, "medium": 2, "low": 0 },
      "verdict": "fail",
      "issues": [
        { "id": 1, "severity": "high", "category": "Artifact consistency", "file": "phase-a/a1.md", "problem": "File path 'utils.ts' in task prose differs from 'helpers.ts' in plan.json", "fix": "Align all references to use 'src/utils.ts'" }
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

    - This is a CONSISTENCY check, not a code style review
    - Trace dependencies across tasks — this is the primary value
    - Be specific: quote plan text, reference task IDs (A1, B2, etc.)
    - If zero issues, say so — don't invent problems
    - READ-ONLY: Do not modify any files
    - DO check codebase when plan references existing files
```
