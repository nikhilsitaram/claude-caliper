# handoff

Delegate scoped work to a **fresh, visible Claude session in a new iTerm2 pane**.
`/handoff` splits the current iTerm2 window (the cmd+d equivalent), launches a new
`claude` in the pane, and relays a self-contained brief to it over
[cross-session messaging](https://code.claude.com/docs/en/cross-session-messaging).
The result is a peer session you can watch and take over — unlike a background
subagent — without hand-typing the context into it.

Reach for it when you want a sibling session working alongside you: run a long
migration in one pane while you keep going, split off a focused sub-task, or fan
a chore out to a pane you can steer.

## Requirements

- **macOS + iTerm2 only.** The launcher drives iTerm2's AppleScript API via
  `osascript` and guards on `TERM_PROGRAM=iTerm.app`; it exits with a clear
  message in any other terminal or OS.
- **Claude Code ≥ 2.1.224** for cross-session messaging (the relay). The optional
  "tell me when it's done" notice (`notify_when_idle`) needs **≥ 2.1.236**.
- Cross-session messaging must not be disabled — no `SendMessage`/`ListAgents`
  deny rules, and the feature-flag env vars (`DISABLE_TELEMETRY`, `DO_NOT_TRACK`,
  etc.) left unset. See the docs' Availability section.

## First-run setup: macOS Automation permission

The first time the launcher tells iTerm2 to open a pane, macOS shows a one-time
**Automation** prompt ("… wants to control iTerm"). Approve it. This is an
out-of-band OS grant a plugin can't make for you — like the statusline tap the
`queue` skill needs. If it was denied earlier, re-enable it under **System
Settings → Privacy & Security → Automation**, then retry. Until it's granted the
launcher reports it couldn't create the pane.

## How it works

1. `scripts/spawn-pane.sh <slug> [cwd]` computes a unique session name
   (`<slug>-<suffix>`), splits the current iTerm2 session vertically, and types
   `claude --name <name> --settings '{"crossSessionInbound":"accept"}'` into the
   new pane. The `crossSessionInbound: accept` setting is what lets the relayed
   brief arrive without a hold dialog.
2. The script polls until the new `claude` process is up, so the caller confirms
   registration with a `ListAgents` check or two — never a poll loop.
3. Claude composes a self-contained brief and sends it in a single `SendMessage`
   to the new session's name, optionally subscribing `notify_when_idle`.

The new session launches in the caller's directory with interactive permissions
by default; pass `--perm-mode acceptEdits` to the launcher for hands-off editing.

## Configuration (env)

| Var | Default | Purpose |
|-----|---------|---------|
| `HANDOFF_REGISTER_TIMEOUT` | `20` | Seconds the launcher waits for the new `claude` process before reporting `LAUNCHED=timeout` |

## Files

- `SKILL.md` — model-facing instructions.
- `scripts/spawn-pane.sh` — the iTerm2 launcher (guard, unique name, split, wait).

Tests: `tests/handoff/caliper-test_spawn_pane.sh` (guards, name/arg validation,
launch-line construction — via `--dry-run`, so it needs no iTerm2 and runs on CI).
