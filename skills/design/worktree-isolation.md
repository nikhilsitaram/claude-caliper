# Worktree Session Isolation

After `EnterWorktree`, Claude Code confines the session (and every subagent it spawns) to that worktree. Observed behavior, probed in gh issue #288:

| Operation | Under isolation |
|---|---|
| Write/Edit tool on a main-checkout path — including gitignored `$PLAN_DIR` | Refused |
| Bash write, or Read, on a main-checkout path | Allowed |
| `X="$(git …)"` | Refused — use unquoted `X=$(git …)` (assignments don't word-split) |
| `git -C "$P"` where `$P` came from a `$(…)` substitution | Refused — run git from the worktree root instead |
| `git -C <main checkout>`, or `cd <sibling worktree> && git …` | Refused |
| `cd`/`git` into a worktree nested under the current one (literal path) | Allowed |
| `ExitWorktree(remove)` on a worktree entered by `path` | Refused — `ExitWorktree(keep)` lifts isolation, then `git worktree remove <path>` |

What follows from it:

- **Create with `git worktree add`, enter with `EnterWorktree(path:)`.** `EnterWorktree(name:)` makes the worktree session-owned, and the harness auto-removes it on exit when it looks unchanged — an integration branch with no commits yet does. Path-entered worktrees are never auto-removed.
- **`$PLAN_DIR` stays in the main checkout; write it through Bash.** For a document (design doc, `plan.json`), Write/Edit a draft at `.claude/caliper-draft/<file>` in the worktree, then `cp` it to `$PLAN_DIR` after every change. `$PLAN_DIR` is the only copy anything reads (reviewers, plan-drafter, orchestrate), so a skipped `cp` means the next reader gets a stale doc. If the `$PLAN_DIR` copy was changed in place since (`jq`, `validate-plan`), `cp` it back to the draft before editing again, or the next `cp` reverts that change. Small writes stay Bash-native: `jq … > tmp && mv`, `touch`, `cat >>`. Don't heredoc whole documents — caliper's Bash hook scans heredoc bodies as commands and denies lines starting with `$VAR` or `bash`. Never move the plan dir itself into the worktree to make Write work — it is deleted with the worktree, which is how #288 lost every plan artifact. `validate-plan --schema` and `--check-entry` warn if it lands there.
- **Nest worktrees created from inside the session** under the current worktree's `.claude/worktrees/`. A sibling under the main checkout is created without error, but every later git command in it is refused.
