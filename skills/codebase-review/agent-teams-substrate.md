# Agent Teams Substrate

Generic mechanics for coordinating a team of parallel teammates: creating a team, spawning named teammates, mailbox messaging, idle notifications, and shutdown ordering. This is the reusable substrate — a consuming skill layers its own task protocol (what each teammate does, how completions are processed) on top.

## Verify Environment

Agent teams require the `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` environment variable. Before spawning any teammate, verify it is set: `[[ "$CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS" == "1" ]]`. If unset, either abort or downgrade to a non-team path — the consuming skill decides which.

## Create Team

Before spawning any teammates, create the team exactly once: `TeamCreate({team_name: "<TEAM_NAME>"})`. Derive `TEAM_NAME` from the work (e.g. a kebab-cased identifier). Store it — every spawn references it.

## Spawn Named Teammates

Spawn teammates with the Agent tool. The `team_name`, `name`, `mode`, and `subagent_type` parameters must appear directly in the Agent tool call — YAML descriptions are not sufficient:

```text
Agent({
  team_name: "<TEAM_NAME>",
  name: "<unique-teammate-name>",
  subagent_type: "<agent-type>",
  model: "<model>",
  mode: "acceptEdits" | "auto",
  description: "<short description>",
  prompt: "<filled prompt template>"
})
```

- **Names must be unique within the team.** If you re-spawn a teammate with a name previously used, the earlier instance must be fully terminated first (see Shutdown), or the name collides.
- **`mode: "acceptEdits"`** lets a teammate make Edit/Write calls without prompting the lead for each one — critical for any teammate that writes files, since per-edit approval blocks parallel execution. Use `mode: "auto"` for read-only reviewers.
- **Spawn all parallel teammates in a single message** — one Agent call per teammate, all in the same turn. Splitting spawns across turns breaks parallelism and forces cache reloads.

## Idle Notifications

Teammate completion is **push-based**: when a teammate finishes its turn and goes idle, the lead receives a notification. Do not poll. A teammate that fanned out to its own `Explore`/`Agent` subagents can appear idle while its output artifact is still pending, so idle-without-expected-output is ambiguous — send one prose nudge and wait for it to go idle again before treating it as a failure.

## Mailbox Messaging (SendMessage)

Send messages to a teammate by name: `SendMessage({to: "<teammate-name>", message: <payload>})`.

- **Protocol objects** — the mailbox validator accepts only the structured shutdown/plan-approval protocol objects, e.g. `{type: "shutdown_request"}`.
- **Prose messages** — for anything else (task instructions, peer-file paths, feedback), send a plain prose string. A bare JSON string is auto-parsed into an object and rejected by the validator, so genuine free-form content must read as prose, not as JSON.

## Shutdown Ordering

Terminate teammates cleanly before deleting the team:

1. `SendMessage({to: "<teammate-name>", message: {type: "shutdown_request"}})` to each teammate.
2. Wait for each teammate's idle notification confirming shutdown. A teammate must fully terminate before its worktree can be removed or its name reused.
3. Once all teammates have confirmed shutdown, call `TeamDelete()` to release team resources.

Teammates must fully terminate before team deletion — deleting the team while a teammate is still running orphans it.
