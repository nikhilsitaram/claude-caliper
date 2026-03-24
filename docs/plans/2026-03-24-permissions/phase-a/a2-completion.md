# A2 Completion Notes

**Summary:** Added shell interpreter resolution so `bash scripts/validate-plan` resolves to `validate-plan` instead of matching against `bash`. Added variable-as-command detection that produces an explicit deny with `permissionDecisionReason` when `$VAR`, `"$VAR"`, or `${VAR}` appears as a command word.

**Deviations:** None

**Files Changed:**
- `hooks/pretooluse-safe-commands.sh` -- added interpreter resolution in `extract_command_words_from_segment`, variable detection in main loop, and deny-with-feedback response block

**Test Results:** All 32 existing tests pass. Manual verification confirms all done_when criteria: `bash scripts/validate-plan` -> allow, `bash -e scripts/validate-plan` -> allow, `bash "$f"` -> deny with reason, bare `bash` -> fall through, `$VAR`/`"$VAR"`/`${VAR}` as command word -> deny with permissionDecisionReason.

**Deferred Issues:** None
