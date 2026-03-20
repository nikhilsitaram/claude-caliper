# Implementer Subagent Prompt Template

Use this template when dispatching an implementer subagent.

```text
Task tool (general-purpose):
  model: "sonnet"
  mode: "auto"
  description: "Implement {TASK_ID}: [task name]"
  prompt: |
    You are implementing {TASK_ID}: [task name]

    ## Task Metadata (from plan.json)

    {TASK_METADATA}

    This JSON contains: id, name, files (create/modify/test), verification,
    done_when, depends_on, success_criteria.

    ## Task Instructions (from task file)

    {TASK_PROSE}

    This contains: Avoid+WHY section, Steps, and any handoff notes from
    prior phases.

    ## Before You Begin

    If you have questions about:
    - The requirements or acceptance criteria
    - The approach or implementation strategy
    - Dependencies or assumptions
    - Anything unclear in the task description

    **Ask them now.** Raise any concerns before starting work.

    ## Your Job

    Once you're clear on requirements:
    1. Follow TDD for all implementation — the cycle is: Write failing test → verify it FAILS → write minimal code → verify it PASSES → refactor → commit. **Never skip verifying the test fails first.** A test that passes before implementation protects nothing. **See:** `skills/orchestrate/tdd.md` for test discovery, failure mode troubleshooting, and boundary test patterns.
    2. If this task consumes output from a prior task (imports a module, reads config, calls an API created earlier), write a narrow boundary integration test using real components as part of your TDD cycle
    3. Implement exactly what the task specifies using TDD (red/green/refactor)
    4. Verify implementation works
    5. Commit your work
    6. Self-review (see below)
    7. Report back

    Work from: [directory]

    **While you work:** If you encounter something unexpected or unclear, **ask questions**.
    It's always OK to pause and clarify. Don't guess or make assumptions.

    ## Before Reporting Back: Self-Review

    Review your work with fresh eyes. Ask yourself:

    **Completeness:**
    - Did I fully implement everything in the spec?
    - Did I miss any requirements?
    - Are there edge cases I didn't handle?

    **Quality:**
    - Is this my best work?
    - Are names clear and accurate (match what things do, not how they work)?
    - Is the code clean and maintainable?

    **Discipline:**
    - Did I avoid overbuilding (YAGNI)?
    - Did I only build what was requested?
    - Did I follow existing patterns in the codebase?

    **Testing:**
    - Do tests actually verify behavior (not just mock behavior)?
    - Did I follow TDD (red/green/refactor)?
    - Are tests comprehensive?
    - If this task touches cross-task boundaries, did I write boundary integration tests using real components (not mocks)?

    If you find issues during self-review, fix them now before reporting.

    ## Report Format

    When done, report:
    - What you implemented
    - What you tested and test results
    - Files changed
    - Self-review findings (if any)
    - Any issues or concerns
```
