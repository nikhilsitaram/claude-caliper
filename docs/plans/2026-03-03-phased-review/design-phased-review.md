# Design: Inter-Phase Implementation Review

## Goal

Add automatic implementation review gates between phases of multi-phase plan execution. Currently, implementation-review runs once after all tasks complete. This means Phase 2 can build on broken Phase 1 interfaces with no verification gate in between.

## Non-Goals

- New skills or reviewer prompts — reuse existing implementation-review
- Changes to single-phase execution (no phase loop, current behavior preserved)
- Changes to per-task spec/code review flow
- Phase-specific test tagging or xfail annotations

## Key Decisions

1. **Always automatic** — every phase boundary gets an implementation review, no opt-in flag
2. **Reuse existing implementation-review** (Approach A) — scope to phase diff, no new skills or templates
3. **Orchestrator dispatches fresh implementer subagent for fixes** — not fixing directly; triages findings through existing deviation rules (Rule 1-3 auto-fix, Rule 4 escalate)
4. **Orchestrator writes authoritative handoff notes** — reviewer suggests handoff notes, but orchestrator writes them into plan doc after fixes (reflects post-fix state)
5. **Cross-phase boundary tests** — reviewer identifies interface contracts downstream phases depend on; orchestrator verifies boundary tests exist for those contracts; dispatches implementer to write missing ones before proceeding
6. **>5 issues re-review rule** — if any review (plan-review, spec/code review, implementation-review) produces more than 5 fix-needed issues, after fixes dispatch a fresh full re-review subagent to confirm clean; applies cross-cutting to all review stages

## Architecture

### Files Changed

| File | Change |
|------|--------|
| `skills/subagent-driven-development/SKILL.md` | Add multi-phase execution loop, >5 re-review rule for all review stages |
| `skills/implementation-review/SKILL.md` | Add inter-phase context to When to Use, phase-scoped BASE_SHA guidance, new template variables |
| `skills/implementation-review/reviewer-prompt.md` | Add `{PHASE_CONTEXT}` block, elevate handoff notes for inter-phase reviews, add "Ready for next phase?" assessment |
| `skills/plan-review/SKILL.md` | Add >5 issues re-review rule |

### Per-Phase Execution Loop (SDD)

```text
For each phase:
  Execute tasks (existing per-task flow: implementer → spec review → code review)

  After phase tasks complete:
    1. Record PHASE_BASE_SHA (commit before phase's first task)
    2. Run full Task 0 integration test suite
       - Failures in current phase's scope = real issues, fix before proceeding
       - Failures in future phase scope = expected, note and continue
    3. Dispatch implementation-review with phase-scoped diff:
       - BASE_SHA = PHASE_BASE_SHA
       - HEAD_SHA = HEAD
       - PHASE_CONTEXT = phase name, downstream phase expectations
    4. Triage findings through deviation rules:
       - Rule 1-3: dispatch fresh implementer subagent to fix
       - Rule 4: escalate to user
    5. If >5 issues were found: after fixes, dispatch fresh full re-review
    6. Check cross-phase boundary test coverage:
       - Reviewer handoff notes list interface contracts downstream phases depend on
       - Orchestrator verifies boundary tests exist for those contracts
       - If missing: dispatch implementer to write them
    7. Orchestrator writes handoff notes into plan doc (before next phase's checklist)
    8. Update phase status: Complete (YYYY-MM-DD)
    9. Begin next phase

After final phase:
  Same review loop, then:
    - Write completion report (summary + deviations across all phases)
    - Ship (create PR)
```

### Reviewer Prompt Changes

New optional template variable:

| Variable | Value |
|----------|-------|
| `{PHASE_CONTEXT}` | "Reviewing Phase N of M: [name]. Downstream phases expect: [interfaces/APIs/config]" |

Assessment section adds: "Ready for next phase? [Yes/No]" alongside existing "Ready to merge after fixing?"

Handoff Notes section becomes primary output for inter-phase reviews — reviewer identifies:
- API/interface differences from plan assumptions
- New dependencies or config needed
- Scope changes affecting future phases
- Interface contracts that downstream phases depend on (for boundary test verification)

### >5 Issues Re-Review Rule (Cross-Cutting)

Applies to all review stages:
- Plan-review
- Per-task spec compliance review
- Per-task code quality review
- Implementation-review (per-phase and final)

Logic: if review produces >5 fix-needed issues → apply all fixes → dispatch fresh subagent with same full review scope → confirm clean. This prevents reviewer hallucination from compounding and catches new issues introduced by bulk fixes.

### What Doesn't Change

- Per-task spec/code review flow (unchanged, just gets >5 rule)
- Task 0 integration test structure (unchanged)
- Deviation rules (unchanged, reused for triaging reviewer findings)
- Single-phase plans (no loop, current behavior preserved)
- Implementer prompt template (unchanged)
- Completion report (still written by orchestrator after final phase)
