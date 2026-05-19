# Scope Reviewer Dispatch (single mode)

Per-directory dispatch body for the `claude-caliper:codebase-auditor` agent in single-mode Phase 2. The agent definition supplies the 5 review categories, Severity definitions, output Finding template, and quality bar — this file holds only the per-directory specifics.

## Inputs

- **SCOPE_PATH**: The directory to review (provided by the codebase-review skill's Phase 2 dispatch — one subagent per top-level directory).

## Process

Read ALL files under `{SCOPE_PATH}`. Do not skip files. Apply the 5 categories and severity definitions from your system prompt. Use the Finding output format from your system prompt.

Mark Critical / High / Medium / Low — single mode keeps Low findings (team mode drops them; see `agents/team-reviewer.md`).

## Output

Return findings to the caller (the codebase-review skill) in your final message. Findings are aggregated and routed by the skill's Phase 4 — you do not write files.

## Rules

- Be concrete — cite `file:line` for every finding (the agent's hard rules require this).
- Only report real issues you can point to in the code (the agent's quality bar requires this).
- Do NOT modify any files — source files are read-only per the agent's hard rules.
