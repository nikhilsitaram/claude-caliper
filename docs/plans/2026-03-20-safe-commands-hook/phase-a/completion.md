# Phase A Completion Notes

**Date:** 2026-03-20
**Summary:** Built the complete safe commands hook infrastructure: a PreToolUse hook (`hooks/pretooluse-safe-commands.sh`) that parses Bash commands (respecting quotes, `&&`/`;`/`|` separators, `$()` subshells, path basenames, and `VAR=` assignments) and instantly approves those matching `hooks/safe-commands.txt` prefixes; 15-test suite covering all edge cases; hook wired in `hooks/hooks.json`; all 5 subagent prompt files switched from `bypassPermissions` to `auto` mode; learning loop added to the phase dispatcher prompt; setup documentation written; plugin version bumped from 1.8.1 to 1.9.0. All 36 hook tests (across 3 suites) pass.

**Deviations:**
- A1/A2 — `run_hook` helper in test file had env vars applied to `echo` instead of `bash` in the pipeline; fixed in A2 by moving env-var prefix to the `bash` command (right side of pipe). Rule 1 (auto-fix bug) — the test design was incorrect and would have caused spurious passes/fails once the hook existed.
- A2 — hook script used `((i++))` for loop counter with `set -euo pipefail`; `((expr))` returns exit code 1 when the expression evaluates to 0 (falsy), causing early exit from the parsing function on the first iteration. Fixed with `i=$((i+1))`. Rule 1 (auto-fix bug).
- A2 — bash regex patterns containing `)` inside `[[ =~ ]]` cause syntax errors; fixed by storing regex in variables first. Rule 1 (auto-fix bug).
- A6 — orchestrate SKILL.md word count is 1337 after addition (was ~1270 before). The pre-existing over-cap is a deferred issue; the new Permission Model section itself is 67 words (under the 100-word section cap specified in done_when).
