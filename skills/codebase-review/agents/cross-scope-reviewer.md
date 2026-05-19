# Cross-Scope Reconciliation Dispatch (single mode)

Cross-scope reconciliation dispatch body for the `claude-caliper:codebase-auditor` agent in single-mode Phase 3. Find issues that only become visible when looking across directory boundaries. Per-directory reviewers have already checked each directory in Phase 2 — your job is to catch what they couldn't see from within a single scope.

## Inputs

- **SCOPE_PATH**: Root directory being reviewed
- **ALL_FINDINGS**: Concatenated findings from all parallel Phase 2 scope reviewers
- **FILE_MANIFEST**: All files in the repo under SCOPE_PATH

## Process

Focus EXCLUSIVELY on cross-boundary issues. Within-scope issues are already covered by Phase 2.

### 1. Cross-Directory DRY Violations

- Same logic implemented in different directories under different names
- Same constant or magic number defined independently in multiple modules
- Utility functions that exist in one module but are reimplemented in another
- Similar patterns that should be extracted to a shared location

### 2. Cross-Directory Naming Inconsistencies

- Same concept named differently across modules (e.g., "user" vs "account" vs "profile")
- Naming conventions that differ between directories (camelCase in one, snake_case in another)
- Config keys or environment variables with inconsistent naming patterns

### 3. Cross-Directory Pattern Divergence

- Error handling done differently in different modules
- Logging patterns inconsistent across directories
- API/interface contracts that don't match between producer and consumer modules

### 4. Duplicate Finding Detection

- Check if individual reviewers flagged the same issue independently (confirms it's real)
- Identify findings that describe the same underlying problem for deduplication

## Output

Use the Finding format from your system prompt. For the `Category` field, use one of:

- `Cross-Directory DRY`
- `Cross-Directory Naming`
- `Cross-Directory Pattern Divergence`

Cite `file:line` from BOTH sides of the boundary for each finding. Severity definitions from your system prompt apply unchanged.

For duplicates noticed across reviewers:

```text
Duplicates Found:
- [Finding X from reviewer A] and [Finding Y from reviewer B] describe the same issue: [brief explanation]
```

## Rules

- ONLY report cross-boundary issues — do not re-report within-scope findings.
- Read actual files to verify suspected cross-scope issues before reporting (the agent's hard rules require `file:line` citations grounded in real code).
- If you find zero cross-scope issues, return `No findings.` per the agent's quality bar — do not invent problems.
- Do NOT modify any files — source files are read-only per the agent's hard rules.
