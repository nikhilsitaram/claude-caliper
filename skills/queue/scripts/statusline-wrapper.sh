#!/usr/bin/env bash
# statusline-wrapper.sh — taps the usage-window data into a state file, then
# renders the statusline.
#
# Claude Code pipes a JSON blob to the statusLine command on stdin. For Pro/Max
# subscribers it includes BOTH rolling windows under `rate_limits`:
# `five_hour.{resets_at,used_percentage}` and `seven_day.{resets_at,used_percentage}`
# — the moment each window flips and how much is consumed. That data is NOT
# available to anything running inside a session, so we capture it here from the
# one channel that carries it.
#
# Rendering: with no external statusline tool the built-in compact line is used,
# so these skills work standalone (no ccstatusline / bun required). Set
# QUEUE_STATUSLINE to forward stdin to any external renderer instead — e.g.
# QUEUE_STATUSLINE="bunx -y ccstatusline@latest" for ccstatusline.
#
# Config (env):
#   QUEUE_STATE_FILE   where to write state (default ~/.claude/queue/state.json)
#   QUEUE_STATUSLINE   external statusline command to forward stdin to; unset
#                      renders the built-in line.
# macOS/BSD `date` only (the built-in line uses `date -r <epoch>`).
set -u

STATE_FILE="${QUEUE_STATE_FILE:-$HOME/.claude/queue/state.json}"
mkdir -p "$(dirname "$STATE_FILE")"

input="$(cat)"

# One jq pass pulls everything we need — both windows' tap fields plus the render
# fields — joined on US (\u001f, 0x1f). A non-whitespace separator is deliberate:
# tab is an IFS-whitespace char, which would collapse the leading empty fields
# when rate_limits is absent (mis-shifting model/dir); 0x1f preserves empty fields
# and can't occur in a model name or path. Use jq's \u001f escape, not a literal
# control byte, so the source stays readable and editor/git-safe.
IFS=$'\x1f' read -r resets_at used seven_resets seven_used model dir <<EOF
$(printf '%s' "$input" | jq -r '[
    (.rate_limits.five_hour.resets_at // ""),
    (.rate_limits.five_hour.used_percentage // ""),
    (.rate_limits.seven_day.resets_at // ""),
    (.rate_limits.seven_day.used_percentage // ""),
    (.model.display_name // .model.id // ""),
    (.workspace.current_dir // .cwd // "")
  ] | map(tostring) | join("\u001f")' 2>/dev/null)
EOF

# Normalize the numeric fields once, shared by the tap and the render below.
# Each resets_at is interpolated raw into JSON, so a non-numeric value (e.g. an
# ISO-8601 string) would corrupt the state file — worse than no file, since the
# consumers would then jq-fail to empty and misreport the cause. Guard each to a
# bare integer epoch; guard each used to a well-formed JSON number. The leading-
# and trailing-dot cases (.5, 40., .) matter: they'd be a non-numeric percentage
# AND invalid JSON if interpolated raw, so they must reduce to null like garbage.
# The two windows are independent — either may be present without the other.
case "$resets_at" in ''|*[!0-9]*) resets_at="" ;; esac
case "$used" in ''|.*|*.|*[!0-9.]*|*.*.*) used="" ;; esac
case "$seven_resets" in ''|*[!0-9]*) seven_resets="" ;; esac
case "$seven_used" in ''|.*|*.|*[!0-9.]*|*.*.*) seven_used="" ;; esac

# Tap: persist whenever either window has a real reset time. five_hour stays the
# top-level shape (backward compatible — existing consumers read .resets_at /
# .used_percentage unchanged); seven_day is always written as a sub-object so the
# shape is stable, with null fields when that window is absent. A missing window's
# resets_at is null, which the consumers treat as "data unavailable".
if [ -n "$resets_at" ] || [ -n "$seven_resets" ]; then
  # Cross-session regression guard. state.json is shared by EVERY Claude session on
  # the machine, and captured_at is stamped at write time — so an idle session still
  # holding a STALE rate_limits blob (a window that reset long ago) would otherwise
  # overwrite an active session's fresh data and stamp it fresh, poisoning every
  # consumer with no staleness signal to catch it. A window's resets_at only ever
  # moves forward, so an incoming value OLDER than what's on disk means this render
  # is the stale one: skip the write. Equal/newer still writes, so used_percentage
  # keeps updating within a window and a genuine reset (resets_at jumps forward) lands.
  skip=""
  if [ -f "$STATE_FILE" ]; then
    cur_resets="$(jq -r '.resets_at // empty' "$STATE_FILE" 2>/dev/null)"
    cur_seven="$(jq -r '.seven_day.resets_at // empty' "$STATE_FILE" 2>/dev/null)"
    case "$cur_resets" in ''|*[!0-9]*) cur_resets="" ;; esac
    case "$cur_seven" in ''|*[!0-9]*) cur_seven="" ;; esac
    { [ -n "$resets_at" ] && [ -n "$cur_resets" ] && [ "$resets_at" -lt "$cur_resets" ]; } && skip="yes"
    { [ -n "$seven_resets" ] && [ -n "$cur_seven" ] && [ "$seven_resets" -lt "$cur_seven" ]; } && skip="yes"
  fi

  # Write via a temp file + atomic mv: this renders every ~10s and the consumers
  # (check-usage.sh / compute-fire.sh) read the file concurrently, so a direct `>`
  # redirect could expose a half-written file and make a consumer misreport
  # "data unavailable". mv on the same filesystem is atomic.
  if [ -z "$skip" ]; then
    tmp="$STATE_FILE.tmp.$$"
    if printf '{"resets_at":%s,"used_percentage":%s,"captured_at":%s,"seven_day":{"resets_at":%s,"used_percentage":%s}}\n' \
        "${resets_at:-null}" "${used:-null}" "$(date +%s)" "${seven_resets:-null}" "${seven_used:-null}" > "$tmp" 2>/dev/null; then
      mv "$tmp" "$STATE_FILE"
    else
      rm -f "$tmp"
    fi
  fi
fi

# Render. Forward to an external renderer if asked; otherwise our own line.
if [ -n "${QUEUE_STATUSLINE:-}" ]; then
  printf '%s' "$input" | ${QUEUE_STATUSLINE}
else
  # Built-in compact line: "dir (branch) · model · 5h NN% (resets HH:MM)".
  # Each segment is included only when its data is available, so free-tier
  # users (no rate_limits) still get a clean "dir (branch) · model" line.
  line=""
  if [ -n "$dir" ]; then
    branch="$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)"
    if [ -n "$branch" ]; then line="${dir##*/} ($branch)"; else line="${dir##*/}"; fi
  fi
  [ -n "$model" ] && line="${line:+$line · }$model"
  if [ -n "$used" ]; then
    # Truncate to whole percent in pure bash (no awk subprocess — this renders
    # on every statusline refresh). `used` is guaranteed well-formed above, so
    # stripping the fraction floors it for a non-negative percentage.
    seg="5h ${used%%.*}%"
    [ -n "$resets_at" ] && seg="$seg (resets $(date -r "$resets_at" +%H:%M))"
    line="${line:+$line · }$seg"
  fi
  printf '%s\n' "$line"
fi
