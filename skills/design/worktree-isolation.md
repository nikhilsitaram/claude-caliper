# Worktree Session Isolation

After `EnterWorktree`, Claude Code confines the session (and every subagent it spawns) to that worktree. Its Bash guard is static analysis that refuses any call naming git that it can't prove stays inside. The dependable pattern: run git bare and read its printed output, carry values into later calls as literals, and keep non-git setup (`mkdir`, `if [ -z … ]`, `$(date)`) in a separate call. Skill snippets use variables for readability — substitute literals under isolation. Observed in calls that name git, probed in gh issue #288:

| Operation | Under isolation |
|---|---|
| Write/Edit tool on a main-checkout path — including gitignored `$PLAN_DIR` | Refused |
| Bash write, or Read, on a main-checkout path | Allowed |
| Plain git with literal paths (incl. into a nested worktree); `if git … \| grep -q …; then …; fi` | Allowed |
| A bare `X=$(git …)` assignment; `$X` reused only inside a longer string (`"refs/heads/$X"`) | Allowed |
| Any quoted `"$(…)"` — even `"$(pwd)"` — or `$(git …)` inside a test | Refused |
| A substitution result reused as a standalone word — `echo "$X"`, a git argument, `[ -z "$X" ]` | Refused |
| `git -C <main checkout>`, or `cd <sibling worktree> && git …` | Refused |
| `ExitWorktree(remove)` on a worktree entered by `path` | Refused — `ExitWorktree(keep)` lifts isolation, then `git worktree remove <path>` |

What follows from it:

- **Create with `git worktree add`, enter with `EnterWorktree(path:)`.** `EnterWorktree(name:)` makes the worktree session-owned, and the harness auto-removes it on exit when it looks unchanged — an integration branch with no commits yet does. Path-entered worktrees are never auto-removed.
- **`$PLAN_DIR` stays in the main checkout; write it through Bash.** To create or change a document (design doc, `plan.json`), go through its draft at `$WORKTREE/.caliper-draft/<file>`, every time: `caliper-draft pull $PLAN_DIR/<file>` (if the file exists), Write/Edit the draft, then `caliper-draft push $PLAN_DIR/<file>`. `$PLAN_DIR` is the only copy anything reads (reviewers, plan-drafter, orchestrate). Pulling first means an in-place change (`jq`, `validate-plan`) is never reverted, and pushing means no reader sees a stale doc. Use `caliper-draft`, not `cp`, and never draft under `.claude/`. Claude Code protects every `.claude/` directory, the worktree's own included. A Write there prompts even in acceptEdits, and no allow rule can pre-approve it. A `cp` into `$PLAN_DIR` prompts too. One narrow `Bash(caliper-draft:*)` rule covers both copies (#306). Small writes stay Bash-native: `jq … > tmp && mv`, `touch`, `cat >>`. Never move the plan dir itself into the worktree to make Write work — it is deleted with the worktree, which is how #288 lost every plan artifact. `validate-plan --schema` and `--check-entry` warn if it lands there.
- **Nest worktrees created from inside the session** under the current worktree's `.claude/worktrees/`. A sibling under the main checkout is created without error, but every later git command in it is refused.
