#!/usr/bin/env bash
# statusline-wrapper.sh — taps the 5-hour usage-window data into a state file,
# then renders the statusline.
#
# Claude Code pipes a JSON blob to the statusLine command on stdin. For Pro/Max
# subscribers it includes `rate_limits.five_hour.{resets_at,used_percentage}` —
# the moment the current 5h usage window flips and how much is consumed. That
# data is NOT available to anything running inside a session, so we capture it
# here from the one channel that carries it.
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

# One jq pass pulls everything we need — the two tap fields plus the render
# fields — joined on US (0x1f). A non-whitespace separator is deliberate: tab is
# an IFS-whitespace char, which would collapse the leading empty fields when
# rate_limits is absent (mis-shifting model/dir); 0x1f preserves empty fields
# and can't occur in a model name or path.
IFS=$'\x1f' read -r resets_at used model dir <<EOF
$(printf '%s' "$input" | jq -r '[
    (.rate_limits.five_hour.resets_at // ""),
    (.rate_limits.five_hour.used_percentage // ""),
    (.model.display_name // .model.id // ""),
    (.workspace.current_dir // .cwd // "")
  ] | map(tostring) | join("\u001f")' 2>/dev/null)
EOF

# Normalize the two numeric fields once, shared by the tap and the render below.
# resets_at is interpolated raw into JSON, so a non-numeric value (e.g. an
# ISO-8601 string) would corrupt the state file — worse than no file, since both
# consumers would then jq-fail to empty and misreport the cause. Guard it to a
# bare integer epoch; guard used to a well-formed JSON number. The leading- and
# trailing-dot cases (.5, 40., .) matter: they'd be a non-numeric percentage AND
# invalid JSON if interpolated raw, so they must reduce to null like any garbage.
case "$resets_at" in ''|*[!0-9]*) resets_at="" ;; esac
case "$used" in ''|.*|*.|*[!0-9.]*|*.*.*) used="" ;; esac

# Tap: only persist a real window (resets_at present); used falls back to null.
if [ -n "$resets_at" ]; then
  printf '{"resets_at":%s,"used_percentage":%s,"captured_at":%s}\n' \
    "$resets_at" "${used:-null}" "$(date +%s)" > "$STATE_FILE"
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
