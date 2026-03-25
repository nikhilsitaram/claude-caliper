# A1 Completion Notes

## What was done

Rewrote `skills/pr-review/SKILL.md` with the 9-step workflow from the design doc:

1. **Setup** — unchanged from original
2. **Mode Selection** — new AskUserQuestion prompt (Automated/Deliberate), skipped when `--automated` flag passed
3. **Rebase onto Base Branch** — unchanged from original
4. **Dispatch Subagent in Background** — changed from synchronous to `run_in_background: true`
5. **External Feedback** — new step with poll-based bot readiness (`gh pr checks`, comment scanning, CodeRabbit rate-limit detection, 10-min timeout), mode-dependent behavior (automated fixes wave 1 locally, deliberate collects only)
6. **Subagent Results** — new step with two-wave fixing in automated mode (dismiss already-fixed findings, fix remaining, single push), deliberate merges into unified finding set
7. **Present & Confirm** — deliberate only, same as original Step 5
8. **Fix, Test, Push** — deliberate only, same as original Step 6
9. **Comment on PR** — unchanged from original

## Preserved sections

- Frontmatter (description unchanged for triggering)
- Header and subtitle
- Prerequisite and review principle
- Arguments table (updated `--skip-review` to reference Steps 4, 6)
- Integration section

## Added to Pitfalls

- "Pushing between wave 1 and wave 2" — explains the local-commit-then-push strategy

## Word count

1,099 words (target: under 1,500, hard cap: 2,000)

## Verification

All grep checks pass: Mode Selection, Dispatch Subagent, External Feedback, Subagent Results, run_in_background, gh pr checks.
