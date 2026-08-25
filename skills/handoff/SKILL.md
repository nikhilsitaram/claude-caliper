---
name: handoff
description: Use when the user wants to hand scoped work to a fresh, visible Claude session in a new iTerm2 pane — "/handoff", "hand this off to another session", "spin up a pane and have it do X", "open a new claude in a split and tell it to…", "delegate this to a sidecar session", "kick off a parallel session for this".
---

# /handoff — delegate scoped work to a sibling session in a new iTerm2 pane

Split the current iTerm2 window, launch a fresh `claude` in the new pane, and
relay a self-contained brief to it over cross-session messaging — so the user
gets a visible, steerable peer session doing the work, without hand-typing the
context into it.

Use this instead of a background subagent when the point is a pane the user can
watch and take over. macOS + iTerm2 only.

## Before spawning

1. **Scope the work.** Nail down what the sibling session should do: the task,
   its boundaries, and how it knows it's done. If the request is vague, ask — the
   brief is the only thing that travels (see below), so gaps can't be filled in later.
2. **Permission-laundering check.** Never relay work that *this* session was
   denied or that its own permission settings would block. A peer doing it for
   you bypasses the user's decision. Route blocked work back to the user instead.

## Spawn the pane

Run the launcher (executable — invoke directly, don't prefix with `bash`):

```text
./skills/handoff/scripts/spawn-pane.sh <slug> [cwd]
```

- `<slug>` — short kebab-case label for the work (e.g. `run-migration`). The
  script appends a random suffix to form the session's `--name`, so it reads back
  a unique `NAME=` the caller addresses. The suffix matters: if two sessions
  shared a name, Claude Code would silently rename one to a variant and the
  address you hold would be wrong.
- `[cwd]` — defaults to the current directory. Same checkout as the caller; the
  sibling uses its own skills to enter a worktree if it will edit files.
- `--perm-mode acceptEdits` — optional, only if the user wants the pane editing
  hands-off. Default is interactive: the pane is right there to answer prompts.

The launcher opens the split, types the launch line into it, and waits for the
new `claude` process to come up. Read `NAME=` from its output. If it prints
`LAUNCHED=timeout` or errors, relay the message and stop — don't message a
session that isn't up. (First run also triggers a one-time macOS Automation
permission prompt — see README.)

The launch line sets `--settings '{"crossSessionInbound":"accept"}'`. That flag
is load-bearing: without it the brief you send could sit in a hold dialog in the
new pane instead of reaching the sibling Claude.

## Relay the brief

Confirm the session registered: call `ListAgents` and look for `NAME`. It should
be there (the launcher already waited for the process); if not, wait a beat and
check once more — at most two or three times, never a poll loop.

Then send **one** `SendMessage` to `NAME`. Write a **self-contained** brief —
only plain text crosses, never this conversation's history or files, so include
everything the sibling needs:

- **Context** — what this is and why, enough to act without your transcript.
- **Scope** — exactly what to do, and what's out of scope.
- **Constraints** — repo conventions, files to touch/avoid, tests to run.
- **Done-criteria** — how it knows it's finished.
- **Reply when done** — ask it to message back the session that sent this brief
  (it has your address from the message's sender).

Batch all of that into that single message. Rapid bursts to one inbox get
refused at the sender, so don't dribble the brief across several sends.

## Optionally hear back

If the user wants to be told when the sibling finishes, add
`notify_when_idle: true` to the `SendMessage` (or send a bare subscription).
That's the mechanism for "tell me when it's done" — **never** poll `ListAgents`
in a loop or send "are you done?" messages to check on it.

## Report

Tell the user the pane is open, the session's name, and that they can steer it
directly in that pane or ask you to relay follow-ups to it.

## Notes

- **macOS + iTerm2 only.** The launcher guards on `TERM_PROGRAM=iTerm.app` and
  exits with a clear message elsewhere.
- Same-machine, peer-to-peer. Cross-machine/cloud relay is out of scope.
- The sibling is independent: its own permission prompts apply to anything the
  brief asks for, and a message from you never counts as the user's approval there.
