#!/usr/bin/env bash
set -euo pipefail

# uv, python3 and the venv's pip are stubs that log their argv, so nothing
# installs and nothing touches the network. PATH is narrowed to the stubs plus
# /usr/bin:/bin, which keeps a real uv (usually ~/.local/bin or Homebrew) out.

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/caliper-python-bootstrap"

pass=0
fail=0
TMPDIR_BASE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BASE"' EXIT
BASE="$(cd "$TMPDIR_BASE" && pwd -P)"
LOG="$BASE/log"

check_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "PASS: $desc"; pass=$((pass + 1))
  else
    echo "FAIL: $desc (expected=[$expected] actual=[$actual])"; fail=$((fail + 1))
  fi
}

# uv stub: `uv venv <path>` makes the venv (with uv's own self-ignoring
# .gitignore); `uv pip …` logs. UV_FAIL makes pip installs fail.
UV_BIN="$BASE/uvbin"
mkdir -p "$UV_BIN"
cat > "$UV_BIN/uv" <<EOF
#!/usr/bin/env bash
echo "uv \$* [cwd=\$(pwd -P)]" >> "$LOG"
if [[ "\$1" == venv ]]; then mkdir -p "\$2/bin" && echo '*' > "\$2/.gitignore"; fi
if [[ "\$1" == pip && -n "\${UV_FAIL:-}" ]]; then echo "uv boom" >&2; exit 1; fi
exit 0
EOF
# python3 stub: `python3 -m venv <path>` makes a venv with a logging pip and,
# like Python < 3.13, no .gitignore.
PY_BIN="$BASE/pybin"
mkdir -p "$PY_BIN"
cat > "$PY_BIN/python3" <<EOF
#!/usr/bin/env bash
echo "python3 \$* [cwd=\$(pwd -P)]" >> "$LOG"
if [[ "\$1 \$2" == "-m venv" ]]; then
  mkdir -p "\$3/bin"
  printf '#!/usr/bin/env bash\necho "pip \$*" >> "$LOG"\n' > "\$3/bin/pip"
  chmod +x "\$3/bin/pip"
fi
EOF
chmod +x "$UV_BIN/uv" "$PY_BIN/python3"

# Sets RC. $1 is the PATH prefix; rest are args. The script's own output is
# dropped: the stubs' log is what the checks read.
run() {
  local prefix="$1"; shift
  : > "$LOG"
  RC=0
  PATH="$prefix:/usr/bin:/bin" "$SCRIPT" "$@" >/dev/null 2>&1 || RC=$?
}
proj() {  # <name> [pyproject|requirements|both|tooling]... -> fresh dir
  local d="$BASE/$1"; shift
  rm -rf "$d"; mkdir -p "$d"
  for kind in "$@"; do
    case "$kind" in
      pyproject) printf '[project]\nname = "p"\n' > "$d/pyproject.toml" ;;
      tooling) printf '[tool.ruff]\nline-length = 100\n' > "$d/pyproject.toml" ;;
      requirements) echo "requests" > "$d/requirements.txt" ;;
    esac
  done
  echo "$d"
}

echo "=== uv: pyproject [project] ==="
D="$(proj uvp pyproject)"
run "$UV_BIN:$PY_BIN" "$D"
check_eq "exit 0" 0 "$RC"
check_eq "venv created at the target, then editable dev install into it" \
  "uv venv .venv [cwd=$D]
uv pip install --python .venv/bin/python -e .[dev] [cwd=$D]" "$(cat "$LOG")"
check_eq "uv's own .gitignore kept" '*' "$(cat "$D/.venv/.gitignore")"

echo "=== uv: inherited VIRTUAL_ENV can't redirect the install ==="
D="$(proj uvve pyproject)"
VIRTUAL_ENV="$BASE/elsewhere" run "$UV_BIN:$PY_BIN" "$D"
check_eq "exit 0" 0 "$RC"
check_eq "install pinned to the target's venv" 1 "$(grep -c -- '--python .venv/bin/python' "$LOG")"

echo "=== uv: requirements.txt only ==="
D="$(proj uvr requirements)"
run "$UV_BIN:$PY_BIN" "$D"
check_eq "exit 0" 0 "$RC"
check_eq "installs the requirements file" \
  "uv venv .venv [cwd=$D]
uv pip install --python .venv/bin/python -r requirements.txt [cwd=$D]" "$(cat "$LOG")"

echo "=== uv: both manifests share one venv ==="
D="$(proj uvb pyproject requirements)"
run "$UV_BIN:$PY_BIN" "$D"
check_eq "exit 0" 0 "$RC"
check_eq "venv created once" 1 "$(grep -c '^uv venv' "$LOG")"
check_eq "both installs ran" 2 "$(grep -c '^uv pip install' "$LOG")"

echo "=== uv: existing venv is reused ==="
D="$(proj uvx pyproject)"
mkdir -p "$D/.venv/bin"
run "$UV_BIN:$PY_BIN" "$D"
check_eq "exit 0" 0 "$RC"
check_eq "no new venv" 0 "$(grep -c '^uv venv' "$LOG" || true)"
check_eq "no .gitignore written into a venv it didn't make" no "$([[ -e "$D/.venv/.gitignore" ]] && echo yes || echo no)"

echo "=== uv: failed install exits nonzero ==="
D="$(proj uvf pyproject)"
UV_FAIL=1 run "$UV_BIN:$PY_BIN" "$D"
check_eq "exit nonzero" 1 "$((RC != 0))"

echo "=== no uv: python3 -m venv + pip ==="
D="$(proj pyp pyproject requirements)"
run "$PY_BIN" "$D"
check_eq "exit 0" 0 "$RC"
check_eq "stdlib venv, then the venv's pip for each manifest" \
  "python3 -m venv .venv [cwd=$D]
pip install -e .[dev]
pip install -r requirements.txt" "$(cat "$LOG")"
check_eq "self-ignoring .gitignore added (Python < 3.13 writes none)" '*' "$(cat "$D/.venv/.gitignore")"

echo "=== no Python manifest is a no-op ==="
for kind in none tooling; do
  if [[ "$kind" == none ]]; then D="$(proj none)"; else D="$(proj tool tooling)"; fi
  run "$UV_BIN:$PY_BIN" "$D"
  check_eq "$kind: exit 0" 0 "$RC"
  check_eq "$kind: nothing run" "" "$(cat "$LOG")"
  check_eq "$kind: no venv" no "$([[ -e "$D/.venv" ]] && echo yes || echo no)"
done

echo "=== usage ==="
run "$UV_BIN"
check_eq "no args: exit 1" 1 "$RC"
run "$UV_BIN" "$BASE/missing"
check_eq "missing dir: exit 1" 1 "$RC"

echo ""
echo "Results: $pass passed, $fail failed"
test "$fail" -eq 0
