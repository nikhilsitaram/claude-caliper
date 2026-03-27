# A6 Completion: Integrate review_mode, skip_review, review_wait_minutes into pr-review

## Changes Made

1. **Step 2 (Mode Selection):** Added `caliper-settings get review_mode` fallback — when no `--automated` flag is passed and the setting returns `automated`, automated mode is used without prompting.

2. **Step 4 (Dispatch Subagent):** Added `caliper-settings get skip_review` fallback — when `--skip-review` flag is not passed but the setting returns `true`, the subagent dispatch is skipped.

3. **Step 5 (External Feedback):** Replaced hardcoded 10-minute timeout with `caliper-settings get review_wait_minutes` (default: 10).

## Verification

All three grep checks pass:
- `caliper-settings get review_mode` in Step 2
- `caliper-settings get skip_review` in Step 4
- `caliper-settings get review_wait_minutes` in Step 5

## Notes

- `--automated`/`-A` flag remains tier 1 and always wins over the setting
- `--skip-review`/`-R` flag remains tier 1 and always wins over the setting
- The 90-second and 60-second warm-up periods are unchanged (fixed values)
