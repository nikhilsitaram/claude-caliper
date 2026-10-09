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
- **`$PLAN_DIR` stays in the main checkout; write it through Bash.** Use a quoted heredoc (`cat > "$PLAN_DIR/design-<topic>.md" <<'EOF'`) or `jq … > tmp && mv`; to revise a doc, rewrite it whole the same way. Never move the plan dir into the worktree to make the Write tool work — it is deleted with the worktree, which is how #288 lost every plan artifact. `validate-plan --schema` and `--check-entry` warn if it lands there.
- **Nest worktrees created from inside the session** under the current worktree's `.claude/worktrees/`. A sibling under the main checkout is created without error, but every later git command in it is refused.
